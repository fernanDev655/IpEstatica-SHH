#!/bin/bash

# ============================================
# Script de configuración automática de UFW
# AutoElite - Servidor BD
# Puerto SSH:        4223
# Puerto PostgreSQL: 5432 (solo desde 192.168.1.10)
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- CONFIGURACIÓN ---
SSH_PORT=4223
PG_PORT=5432
WEB_SERVER_IP="192.168.1.10"
ENABLE_LIMIT_SSH=true

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} Ejecutar como root: sudo $0"
    exit 1
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  CONFIGURACIÓN UFW - SERVIDOR BD      ${NC}"
echo -e "${YELLOW}  SSH: $SSH_PORT | PG: $PG_PORT         ${NC}"
echo -e "${YELLOW}========================================${NC}"

# ============================================
# 1. INSTALACIÓN
# ============================================
echo -e "\n${GREEN}[1/7] Instalando UFW...${NC}"
apt update -qq
apt install ufw -y -qq

# ============================================
# 2. CONFIGURAR IPv6
# ============================================
echo -e "\n${GREEN}[2/7] Habilitando IPv6 en UFW...${NC}"
sed -i 's/IPV6=.*/IPV6=yes/' /etc/default/ufw

# ============================================
# 3. RESETEAR REGLAS EXISTENTES
# ============================================
echo -e "\n${GREEN}[3/7] Limpiando reglas anteriores...${NC}"
ufw --force reset
ufw disable

# ============================================
# 4. POLÍTICAS POR DEFECTO
# ============================================
echo -e "\n${GREEN}[4/7] Configurando políticas por defecto...${NC}"
ufw default deny incoming
ufw default allow outgoing

# ============================================
# 5. REGLAS ESPECÍFICAS
# ============================================
echo -e "\n${GREEN}[5/7] Añadiendo reglas de servicios...${NC}"

# SSH
echo "  → Permitir SSH en puerto $SSH_PORT"
ufw allow "$SSH_PORT/tcp"

# PostgreSQL SOLO desde el servidor web
echo "  → Permitir PostgreSQL (puerto $PG_PORT) solo desde $WEB_SERVER_IP"
ufw allow from "$WEB_SERVER_IP" to any port "$PG_PORT" proto tcp

# ============================================
# 6. PROTECCIÓN ANTI-FUERZA BRUTA SSH
# ============================================
if [ "$ENABLE_LIMIT_SSH" = true ]; then
    echo -e "\n${GREEN}[6/7] Activando protección anti-fuerza bruta SSH...${NC}"
    ufw limit "$SSH_PORT/tcp" comment 'Limitar intentos SSH'
    echo -e "  ${YELLOW}⚡ UFW limitará conexiones repetidas desde la misma IP${NC}"
fi

# ============================================
# 7. ACTIVAR FIREWALL
# ============================================
echo -e "\n${GREEN}[7/7] Activando firewall...${NC}"
ufw --force enable

echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  CONFIGURACIÓN UFW COMPLETADA         ${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "\n${GREEN}Estado del firewall:${NC}"
ufw status verbose

echo -e "\n${GREEN}Reglas activas:${NC}"
ufw status numbered

echo -e "\n${YELLOW}⚠️  IMPORTANTE:${NC}"
echo -e "   - Puerto SSH:        ${GREEN}$SSH_PORT${NC}"
echo -e "   - Puerto PostgreSQL: ${GREEN}$PG_PORT${NC} (solo desde ${GREEN}$WEB_SERVER_IP${NC})"
echo -e "   - Para ver logs:     ${GREEN}sudo tail -f /var/log/ufw.log${NC}"
echo -e "   - Para desactivar:   ${RED}sudo ufw disable${NC}"

exit 0
