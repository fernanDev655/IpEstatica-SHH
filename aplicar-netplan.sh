#!/bin/bash
echo "=================================="
echo "  AutoConfigurador de Red"
echo "=================================="
echo "Verificando net-tools..."
if ! dpkg -l | grep -q "net-tools"; then
    echo "Instalando net-tools..."
    sudo apt update -qq && sudo apt install -y net-tools
    echo "net-tools instalado"
else
    echo "net-tools ya esta instalado"
fi
echo ""
echo "Creando configuracion de red..."
sudo tee /etc/netplan/50-cloud-init.yaml > /dev/null << 'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s3:
      dhcp4: no
      addresses: [192.168.1.10/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [208.67.222.222]
EOF
echo "Archivo creado"
echo ""
echo "Aplicando configuracion..."
sudo netplan apply
if [ $? -eq 0 ]; then
    echo ""
    echo "Configuracion aplicada correctamente"
    echo "IP:"
    ip addr show enp0s3 | grep "inet " | awk '{print $2}'
    echo "Gateway:"
    ip route | grep default | awk '{print $3}'
    echo "DNS:"
    cat /etc/resolv.conf | grep nameserver | awk '{print $2}'
else
    echo "Error al aplicar la configuracion"
    exit 1
fi