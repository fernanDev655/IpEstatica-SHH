#!/bin/bash

# ============================================
# Script de Hardening SSH - AutoElite
# Servidor BD: 192.168.1.20
# Puerto SSH:  4223
# ============================================

set -euo pipefail

# --- CONFIGURACIÓN ---
SSH_USER="adminseguro"
SSH_PORT="4223"
SSHD_CONFIG="/etc/ssh/sshd_config"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Este script debe ejecutarse como root. Usa: sudo $0"
    exit 1
fi

echo "=========================================="
echo "  Hardening SSH - Servidor BD"
echo "  Usuario: $SSH_USER | Puerto: $SSH_PORT"
echo "=========================================="

# ============================================
# 1. CREAR USUARIO Y AÑADIR A SUDO
# ============================================
log_info "Verificando usuario '$SSH_USER'..."

if id "$SSH_USER" &>/dev/null; then
    log_warn "El usuario '$SSH_USER' ya existe. Verificando grupo sudo..."
else
    adduser --gecos "" --disabled-password "$SSH_USER"
    log_info "Usuario '$SSH_USER' creado correctamente."
fi

if groups "$SSH_USER" | grep -qw "sudo"; then
    log_warn "El usuario '$SSH_USER' ya está en el grupo sudo."
else
    usermod -aG sudo "$SSH_USER"
    log_info "Usuario '$SSH_USER' añadido al grupo sudo."
fi

log_warn "Establece la contraseña para '$SSH_USER':"
passwd "$SSH_USER"

# ============================================
# 2. BACKUP DE SSHD_CONFIG
# ============================================
BACKUP_FILE="${SSHD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$SSHD_CONFIG" "$BACKUP_FILE"
log_info "Backup creado en: $BACKUP_FILE"

# ============================================
# 3. CONFIGURAR SSH
# ============================================
log_info "Configurando SSH en puerto $SSH_PORT..."

update_sshd_config() {
    local key="$1"
    local value="$2"
    local pattern="^#?${key}[[:space:]]"
    if grep -qE "$pattern" "$SSHD_CONFIG"; then
        sed -i "s|${pattern}.*|${key} ${value}|" "$SSHD_CONFIG"
    else
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
}

update_sshd_config "Port"                "$SSH_PORT"
update_sshd_config "PermitRootLogin"     "no"
update_sshd_config "PermitEmptyPasswords" "no"

if grep -qE "^AllowUsers" "$SSHD_CONFIG"; then
    sed -i "s/^AllowUsers.*/AllowUsers $SSH_USER/" "$SSHD_CONFIG"
else
    echo "AllowUsers $SSH_USER" >> "$SSHD_CONFIG"
fi

log_info "Configuración SSH actualizada."

# ============================================
# 4. VERIFICAR Y REINICIAR SSH
# ============================================
log_info "Verificando sintaxis de sshd_config..."
if sshd -t; then
    if command -v systemctl &>/dev/null; then
        systemctl restart sshd || systemctl restart ssh
    else
        service ssh restart || service sshd restart
    fi
    log_info "Servicio SSH reiniciado correctamente."
else
    log_error "Error en la sintaxis. Restaurando backup..."
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    exit 1
fi

# ============================================
# 5. VERIFICAR PUERTO EN ESCUCHA
# ============================================
sleep 2
if ss -tlnp | grep -q ":$SSH_PORT"; then
    log_info "✅ SSH escuchando correctamente en el puerto $SSH_PORT."
else
    log_warn "⚠️  SSH no parece estar escuchando en el puerto $SSH_PORT."
fi

echo ""
echo "=========================================="
echo -e "${GREEN}  CONFIGURACIÓN SSH COMPLETADA${NC}"
echo "=========================================="
echo ""
echo "  👤 Usuario SSH:  $SSH_USER"
echo "  🔒 Puerto SSH:   $SSH_PORT"
echo "  🚫 Root login:   Deshabilitado"
echo "  📁 Backup:       $BACKUP_FILE"
echo ""
echo "  📝 Para conectar desde el cliente:"
echo "     ssh -p $SSH_PORT $SSH_USER@192.168.1.20"
echo ""
echo "=========================================="
log_warn "IMPORTANTE: No cierres esta sesión hasta verificar"
log_warn "que puedes conectar con el nuevo usuario y puerto."
