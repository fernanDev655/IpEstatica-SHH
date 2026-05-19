#!/bin/bash

# =============================================================================
# SCRIPT DE CONFIGURACIÓN AUTOMÁTICA DE SERVIDOR SFTP EN UBUNTU
# Basado en la guía oficial de Zentyal
# =============================================================================

set -e  # Detenerse si hay algún error

# --- CONFIGURACIÓN PERSONALIZABLE ---
SFTP_USER="user"
SFTP_GROUP="sftp_users"
SFTP_PASSWORD="user123"  # Cambiar por contraseña segura
DATA_DIR="/data"
SSH_CONFIG="/etc/ssh/sshd_config"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  CONFIGURACIÓN AUTOMÁTICA SFTP${NC}"
echo -e "${GREEN}  Basado en guía Zentyal${NC}"
echo -e "${GREEN}========================================${NC}"

# =============================================================================
# PASO 1: ACTUALIZAR E INSTALAR OPENSSH-SERVER
# =============================================================================
echo -e "\n${YELLOW}[PASO 1/6] Actualizando paquetes e instalando OpenSSH...${NC}"
sudo apt update -qq
sudo apt install -y -qq openssh-server

echo -e "${GREEN}✓ OpenSSH instalado correctamente${NC}"

# =============================================================================
# PASO 2: CREAR GRUPO Y USUARIO SFTP
# =============================================================================
echo -e "\n${YELLOW}[PASO 2/6] Creando grupo y usuario SFTP...${NC}"

# Crear grupo si no existe
if getent group "$SFTP_GROUP" > /dev/null 2>&1; then
    echo -e "${YELLOW}  → El grupo '$SFTP_GROUP' ya existe, omitiendo...${NC}"
else
    sudo groupadd "$SFTP_GROUP"
    echo -e "${GREEN}  ✓ Grupo '$SFTP_GROUP' creado${NC}"
fi

# Crear usuario si no existe
if id "$SFTP_USER" > /dev/null 2>&1; then
    echo -e "${YELLOW}  → El usuario '$SFTP_USER' ya existe, omitiendo...${NC}"
else
    # -m: crear directorio home
    # -g: grupo primario
    # -s /sbin/nologin: sin acceso a shell SSH (solo SFTP)
    sudo useradd -m -g "$SFTP_GROUP" -s /sbin/nologin "$SFTP_USER"

    # Establecer contraseña
    echo "$SFTP_USER:$SFTP_PASSWORD" | sudo chpasswd
    echo -e "${GREEN}  ✓ Usuario '$SFTP_USER' creado con shell /sbin/nologin${NC}"
    echo -e "${GREEN}  ✓ Contraseña establecida${NC}"
fi

# =============================================================================
# PASO 3: CREAR ESTRUCTURA DE DIRECTORIOS Y PERMISOS
# =============================================================================
echo -e "\n${YELLOW}[PASO 3/6] Configurando directorios y permisos...${NC}"

# Crear directorio principal y subdirectorio upload
sudo mkdir -p "$DATA_DIR/$SFTP_USER/upload"

# /data/user → propietario root, grupo sftp_users, permisos 755
# REGLA OBLIGATORIA: chroot debe ser propiedad de root y NO escribible por el usuario
sudo chown root:"$SFTP_GROUP" "$DATA_DIR/$SFTP_USER"
sudo chmod 755 "$DATA_DIR/$SFTP_USER"
echo -e "${GREEN}  ✓ $DATA_DIR/$SFTP_USER → root:$SFTP_GROUP, 755${NC}"

# /data/user/upload → propietario el usuario, grupo sftp_users
# Aquí el usuario SÍ puede escribir (subir archivos)
sudo chown "$SFTP_USER":"$SFTP_GROUP" "$DATA_DIR/$SFTP_USER/upload"
sudo chmod 755 "$DATA_DIR/$SFTP_USER/upload"
echo -e "${GREEN}  ✓ $DATA_DIR/$SFTP_USER/upload → $SFTP_USER:$SFTP_GROUP, 755${NC}"

# =============================================================================
# PASO 4: CONFIGURAR sshd_config
# =============================================================================
echo -e "\n${YELLOW}[PASO 4/6] Configurando sshd_config...${NC}"

# Crear backup del archivo original
sudo cp "$SSH_CONFIG" "$SSH_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${GREEN}  ✓ Backup creado${NC}"

# Verificar si ya existe la configuración SFTP
if grep -q "Match Group $SFTP_GROUP" "$SSH_CONFIG"; then
    echo -e "${YELLOW}  → Configuración SFTP ya existe en sshd_config, omitiendo...${NC}"
else
    # Añadir configuración al final del archivo
    sudo tee -a "$SSH_CONFIG" > /dev/null <<'EOF'

# =============================================================================
# CONFIGURACIÓN SFTP - AÑADIDA AUTOMÁTICAMENTE
# Basado en guía Zentyal: https://www.zentyal.com/news/como-configurar-un-servidor-sftp-en-linux/
# =============================================================================

# Match Group: bloque condicional que solo aplica a usuarios del grupo sftp_users
# Permite tener reglas exclusivas para SFTP sin afectar usuarios SSH normales
Match Group sftp_users

    # ChrootDirectory: define la jaula (jail) del usuario
    # %u se sustituye por el nombre de usuario conectado
    # El usuario NO puede salir de este directorio - ve esta carpeta como la raíz (/)
    ChrootDirectory /data/%u

    # ForceCommand: fuerza el uso exclusivo del subsistema SFTP interno
    # Impide que el usuario abra un shell SSH interactivo
    # Solo permite transferencia de archivos (subir/bajar/listar)
    ForceCommand internal-sftp

    # AllowTcpForwarding no: bloquea la creación de túneles TCP (port forwarding)
    # Evita que el usuario use la conexión como puente a otros servicios internos
    AllowTcpForwarding no

    # X11Forwarding no: deshabilita reenvío de sesiones gráficas X11
    # El usuario no puede lanzar aplicaciones gráficas del servidor en su máquina
    X11Forwarding no

# =============================================================================
EOF
    echo -e "${GREEN}  ✓ Configuración SFTP añadida a sshd_config${NC}"
fi

# =============================================================================
# PASO 5: REINICIAR SERVICIO SSH
# =============================================================================
echo -e "\n${YELLOW}[PASO 5/6] Reiniciando servicio SSH...${NC}"
sudo systemctl restart sshd

# Verificar que el servicio está activo
if systemctl is-active --quiet sshd; then
    echo -e "${GREEN}  ✓ Servicio SSH reiniciado correctamente${NC}"
else
    echo -e "${RED}  ✗ ERROR: El servicio SSH no se reinició correctamente${NC}"
    exit 1
fi

# =============================================================================
# PASO 6: VERIFICACIÓN FINAL
# =============================================================================
echo -e "\n${YELLOW}[PASO 6/6] Verificando configuración...${NC}"

# Verificar sintaxis de sshd_config
if sudo sshd -t; then
    echo -e "${GREEN}  ✓ Sintaxis de sshd_config correcta${NC}"
else
    echo -e "${RED}  ✗ ERROR: Sintaxis incorrecta en sshd_config${NC}"
    exit 1
fi

# Mostrar resumen
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  CONFIGURACIÓN COMPLETADA${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Resumen de la configuración:${NC}"
echo -e "  • Grupo creado:     $SFTP_GROUP"
echo -e "  • Usuario creado:   $SFTP_USER"
echo -e "  • Contraseña:       $SFTP_PASSWORD"
echo -e "  • Directorio raíz:  $DATA_DIR/$SFTP_USER (root:$SFTP_GROUP, 755)"
echo -e "  • Directorio upload: $DATA_DIR/$SFTP_USER/upload ($SFTP_USER:$SFTP_GROUP, 755)"
echo -e "  • Puerto SFTP:      22"
echo -e "  • Shell:            /sbin/nologin (solo SFTP, no SSH)"

SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "\n${YELLOW}Para conectarte desde otro equipo:${NC}"
echo -e "  sftp -P 22 $SFTP_USER@$SERVER_IP"
echo -e "\n${YELLOW}Comandos útiles una vez conectado:${NC}"
echo -e "  ls              → Listar archivos"
echo -e "  put archivo.txt → Subir archivo"
echo -e "  get archivo.txt → Descargar archivo"
echo -e "  cd upload       → Entrar a carpeta de subidas"
echo -e "  exit            → Desconectar"

echo -e "\n${GREEN}========================================${NC}"
