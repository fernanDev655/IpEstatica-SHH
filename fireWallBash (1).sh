#!/bin/bash
# ============================================
# Script de configuración automática de UFW
# AutoElite - Práctica Firewall
# ============================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================
# CONFIGURACIÓN PERSONALIZABLE
# ============================================
SSH_PORT=2222              # Cambia según tu configuración
ENABLE_HTTP=false          # true si necesitas servidor web
ENABLE_HTTPS=false         # true si necesitas SSL
ENABLE_LIMIT_SSH=true      # Activar límite de intentos SSH (EXTRA)

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  CONFIGURACIÓN AUTOMÁTICA DE UFW     ${NC}"
echo -e "${YELLOW}========================================${NC}"

# ============================================
# 1. INSTALACIÓN
# ============================================
echo -e "\n${GREEN}[1/7] Instalando UFW...${NC}"
sudo apt update -qq
sudo apt install ufw -y -qq

# ============================================
# 2. CONFIGURAR IPv6
# ============================================
echo -e "\n${GREEN}[2/7] Habilitando IPv6 en UFW...${NC}"
sudo sed -i 's/IPV6=.*/IPV6=yes/' /etc/default/ufw

# ============================================
# 3. RESETEAR REGLAS EXISTENTES
# ============================================
echo -e "\n${GREEN}[3/7] Limpiando reglas anteriores...${NC}"
sudo ufw --force reset
sudo ufw disable

# ============================================
# 4. POLÍTICAS POR DEFECTO
# ============================================
echo -e "\n${GREEN}[4/7] Configurando políticas por defecto...${NC}"
sudo ufw default deny incoming
sudo ufw default allow outgoing

# ============================================
# 5. REGLAS ESPECÍFICAS
# ============================================
echo -e "\n${GREEN}[5/7] Añadiendo reglas de servicios...${NC}"

# SSH (¡IMPRESCINDIBLE! No te quedes fuera)
echo "  → Permitir SSH en puerto $SSH_PORT"
sudo ufw allow $SSH_PORT/tcp

# HTTP (opcional)
if [ "$ENABLE_HTTP" = true ]; then
    echo "  → Permitir HTTP (puerto 80)"
    sudo ufw allow 80/tcp
fi

# HTTPS (opcional)
if [ "$ENABLE_HTTPS" = true ]; then
    echo "  → Permitir HTTPS (puerto 443)"
    sudo ufw allow 443/tcp
fi

# ============================================
# 6. EXTRA: LIMITAR INTENTOS SSH (anti-fuerza bruta)
# ============================================
if [ "$ENABLE_LIMIT_SSH" = true ]; then
    echo -e "\n${GREEN}[6/7] Activando protección anti-fuerza bruta...${NC}"
    sudo ufw limit $SSH_PORT/tcp comment 'Limitar intentos SSH'
    echo -e "  ${YELLOW}⚡ UFW limitará conexiones repetidas desde la misma IP${NC}"
fi

# ============================================
# 7. ACTIVAR FIREWALL
# ============================================
echo -e "\n${GREEN}[7/7] Activando firewall...${NC}"
sudo ufw --force enable

# ============================================
# RESUMEN FINAL
# ============================================
echo -e "\n${YELLOW}========================================${NC}"
echo -e "${YELLOW}  CONFIGURACIÓN COMPLETADA            ${NC}"
echo -e "${YELLOW}========================================${NC}"
echo -e "\n${GREEN}Estado del firewall:${NC}"
sudo ufw status verbose

echo -e "\n${GREEN}Reglas activas:${NC}"
sudo ufw status numbered

echo -e "\n${YELLOW}⚠️  IMPORTANTE:${NC}"
echo -e "   - Puerto SSH configurado: ${GREEN}$SSH_PORT${NC}"
echo -e "   - Si no puedes conectar, verifica el puerto en /etc/ssh/sshd_config"
echo -e "   - Para desactivar: ${RED}sudo ufw disable${NC}"
echo -e "   - Para ver logs: ${GREEN}sudo tail -f /var/log/ufw.log${NC}"

exit 0