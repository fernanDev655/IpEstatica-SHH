#!/bin/bash

# ============================================
# Script de Instalación PostgreSQL - AutoElite
# Servidor BD:  192.168.1.20
# Servidor Web: 192.168.1.10
# Puerto PG:    5432
# Puerto SSH:   4223
# ============================================

set -euo pipefail

# --- CONFIGURACIÓN ---
DB_SERVER_IP="192.168.1.20"
WEB_SERVER_IP="192.168.1.10"
SSH_PORT="4223"
PG_PORT="5432"

DB_NAME="autoelite_db"
DB_ADMIN="admin_autoelite"
DB_APP_USER="app_autoelite"
DB_READONLY="readonly_autoelite"
IMPORTS_DIR="/home/postgres/imports"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}============================================${NC}"; \
                echo -e "${BLUE}  $1${NC}"; \
                echo -e "${BLUE}============================================${NC}"; }

if [[ $EUID -ne 0 ]]; then
    log_error "Este script debe ejecutarse como root. Usa: sudo $0"
    exit 1
fi

log_section "INSTALACIÓN POSTGRESQL - AutoElite"
echo -e "  Servidor BD:  ${GREEN}$DB_SERVER_IP${NC}"
echo -e "  Servidor Web: ${YELLOW}$WEB_SERVER_IP${NC}"
echo -e "  Puerto PG:    ${GREEN}$PG_PORT${NC}"
echo ""

# ============================================
# 1. INSTALAR POSTGRESQL
# ============================================
log_section "PASO 1/4 - INSTALACIÓN"

log_info "Actualizando paquetes..."
apt update -qq && apt upgrade -y -qq

log_info "Instalando PostgreSQL..."
apt install -y postgresql postgresql-contrib

systemctl enable postgresql
systemctl start postgresql

if systemctl is-active --quiet postgresql; then
    log_info "✅ PostgreSQL activo y habilitado al inicio."
else
    log_error "PostgreSQL no se ha iniciado correctamente."
    exit 1
fi

PG_VERSION=$(psql --version | awk '{print $3}' | cut -d'.' -f1)
log_info "Versión instalada: PostgreSQL $PG_VERSION"

# ============================================
# 2. CREAR ROLES
# ============================================
log_section "PASO 2/4 - CREACIÓN DE ROLES"

log_warn "Introduce las contraseñas para los 3 roles:"

echo -n "  Contraseña para '$DB_ADMIN' (administrador/superusuario): "
read -s PASS_ADMIN; echo
echo -n "  Contraseña para '$DB_APP_USER' (aplicación web): "
read -s PASS_APP; echo
echo -n "  Contraseña para '$DB_READONLY' (solo lectura): "
read -s PASS_RO; echo

sudo -u postgres psql << EOF

-- ROL 1: Administrador superusuario
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_ADMIN') THEN
        CREATE ROLE $DB_ADMIN WITH LOGIN PASSWORD '$PASS_ADMIN'
            SUPERUSER CREATEDB CREATEROLE;
        RAISE NOTICE 'Rol $DB_ADMIN creado.';
    ELSE
        RAISE NOTICE 'Rol $DB_ADMIN ya existe.';
    END IF;
END
\$\$;

-- ROL 2: Usuario de aplicación (lectura + escritura)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_APP_USER') THEN
        CREATE ROLE $DB_APP_USER WITH LOGIN PASSWORD '$PASS_APP'
            NOSUPERUSER NOCREATEDB NOCREATEROLE;
        RAISE NOTICE 'Rol $DB_APP_USER creado.';
    ELSE
        RAISE NOTICE 'Rol $DB_APP_USER ya existe.';
    END IF;
END
\$\$;

-- ROL 3: Solo lectura
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_READONLY') THEN
        CREATE ROLE $DB_READONLY WITH LOGIN PASSWORD '$PASS_RO'
            NOSUPERUSER NOCREATEDB NOCREATEROLE;
        RAISE NOTICE 'Rol $DB_READONLY creado.';
    ELSE
        RAISE NOTICE 'Rol $DB_READONLY ya existe.';
    END IF;
END
\$\$;

-- Verificar roles creados
\du

EOF

log_info "Roles creados correctamente."

# ============================================
# 3. CREAR BD, PERMISOS E IMPORTAR
# ============================================
log_section "PASO 3/4 - BASE DE DATOS E IMPORTACIÓN"

# Crear base de datos
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
    sudo -u postgres createdb -O "$DB_ADMIN" "$DB_NAME"
log_info "Base de datos '$DB_NAME' lista."

# Asignar permisos
sudo -u postgres psql -d "$DB_NAME" << EOF

-- app_user: lectura y escritura
GRANT CONNECT ON DATABASE $DB_NAME TO $DB_APP_USER;
GRANT USAGE ON SCHEMA public TO $DB_APP_USER;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $DB_APP_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $DB_APP_USER;

-- readonly: solo lectura
GRANT CONNECT ON DATABASE $DB_NAME TO $DB_READONLY;
GRANT USAGE ON SCHEMA public TO $DB_READONLY;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO $DB_READONLY;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO $DB_READONLY;

EOF
log_info "Permisos asignados."

# Crear carpeta de importaciones
mkdir -p "$IMPORTS_DIR"
chown postgres:postgres "$IMPORTS_DIR"
chmod 750 "$IMPORTS_DIR"
log_info "Carpeta de importaciones: $IMPORTS_DIR"

# Importar .sql si ya existe alguno
SQL_FILES=("$IMPORTS_DIR"/*.sql)
if [ -f "${SQL_FILES[0]}" ]; then
    for SQL_FILE in "${SQL_FILES[@]}"; do
        log_info "Importando: $(basename $SQL_FILE)..."
        sudo -u postgres psql -d "$DB_NAME" -f "$SQL_FILE"
        log_info "✅ Importado: $(basename $SQL_FILE)"
    done
else
    log_warn "No hay archivos .sql en $IMPORTS_DIR todavía."
    log_warn "Cuando tengas el backup de pgAdmin, cópialo así:"
    echo ""
    echo "  scp -P $SSH_PORT archivo.sql adminseguro@$DB_SERVER_IP:$IMPORTS_DIR/"
    echo "  sudo -u postgres psql -d $DB_NAME -f $IMPORTS_DIR/archivo.sql"
    echo ""
fi

# ============================================
# 4. ACCESO REMOTO DESDE EL SERVIDOR WEB
# ============================================
log_section "PASO 4/4 - ACCESO REMOTO"

PG_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"

cp "$PG_CONF" "${PG_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$PG_HBA"  "${PG_HBA}.backup.$(date +%Y%m%d_%H%M%S)"
log_info "Backups de configuración creados."

# Escuchar en la IP del servidor BD
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '$DB_SERVER_IP'/" "$PG_CONF"
log_info "PostgreSQL escuchará en $DB_SERVER_IP."

# Permitir conexión del servidor web solo para los roles de app
cat >> "$PG_HBA" << EOF

# AutoElite - Acceso desde servidor web ($WEB_SERVER_IP)
host    $DB_NAME    $DB_APP_USER    $WEB_SERVER_IP/32    md5
host    $DB_NAME    $DB_READONLY    $WEB_SERVER_IP/32    md5
EOF
log_info "pg_hba.conf: acceso autorizado desde $WEB_SERVER_IP."

systemctl restart postgresql
log_info "PostgreSQL reiniciado."

# ============================================
# VERIFICACIÓN FINAL
# ============================================
log_section "VERIFICACIÓN FINAL"

log_info "Puerto en escucha:"
ss -tlnp | grep ":$PG_PORT" || log_warn "Puerto $PG_PORT no detectado aún."

log_info "Bases de datos:"
sudo -u postgres psql -c "\l"

log_info "Roles:"
sudo -u postgres psql -c "\du"

echo ""
echo "=========================================================="
echo -e "${GREEN}  ✅ POSTGRESQL CONFIGURADO CORRECTAMENTE${NC}"
echo "=========================================================="
echo ""
echo -e "  🖥️  Servidor BD:       ${GREEN}$DB_SERVER_IP${NC}"
echo -e "  🌐  Servidor Web:      ${YELLOW}$WEB_SERVER_IP${NC}"
echo -e "  🐘  Puerto PG:         ${GREEN}$PG_PORT${NC}"
echo -e "  🔒  Puerto SSH:        ${GREEN}$SSH_PORT${NC}"
echo ""
echo -e "  📦  Base de datos:     ${GREEN}$DB_NAME${NC}"
echo ""
echo -e "  👥  Roles:"
echo -e "      ${RED}$DB_ADMIN${NC}     → superusuario (solo administración)"
echo -e "      ${GREEN}$DB_APP_USER${NC}    → lectura/escritura (para la web)"
echo -e "      ${YELLOW}$DB_READONLY${NC} → solo lectura (informes)"
echo ""
echo -e "  📁  Importaciones:     $IMPORTS_DIR"
echo ""
echo -e "  📝  Conexión desde el servidor web:"
echo -e "      ${GREEN}psql -h $DB_SERVER_IP -p $PG_PORT -U $DB_APP_USER -d $DB_NAME${NC}"
echo ""
echo "=========================================================="
log_warn "Usa '$DB_ADMIN' solo para administración, nunca en la app web."
