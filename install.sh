#!/bin/bash
# ============================================
# Script de instalación de entorno LAMP + Redis + Postgres + Mailpit
# Debian/Ubuntu — Versión profesional mejorada
# Autor: Sebastian Sotelo
# Versión: 2.2 (con mejoras esenciales)
# ============================================

set -e

# Detectar el usuario que ejecuta el script (no root)
if [ "$EUID" -eq 0 ]; then 
    # Si se ejecuta con sudo, obtener el usuario real
    USER_NAME="${SUDO_USER:-$USER}"
else
    # Si se ejecuta sin sudo, usar el usuario actual
    USER_NAME="$USER"
fi

WEB_ROOT="/home/${USER_NAME}/proyectos/php"
TIMEZONE="America/Santiago"  # Ajusta según tu zona horaria

# Verificar que el usuario existe
if ! id "$USER_NAME" &>/dev/null; then
    echo "Error: El usuario $USER_NAME no existe en el sistema"
    exit 1
fi

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
echo "║   LAMP Stack Installer v2.2                ║"
echo "║   Instalador Automatizado de Entorno       ║"
echo "║   de Desarrollo Web Profesional            ║"
echo "╚════════════════════════════════════════════╝"
echo
echo "👤 Usuario detectado: ${USER_NAME}"
echo "📁 Directorio de trabajo: ${WEB_ROOT}"
echo "🌍 Zona horaria: ${TIMEZONE}"
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
# Limpiar repositorios antiguos de Docker
# --------------------------------------------
log "Verificando repositorios previos de Docker..."
if [ -f /etc/apt/sources.list.d/docker.list ]; then
    log_warn "Detectado repositorio antiguo de Docker, eliminando para evitar conflictos..."
    sudo rm -f /etc/apt/sources.list.d/docker.list
fi

# --------------------------------------------
# Actualización del sistema
# --------------------------------------------
log "Actualizando índice de paquetes del sistema..."
wait_for_apt
sudo apt update -y && sudo apt upgrade -y

# --------------------------------------------
# Paquetes base + utilidades esenciales
# --------------------------------------------
log "Instalando paquetes base y utilidades del sistema..."
wait_for_apt

# Detectar si es Debian o Ubuntu para instalar paquetes correctos
OS_ID=$(. /etc/os-release && echo "$ID")

if [ "$OS_ID" = "debian" ]; then
    # Paquetes para Debian
    sudo apt install -y curl wget unzip git lsb-release ca-certificates \
        apt-transport-https gnupg vlc filezilla \
        build-essential net-tools htop ncdu
    log "Paquetes del sistema instalados correctamente (Debian)"
else
    # Paquetes para Ubuntu/Mint
    sudo apt install -y curl wget unzip git lsb-release ca-certificates \
        apt-transport-https software-properties-common gnupg vlc filezilla \
        build-essential net-tools htop ncdu
    log "Paquetes del sistema instalados correctamente (Ubuntu/Mint)"
fi

# --------------------------------------------
# PHP + extensiones
# --------------------------------------------
log "Instalando PHP con extensiones para desarrollo web..."
wait_for_apt
sudo apt install -y php php-cli php-fpm php-common php-dev \
    php-mbstring php-xml php-curl php-mysql php-pgsql php-zip php-gd \
    php-intl php-bcmath php-soap php-redis php-sqlite3

# Detectar versión de PHP instalada automáticamente
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
log "PHP ${PHP_VERSION} instalado correctamente"

# Verificar que el servicio FPM existe
if systemctl list-unit-files | grep -q "php${PHP_VERSION}-fpm.service"; then
    sudo systemctl enable php${PHP_VERSION}-fpm
    sudo systemctl restart php${PHP_VERSION}-fpm
    log "Servicio PHP-FPM ${PHP_VERSION} iniciado y configurado para arranque automático"
else
    log_error "No se encontró el servicio php${PHP_VERSION}-fpm.service"
    log_warn "Buscando servicios PHP-FPM alternativos en el sistema..."
    
    # Buscar cualquier versión de PHP-FPM disponible
    FPM_SERVICE=$(systemctl list-unit-files | grep 'php.*-fpm' | head -n 1 | awk '{print $1}')
    if [ -n "$FPM_SERVICE" ]; then
        sudo systemctl enable $FPM_SERVICE
        sudo systemctl restart $FPM_SERVICE
        log "Servicio alternativo configurado: $FPM_SERVICE"
    else
        log_error "No se encontró ningún servicio PHP-FPM disponible en el sistema"
    fi
fi

# --------------------------------------------
# Configurar PHP para desarrollo
# --------------------------------------------
log "Optimizando configuración de PHP para entorno de desarrollo..."
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
PHP_CLI_INI="/etc/php/${PHP_VERSION}/cli/php.ini"

if [ -f "$PHP_INI" ]; then
    sudo sed -i "s|^;date.timezone =.*|date.timezone = ${TIMEZONE}|" "$PHP_INI"
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sudo sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sudo sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI"
    sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI"
    log "PHP-FPM configurado: Timezone=${TIMEZONE}, Upload=64MB, Memory=256MB, MaxTime=300s"
fi

if [ -f "$PHP_CLI_INI" ]; then
    sudo sed -i "s|^;date.timezone =.*|date.timezone = ${TIMEZONE}|" "$PHP_CLI_INI"
    log "PHP-CLI configurado con zona horaria: ${TIMEZONE}"
fi

sudo systemctl restart php${PHP_VERSION}-fpm

# --------------------------------------------
# Apache
# --------------------------------------------
log "Instalando servidor web Apache con módulo PHP..."
wait_for_apt
sudo apt install -y apache2 libapache2-mod-php

log "Habilitando módulos esenciales de Apache (rewrite, headers, SSL, proxy)..."
sudo a2enmod proxy_fcgi setenvif rewrite headers ssl

log "Integrando PHP-FPM con Apache..."
sudo a2enconf php${PHP_VERSION}-fpm 2>/dev/null || log_warn "Configuración automática PHP-FPM no disponible"

sudo systemctl enable apache2
sudo systemctl restart apache2
log "Apache iniciado correctamente en http://localhost"

# Configuración del DocumentRoot
log "Configurando directorio de proyectos web..."
sudo mkdir -p ${WEB_ROOT}
sudo chown -R ${USER_NAME}:www-data ${WEB_ROOT}
sudo chmod -R 775 ${WEB_ROOT}
log "Directorio creado: ${WEB_ROOT} (usuario: ${USER_NAME}, grupo: www-data)"

# Crear un index.php de prueba
cat > ${WEB_ROOT}/index.php <<'PHPEOF'
<?php
phpinfo();
PHPEOF
sudo chown ${USER_NAME}:www-data ${WEB_ROOT}/index.php
log "Archivo de prueba creado: ${WEB_ROOT}/index.php"

# --------------------------------------------
# VirtualHost ejemplo
# --------------------------------------------
log "Creando plantilla de VirtualHost para proyectos..."

sudo tee /etc/apache2/sites-available/proyecto-ejemplo.conf > /dev/null <<VHOSTEOF
<VirtualHost *:80>
    ServerName proyecto.local
    ServerAlias www.proyecto.local
    
    DocumentRoot ${WEB_ROOT}/proyecto
    
    <Directory ${WEB_ROOT}/proyecto>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/proyecto-error.log
    CustomLog \${APACHE_LOG_DIR}/proyecto-access.log combined
</VirtualHost>
VHOSTEOF

log "Plantilla de VirtualHost guardada en: /etc/apache2/sites-available/proyecto-ejemplo.conf"
log_warn "Para activar: sudo a2ensite proyecto-ejemplo.conf && sudo systemctl reload apache2"

# --------------------------------------------
# MariaDB
# --------------------------------------------
log "Instalando sistema de gestión de bases de datos MariaDB..."
wait_for_apt

# Configurar instalación no interactiva
export DEBIAN_FRONTEND=noninteractive

# Pre-configurar la contraseña de root para MariaDB
sudo debconf-set-selections <<< "mariadb-server mysql-server/root_password password root"
sudo debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password root"

sudo apt install -y mariadb-server mariadb-client

sudo systemctl enable mariadb
sudo systemctl start mariadb

# Esperar a que MariaDB esté listo
log "Esperando inicialización completa del servicio MariaDB..."
sleep 3

# Configuración de MariaDB
log "Aplicando configuración de seguridad básica a MariaDB..."

# Asegurar que root tiene contraseña
sudo mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';" 2>/dev/null || true
sudo mariadb -u root -proot -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Crear usuario de desarrollo
log "Creando usuario de desarrollo para MariaDB..."
sudo mariadb -u root -proot <<MARIADB_SCRIPT 2>/dev/null || log_warn "Algunas configuraciones ya existían"
-- Crear usuario si no existe
CREATE USER IF NOT EXISTS '${USER_NAME}'@'localhost' IDENTIFIED BY 'dev2024';
GRANT ALL PRIVILEGES ON *.* TO '${USER_NAME}'@'localhost' WITH GRANT OPTION;

-- Eliminar usuarios anónimos
DELETE FROM mysql.user WHERE User='';

-- Deshabilitar acceso remoto de root
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Eliminar base de datos de prueba
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Aplicar cambios
FLUSH PRIVILEGES;
MARIADB_SCRIPT

log "MariaDB configurado: Usuario '${USER_NAME}' creado con privilegios completos"
log "Credenciales → ${USER_NAME}/dev2024 | root/root"

# --------------------------------------------
# PostgreSQL
# --------------------------------------------
log "Instalando sistema de gestión de bases de datos PostgreSQL..."
wait_for_apt
sudo apt install -y postgresql postgresql-contrib
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Configurar usuario postgres
log "Configurando PostgreSQL con usuarios de desarrollo..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'root';" 2>/dev/null || log_warn "Usuario postgres ya configurado"

# Crear usuario local si no existe
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${USER_NAME}'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE ROLE ${USER_NAME} LOGIN SUPERUSER PASSWORD 'root';"

log "PostgreSQL configurado: Usuarios 'postgres' y '${USER_NAME}' con contraseña 'root'"

# --------------------------------------------
# Redis
# --------------------------------------------
log "Instalando Redis Server (sistema de caché en memoria)..."
wait_for_apt
sudo apt install -y redis-server
sudo systemctl enable redis-server
sudo systemctl start redis-server
log "Redis Server iniciado en localhost:6379"

# --------------------------------------------
# Composer (PHP Package Manager)
# --------------------------------------------
log "Instalando Composer (gestor de dependencias PHP)..."

EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
    log_error 'ERROR: Verificación de integridad de Composer falló (checksum inválido)'
    rm composer-setup.php
else
    php composer-setup.php --quiet
    rm composer-setup.php
    sudo mv composer.phar /usr/local/bin/composer
    sudo chmod +x /usr/local/bin/composer
    
    COMPOSER_VERSION=$(composer --version | awk '{print $3}')
    log "Composer ${COMPOSER_VERSION} instalado globalmente en /usr/local/bin/composer"
fi

# --------------------------------------------
# Adminer (gestión de bases de datos)
# --------------------------------------------
log "Instalando Adminer (gestor web de bases de datos)..."

sudo mkdir -p ${WEB_ROOT}/adminer
wget -q "https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php" -O ${WEB_ROOT}/adminer/index.php
sudo chown -R ${USER_NAME}:www-data ${WEB_ROOT}/adminer

log "Adminer 4.8.1 instalado y accesible en: http://localhost/adminer/"

# --------------------------------------------
# Mailpit
# --------------------------------------------
log "Instalando Mailpit (capturador de emails para desarrollo)..."

# Obtener URL con timeout
MAILPIT_URL=$(curl -s --max-time 10 https://api.github.com/repos/axllent/mailpit/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4)

if [ -z "$MAILPIT_URL" ]; then
    log_warn "No se pudo obtener la última versión desde GitHub API"
    log "Usando versión estable v1.21.4 como respaldo..."
    MAILPIT_URL="https://github.com/axllent/mailpit/releases/download/v1.21.4/mailpit-linux-amd64.tar.gz"
fi

log "Descargando Mailpit desde: $MAILPIT_URL"
wget --timeout=30 --tries=3 -qO mailpit.tar.gz "$MAILPIT_URL" 2>/dev/null || {
    log_error "No se pudo descargar Mailpit (sin conexión o servidor inaccesible)"
    log_warn "Mailpit no se instalará. Instalación manual: curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | sudo bash"
}

if [ -f mailpit.tar.gz ]; then
    tar -xzf mailpit.tar.gz
    sudo mv mailpit /usr/local/bin/
    sudo chmod +x /usr/local/bin/mailpit
    rm -f mailpit.tar.gz
    
    sudo tee /etc/systemd/system/mailpit.service > /dev/null <<EOF
[Unit]
Description=Mailpit Email Testing Service
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
    log "Mailpit instalado y accesible en: http://localhost:8025"
else
    log_warn "Mailpit omitido (archivo no descargado)"
fi

# --------------------------------------------
# Python + venv
# --------------------------------------------
log "Instalando Python 3 con soporte para entornos virtuales..."
wait_for_apt
sudo apt install -y python3 python3-pip python3-venv python3-dev

PYTHON_VERSION=$(python3 --version | awk '{print $2}')
log "Python ${PYTHON_VERSION} instalado con pip y venv"

# --------------------------------------------
# Node.js (última versión LTS)
# --------------------------------------------
log "Instalando Node.js LTS mediante Node Version Manager (nvm)..."

# Instalar nvm (Node Version Manager) para el usuario
if [ ! -d "$HOME/.nvm" ]; then
    log "Descargando e instalando nvm v0.40.1..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    
    # Cargar nvm en la sesión actual
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # Instalar Node.js LTS
    log "Instalando versión LTS de Node.js..."
    nvm install --lts
    nvm use --lts
    nvm alias default 'lts/*'
    
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    log "Node.js ${NODE_VERSION} instalado"
    log "npm ${NPM_VERSION} instalado"
else
    log_warn "nvm ya está instalado en el sistema"
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

# Detectar sistema operativo
OS_ID=$(. /etc/os-release && echo "$ID")
OS_VERSION_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

if [ "$OS_ID" = "debian" ]; then
    log "Debian detectado (versión: $OS_VERSION_CODENAME)"
    
    # Para Debian Trixie (13) o Testing, usar Bookworm (12)
    if [ "$OS_VERSION_CODENAME" = "trixie" ] || [ "$OS_VERSION_CODENAME" = "sid" ]; then
        DOCKER_CODENAME="bookworm"
        log_warn "Debian Trixie/Sid detectado, usando repositorio de Bookworm"
    else
        DOCKER_CODENAME="$OS_VERSION_CODENAME"
    fi
    
    # Descargar clave GPG de Docker para Debian
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Agregar repositorio de Docker para Debian
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      ${DOCKER_CODENAME} stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log "Usando repositorio Docker para Debian ${DOCKER_CODENAME}"
    
elif [ -f /etc/linuxmint/info ]; then
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
    
    # Descargar clave GPG de Docker para Ubuntu
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Agregar repositorio de Docker para Ubuntu
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      ${UBUNTU_CODENAME} stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log "Usando Ubuntu codename: $UBUNTU_CODENAME"
    
else
    # Ubuntu o derivados
    UBUNTU_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    
    # Descargar clave GPG de Docker para Ubuntu
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Agregar repositorio de Docker para Ubuntu
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      ${UBUNTU_CODENAME} stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log "Ubuntu detectado: $UBUNTU_CODENAME"
fi

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

# Verificar si Portainer ya existe
if sudo docker ps -a --format '{{.Names}}' | grep -q '^portainer

# --------------------------------------------
# Supervisor
# --------------------------------------------
log "Instalando Supervisor..."
wait_for_apt
sudo apt install -y supervisor
sudo systemctl enable supervisor
sudo systemctl start supervisor

# --------------------------------------------
# Configuración de Git
# --------------------------------------------
log "Verificando configuración global de Git..."

GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    log_warn "Git no está configurado con identidad de usuario"
    echo ""
    echo "📝 Configura Git después de la instalación con estos comandos:"
    echo "   git config --global user.name \"Tu Nombre Completo\""
    echo "   git config --global user.email \"tu@email.com\""
    echo ""
else
    log "Git ya configurado → Nombre: ${GIT_NAME} | Email: ${GIT_EMAIL}"
fi

# --------------------------------------------
# Limpieza
# --------------------------------------------
log "Limpiando paquetes y archivos temporales del sistema..."
sudo apt autoremove -y
sudo apt autoclean -y
log "Limpieza completada (espacio liberado en disco)"

# --------------------------------------------
# Verificación post-instalación
# --------------------------------------------
log "Ejecutando verificación de servicios instalados..."
echo ""

check_service() {
    if systemctl is-active --quiet $1; then
        echo "  ✅ $1 → Activo y en ejecución"
    else
        echo "  ❌ $1 → No está en ejecución (verificar manualmente)"
    fi
}

check_service apache2
check_service mariadb
check_service postgresql
check_service redis-server
check_service docker

if [ -f /usr/local/bin/mailpit ]; then
    check_service mailpit
fi

check_service supervisor

echo ""

# Verificar comandos disponibles
check_command() {
    if command -v $1 &> /dev/null; then
        VERSION=$($1 --version 2>&1 | head -n 1)
        echo "  ✅ $1 → ${VERSION}"
    else
        echo "  ❌ $1 → No disponible en el sistema"
    fi
}

log "Verificando herramientas de línea de comandos..."
check_command php
check_command composer
check_command python3
check_command docker

if command -v node &> /dev/null; then
    echo "  ✅ node → $(node --version)"
    echo "  ✅ npm → $(npm --version)"
else
    echo "  ⚠️  node/npm → Disponible tras reiniciar la terminal"
fi

# --------------------------------------------
# Resumen final
# --------------------------------------------
echo
echo "╔════════════════════════════════════════════╗"
echo "║     ✅ INSTALACIÓN FINALIZADA ✅           ║"
echo "║   Entorno de Desarrollo Web Completo       ║"
echo "╚════════════════════════════════════════════╝"
echo
echo "🎉 Stack LAMP instalado y configurado:"
echo "  ✓ Apache 2 + PHP ${PHP_VERSION} (FPM habilitado)"
echo "  ✓ MariaDB → Usuario: ${USER_NAME}/dev2024 | root/root"
echo "  ✓ PostgreSQL → Usuario: ${USER_NAME}/root | postgres/root"
echo "  ✓ Redis Server → localhost:6379"
if [ -f /usr/local/bin/mailpit ]; then
    echo "  ✓ Mailpit → http://localhost:8025 (captura emails)"
else
    echo "  ⚠ Mailpit → No instalado (opcional)"
fi
echo "  ✓ Supervisor → Gestor de procesos"
if command -v composer &> /dev/null; then
    COMPOSER_VERSION=$(composer --version 2>/dev/null | awk '{print $3}')
    echo "  ✓ Composer ${COMPOSER_VERSION} → Gestor de paquetes PHP"
else
    echo "  ✓ Composer → Instalado globalmente"
fi
echo "  ✓ Adminer 4.8.1 → http://localhost/adminer/ (gestor DB)"
echo "  ✓ Python ${PYTHON_VERSION} → Con pip y venv"
if command -v node &> /dev/null; then
    echo "  ✓ Node.js $(node --version) → Con npm $(npm --version)"
else
    echo "  ⚠ Node.js → Disponible tras reiniciar terminal"
fi
echo "  ✓ Docker ${DOCKER_VERSION} → Con Docker Compose"
echo "  ✓ Portainer CE → https://localhost:9443 (gestor Docker)"
echo
echo "📂 Directorio de trabajo configurado:"
echo "   ${WEB_ROOT}"
echo "   • Propietario: ${USER_NAME}:www-data"
echo "   • Permisos: 775 (lectura/escritura para desarrollo)"
echo
echo "🌐 URLs de acceso rápido:"
echo "   • Servidor web:     http://localhost"
echo "   • Información PHP:  http://localhost/index.php"
echo "   • Adminer (DB):     http://localhost/adminer/"
if [ -f /usr/local/bin/mailpit ]; then
    echo "   • Mailpit (emails): http://localhost:8025"
fi
echo "   • Portainer:        https://localhost:9443"
echo
echo "🔐 Credenciales de acceso a bases de datos:"
echo "   MariaDB:"
echo "     • Usuario desarrollo: ${USER_NAME} | Contraseña: dev2024"
echo "     • Usuario root:       root | Contraseña: root"
echo "   PostgreSQL:"
echo "     • Usuario desarrollo: ${USER_NAME} | Contraseña: root"
echo "     • Usuario sistema:    postgres | Contraseña: root"
echo
echo "💻 Comandos útiles para el día a día:"
echo "   Gestión de servicios:"
echo "     sudo systemctl restart apache2       # Reiniciar servidor web"
echo "     sudo systemctl restart php${PHP_VERSION}-fpm  # Reiniciar PHP"
echo "     sudo systemctl status mariadb        # Ver estado MariaDB"
echo "     sudo systemctl status postgresql     # Ver estado PostgreSQL"
echo
echo "   Acceso a bases de datos:"
echo "     mariadb -u ${USER_NAME} -p          # Conectar a MariaDB"
echo "     sudo mariadb -u root -p              # MariaDB como root"
echo "     psql -U ${USER_NAME}                 # Conectar a PostgreSQL"
echo "     redis-cli                            # Cliente Redis"
echo
echo "   Desarrollo PHP:"
echo "     composer install                     # Instalar dependencias"
echo "     composer require vendor/package      # Agregar paquete"
echo "     php artisan serve                    # Laravel dev server"
echo
echo "   Docker:"
echo "     docker ps                            # Ver contenedores activos"
echo "     docker compose up -d                 # Iniciar proyecto"
echo "     docker logs nombre_contenedor        # Ver logs"
echo
echo "   Python:"
echo "     python3 -m venv mi_entorno           # Crear entorno virtual"
echo "     source mi_entorno/bin/activate       # Activar entorno"
echo
echo "📊 Verificar estado del sistema:"
echo "     sudo systemctl status apache2"
echo "     sudo systemctl status mariadb"
echo "     sudo systemctl status postgresql"
echo "     sudo systemctl status redis-server"
echo "     sudo systemctl status docker"
if [ -f /usr/local/bin/mailpit ]; then
    echo "     sudo systemctl status mailpit"
fi
echo "     sudo systemctl status supervisor"
echo
echo "📝 Configurar VirtualHost personalizado:"
echo "   1. Editar: /etc/apache2/sites-available/proyecto-ejemplo.conf"
echo "   2. Activar: sudo a2ensite proyecto-ejemplo.conf"
echo "   3. Recargar: sudo systemctl reload apache2"
echo "   4. Agregar a /etc/hosts: 127.0.0.1 proyecto.local"
echo
echo "⚠️  ACCIONES IMPORTANTES POST-INSTALACIÓN:"
echo
echo "   1️⃣  Reiniciar tu terminal (o ejecutar: exec bash)"
echo "      → Necesario para usar Docker sin sudo y Node.js/npm"
echo
echo "   2️⃣  Configurar Git (si aún no lo has hecho):"
echo "      git config --global user.name \"Tu Nombre Completo\""
echo "      git config --global user.email \"tu@email.com\""
echo
echo "   3️⃣  Acceder a Portainer (primera vez):"
echo "      • Abrir: https://localhost:9443"
echo "      • Crear usuario administrador"
echo "      • Puede tardar 1-2 minutos en estar disponible"
echo
echo "   4️⃣  Verificar logs de Apache si algo falla:"
echo "      sudo tail -f /var/log/apache2/error.log"
echo
echo "💡 Consejos útiles:"
echo "   • Timezone configurado: ${TIMEZONE}"
echo "   • Para cambiar timezone: editar variable TIMEZONE en el script"
echo "   • Las contraseñas simples son SOLO para desarrollo local"
echo "   • NUNCA usar estas configuraciones en producción"
echo "   • MariaDB es 100% compatible con MySQL (mismos comandos)"
echo
echo "📚 Recursos y documentación:"
echo "   • PHP:        https://www.php.net/docs.php"
echo "   • Composer:   https://getcomposer.org/doc/"
echo "   • Laravel:    https://laravel.com/docs"
echo "   • Docker:     https://docs.docker.com/"
echo "   • MariaDB:    https://mariadb.com/kb/en/documentation/"
echo "   • PostgreSQL: https://www.postgresql.org/docs/"
echo
log "🚀 ¡Entorno de desarrollo listo! Feliz programación."; then
    log_warn "Portainer ya está instalado"
    
    # Verificar si está corriendo
    if sudo docker ps --format '{{.Names}}' | grep -q '^portainer

# --------------------------------------------
# Supervisor
# --------------------------------------------
log "Instalando Supervisor..."
wait_for_apt
sudo apt install -y supervisor
sudo systemctl enable supervisor
sudo systemctl start supervisor

# --------------------------------------------
# Configuración de Git
# --------------------------------------------
log "Verificando configuración de Git..."

GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    log_warn "Git no está configurado. Por favor configura tu identidad:"
    echo ""
    echo "Ejecuta estos comandos después de la instalación:"
    echo "  git config --global user.name \"Tu Nombre\""
    echo "  git config --global user.email \"tu@email.com\""
    echo ""
else
    log "Git ya está configurado: ${GIT_NAME} <${GIT_EMAIL}>"
fi

# --------------------------------------------
# Limpieza
# --------------------------------------------
log "Limpiando paquetes innecesarios..."
sudo apt autoremove -y
sudo apt autoclean -y

# --------------------------------------------
# Verificación post-instalación
# --------------------------------------------
log "Verificando servicios instalados..."
echo ""

check_service() {
    if systemctl is-active --quiet $1; then
        echo "  ✅ $1 → Funcionando"
    else
        echo "  ❌ $1 → No está corriendo"
    fi
}

check_service apache2
check_service mariadb
check_service postgresql
check_service redis-server
check_service docker

if [ -f /usr/local/bin/mailpit ]; then
    check_service mailpit
fi

check_service supervisor

echo ""

# Verificar comandos disponibles
check_command() {
    if command -v $1 &> /dev/null; then
        VERSION=$($1 --version 2>&1 | head -n 1)
        echo "  ✅ $1 → ${VERSION}"
    else
        echo "  ❌ $1 → No disponible"
    fi
}

log "Verificando herramientas instaladas..."
check_command php
check_command composer
check_command python3
check_command docker

if command -v node &> /dev/null; then
    echo "  ✅ node → $(node --version)"
    echo "  ✅ npm → $(npm --version)"
else
    echo "  ⚠️  node/npm → Requiere reiniciar terminal"
fi

# --------------------------------------------
# Resumen final
# --------------------------------------------
echo
echo "╔════════════════════════════════════════════╗"
echo "║        ✅ INSTALACIÓN COMPLETA ✅          ║"
echo "╚════════════════════════════════════════════╝"
echo
echo "📦 Servicios instalados y funcionando:"
echo "  ✓ Apache2 + PHP ${PHP_VERSION} (timezone: ${TIMEZONE})"
echo "  ✓ MariaDB (usuario: ${USER_NAME}/dev2024, root/root)"
echo "  ✓ PostgreSQL (usuario: postgres/root, ${USER_NAME}/root)"
echo "  ✓ Redis Server"
if [ -f /usr/local/bin/mailpit ]; then
    echo "  ✓ Mailpit (http://localhost:8025)"
else
    echo "  ⚠ Mailpit (no instalado)"
fi
echo "  ✓ Supervisor"
echo "  ✓ Composer ${COMPOSER_VERSION:-instalado}"
echo "  ✓ Adminer (http://localhost/adminer/)"
echo "  ✓ Python ${PYTHON_VERSION} + venv"
if command -v node &> /dev/null; then
    echo "  ✓ Node.js $(node --version) + npm $(npm --version)"
else
    echo "  ⚠ Node.js (requiere reiniciar terminal)"
fi
echo "  ✓ Docker ${DOCKER_VERSION}"
echo "  ✓ Portainer (https://localhost:9443)"
echo
echo "📁 Carpeta de proyectos: ${WEB_ROOT}"
echo "   • http://localhost/index.php (phpinfo)"
echo "   • http://localhost/adminer/ (gestión de bases de datos)"
echo
echo "🔧 Comandos útiles:"
echo "  • Reiniciar Apache:     sudo systemctl restart apache2"
echo "  • Reiniciar PHP-FPM:    sudo systemctl restart php${PHP_VERSION}-fpm"
echo "  • Ver logs Apache:      sudo tail -f /var/log/apache2/error.log"
echo "  • MariaDB CLI:          mariadb -u ${USER_NAME} -p"
echo "  • MariaDB root:         sudo mariadb -u root -p"
echo "  • PostgreSQL CLI:       psql -U ${USER_NAME}"
echo "  • Redis CLI:            redis-cli"
echo "  • Composer:             composer install"
echo "  • Crear venv Python:    python3 -m venv mi_entorno"
echo "  • Node.js version:      node --version"
echo "  • npm version:          npm --version"
echo "  • Docker version:       docker --version"
echo "  • Docker Compose:       docker compose --version"
echo "  • Ver contenedores:     docker ps (requiere reiniciar terminal)"
echo
echo "📊 Verificar estado de servicios:"
echo "  sudo systemctl status apache2"
echo "  sudo systemctl status mariadb"
echo "  sudo systemctl status postgresql"
echo "  sudo systemctl status redis-server"
if [ -f /usr/local/bin/mailpit ]; then
    echo "  sudo systemctl status mailpit"
fi
echo
echo "🔐 Credenciales:"
echo "  MariaDB:    ${USER_NAME} / dev2024"
echo "  MariaDB:    root / root"
echo "  PostgreSQL: ${USER_NAME} / root"
echo "  Adminer:    http://localhost/adminer/"
echo "  Portainer:  https://localhost:9443 (crear usuario en primer acceso)"
echo
echo "📝 VirtualHost ejemplo:"
echo "  • Archivo: /etc/apache2/sites-available/proyecto-ejemplo.conf"
echo "  • Activar: sudo a2ensite proyecto-ejemplo.conf && sudo systemctl reload apache2"
echo "  • Luego agregar a /etc/hosts: 127.0.0.1 proyecto.local"
echo
echo "⚠️  IMPORTANTE - Acciones post-instalación:"
echo "  1. Cierra y abre tu terminal para usar Node.js/npm y Docker sin sudo"
echo "  2. Configura Git si aún no lo has hecho:"
echo "     git config --global user.name \"Tu Nombre\""
echo "     git config --global user.email \"tu@email.com\""
echo "  3. Portainer puede tardar 1-2 min en iniciar (primer acceso)"
echo "  4. Ajusta la variable TIMEZONE en el script si no usas America/Santiago"
echo
log "¡Listo para desarrollar! 🚀"; then
        log "Portainer está corriendo correctamente"
    else
        log_warn "Portainer existe pero no está corriendo. Iniciando..."
        sudo docker start portainer
    fi
else
    # Crear volumen para datos de Portainer (usando sudo temporalmente)
    sudo docker volume create portainer_data 2>/dev/null || true

    # Instalar Portainer CE (Community Edition)
    sudo docker run -d \
      -p 8000:8000 \
      -p 9443:9443 \
      --name portainer \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:latest

    log "Portainer instalado correctamente"
fi

# --------------------------------------------
# Supervisor
# --------------------------------------------
log "Instalando Supervisor..."
wait_for_apt
sudo apt install -y supervisor
sudo systemctl enable supervisor
sudo systemctl start supervisor

# --------------------------------------------
# Configuración de Git
# --------------------------------------------
log "Verificando configuración de Git..."

GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")

if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
    log_warn "Git no está configurado. Por favor configura tu identidad:"
    echo ""
    echo "Ejecuta estos comandos después de la instalación:"
    echo "  git config --global user.name \"Tu Nombre\""
    echo "  git config --global user.email \"tu@email.com\""
    echo ""
else
    log "Git ya está configurado: ${GIT_NAME} <${GIT_EMAIL}>"
fi

# --------------------------------------------
# Limpieza
# --------------------------------------------
log "Limpiando paquetes innecesarios..."
sudo apt autoremove -y
sudo apt autoclean -y

# --------------------------------------------
# Verificación post-instalación
# --------------------------------------------
log "Verificando servicios instalados..."
echo ""

check_service() {
    if systemctl is-active --quiet $1; then
        echo "  ✅ $1 → Funcionando"
    else
        echo "  ❌ $1 → No está corriendo"
    fi
}

check_service apache2
check_service mariadb
check_service postgresql
check_service redis-server
check_service docker

if [ -f /usr/local/bin/mailpit ]; then
    check_service mailpit
fi

check_service supervisor

echo ""

# Verificar comandos disponibles
check_command() {
    if command -v $1 &> /dev/null; then
        VERSION=$($1 --version 2>&1 | head -n 1)
        echo "  ✅ $1 → ${VERSION}"
    else
        echo "  ❌ $1 → No disponible"
    fi
}

log "Verificando herramientas instaladas..."
check_command php
check_command composer
check_command python3
check_command docker

if command -v node &> /dev/null; then
    echo "  ✅ node → $(node --version)"
    echo "  ✅ npm → $(npm --version)"
else
    echo "  ⚠️  node/npm → Requiere reiniciar terminal"
fi

# --------------------------------------------
# Resumen final
# --------------------------------------------
echo
echo "╔════════════════════════════════════════════╗"
echo "║        ✅ INSTALACIÓN COMPLETA ✅          ║"
echo "╚════════════════════════════════════════════╝"
echo
echo "📦 Servicios instalados y funcionando:"
echo "  ✓ Apache2 + PHP ${PHP_VERSION} (timezone: ${TIMEZONE})"
echo "  ✓ MariaDB (usuario: ${USER_NAME}/dev2024, root/root)"
echo "  ✓ PostgreSQL (usuario: postgres/root, ${USER_NAME}/root)"
echo "  ✓ Redis Server"
if [ -f /usr/local/bin/mailpit ]; then
    echo "  ✓ Mailpit (http://localhost:8025)"
else
    echo "  ⚠ Mailpit (no instalado)"
fi
echo "  ✓ Supervisor"
echo "  ✓ Composer ${COMPOSER_VERSION:-instalado}"
echo "  ✓ Adminer (http://localhost/adminer/)"
echo "  ✓ Python ${PYTHON_VERSION} + venv"
if command -v node &> /dev/null; then
    echo "  ✓ Node.js $(node --version) + npm $(npm --version)"
else
    echo "  ⚠ Node.js (requiere reiniciar terminal)"
fi
echo "  ✓ Docker ${DOCKER_VERSION}"
echo "  ✓ Portainer (https://localhost:9443)"
echo
echo "📁 Carpeta de proyectos: ${WEB_ROOT}"
echo "   • http://localhost/index.php (phpinfo)"
echo "   • http://localhost/adminer/ (gestión de bases de datos)"
echo
echo "🔧 Comandos útiles:"
echo "  • Reiniciar Apache:     sudo systemctl restart apache2"
echo "  • Reiniciar PHP-FPM:    sudo systemctl restart php${PHP_VERSION}-fpm"
echo "  • Ver logs Apache:      sudo tail -f /var/log/apache2/error.log"
echo "  • MariaDB CLI:          mariadb -u ${USER_NAME} -p"
echo "  • MariaDB root:         sudo mariadb -u root -p"
echo "  • PostgreSQL CLI:       psql -U ${USER_NAME}"
echo "  • Redis CLI:            redis-cli"
echo "  • Composer:             composer install"
echo "  • Crear venv Python:    python3 -m venv mi_entorno"
echo "  • Node.js version:      node --version"
echo "  • npm version:          npm --version"
echo "  • Docker version:       docker --version"
echo "  • Docker Compose:       docker compose --version"
echo "  • Ver contenedores:     docker ps (requiere reiniciar terminal)"
echo
echo "📊 Verificar estado de servicios:"
echo "  sudo systemctl status apache2"
echo "  sudo systemctl status mariadb"
echo "  sudo systemctl status postgresql"
echo "  sudo systemctl status redis-server"
if [ -f /usr/local/bin/mailpit ]; then
    echo "  sudo systemctl status mailpit"
fi
echo
echo "🔐 Credenciales:"
echo "  MariaDB:    ${USER_NAME} / dev2024"
echo "  MariaDB:    root / root"
echo "  PostgreSQL: ${USER_NAME} / root"
echo "  Adminer:    http://localhost/adminer/"
echo "  Portainer:  https://localhost:9443 (crear usuario en primer acceso)"
echo
echo "📝 VirtualHost ejemplo:"
echo "  • Archivo: /etc/apache2/sites-available/proyecto-ejemplo.conf"
echo "  • Activar: sudo a2ensite proyecto-ejemplo.conf && sudo systemctl reload apache2"
echo "  • Luego agregar a /etc/hosts: 127.0.0.1 proyecto.local"
echo
echo "⚠️  IMPORTANTE - Acciones post-instalación:"
echo "  1. Cierra y abre tu terminal para usar Node.js/npm y Docker sin sudo"
echo "  2. Configura Git si aún no lo has hecho:"
echo "     git config --global user.name \"Tu Nombre\""
echo "     git config --global user.email \"tu@email.com\""
echo "  3. Portainer puede tardar 1-2 min en iniciar (primer acceso)"
echo "  4. Ajusta la variable TIMEZONE en el script si no usas America/Santiago"
echo
log "¡Listo para desarrollar! 🚀"
