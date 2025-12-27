#!/bin/bash
# ============================================
# Script de Entorno de Desarrollo Profesional V4.0
# Compatible con: Debian, Ubuntu, Linux Mint
# Mejoras: Error handling, seguridad, logs, rollback
# ============================================

set -euo pipefail

# --- CONFIGURACIÓN DE LOGS ---
LOG_DIR="/var/log/dev-setup"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- 1. Verificación de Privilegios y SUDO ---
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecuta el script con sudo: sudo bash $0"
    exit 1
fi

# Obtener el usuario real (no root)
USER_NAME="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
CREDENTIALS_FILE="$USER_HOME/credenciales-dev.txt"

# En Debian puro, a veces sudo no está instalado
if ! command -v sudo &>/dev/null; then
    echo "Instalando sudo..."
    apt update && apt install -y sudo
    usermod -aG sudo "$USER_NAME"
fi

# --- 2. Variables de Entorno ---
WEB_ROOT="$USER_HOME/proyectos/php"
TIMEZONE="America/Santiago"
OS_ID=$(. /etc/os-release && echo "$ID")
OS_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")

# Contraseñas seguras generadas
MARIA_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-20)
POSTGRES_PASS=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-20)

# Array para tracking de servicios instalados
declare -a INSTALLED_SERVICES=()
declare -a FAILED_SERVICES=()

# --- 3. Funciones Estéticas y Utilidad ---
log() { 
    echo -e "\e[1;32m[✔]\e[0m $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_warn() { 
    echo -e "\e[1;33m[!]\e[0m $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "\e[1;31m[✘]\e[0m $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

save_credential() {
    echo "$1" >> "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    chown "$USER_NAME":"$USER_NAME" "$CREDENTIALS_FILE"
}

backup_config() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup-$(date +%Y%m%d)"
        log "Backup creado: ${file}.backup-$(date +%Y%m%d)"
    fi
}

verify_service() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        log "$service está corriendo correctamente"
        INSTALLED_SERVICES+=("$service")
        return 0
    else
        log_warn "$service instalado pero no está activo"
        FAILED_SERVICES+=("$service")
        return 1
    fi
}

# --- 4. Menú de Selección ---
clear
echo "=============================================="
echo "    INSTALADOR DE ENTORNO AUTOMATIZADO V4.0  "
echo "    Usuario: $USER_NAME | Sistema: $OS_ID    "
echo "=============================================="
echo "Selecciona tu modo de trabajo:"
echo "1) TODO EN LOCAL (Apache, PHP, DBs, Docker, Node...)"
echo "2) SOLO DOCKER (Docker + Node.js, ideal para no ensuciar el OS)"
echo "3) PERSONALIZADO (Tú eliges componente por componente)"
read -p "Opción [1-3]: " MODO_GENERAL

# Lógica de banderas
if [ "$MODO_GENERAL" -eq 1 ]; then
    INS_BASE="s"; INS_LAMP="s"; INS_MARIA="s"; INS_POSTGRES="s"; INS_REDIS="s"; INS_MAILPIT="s"; INS_NODE="s"; INS_DOCKER="s"
elif [ "$MODO_GENERAL" -eq 2 ]; then
    INS_BASE="s"; INS_LAMP="n"; INS_MARIA="n"; INS_POSTGRES="n"; INS_REDIS="n"; INS_MAILPIT="n"; INS_NODE="s"; INS_DOCKER="s"
else
    read -p "• ¿Instalar Base (git, curl, build-essential)? [s/n]: " INS_BASE
    read -p "• ¿Instalar LAMP (Apache + PHP)? [s/n]: " INS_LAMP
    read -p "• ¿Instalar MariaDB? [s/n]: " INS_MARIA
    read -p "• ¿Instalar PostgreSQL? [s/n]: " INS_POSTGRES
    read -p "• ¿Instalar Redis? [s/n]: " INS_REDIS
    read -p "• ¿Instalar Mailpit? [s/n]: " INS_MAILPIT
    read -p "• ¿Instalar Node.js (vía NVM)? [s/n]: " INS_NODE
    read -p "• ¿Instalar Docker + Portainer? [s/n]: " INS_DOCKER
fi

# --- 5. Proceso de Instalación ---

log "Iniciando instalación..."
echo "========================================" > "$CREDENTIALS_FILE"
echo "CREDENCIALES DEL ENTORNO DE DESARROLLO" >> "$CREDENTIALS_FILE"
echo "Generado: $(date)" >> "$CREDENTIALS_FILE"
echo "========================================" >> "$CREDENTIALS_FILE"

log "Actualizando sistema..."
if apt update && apt upgrade -y; then
    log "Sistema actualizado correctamente"
else
    log_error "Fallo al actualizar el sistema"
    exit 1
fi

# --- BASE ---
if [[ "$INS_BASE" =~ ^[Ss]$ ]]; then
    log "Instalando utilidades base..."
    if apt install -y wget curl git unzip zip htop build-essential ca-certificates gnupg lsb-release openssl; then
        log "Utilidades base instaladas"
    else
        log_error "Error instalando utilidades base"
    fi
fi

# --- LAMP ---
if [[ "$INS_LAMP" =~ ^[Ss]$ ]]; then
    log "Instalando Apache y PHP..."
    
    if apt install -y apache2 php php-cli php-fpm php-common php-mysql php-pgsql php-mbstring php-xml php-curl php-zip php-gd php-intl php-redis php-bcmath; then
        log "Apache y PHP instalados"
        
        # Configurar Apache
        a2enmod rewrite headers proxy_fcgi setenvif ssl
        
        # --- Ajustar php.ini (CLI y FPM/Apache) ---
        log "Optimizando configuración de PHP..."
        
        # Obtenemos la versión de PHP instalada (ej: 8.3)
        PHP_VER=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
        
        # Definimos las rutas posibles para las configuraciones
        # Buscamos en 'fpm' (recomendado) y 'apache2' (si no se usa FPM)
        PATHS=(
            "/etc/php/$PHP_VER/cli/php.ini"
            "/etc/php/$PHP_VER/fpm/php.ini"
            "/etc/php/$PHP_VER/apache2/php.ini"
        )
        for INI in "${PATHS[@]}"; do
            if [ -f "$INI" ]; then
                backup_config "$INI"
                sed -i "s/^;date.timezone =.*/date.timezone = ${TIMEZONE}/" "$INI"
                sed -i 's/memory_limit = .*/memory_limit = 512M/' "$INI"
                sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$INI"
                sed -i 's/post_max_size = .*/post_max_size = 64M/' "$INI"
                sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$INI"
                log "Configurado: $INI"
            fi
        done
        
        # Reiniciar servicios para aplicar cambios de PHP
        systemctl restart "php${PHP_VER}-fpm" 2>/dev/null || true
        systemctl restart apache2
        
        # Crear estructura de directorios
        mkdir -p "$WEB_ROOT"
        chown -R "$USER_NAME":www-data "$WEB_ROOT"
        chmod -R 755 "$WEB_ROOT"
        
        # Crear VirtualHost básico
        cat > /etc/apache2/sites-available/dev.conf <<EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot $WEB_ROOT
    
    <Directory $WEB_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    ErrorLog \${APACHE_LOG_DIR}/dev-error.log
    CustomLog \${APACHE_LOG_DIR}/dev-access.log combined
</VirtualHost>
EOF
        a2ensite dev.conf
        
        if systemctl enable --now apache2 && systemctl reload apache2; then
            verify_service apache2
            echo "Apache: http://localhost" >> "$CREDENTIALS_FILE"
            echo "Webroot: $WEB_ROOT" >> "$CREDENTIALS_FILE"
        else
            log_error "Apache no pudo iniciarse"
        fi
        
        # Composer
        log "Instalando Composer..."
        if curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer; then
            log "Composer instalado: $(composer --version 2>/dev/null | head -n1)"
        else
            log_warn "Error instalando Composer"
        fi
    else
        log_error "Error instalando LAMP"
    fi
fi

# --- MARIADB ---
if [[ "$INS_MARIA" =~ ^[Ss]$ ]]; then
    log "Instalando MariaDB..."
    
    if apt install -y mariadb-server mariadb-client; then
        log "MariaDB instalado"
        
        if systemctl enable --now mariadb; then
            sleep 2
            
            # Configurar contraseña root
            if mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MARIA_PASS'; FLUSH PRIVILEGES;"; then
                log "MariaDB configurado con contraseña segura"
                save_credential ""
                save_credential "MariaDB:"
                save_credential "  Usuario: root"
                save_credential "  Contraseña: $MARIA_PASS"
                save_credential "  Conexión: mysql -u root -p"
                
                verify_service mariadb
            else
                log_warn "Error configurando contraseña de MariaDB"
            fi
        else
            log_error "MariaDB no pudo iniciarse"
        fi
    else
        log_error "Error instalando MariaDB"
    fi
fi

# --- POSTGRESQL ---
if [[ "$INS_POSTGRES" =~ ^[Ss]$ ]]; then
    log "Instalando PostgreSQL..."
    
    if apt install -y postgresql postgresql-contrib; then
        log "PostgreSQL instalado"
        
        if systemctl enable --now postgresql; then
            sleep 2
            
            if sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASS';"; then
                log "PostgreSQL configurado con contraseña segura"
                save_credential ""
                save_credential "PostgreSQL:"
                save_credential "  Usuario: postgres"
                save_credential "  Contraseña: $POSTGRES_PASS"
                save_credential "  Conexión: psql -U postgres -h localhost"
                
                verify_service postgresql
            else
                log_warn "Error configurando contraseña de PostgreSQL"
            fi
        else
            log_error "PostgreSQL no pudo iniciarse"
        fi
    else
        log_error "Error instalando PostgreSQL"
    fi
fi

# --- REDIS ---
if [[ "$INS_REDIS" =~ ^[Ss]$ ]]; then
    log "Instalando Redis..."
    
    if apt install -y redis-server; then
        log "Redis instalado"
        
        # Configurar Redis
        backup_config /etc/redis/redis.conf
        sed -i 's/^# maxmemory .*/maxmemory 256mb/' /etc/redis/redis.conf
        sed -i 's/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/' /etc/redis/redis.conf
        
        if systemctl enable --now redis-server; then
            verify_service redis-server
            save_credential ""
            save_credential "Redis:"
            save_credential "  Puerto: 6379"
            save_credential "  Conexión: redis-cli"
        else
            log_error "Redis no pudo iniciarse"
        fi
    else
        log_error "Error instalando Redis"
    fi
fi

# --- MAILPIT ---
if [[ "$INS_MAILPIT" =~ ^[Ss]$ ]]; then
    log "Instalando Mailpit..."
    
    if curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | bash; then
        log "Mailpit instalado"
        
        cat > /etc/systemd/system/mailpit.service <<EOF
[Unit]
Description=Mailpit Email Testing Service
After=network.target

[Service]
ExecStart=/usr/local/bin/mailpit
User=$USER_NAME
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        if systemctl enable --now mailpit; then
            verify_service mailpit
            save_credential ""
            save_credential "Mailpit:"
            save_credential "  Web UI: http://localhost:8025"
            save_credential "  SMTP: localhost:1025"
        else
            log_error "Mailpit no pudo iniciarse"
        fi
    else
        log_error "Error instalando Mailpit"
    fi
fi

# --- NODE.JS (NVM) ---
if [[ "$INS_NODE" =~ ^[Ss]$ ]]; then
    log "Instalando NVM (Node Version Manager)..."
    
    if sudo -u "$USER_NAME" bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"; then
        log "NVM instalado"
        
        # Instalar Node LTS automáticamente
        sudo -u "$USER_NAME" bash <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
nvm alias default lts/*
EOF
        
        # Añadir carga de NVM al bashrc si no existe (doble check)
        if ! grep -q "nvm.sh" "$USER_HOME/.bashrc"; then
            echo '' >> "$USER_HOME/.bashrc"
            echo '# NVM Configuration' >> "$USER_HOME/.bashrc"
            echo 'export NVM_DIR="$HOME/.nvm"' >> "$USER_HOME/.bashrc"
            echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$USER_HOME/.bashrc"
            echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> "$USER_HOME/.bashrc"
            log "NVM añadido a .bashrc"
        fi
        
        NODE_VERSION=$(sudo -u "$USER_NAME" bash -c 'source ~/.nvm/nvm.sh && node --version 2>/dev/null' || echo "Requiere reinicio")
        NPM_VERSION=$(sudo -u "$USER_NAME" bash -c 'source ~/.nvm/nvm.sh && npm --version 2>/dev/null' || echo "")
        log "Node.js instalado: $NODE_VERSION"
        
        save_credential ""
        save_credential "Node.js (via NVM):"
        save_credential "  Versión Node: $NODE_VERSION"
        save_credential "  Versión NPM: $NPM_VERSION"
        save_credential "  Comandos: nvm install <version>, nvm use <version>"
        save_credential "  Nota: Ejecuta 'source ~/.bashrc' o reinicia el terminal"
    else
        log_error "Error instalando NVM"
    fi
fi

# --- DOCKER ---
if [[ "$INS_DOCKER" =~ ^[Ss]$ ]]; then
    log "Instalando Docker Engine..."
    
    # Mapeo específico para Mint
    REPO_NAME="$OS_CODENAME"
    if [ "$OS_ID" = "linuxmint" ]; then
        MINT_VER=$(grep RELEASE /etc/linuxmint/info 2>/dev/null | cut -d= -f2 || echo "21")
        [[ "$MINT_VER" == 22* ]] && REPO_NAME="noble" || REPO_NAME="jammy"
        log "Linux Mint detectado, usando repositorio: $REPO_NAME"
    fi
    
    install -m 0755 -d /etc/apt/keyrings
    
    if [ "$OS_ID" = "debian" ]; then
        URL_DOCKER="https://download.docker.com/linux/debian"
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    else
        URL_DOCKER="https://download.docker.com/linux/ubuntu"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    fi
    
    chmod a+r /etc/apt/keyrings/docker.asc
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $URL_DOCKER $REPO_NAME stable" > /etc/apt/sources.list.d/docker.list
    
    if apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log "Docker instalado"
        
        usermod -aG docker "$USER_NAME"
        
        if systemctl enable --now docker; then
            verify_service docker
            
            # Esperar a que Docker esté listo
            sleep 3
            
            # Portainer
            log "Instalando Portainer..."
            if docker run -d -p 9443:9443 -p 8000:8000 --name portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                portainer/portainer-ce:latest; then
                log "Portainer instalado correctamente"
                save_credential ""
                save_credential "Docker:"
                save_credential "  Versión: $(docker --version)"
                save_credential "  Compose: $(docker compose version)"
                save_credential ""
                save_credential "Portainer:"
                save_credential "  Web UI: https://localhost:9443"
                save_credential "  Usuario: Configurar en primer acceso"
            else
                log_warn "Error instalando Portainer (puede que ya exista)"
            fi
        else
            log_error "Docker no pudo iniciarse"
        fi
    else
        log_error "Error instalando Docker"
    fi
fi

# --- 6. Configuración de Firewall (Opcional) ---
if command -v ufw &>/dev/null; then
    log "Configurando firewall básico..."
    ufw --force enable
    ufw allow 22/tcp    # SSH
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS
    ufw allow 8025/tcp  # Mailpit
    ufw allow 9443/tcp  # Portainer
    ufw reload
    log "Firewall configurado (puertos: 22, 80, 443, 8025, 9443)"
fi

# --- 7. Testing de Servicios ---
log "Verificando servicios instalados..."
echo "" >> "$CREDENTIALS_FILE"
echo "========================================" >> "$CREDENTIALS_FILE"
echo "RESUMEN DE SERVICIOS" >> "$CREDENTIALS_FILE"
echo "========================================" >> "$CREDENTIALS_FILE"

for service in "${INSTALLED_SERVICES[@]}"; do
    echo "✔ $service - OK" >> "$CREDENTIALS_FILE"
done

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo "" >> "$CREDENTIALS_FILE"
    echo "Servicios con advertencias:" >> "$CREDENTIALS_FILE"
    for service in "${FAILED_SERVICES[@]}"; do
        echo "! $service - Revisar manualmente" >> "$CREDENTIALS_FILE"
    done
fi

# --- 8. Crear script de desinstalación ---
cat > "$USER_HOME/desinstalar-entorno.sh" <<'UNINSTALL_EOF'
#!/bin/bash
echo "⚠️  DESINSTALADOR DE ENTORNO DE DESARROLLO"
echo "Esto eliminará todos los componentes instalados"
read -p "¿Continuar? [s/N]: " confirm
[[ ! "$confirm" =~ ^[Ss]$ ]] && exit 0

sudo systemctl stop apache2 mariadb postgresql redis-server mailpit docker
sudo apt remove --purge -y apache2 php* mariadb-server postgresql redis-server docker-ce docker-ce-cli
sudo apt autoremove -y
sudo rm -rf /etc/apache2 /etc/mysql /etc/postgresql /var/lib/mysql /var/lib/postgresql
echo "Desinstalación completada"
UNINSTALL_EOF

chmod +x "$USER_HOME/desinstalar-entorno.sh"
chown "$USER_NAME":"$USER_NAME" "$USER_HOME/desinstalar-entorno.sh"

# --- 9. Limpieza y Despedida ---
apt autoremove -y
apt autoclean

clear
echo "=============================================="
echo "    ✅ INSTALACIÓN COMPLETADA CON ÉXITO      "
echo "=============================================="
echo ""
cat "$CREDENTIALS_FILE"
echo ""
echo "=============================================="
echo "📁 Archivos importantes:"
echo "  • Credenciales: $CREDENTIALS_FILE"
echo "  • Logs: $LOG_FILE"
echo "  • Desinstalador: $USER_HOME/desinstalar-entorno.sh"
echo "=============================================="
log_warn "IMPORTANTE:"
log_warn "1. Reinicia tu PC o cierra sesión para que Docker funcione"
log_warn "2. Para activar NVM ahora: source ~/.bashrc"
log_warn "3. Guarda el archivo de credenciales en lugar seguro"
echo "=============================================="

# Mostrar servicios fallidos si los hay
if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo ""
    log_warn "Servicios que requieren atención:"
    for service in "${FAILED_SERVICES[@]}"; do
        echo "  • $service - Ejecuta: sudo systemctl status $service"
    done
fi

log "Instalación finalizada. ¡Disfruta tu entorno de desarrollo!"
