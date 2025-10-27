#!/bin/bash
# ============================================
# Script de instalación de entorno LAMP + Redis + Postgres + Mailpit
# Debian/Ubuntu — Versión profesional mejorada
# Autor: Sebastian Sotelo
# Versión: 2.0
# ============================================

set -e

USER_NAME="sebastian"
WEB_ROOT="/home/${USER_NAME}/proyectos/php"

# --------------------------------------------
# Funciones de log
# --------------------------------------------
log() { echo -e "\e[1;32m[✔]\e[0m $1"; }
log_warn() { echo -e "\e[1;33m[!]\e[0m $1"; }
log_error() { echo -e "\e[1;31m[✖]\e[0m $1"; }

# --------------------------------------------
# Banner
# --------------------------------------------
clear
echo "╔════════════════════════════════════════════╗"
echo "║   LAMP Stack Installer v2.0                ║"
echo "║   PHP + Apache + MySQL + PostgreSQL        ║"
echo "║   + Redis + Mailpit + Supervisor           ║"
echo "╚════════════════════════════════════════════╝"
echo

# --------------------------------------------
# Verificar y esperar bloqueos de apt
# --------------------------------------------
wait_for_apt() {
    local max_wait=300  # 5 minutos máximo
    local waited=0
    
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        if [ $waited -eq 0 ]; then
            log_warn "Otro proceso está usando apt. Esperando..."
        fi
        sleep 5
        waited=$((waited + 5))
        
        if [ $waited -ge $max_wait ]; then
            log_error "Timeout esperando por apt. Ejecuta: sudo kill \$(sudo lsof -t /var/lib/dpkg/lock-frontend)"
            exit 1
        fi
    done
    
    if [ $waited -gt 0 ]; then
        log "Bloqueo de apt liberado. Continuando..."
    fi
}

# --------------------------------------------
# Actualización del sistema
# --------------------------------------------
log "Actualizando sistema..."
wait_for_apt
sudo apt update -y && sudo apt upgrade -y

# --------------------------------------------
# Paquetes base
# --------------------------------------------
log "Instalando herramientas básicas..."
wait_for_apt
sudo apt install -y curl wget unzip git lsb-release ca-certificates \
    apt-transport-https software-properties-common gnupg vlc filezilla

# --------------------------------------------
# PHP + extensiones
# --------------------------------------------
log "Instalando PHP y extensiones..."
wait_for_apt
sudo apt install -y php php-cli php-fpm php-common php-dev \
    php-mbstring php-xml php-curl php-mysql php-pgsql php-zip php-gd \
    php-intl php-bcmath php-soap php-redis php-sqlite3

# Detectar versión de PHP instalada automáticamente
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
log "PHP detectado: versión ${PHP_VERSION}"

# Verificar que el servicio FPM existe
if systemctl list-unit-files | grep -q "php${PHP_VERSION}-fpm.service"; then
    sudo systemctl enable php${PHP_VERSION}-fpm
    sudo systemctl restart php${PHP_VERSION}-fpm
    log "PHP-FPM ${PHP_VERSION} habilitado y reiniciado"
else
    log_error "No se encontró php${PHP_VERSION}-fpm.service"
    log_warn "Buscando versiones alternativas de PHP-FPM..."
    
    # Buscar cualquier versión de PHP-FPM disponible
    FPM_SERVICE=$(systemctl list-unit-files | grep 'php.*-fpm' | head -n 1 | awk '{print $1}')
    if [ -n "$FPM_SERVICE" ]; then
        sudo systemctl enable $FPM_SERVICE
        sudo systemctl restart $FPM_SERVICE
        log "Usando $FPM_SERVICE"
    else
        log_error "No se encontró ningún servicio PHP-FPM disponible"
    fi
fi

# --------------------------------------------
# Apache
# --------------------------------------------
log "Instalando Apache..."
wait_for_apt
sudo apt install -y apache2 libapache2-mod-php

log "Habilitando módulos de Apache..."
sudo a2enmod proxy_fcgi setenvif rewrite headers ssl

log "Configurando PHP-FPM en Apache..."
sudo a2enconf php${PHP_VERSION}-fpm 2>/dev/null || log_warn "No se pudo auto-configurar PHP-FPM"

sudo systemctl enable apache2
sudo systemctl restart apache2

# Configuración del DocumentRoot
log "Configurando carpeta de proyectos..."
sudo mkdir -p ${WEB_ROOT}
sudo chown -R ${USER_NAME}:www-data ${WEB_ROOT}
sudo chmod -R 775 ${WEB_ROOT}

# Crear un index.php de prueba
cat > ${WEB_ROOT}/index.php <<'PHPEOF'
<?php
phpinfo();
PHPEOF
sudo chown ${USER_NAME}:www-data ${WEB_ROOT}/index.php

# --------------------------------------------
# MySQL
# --------------------------------------------
log "Instalando MySQL Server..."
wait_for_apt
sudo apt install -y mysql-server
sudo systemctl enable mysql
sudo systemctl start mysql

# Configuración usuario local (dejamos root sin tocar)
log "Configurando MySQL..."
log_warn "Dejando usuario root con autenticación por socket (más seguro)"

# Crear usuario de desarrollo si no existe
sudo mysql -e "CREATE USER IF NOT EXISTS '${USER_NAME}'@'localhost' IDENTIFIED BY 'dev2024';" 2>/dev/null || log_warn "Usuario MySQL ya existe"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${USER_NAME}'@'localhost' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"

log "Usuario MySQL creado: ${USER_NAME} / dev2024"

# --------------------------------------------
# PostgreSQL
# --------------------------------------------
log "Instalando PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Configurar usuario postgres
log "Configurando PostgreSQL..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'root';" 2>/dev/null || log_warn "Usuario postgres ya configurado"

# Crear usuario local si no existe
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${USER_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE ROLE ${USER_NAME} LOGIN SUPERUSER PASSWORD 'root';"

log "Usuarios PostgreSQL: postgres/root, ${USER_NAME}/root"

# --------------------------------------------
# Redis
# --------------------------------------------
log "Instalando Redis..."
sudo apt install -y redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server

# --------------------------------------------
# Mailpit
# --------------------------------------------
log "Instalando Mailpit..."

# Obtener URL con timeout
MAILPIT_URL=$(curl -s --max-time 10 https://api.github.com/repos/axllent/mailpit/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4)

if [ -z "$MAILPIT_URL" ]; then
    log_warn "No se pudo obtener la última versión desde GitHub"
    log "Usando versión directa v1.21.4..."
    MAILPIT_URL="https://github.com/axllent/mailpit/releases/download/v1.21.4/mailpit-linux-amd64.tar.gz"
fi

log "Descargando desde: $MAILPIT_URL"
wget --timeout=30 --tries=3 -qO mailpit.tar.gz "$MAILPIT_URL" 2>/dev/null || {
    log_error "No se pudo descargar Mailpit"
    log_warn "Saltando instalación de Mailpit (puedes instalarlo manualmente después)"
}

if [ -f mailpit.tar.gz ]; then
    tar -xzf mailpit.tar.gz
    sudo mv mailpit /usr/local/bin/
    sudo chmod +x /usr/local/bin/mailpit
    rm -f mailpit.tar.gz
    
    sudo tee /etc/systemd/system/mailpit.service > /dev/null <<EOF
[Unit]
Description=Mailpit Email Testing
After=network.target

[Service]
ExecStart=/usr/local/bin/mailpit
Restart=always
User=${USER_NAME}

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable mailpit
    sudo systemctl start mailpit
    log "Mailpit instalado correctamente"
else
    log_warn "Mailpit no se instaló. Para instalarlo manualmente:"
    echo "  curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | sudo bash"
fi

# --------------------------------------------
# Python + venv
# --------------------------------------------
log "Instalando Python y venv..."
wait_for_apt
sudo apt install -y python3 python3-pip python3-venv python3-dev

PYTHON_VERSION=$(python3 --version | awk '{print $2}')
log "Python instalado: versión ${PYTHON_VERSION}"

# --------------------------------------------
# Node.js (última versión LTS)
# --------------------------------------------
log "Instalando Node.js (última LTS)..."

# Instalar nvm (Node Version Manager) para el usuario
if [ ! -d "$HOME/.nvm" ]; then
    log "Descargando e instalando nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    
    # Cargar nvm en la sesión actual
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Instalar Node.js LTS
    log "Instalando Node.js LTS..."
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
    
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    log "Node.js instalado: ${NODE_VERSION}"
    log "npm instalado: ${NPM_VERSION}"
else
    log_warn "nvm ya está instalado"
fi

# --------------------------------------------
# Docker
# --------------------------------------------
log "Instalando Docker..."

# Desinstalar versiones antiguas si existen
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Instalar dependencias
wait_for_apt
sudo apt install -y ca-certificates curl gnupg lsb-release

# Agregar clave GPG oficial de Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Detectar si es Linux Mint y usar base Ubuntu correspondiente
if [ -f /etc/linuxmint/info ]; then
    log_warn "Linux Mint detectado, usando repositorio de Ubuntu compatible"
    # Linux Mint 22 (Wilma) = Ubuntu 24.04 (Noble)
    # Linux Mint 21 (Victoria/Vanessa/Vera/Virginia) = Ubuntu 22.04 (Jammy)
    MINT_VERSION=$(grep RELEASE /etc/linuxmint/info | cut -d= -f2)
    if [[ "$MINT_VERSION" == 22* ]]; then
        UBUNTU_CODENAME="noble"
    elif [[ "$MINT_VERSION" == 21* ]]; then
        UBUNTU_CODENAME="jammy"
    else
        UBUNTU_CODENAME="jammy"  # fallback
    fi
    log "Usando Ubuntu codename: $UBUNTU_CODENAME"
else
    # Si es Ubuntu directamente
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
fi

# Agregar repositorio de Docker
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  ${UBUNTU_CODENAME} stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker Engine
log "Instalando Docker Engine..."
wait_for_apt
sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Iniciar y habilitar Docker
sudo systemctl enable docker
sudo systemctl start docker

# Agregar usuario al grupo docker
sudo usermod -aG docker ${USER_NAME}
log "Usuario ${USER_NAME} agregado al grupo docker"

DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
log "Docker instalado: versión ${DOCKER_VERSION}"

# --------------------------------------------
# Portainer
# --------------------------------------------
log "Instalando Portainer..."

# Crear volumen para datos de Portainer
docker volume create portainer_data

# Instalar Portainer CE (Community Edition)
docker run -d \
  -p 8000:8000 \
  -p 9443:9443 \
  --name portainer \
  --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest

log "Portainer instalado correctamente"
log "Accede a Portainer en: https://localhost:9443"

# --------------------------------------------
# Supervisor
# --------------------------------------------
log "Instalando Supervisor..."
wait_for_apt
sudo apt install -y supervisor
sudo systemctl enable supervisor
sudo systemctl start supervisor

# --------------------------------------------
# Configurar PHP para desarrollo
# --------------------------------------------
log "Configurando PHP para desarrollo..."
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"

if [ -f "$PHP_INI" ]; then
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sudo sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sudo sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    sudo systemctl restart php${PHP_VERSION}-fpm
    log "PHP configurado para desarrollo (64MB uploads, 256MB memory)"
fi

# --------------------------------------------
# Limpieza
# --------------------------------------------
log "Limpiando paquetes innecesarios..."
sudo apt autoremove -y
sudo apt autoclean -y

# --------------------------------------------
# Resumen final
# --------------------------------------------
echo
echo "╔════════════════════════════════════════════╗"
echo "║        ✅ INSTALACIÓN COMPLETA ✅          ║"
echo "╚════════════════════════════════════════════╝"
echo
echo "📦 Servicios instalados y funcionando:"
echo "  ✓ Apache2 + PHP ${PHP_VERSION}"
echo "  ✓ MySQL (usuario: ${USER_NAME}/dev2024) - root usa socket"
echo "  ✓ PostgreSQL (usuario: postgres/root, ${USER_NAME}/root)"
echo "  ✓ Redis Server"
if [ -f /usr/local/bin/mailpit ]; then
    echo "  ✓ Mailpit (http://localhost:8025)"
else
    echo "  ⚠ Mailpit (no instalado)"
fi
echo "  ✓ Supervisor"
echo "  ✓ Python ${PYTHON_VERSION} + venv"
if command -v node &> /dev/null; then
    echo "  ✓ Node.js $(node --version) + npm $(npm --version)"
else
    echo "  ⚠ Node.js (requiere reiniciar terminal)"
fi
if command -v docker &> /dev/null; then
    echo "  ✓ Docker ${DOCKER_VERSION}"
    echo "  ✓ Portainer (https://localhost:9443)"
else
    echo "  ⚠ Docker (no instalado)"
fi
echo
echo "📁 Carpeta de proyectos: ${WEB_ROOT}"
echo "   Archivo de prueba: http://localhost/index.php"
echo
echo "🔧 Comandos útiles:"
echo "  • Reiniciar Apache:     sudo systemctl restart apache2"
echo "  • Reiniciar PHP-FPM:    sudo systemctl restart php${PHP_VERSION}-fpm"
echo "  • Ver logs Apache:      sudo tail -f /var/log/apache2/error.log"
echo "  • MySQL CLI:            mysql -u ${USER_NAME} -p"
echo "  • PostgreSQL CLI:       psql -U ${USER_NAME}"
echo "  • Redis CLI:            redis-cli"
echo "  • Crear venv Python:    python3 -m venv mi_entorno"
echo "  • Node.js version:      node --version"
echo "  • npm version:          npm --version"
echo "  • Docker version:       docker --version"
echo "  • Docker Compose:       docker compose --version"
echo "  • Ver contenedores:     docker ps"
echo
echo "📊 Verificar estado de servicios:"
echo "  sudo systemctl status apache2"
echo "  sudo systemctl status mysql"
echo "  sudo systemctl status postgresql"
echo "  sudo systemctl status redis-server"
if [ -f /usr/local/bin/mailpit ]; then
    echo "  sudo systemctl status mailpit"
fi
echo
echo "🔐 Credenciales:"
echo "  MySQL:      ${USER_NAME} / dev2024"
echo "  PostgreSQL: ${USER_NAME} / root"
echo "  Portainer:  https://localhost:9443 (crear usuario en primer acceso)"
echo
echo "⚠️  IMPORTANTE:"
echo "  • Cierra y abre tu terminal para usar Node.js/npm y Docker sin sudo"
echo "  • Portainer puede tardar 1-2 min en iniciar la primera vez"
echo
log "¡Listo para desarrollar! 🚀"
