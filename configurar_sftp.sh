#!/bin/bash

# =============================================================================
# Script de Configuración SFTP - AutoElite
# Servidor Web: 192.168.1.10 | Puerto SSH: 4222
# Cliente:      192.168.1.5
# =============================================================================

set -e

# --- CONFIGURACIÓN ---
SFTP_USER="user"
SFTP_GROUP="sftp_users"
SFTP_PASSWORD="user123"
DATA_DIR="/data"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_PORT="4223"         # Puerto del servidor BD (distinto al web que usa 4222)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  CONFIGURACIÓN AUTOMÁTICA SFTP        ${NC}"
echo -e "${GREEN}  Servidor BD: 192.168.1.10            ${NC}"
echo -e "${GREEN}  Puerto SSH:  $SSH_PORT               ${NC}"
echo -e "${GREEN}========================================${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Ejecutar como root: sudo $0"
    exit 1
fi

# =============================================================================
# PASO 1: INSTALAR OPENSSH
# =============================================================================
echo -e "\n${YELLOW}[PASO 1/6] Instalando OpenSSH...${NC}"
apt update -qq
apt install -y -qq openssh-server
echo -e "${GREEN}✓ OpenSSH instalado${NC}"

# =============================================================================
# PASO 2: CREAR GRUPO Y USUARIO SFTP
# =============================================================================
echo -e "\n${YELLOW}[PASO 2/6] Creando grupo y usuario SFTP...${NC}"

if getent group "$SFTP_GROUP" > /dev/null 2>&1; then
    echo -e "${YELLOW}  → El grupo '$SFTP_GROUP' ya existe, omitiendo...${NC}"
else
    groupadd "$SFTP_GROUP"
    echo -e "${GREEN}  ✓ Grupo '$SFTP_GROUP' creado${NC}"
fi

if id "$SFTP_USER" > /dev/null 2>&1; then
    echo -e "${YELLOW}  → El usuario '$SFTP_USER' ya existe, omitiendo...${NC}"
else
    useradd -m -g "$SFTP_GROUP" -s /sbin/nologin "$SFTP_USER"
    echo "$SFTP_USER:$SFTP_PASSWORD" | chpasswd
    echo -e "${GREEN}  ✓ Usuario '$SFTP_USER' creado (solo SFTP, sin shell)${NC}"
    echo -e "${GREEN}  ✓ Contraseña establecida${NC}"
fi

# =============================================================================
# PASO 3: DIRECTORIOS Y PERMISOS
# =============================================================================
echo -e "\n${YELLOW}[PASO 3/6] Configurando directorios y permisos...${NC}"

mkdir -p "$DATA_DIR/$SFTP_USER/upload"

# Directorio raíz: propietario root (obligatorio para chroot)
chown root:"$SFTP_GROUP" "$DATA_DIR/$SFTP_USER"
chmod 755 "$DATA_DIR/$SFTP_USER"
echo -e "${GREEN}  ✓ $DATA_DIR/$SFTP_USER → root:$SFTP_GROUP, 755${NC}"

# Directorio upload: el usuario puede escribir aquí
chown "$SFTP_USER":"$SFTP_GROUP" "$DATA_DIR/$SFTP_USER/upload"
chmod 755 "$DATA_DIR/$SFTP_USER/upload"
echo -e "${GREEN}  ✓ $DATA_DIR/$SFTP_USER/upload → $SFTP_USER:$SFTP_GROUP, 755${NC}"

# =============================================================================
# PASO 4: CONFIGURAR SSHD_CONFIG
# =============================================================================
echo -e "\n${YELLOW}[PASO 4/6] Configurando sshd_config...${NC}"

BACKUP_FILE="${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$SSH_CONFIG" "$BACKUP_FILE"
echo -e "${GREEN}  ✓ Backup creado: $BACKUP_FILE${NC}"

# Asegurarse de que el puerto está bien configurado
if grep -qE "^Port" "$SSH_CONFIG"; then
    sed -i "s/^Port.*/Port $SSH_PORT/" "$SSH_CONFIG"
else
    echo "Port $SSH_PORT" >> "$SSH_CONFIG"
fi
echo -e "${GREEN}  ✓ Puerto SSH confirmado: $SSH_PORT${NC}"

# Añadir bloque SFTP si no existe ya
if grep -q "Match Group $SFTP_GROUP" "$SSH_CONFIG"; then
    echo -e "${YELLOW}  → Configuración SFTP ya existe en sshd_config, omitiendo...${NC}"
else
    cat >> "$SSH_CONFIG" << EOF

# =============================================================================
# CONFIGURACIÓN SFTP - AutoElite Servidor BD
# El cliente 192.168.1.5 puede conectar a este servidor (192.168.1.20)
# y al servidor web (192.168.1.10) con las mismas credenciales SFTP
# =============================================================================
Match Group $SFTP_GROUP

    # Jaula: el usuario ve esta carpeta como raíz, no puede salir
    ChrootDirectory $DATA_DIR/%u

    # Solo transferencia de archivos, sin shell interactiva
    ForceCommand internal-sftp

    # Sin túneles TCP ni sesiones gráficas
    AllowTcpForwarding no
    X11Forwarding no

EOF
    echo -e "${GREEN}  ✓ Bloque SFTP añadido a sshd_config${NC}"
fi

# =============================================================================
# PASO 5: REINICIAR SSH
# =============================================================================
echo -e "\n${YELLOW}[PASO 5/6] Reiniciando servicio SSH...${NC}"

if sshd -t; then
    systemctl restart sshd
    echo -e "${GREEN}  ✓ SSH reiniciado correctamente${NC}"
else
    echo -e "${RED}  ✗ Error en sshd_config. Restaurando backup...${NC}"
    cp "$BACKUP_FILE" "$SSH_CONFIG"
    exit 1
fi

if systemctl is-active --quiet sshd; then
    echo -e "${GREEN}  ✓ Servicio SSH activo${NC}"
else
    echo -e "${RED}  ✗ El servicio SSH no está activo${NC}"
    exit 1
fi

# =============================================================================
# PASO 6: VERIFICACIÓN
# =============================================================================
echo -e "\n${YELLOW}[PASO 6/6] Verificando configuración...${NC}"

if sshd -t; then
    echo -e "${GREEN}  ✓ Sintaxis de sshd_config correcta${NC}"
fi

if ss -tlnp | grep -q ":$SSH_PORT"; then
    echo -e "${GREEN}  ✓ SSH escuchando en puerto $SSH_PORT${NC}"
else
    echo -e "${YELLOW}  ⚠ SSH no detectado en puerto $SSH_PORT aún${NC}"
fi

# =============================================================================
# RESUMEN FINAL
# =============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  CONFIGURACIÓN SFTP COMPLETADA        ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "  👤 Usuario SFTP:    ${GREEN}$SFTP_USER${NC}"
echo -e "  🔑 Contraseña:      ${GREEN}$SFTP_PASSWORD${NC}"
echo -e "  📁 Directorio raíz: ${GREEN}$DATA_DIR/$SFTP_USER${NC}"
echo -e "  📂 Subir archivos:  ${GREEN}$DATA_DIR/$SFTP_USER/upload${NC}"
echo -e "  🔒 Shell:           ${GREEN}/sbin/nologin (solo SFTP)${NC}"
echo ""
echo -e "  📡 Conexión desde el cliente (192.168.1.5):"
echo ""
echo ""
echo -e "     ${YELLOW}Servidor Web:${NC}"
echo -e "     sftp -P 4222 $SFTP_USER@192.168.1.10"
echo ""
echo -e "  📝 Comandos útiles una vez conectado:"
echo -e "     cd upload        → entrar a la carpeta de subidas"
echo -e "     put archivo.sql  → subir archivo al servidor"
echo -e "     get archivo.sql  → descargar archivo del servidor"
echo -e "     ls               → listar archivos"
echo -e "     exit             → desconectar"
echo ""
echo ""
echo -e "${GREEN}========================================${NC}"
