#!/bin/bash

# ============================================
# Script de Configuración IP Estática - AutoElite
# Servidor BD: 192.168.1.20
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- CONFIGURACIÓN ---
IFACE="enp0s3"
IP="192.168.1.20"
GATEWAY="192.168.1.1"
DNS="208.67.222.222"

if [[ $EUID -ne 0 ]]; then
    log_error "Este script debe ejecutarse como root. Usa: sudo $0"
    exit 1
fi

echo "=================================="
echo "  AutoConfigurador de Red - BD"
echo "  IP: $IP"
echo "=================================="

log_info "Verificando net-tools..."
if ! dpkg -l | grep -q "net-tools"; then
    apt update -qq && apt install -y net-tools
    log_info "net-tools instalado."
else
    log_warn "net-tools ya está instalado."
fi

log_info "Creando configuración de red..."
tee /etc/netplan/50-cloud-init.yaml > /dev/null << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses: [${IP}/24]
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses: [${DNS}]
EOF

log_info "Aplicando configuración..."
netplan apply

if [ $? -eq 0 ]; then
    echo ""
    log_info "✅ Configuración aplicada correctamente."
    echo "  IP:      $(ip addr show $IFACE | grep 'inet ' | awk '{print $2}')"
    echo "  Gateway: $(ip route | grep default | awk '{print $3}')"
    echo "  DNS:     $(cat /etc/resolv.conf | grep nameserver | awk '{print $2}')"
else
    log_error "Error al aplicar la configuración."
    exit 1
fi
