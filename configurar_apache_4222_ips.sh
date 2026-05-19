#!/bin/bash
###############################################################################
# Script: Apache en Puerto 4222 - IPs Fijas
# Servidor: 192.168.1.10 | Cliente: 192.168.1.5
###############################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

HTTP_PORT=4222
HTTPS_PORT=4223
SERVER_IP="192.168.1.10"
CLIENT_IP="192.168.1.5"

print_msg() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${BLUE}[CONFIG]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then 
    print_error "Ejecutar como root: sudo ./configurar_apache.sh"
    exit 1
fi

print_msg "=========================================="
print_msg "  APACHE - PUERTO 4222 | IP: $SERVER_IP"
print_msg "=========================================="

# 1. ACTUALIZAR
print_msg "Paso 1/10: Actualizando sistema..."
apt update && apt upgrade -y

# 2. INSTALAR APACHE
print_msg "Paso 2/10: Instalando Apache2..."
apt install apache2 -y
systemctl enable apache2
systemctl start apache2

# 3. CONFIGURAR PUERTOS
print_msg "Paso 3/10: Configurando puertos..."
cat > /etc/apache2/ports.conf << EOF
Listen $HTTP_PORT

<IfModule ssl_module>
    Listen $HTTPS_PORT
</IfModule>

<IfModule mod_gnutls.c>
    Listen $HTTPS_PORT
</IfModule>
EOF

print_info "HTTP: $HTTP_PORT | HTTPS: $HTTPS_PORT"

# 4. CONFIGURAR SITIO HTTP
cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:$HTTP_PORT>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <Directory /var/www/html>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ServerSignature Off
</VirtualHost>
EOF

# 5. FIREWALL
print_msg "Paso 5/10: Configurando firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp
    ufw allow $HTTP_PORT/tcp
    ufw allow $HTTPS_PORT/tcp
    print_msg "UFW configurado: 22(SSH), $HTTP_PORT(HTTP), $HTTPS_PORT(HTTPS)"
else
    apt install ufw -y
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow $HTTP_PORT/tcp
    ufw allow $HTTPS_PORT/tcp
    ufw --force enable
fi

# 6. PÁGINA WEB
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AutoElite - Servidor 192.168.1.10:4222</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #0f0c29 0%, #302b63 50%, #24243e 100%);
            color: #fff;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
        }
        .container {
            text-align: center;
            padding: 2rem;
            max-width: 900px;
        }
        .ip-badge {
            display: inline-block;
            background: rgba(243, 156, 18, 0.2);
            border: 2px solid #f39c12;
            color: #f39c12;
            padding: 0.5rem 1.5rem;
            border-radius: 25px;
            font-weight: bold;
            font-size: 1.1rem;
            margin-bottom: 0.5rem;
        }
        .port-badge {
            display: inline-block;
            background: rgba(46, 204, 113, 0.2);
            border: 2px solid #2ecc71;
            color: #2ecc71;
            padding: 0.3rem 1rem;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9rem;
            margin-bottom: 1rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 0.5rem;
            background: linear-gradient(45deg, #f39c12, #e74c3c);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .status-box {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            padding: 2rem;
            margin: 2rem 0;
            border: 1px solid rgba(255,255,255,0.2);
        }
        .status-box h2 {
            color: #f39c12;
            margin-bottom: 1rem;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 1rem;
            text-align: left;
            margin-top: 1rem;
        }
        .info-item {
            background: rgba(0,0,0,0.3);
            padding: 1rem;
            border-radius: 8px;
            border-left: 3px solid #f39c12;
        }
        .info-item strong {
            color: #f39c12;
            display: block;
            margin-bottom: 0.3rem;
        }
        .url-box {
            background: rgba(46, 204, 113, 0.1);
            border: 1px solid #2ecc71;
            border-radius: 8px;
            padding: 1rem;
            margin-top: 1.5rem;
            font-family: 'Courier New', monospace;
            font-size: 1.1rem;
        }
        .footer {
            margin-top: 2rem;
            opacity: 0.6;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="ip-badge">🖥️ 192.168.1.10</div><br>
        <div class="port-badge">🌐 PUERTO 4222</div>
        <h1>AutoElite Server</h1>

        <div class="status-box">
            <h2>✅ Servidor Apache Activo</h2>
            <div class="info-grid">
                <div class="info-item">
                    <strong>IP Servidor</strong>
                    192.168.1.10
                </div>
                <div class="info-item">
                    <strong>Puerto HTTP</strong>
                    4222
                </div>
                <div class="info-item">
                    <strong>Puerto HTTPS</strong>
                    4223
                </div>
                <div class="info-item">
                    <strong>PHP</strong>
                    Habilitado
                </div>
                <div class="info-item">
                    <strong>Base de Datos</strong>
                    PostgreSQL
                </div>
                <div class="info-item">
                    <strong>SSL</strong>
                    Certificado auto-firmado
                </div>
            </div>

            <div class="url-box">
                <strong style="color: #2ecc71;">URLs de acceso:</strong><br>
                HTTP: http://192.168.1.10:4222<br>
                HTTPS: https://192.168.1.10:4223
            </div>
        </div>

        <p class="footer">
            Práctica de Despliegue | Servidor: 192.168.1.10 | Cliente: 192.168.1.5
        </p>
    </div>
</body>
</html>
HTMLEOF

chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# 7. LOGS
print_msg "Paso 7/10: Configurando logs..."
cat > /etc/apache2/conf-available/custom-log.conf << 'EOF'
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %D %p" combined
EOF
a2enconf custom-log

# 8. SSL
print_msg "Paso 8/10: Generando certificados SSL..."
apt install openssl -y
mkdir -p /etc/apache2/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048     -keyout /etc/apache2/ssl/apache.key     -out /etc/apache2/ssl/apache.crt     -subj "/C=ES/ST=Madrid/L=Madrid/O=AutoElite/CN=192.168.1.10" 2>/dev/null
chmod 600 /etc/apache2/ssl/apache.key
chmod 644 /etc/apache2/ssl/apache.crt

# 9. HTTPS
print_msg "Paso 9/10: Configurando HTTPS en puerto $HTTPS_PORT..."
a2enmod ssl
a2enmod headers
a2enmod rewrite

cat > /etc/apache2/sites-available/default-ssl.conf << EOF
<IfModule mod_ssl.c>
    <VirtualHost _default_:$HTTPS_PORT>
        ServerAdmin webmaster@localhost
        DocumentRoot /var/www/html
        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined

        SSLEngine on
        SSLCertificateFile /etc/apache2/ssl/apache.crt
        SSLCertificateKeyFile /etc/apache2/ssl/apache.key

        SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
        SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
        SSLHonorCipherOrder on

        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-XSS-Protection "1; mode=block"

        <Directory /var/www/html>
            Options -Indexes +FollowSymLinks
            AllowOverride All
            Require all granted
        </Directory>
    </VirtualHost>
</IfModule>
EOF

a2ensite default-ssl.conf

# 10. PHP + PostgreSQL
print_msg "Paso 10/10: Instalando PHP y PostgreSQL..."
apt install php libapache2-mod-php -y
apt install php-pgsql -y

cat > /var/www/html/info.php << 'EOF'
<?php phpinfo(); ?>
EOF

# VERIFICACIÓN
print_msg "=========================================="
print_msg "  VERIFICANDO..."
print_msg "=========================================="

apache2ctl configtest
systemctl restart apache2

print_msg "Puertos activos:"
ss -tlnp | grep -E ':4222|:4223'

echo ""
echo "=========================================="
echo -e "  ${GREEN}✅ CONFIGURACIÓN COMPLETADA${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}🌐 URLs de acceso desde el cliente (192.168.1.5):${NC}"
echo -e "  ${GREEN}http://192.168.1.10:4222${NC}"
echo -e "  ${GREEN}https://192.168.1.10:4223${NC}"
echo -e "  ${GREEN}http://192.168.1.10:4222/info.php${NC}"
echo ""
echo -e "${YELLOW}📊 Ver logs de acceso del cliente:${NC}"
echo "  sudo tail -f /var/log/apache2/access.log"
echo "  sudo grep '192.168.1.5' /var/log/apache2/access.log"
echo ""
echo -e "${YELLOW}📁 Archivos:${NC}"
echo "  Web:      /var/www/html/"
echo "  Logs:     /var/log/apache2/"
echo "  SSL:      /etc/apache2/ssl/"
echo ""

cat > /root/server-info.txt << EOF
SERVIDOR APACHE - CONFIGURACIÓN FINAL
======================================
IP Servidor: 192.168.1.10
IP Cliente:  192.168.1.5
Puerto HTTP:  4222
Puerto HTTPS: 4223

ACCESO DESDE CLIENTE:
  http://192.168.1.10:4222
  https://192.168.1.10:4223

COMANDOS ÚTILES:
  Ver logs:     sudo tail -f /var/log/apache2/access.log
  Filtrar IP:   sudo grep "192.168.1.5" /var/log/apache2/access.log
  Reiniciar:    sudo systemctl restart apache2
  Estado:       sudo systemctl status apache2
EOF

print_msg "Resumen guardado en /root/server-info.txt"
