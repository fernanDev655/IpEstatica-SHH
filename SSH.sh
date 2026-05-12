#!/bin/bash

# ============================================
# Script de Hardening SSH - AutoElite
# Servidor: 192.168.1.10
# ============================================

set -euo pipefail

# --- CONFIGURACIÓN ---
SSH_USER="adminseguro"
SSH_PORT="4222"
SSHD_CONFIG="/etc/ssh/sshd_config"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# 1. VERIFICAR QUE SE EJECUTA COMO ROOT
# ============================================
if [[ $EUID -ne 0 ]]; then
    log_error "Este script debe ejecutarse como root. Usa: sudo $0"
    exit 1
fi

log_info "Iniciando configuración de seguridad SSH..."

# ============================================
# 2. CREAR USUARIO Y AÑADIR A SUDO
# ============================================
if id "$SSH_USER" &>/dev/null; then
    log_warn "El usuario '$SSH_USER' ya existe. Verificando grupo sudo..."
else
    log_info "Creando usuario '$SSH_USER'..."
    adduser --gecos "" --disabled-password "$SSH_USER"
    log_info "Usuario '$SSH_USER' creado correctamente."
fi

# Añadir al grupo sudo
if groups "$SSH_USER" | grep -qw "sudo"; then
    log_warn "El usuario '$SSH_USER' ya está en el grupo sudo."
else
    usermod -aG sudo "$SSH_USER"
    log_info "Usuario '$SSH_USER' añadido al grupo sudo."
fi

# Establecer contraseña (interactivo)
log_warn "Ahora debes establecer una contraseña para '$SSH_USER':"
passwd "$SSH_USER"

# ============================================
# 3. HACER BACKUP DE SSHD_CONFIG
# ============================================
BACKUP_FILE="${SSHD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$SSHD_CONFIG" "$BACKUP_FILE"
log_info "Backup creado en: $BACKUP_FILE"

# ============================================
# 4. CONFIGURAR SSH - PUERTO Y USUARIO
# ============================================
log_info "Configurando SSH en puerto $SSH_PORT..."

# Función para actualizar o añadir línea en sshd_config
update_sshd_config() {
    local key="$1"
    local value="$2"
    local pattern="^#?${key}[[:space:]]"
    
    if grep -qE "$pattern" "$SSHD_CONFIG"; then
        # Reemplazar línea existente
        sed -i "s|${pattern}.*|${key} ${value}|" "$SSHD_CONFIG"
    else
        # Añadir al final
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

# Cambiar puerto
update_sshd_config "Port" "$SSH_PORT"

# Permitir solo nuestro usuario
if grep -qE "^AllowUsers" "$SSHD_CONFIG"; then
    sed -i "s/^AllowUsers.*/AllowUsers $SSH_USER/" "$SSHD_CONFIG"
else
    echo "AllowUsers $SSH_USER" >> "$SSHD_CONFIG"
fi

# Deshabilitar root login
update_sshd_config "PermitRootLogin" "no"

# Deshabilitar login vacío
update_sshd_config "PermitEmptyPasswords" "no"

log_info "Configuración SSH actualizada."

# ============================================
# 5. VERIFICAR SINTAXIS Y REINICIAR SSH
# ============================================
log_info "Verificando sintaxis de sshd_config..."
if sshd -t; then
    log_info "Sintaxis correcta. Reiniciando servicio SSH..."
    
    # Reiniciar servicio (compatible con systemd y sysvinit)
    if command -v systemctl &>/dev/null; then
        systemctl restart sshd || systemctl restart ssh
    else
        service ssh restart || service sshd restart
    fi
    
    log_info "Servicio SSH reiniciado correctamente."
else
    log_error "Error en la sintaxis de sshd_config. Restaurando backup..."
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    exit 1
fi

# ============================================
# 6. VERIFICAR PUERTO EN ESCUCHA
# ============================================
sleep 2
if ss -tlnp | grep -q ":$SSH_PORT"; then
    log_info "✅ SSH está escuchando correctamente en el puerto $SSH_PORT"
else
    log_error "⚠️ SSH no parece estar escuchando en el puerto $SSH_PORT"
fi

# ============================================
# 7. CONFIGURAR FIREWALL (UFW)
# ============================================
if command -v ufw &>/dev/null; then
    log_info "Configurando UFW..."
    
    # Permitir nuevo puerto
    ufw allow "$SSH_PORT/tcp" --quiet 2>/dev/null || true
    
    # Opcional: denegar puerto 22 (descomenta si quieres)
    # ufw delete allow 22/tcp --quiet 2>/dev/null || true
    
    log_info "UFW configurado. Puerto $SSH_PORT permitido."
else
    log_warn "UFW no está instalado. Configura el firewall manualmente."
fi

# ============================================
# RESUMEN FINAL
# ============================================
echo ""
echo "=========================================="
echo -e "${GREEN}  CONFIGURACIÓN COMPLETADA${NC}"
echo "=========================================="
echo ""
echo "  👤 Usuario SSH:  $SSH_USER"
echo "  🔒 Puerto SSH:   $SSH_PORT"
echo "  🚫 Root login:   Deshabilitado"
echo ""
echo "  📁 Backup:       $BACKUP_FILE"
echo ""
echo "  📝 Para conectar desde el cliente:"
echo "     ssh -p $SSH_PORT $SSH_USER@192.168.1.10"
echo ""
echo "=========================================="
echo ""
log_warn "IMPORTANTE: No cierres esta sesión hasta verificar"
log_warn "que puedes conectar con el nuevo usuario y puerto."