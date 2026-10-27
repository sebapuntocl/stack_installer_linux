#!/usr/bin/env bash
# ============================================================
# Entorno de Desarrollo — Debian / Ubuntu / Linux Mint · v4
# 1) TODO:   Base + Apache/PHP + MariaDB + PostgreSQL + Redis
#            + Mailpit + Node (NVM)
# 2) BÁSICO: Base + Docker + Portainer
# Uso: sudo bash install-dev.sh
# ============================================================

set -euo pipefail

# ============================================================
# CONFIGURACIÓN
# ============================================================

PHP_MAIN="8.5"                    # versión de PHP a instalar
WEB_ROOT_REL="proyectos/php"
TIMEZONE="America/Santiago"

MARIADB_DEV_USER="dev"
MARIADB_DEV_PASSWORD="auto"
POSTGRES_PASSWORD="auto"
PG_VERSION="18"

NODE_VERSION="24"                 # versión que instala NVM (24, 22, --lts)
NVM_VERSION="v0.40.3"             # versión del instalador de NVM

INSTALL_XDEBUG="s"

# ============================================================
# FIN CONFIGURACIÓN
# ============================================================

[ "$EUID" -ne 0 ] && { echo "Ejecuta con sudo: sudo bash $0"; exit 1; }
[ -z "${SUDO_USER:-}" ] && { echo "Ejecuta con sudo desde tu usuario normal, no como root."; exit 1; }

USER_NAME="$SUDO_USER"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_GROUP=$(id -gn "$USER_NAME")
WEB_ROOT="$USER_HOME/$WEB_ROOT_REL"

# --- Detección de distro: Debian, Ubuntu, Mint (y LMDE) y derivadas ---
OS_ID=$(. /etc/os-release && echo "$ID")
OS_LIKE=$(. /etc/os-release && echo "${ID_LIKE:-}")
OS_PRETTY=$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
# Codename de la base: Ubuntu/Mint(Ubuntu) -> UBUNTU_CODENAME, LMDE -> DEBIAN_CODENAME
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${DEBIAN_CODENAME:-${VERSION_CODENAME:-}}}")
# Ubuntu primero: su ID_LIKE contiene "debian", el orden importa.
case " ${OS_ID} ${OS_LIKE} " in
    *" ubuntu "*) DISTRO="ubuntu" ;;
    *" debian "*) DISTRO="debian" ;;
    *) echo "Distro no soportada: $OS_PRETTY (solo Debian/Ubuntu/Mint)"; exit 1 ;;
esac
[ -z "$CODENAME" ] && { echo "No pude detectar el codename de tu distro."; exit 1; }
ARCH=$(dpkg --print-architecture)

export DEBIAN_FRONTEND=noninteractive

LOG_DIR="/var/log/dev-setup"; mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

CREDENTIALS_FILE="$USER_HOME/credenciales-dev.txt"

log()       { echo -e "\e[1;32m[OK]\e[0m $1"; }
log_warn()  { echo -e "\e[1;33m[!]\e[0m  $1"; }
log_error() { echo -e "\e[1;31m[X]\e[0m  $1"; }

as_user() { sudo -u "$USER_NAME" -H "$@"; }

save_credential() {
    echo "$1" >> "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    chown "$USER_NAME":"$USER_GROUP" "$CREDENTIALS_FILE"
}

backup_config() { [ -f "$1" ] && cp -n "$1" "${1}.backup-$(date +%Y%m%d)" || true; }
gen_password()  { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-20; }

declare -a INSTALLED=()
declare -a FAILED=()

verify_service() {
    if systemctl is-active --quiet "$1"; then
        log "$1 corriendo"; INSTALLED+=("$1")
    else
        log_warn "$1 no está activo — revisa: systemctl status $1"; FAILED+=("$1")
    fi
}

# ¿Responde esta URL (200)? Sirve para saber si un repo publica para tu versión.
url_ok() { curl -fsS -o /dev/null --max-time 20 "$1" 2>/dev/null; }

# ¿Existe el paquete en los repos? LC_ALL=C es obligatorio: apt traduce su salida.
pkg_exists() {
    local cand
    cand=$(LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '/^ *Candidate:/{print $2}') || cand=""
    [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

# Instala solo los paquetes que existen y avisa de los que no.
apt_install_available() {
    local have=() missing=() p
    for p in "$@"; do
        if pkg_exists "$p"; then have+=("$p"); else missing+=("$p"); fi
    done
    [ ${#have[@]}    -gt 0 ] && apt-get install -y "${have[@]}"
    [ ${#missing[@]} -gt 0 ] && log_warn "No existen en el repo (se omiten): ${missing[*]}"
    return 0
}

add_repo() {
    local name="$1" key_url="$2" uri="$3" suites="$4" components="$5"
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL "$key_url" | gpg --dearmor --yes -o "/etc/apt/keyrings/${name}.gpg"
    chmod 0644 "/etc/apt/keyrings/${name}.gpg"
    cat > "/etc/apt/sources.list.d/${name}.sources" <<EOF
Types: deb
URIs: ${uri}
Suites: ${suites}
Components: ${components}
Signed-By: /etc/apt/keyrings/${name}.gpg
EOF
}

# ------------------------------------------------------------
# MENÚ
# ------------------------------------------------------------
clear
cat <<BANNER
==================================================
  ENTORNO DEV — $OS_PRETTY · $ARCH
  Usuario: $USER_NAME
==================================================
1) TODO
   Base · Apache + PHP $PHP_MAIN · MariaDB · PostgreSQL $PG_VERSION
   Redis · Mailpit · Node $NODE_VERSION (NVM)
2) BÁSICO
   Base · Docker + Portainer
==================================================
BANNER
read -rp "Opción [1-2]: " MODO

INS_WEB=n; INS_MARIA=n; INS_POSTGRES=n; INS_REDIS=n
INS_MAILPIT=n; INS_NODE=n; INS_DOCKER=n

case "$MODO" in
    1) INS_WEB=s; INS_MARIA=s; INS_POSTGRES=s; INS_REDIS=s; INS_MAILPIT=s; INS_NODE=s ;;
    2) INS_DOCKER=s ;;
    *) log_error "Opción inválida"; exit 1 ;;
esac

{
    echo "========================================"
    echo "CREDENCIALES — ENTORNO DE DESARROLLO"
    echo "Generado: $(date)"
    echo "$OS_PRETTY ($CODENAME) — $(hostname)"
    echo "========================================"
} > "$CREDENTIALS_FILE"
chown "$USER_NAME":"$USER_GROUP" "$CREDENTIALS_FILE"; chmod 600 "$CREDENTIALS_FILE"

# ------------------------------------------------------------
# BASE (git, curl, build-essential) — en ambas opciones
# ------------------------------------------------------------
# Si quedó el PPA de ondrej en una Ubuntu que ya no lo soporta, apt update falla con 404.
if [ "$DISTRO" = "ubuntu" ] && compgen -G "/etc/apt/sources.list.d/ondrej-ubuntu-php*" >/dev/null; then
    if ! url_ok "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${CODENAME}/InRelease"; then
        log_warn "El PPA ondrej/php no soporta ${CODENAME} — lo elimino"
        rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php* \
              /etc/apt/keyrings/ondrej-ubuntu-php* /etc/apt/trusted.gpg.d/ondrej-ubuntu-php*
    fi
fi

log "Actualizando sistema..."
apt-get update || log_warn "apt update reportó errores (¿algún repo de terceros caído?) — continúo"
apt-get upgrade -y

log "Instalando base (git, curl, build-essential)..."
apt-get install -y git curl wget build-essential unzip zip jq \
    ca-certificates gnupg lsb-release openssl apt-transport-https acl
INSTALLED+=("base")

# ------------------------------------------------------------
# APACHE + PHP-FPM
# ------------------------------------------------------------
if [[ "$INS_WEB" =~ ^[Ss]$ ]]; then
    log "Instalando Apache..."
    apt-get install -y apache2

    # Orden para conseguir PHP ${PHP_MAIN}:
    #  1) repos de tu distro si ya lo traen
    #  2) Debian: Sury  3) Ubuntu/Mint: PPA de Ondřej, o Sury si el PPA no soporta tu versión
    if pkg_exists "php${PHP_MAIN}-fpm"; then
        log "PHP ${PHP_MAIN} ya está en tus repos — no agrego repo externo"
    elif [ "$DISTRO" = "debian" ]; then
        log "Añadiendo repositorio Sury (PHP para Debian $CODENAME)..."
        add_repo "sury-php" "https://packages.sury.org/php/apt.gpg" \
                 "https://packages.sury.org/php/" "$CODENAME" "main"
        apt-get update
    elif url_ok "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${CODENAME}/InRelease"; then
        log "Añadiendo PPA ondrej/php (PHP para Ubuntu/Mint $CODENAME)..."
        apt-get install -y software-properties-common
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
        apt-get update
    elif url_ok "https://packages.sury.org/php/dists/${CODENAME}/InRelease"; then
        log "El PPA no soporta $CODENAME — uso packages.sury.org"
        add_repo "sury-php" "https://packages.sury.org/php/apt.gpg" \
                 "https://packages.sury.org/php/" "$CODENAME" "main"
        apt-get update
    else
        log_warn "No encontré un repo externo con PHP para $CODENAME — pruebo con los de tu distro"
    fi

    V="$PHP_MAIN"
    if ! pkg_exists "php${V}-fpm"; then
        log_error "php${V}-fpm no existe en los repos de $OS_PRETTY ($CODENAME)."
        log_error "Disponibles: $(apt-cache search --names-only '^php[0-9]\.[0-9]+-fpm$' | awk '{print $1}' | tr '\n' ' ')"
        exit 1
    fi

    log "Instalando PHP $V..."
    apt-get install -y "php${V}-fpm" "php${V}-cli" "php${V}-common"
    apt_install_available \
        "php${V}-opcache"  "php${V}-mysql"   "php${V}-pgsql"  "php${V}-sqlite3" \
        "php${V}-mbstring" "php${V}-xml"     "php${V}-curl"   "php${V}-zip" \
        "php${V}-gd"       "php${V}-intl"    "php${V}-bcmath" "php${V}-readline" \
        "php${V}-redis"    "php${V}-imagick"

    for EXT in pdo_mysql pgsql mbstring curl; do
        "php${V}" -m 2>/dev/null | grep -qi "^${EXT}$" \
            || log_warn "PHP $V: la extensión '${EXT}' no quedó cargada"
    done

    for SAPI in fpm cli; do
        INI="/etc/php/${V}/${SAPI}/php.ini"
        [ -f "$INI" ] || continue
        backup_config "$INI"
        sed -i "s|^;*\s*date.timezone\s*=.*|date.timezone = ${TIMEZONE}|"     "$INI"
        sed -i "s|^;*\s*memory_limit\s*=.*|memory_limit = 512M|"              "$INI"
        sed -i "s|^;*\s*upload_max_filesize\s*=.*|upload_max_filesize = 64M|" "$INI"
        sed -i "s|^;*\s*post_max_size\s*=.*|post_max_size = 64M|"             "$INI"
        sed -i "s|^;*\s*max_execution_time\s*=.*|max_execution_time = 300|"   "$INI"
    done

    # Pool FPM con TU usuario — sin peleas de permisos
    POOL="/etc/php/${V}/fpm/pool.d/www.conf"
    backup_config "$POOL"
    sed -i "s|^user\s*=.*|user = ${USER_NAME}|"             "$POOL"
    sed -i "s|^group\s*=.*|group = ${USER_GROUP}|"          "$POOL"
    sed -i "s|^listen.owner\s*=.*|listen.owner = www-data|" "$POOL"
    sed -i "s|^listen.group\s*=.*|listen.group = www-data|" "$POOL"
    grep -q '^listen.mode' "$POOL" || echo "listen.mode = 0660" >> "$POOL"

    if [[ "$INSTALL_XDEBUG" =~ ^[Ss]$ ]]; then
        apt-get install -y "php${V}-xdebug" 2>/dev/null || log_warn "Xdebug no disponible para PHP $V"
        XINI="/etc/php/${V}/mods-available/xdebug.ini"
        if [ -f "$XINI" ] && ! grep -q 'xdebug.mode' "$XINI"; then
            cat >> "$XINI" <<'XDEBUG'
xdebug.mode = develop,debug
xdebug.start_with_request = trigger
xdebug.client_host = 127.0.0.1
xdebug.client_port = 9003
XDEBUG
        fi
    fi

    systemctl enable --now "php${V}-fpm"
    systemctl restart "php${V}-fpm"
    verify_service "php${V}-fpm"

    # --- Apache: MPM event + proxy_fcgi hacia PHP-FPM ---
    mkdir -p "$WEB_ROOT"
    chown -R "$USER_NAME":"$USER_GROUP" "$WEB_ROOT"
    chmod 755 "$USER_HOME" "$WEB_ROOT"

    a2dismod -q mpm_prefork 2>/dev/null || true
    a2dismod -q php"${V}" 2>/dev/null || true
    a2enmod -q mpm_event proxy_fcgi setenvif rewrite headers expires
    a2enconf -q "php${V}-fpm"

    echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
    a2enconf -q servername

    cat > /etc/apache2/sites-available/dev-default.conf <<EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot ${WEB_ROOT}
    <Directory ${WEB_ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
</VirtualHost>
EOF
    a2dissite -q 000-default 2>/dev/null || true
    a2ensite -q dev-default

    apachectl configtest
    systemctl enable --now apache2
    systemctl reload apache2
    verify_service apache2

    # --- Composer con verificación de firma ---
    log "Instalando Composer..."
    EXPECTED=$(curl -fsSL https://composer.github.io/installer.sig)
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
    ACTUAL=$(php -r "echo hash_file('sha384','/tmp/composer-setup.php');")
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        log_error "Hash de Composer NO coincide. Instalación omitida por seguridad."
        FAILED+=("composer")
    else
        php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
        log "Composer $(composer --version 2>/dev/null | awk '{print $3}') instalado"
    fi
    rm -f /tmp/composer-setup.php

    # --- Comandos newsite / delsite (vhost Apache <nombre>.test) ---
    cat > /etc/dev-env.conf <<EOF
DEV_USER="${USER_NAME}"
DEV_GROUP="${USER_GROUP}"
DEV_WEB_ROOT="${WEB_ROOT}"
EOF

    cat > /usr/local/bin/newsite <<'NEWSITE'
#!/usr/bin/env bash
# newsite <nombre>  — crea http://<nombre>.test
set -euo pipefail
[ "$EUID" -ne 0 ] && { echo "Usa: sudo newsite <nombre>"; exit 1; }
source /etc/dev-env.conf

NAME="${1:?Uso: sudo newsite <nombre>}"
ROOT="$DEV_WEB_ROOT/$NAME"
DOCROOT="$ROOT/public"; [ -d "$DOCROOT" ] || DOCROOT="$ROOT"
mkdir -p "$DOCROOT"; chown -R "$DEV_USER":"$DEV_GROUP" "$ROOT"

cat > "/etc/apache2/sites-available/$NAME.conf" <<CONF
<VirtualHost *:80>
    ServerName $NAME.test
    ServerAlias *.$NAME.test
    DocumentRoot $DOCROOT
    <Directory $DOCROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
    </Directory>
</VirtualHost>
CONF

a2ensite -q "$NAME"
grep -q "[[:space:]]$NAME.test\$" /etc/hosts || echo "127.0.0.1   $NAME.test" >> /etc/hosts
apachectl configtest && systemctl reload apache2
echo "Listo → http://$NAME.test"
echo "  docroot: $DOCROOT"
NEWSITE
    chmod +x /usr/local/bin/newsite

    cat > /usr/local/bin/delsite <<'DELSITE'
#!/usr/bin/env bash
# delsite <nombre> — borra el vhost (NO borra tus archivos)
set -euo pipefail
[ "$EUID" -ne 0 ] && { echo "Usa: sudo delsite <nombre>"; exit 1; }
source /etc/dev-env.conf
NAME="${1:?Uso: sudo delsite <nombre>}"
a2dissite -q "$NAME" 2>/dev/null || true
rm -f "/etc/apache2/sites-available/$NAME.conf"
sed -i "/[[:space:]]$NAME\.test\$/d" /etc/hosts
apachectl configtest && systemctl reload apache2
echo "Vhost $NAME eliminado. Los archivos en $DEV_WEB_ROOT/$NAME siguen ahí."
DELSITE
    chmod +x /usr/local/bin/delsite

    save_credential ""
    save_credential "APACHE + PHP-FPM"
    save_credential "  PHP: ${PHP_MAIN} (FPM, pool con tu usuario)"
    save_credential "  Webroot: ${WEB_ROOT}   ·   http://localhost"
    save_credential "  Nuevo sitio:  sudo newsite miapp        -> http://miapp.test"
    save_credential "  Borrar sitio: sudo delsite miapp"
    save_credential "  Módulos: rewrite, headers, expires, proxy_fcgi (AllowOverride All)"
    save_credential "  Xdebug: modo trigger, puerto 9003"
fi

# ------------------------------------------------------------
# MARIADB
# ------------------------------------------------------------
if [[ "$INS_MARIA" =~ ^[Ss]$ ]]; then
    log "Instalando MariaDB (versión del repo de $OS_PRETTY)..."
    apt-get install -y mariadb-server mariadb-client
    systemctl enable --now mariadb
    sleep 3

    [ "$MARIADB_DEV_PASSWORD" = "auto" ] && MARIADB_DEV_PASSWORD=$(gen_password)

    mariadb <<SQL
CREATE USER IF NOT EXISTS '${MARIADB_DEV_USER}'@'localhost' IDENTIFIED BY '${MARIADB_DEV_PASSWORD}';
ALTER  USER '${MARIADB_DEV_USER}'@'localhost' IDENTIFIED BY '${MARIADB_DEV_PASSWORD}';
CREATE USER IF NOT EXISTS '${MARIADB_DEV_USER}'@'127.0.0.1' IDENTIFIED BY '${MARIADB_DEV_PASSWORD}';
ALTER  USER '${MARIADB_DEV_USER}'@'127.0.0.1' IDENTIFIED BY '${MARIADB_DEV_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${MARIADB_DEV_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '${MARIADB_DEV_USER}'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS '${USER_NAME}'@'localhost' IDENTIFIED VIA unix_socket;
GRANT ALL PRIVILEGES ON *.* TO '${USER_NAME}'@'localhost' WITH GRANT OPTION;
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SQL

    verify_service mariadb

    save_credential ""
    save_credential "MARIADB $(mariadb --version | grep -oP '\d+\.\d+\.\d+' | head -n1)"
    save_credential "  Acceso directo: mariadb          (tu usuario, unix_socket, sin password)"
    save_credential "  Root:           sudo mariadb"
    save_credential "  Usuario app:    ${MARIADB_DEV_USER}"
    save_credential "  Contraseña:     ${MARIADB_DEV_PASSWORD}"
    save_credential "  Host: 127.0.0.1:3306"
fi

# ------------------------------------------------------------
# POSTGRESQL
# ------------------------------------------------------------
if [[ "$INS_POSTGRES" =~ ^[Ss]$ ]]; then
    PG_PKG="postgresql-${PG_VERSION}"
    if pkg_exists "$PG_PKG"; then
        log "PostgreSQL ${PG_VERSION} ya está en tus repos — no agrego PGDG"
    elif url_ok "https://apt.postgresql.org/pub/repos/apt/dists/${CODENAME}-pgdg/InRelease"; then
        log "Añadiendo repositorio PGDG..."
        add_repo "pgdg" "https://www.postgresql.org/media/keys/ACCC4CF8.asc" \
                 "https://apt.postgresql.org/pub/repos/apt" "${CODENAME}-pgdg" "main"
        apt-get update
    else
        log_warn "PGDG no publica para ${CODENAME} y tu distro no trae PostgreSQL ${PG_VERSION} — instalo el 'postgresql' de tu distro"
        PG_PKG="postgresql"
    fi

    log "Instalando ${PG_PKG}..."
    apt-get install -y "$PG_PKG"
    systemctl enable --now postgresql
    sleep 3

    [ "$POSTGRES_PASSWORD" = "auto" ] && POSTGRES_PASSWORD=$(gen_password)

    sudo -u postgres psql -qc "ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';"
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${USER_NAME}'" | grep -q 1 || \
        sudo -u postgres psql -qc "CREATE ROLE ${USER_NAME} LOGIN SUPERUSER CREATEDB PASSWORD '${POSTGRES_PASSWORD}';"
    sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${USER_NAME}'" | grep -q 1 || \
        sudo -u postgres createdb -O "${USER_NAME}" "${USER_NAME}"

    verify_service postgresql

    save_credential ""
    save_credential "POSTGRESQL $(psql --version 2>/dev/null | awk '{print $3}')"
    save_credential "  Acceso directo: psql            (rol ${USER_NAME}, peer auth)"
    save_credential "  Usuarios:       postgres / ${USER_NAME}"
    save_credential "  Contraseña:     ${POSTGRES_PASSWORD}"
    save_credential "  Host: 127.0.0.1:5432"
fi

# ------------------------------------------------------------
# REDIS
# ------------------------------------------------------------
if [[ "$INS_REDIS" =~ ^[Ss]$ ]]; then
    log "Instalando Redis..."
    apt-get install -y redis-server redis-tools

    CONF="/etc/redis/redis.conf"
    if [ -f "$CONF" ]; then
        backup_config "$CONF"
        sed -i 's|^#*\s*maxmemory\s.*|maxmemory 512mb|'                     "$CONF"
        sed -i 's|^#*\s*maxmemory-policy\s.*|maxmemory-policy allkeys-lru|' "$CONF"
        grep -q '^maxmemory '       "$CONF" || echo "maxmemory 512mb"              >> "$CONF"
        grep -q '^maxmemory-policy' "$CONF" || echo "maxmemory-policy allkeys-lru" >> "$CONF"
    fi

    systemctl enable --now redis-server
    systemctl restart redis-server
    verify_service redis-server

    save_credential ""
    save_credential "REDIS"
    save_credential "  Host: 127.0.0.1:6379   ·   sin password (solo local)"
    save_credential "  Probar: redis-cli ping"
    save_credential "  maxmemory 512mb / allkeys-lru"
fi

# ------------------------------------------------------------
# MAILPIT — captura TODO el correo saliente
# ------------------------------------------------------------
if [[ "$INS_MAILPIT" =~ ^[Ss]$ ]]; then
    log "Instalando Mailpit..."
    if curl -fsSL https://raw.githubusercontent.com/axllent/mailpit/develop/install.sh | bash; then
        id -u mailpit >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin -d /var/lib/mailpit mailpit
        mkdir -p /var/lib/mailpit && chown mailpit:mailpit /var/lib/mailpit

        cat > /etc/systemd/system/mailpit.service <<'MAILPIT'
[Unit]
Description=Mailpit - servidor SMTP de pruebas
After=network.target

[Service]
User=mailpit
Group=mailpit
ExecStart=/usr/local/bin/mailpit \
    --db-file /var/lib/mailpit/mailpit.db \
    --listen 127.0.0.1:8025 \
    --smtp 127.0.0.1:1025 \
    --max 2000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
MAILPIT
        systemctl daemon-reload
        systemctl enable --now mailpit
        verify_service mailpit

        # Que mail() de PHP también caiga en Mailpit
        if [[ "$INS_WEB" =~ ^[Ss]$ ]]; then
            for SAPI in fpm cli; do
                INI="/etc/php/${PHP_MAIN}/${SAPI}/php.ini"
                [ -f "$INI" ] && sed -i \
                    "s|^;*\s*sendmail_path\s*=.*|sendmail_path = /usr/local/bin/mailpit sendmail --smtp-addr localhost:1025|" "$INI"
            done
            systemctl restart "php${PHP_MAIN}-fpm" 2>/dev/null || true
        fi

        save_credential ""
        save_credential "MAILPIT (captura de correos)"
        save_credential "  Bandeja web: http://localhost:8025"
        save_credential "  SMTP:        127.0.0.1:1025 (sin auth, sin TLS)"
        save_credential "  PHP mail() queda redirigido a Mailpit."
    else
        log_error "Falló la instalación de Mailpit"
        FAILED+=("mailpit")
    fi
fi

# ------------------------------------------------------------
# NODE.JS vía NVM (por usuario, sin sudo)
# ------------------------------------------------------------
if [[ "$INS_NODE" =~ ^[Ss]$ ]]; then
    log "Instalando NVM ${NVM_VERSION}..."
    as_user touch "$USER_HOME/.bashrc"
    if as_user bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | PROFILE='$USER_HOME/.bashrc' bash"; then
        log "Instalando Node ${NODE_VERSION}..."
        if as_user bash -c ". '$USER_HOME/.nvm/nvm.sh' && nvm install ${NODE_VERSION} && nvm alias default ${NODE_VERSION} && corepack enable"; then
            NODE_V=$(as_user bash -c ". '$USER_HOME/.nvm/nvm.sh' && node --version")
            log "Node ${NODE_V} listo"
            INSTALLED+=("nvm+node")
            save_credential ""
            save_credential "NODE.JS (NVM)"
            save_credential "  Node por defecto: ${NODE_V}"
            save_credential "  Abre una terminal NUEVA para tener 'nvm' y 'node' en el PATH."
            save_credential "  Otra versión:  nvm install 22 && nvm use 22"
            save_credential "  corepack activo — 'pnpm' y 'yarn' funcionan directo"
        else
            log_error "NVM quedó instalado pero falló la instalación de Node"
            FAILED+=("node")
        fi
    else
        log_error "Falló la instalación de NVM"
        FAILED+=("nvm")
    fi
fi

# ------------------------------------------------------------
# DOCKER + PORTAINER
# ------------------------------------------------------------
if [[ "$INS_DOCKER" =~ ^[Ss]$ ]]; then
    log "Quitando paquetes de Docker no oficiales (si existen)..."
    for p in docker.io docker-doc docker-compose podman-docker containerd runc; do
        apt-get remove -y "$p" >/dev/null 2>&1 || true
    done

    log "Añadiendo repositorio oficial de Docker ($DISTRO $CODENAME)..."
    if url_ok "https://download.docker.com/linux/${DISTRO}/dists/${CODENAME}/InRelease"; then
        add_repo "docker" "https://download.docker.com/linux/${DISTRO}/gpg" \
                 "https://download.docker.com/linux/${DISTRO}" "$CODENAME" "stable"
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io \
            docker-buildx-plugin docker-compose-plugin
        systemctl enable --now docker
        sleep 3
        usermod -aG docker "$USER_NAME"
        verify_service docker

        if docker info >/dev/null 2>&1; then
            log "Levantando Portainer CE..."
            docker volume create portainer_data >/dev/null
            if docker inspect portainer >/dev/null 2>&1; then
                log_warn "El contenedor 'portainer' ya existe — lo dejo como está"
            else
                docker run -d --name portainer --restart=always \
                    -p 9443:9443 \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v portainer_data:/data \
                    portainer/portainer-ce:lts \
                    && INSTALLED+=("portainer") \
                    || { log_error "Falló Portainer"; FAILED+=("portainer"); }
            fi
        else
            log_error "Docker no responde — Portainer omitido"
            FAILED+=("portainer")
        fi

        save_credential ""
        save_credential "DOCKER + PORTAINER"
        save_credential "  Docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')  ·  compose: docker compose"
        save_credential "  Tu usuario quedó en el grupo 'docker': CIERRA SESIÓN y vuelve a entrar"
        save_credential "  (o corre 'newgrp docker') para usar docker sin sudo."
        save_credential "  Portainer: https://localhost:9443  (certificado autofirmado)"
        save_credential "  Crea el usuario admin en los primeros 5 min o Portainer se bloquea;"
        save_credential "  si pasa:  docker restart portainer"
    else
        log_error "Docker no publica repo para ${DISTRO} ${CODENAME}"
        FAILED+=("docker")
    fi
fi

# ------------------------------------------------------------
# DESINSTALADOR
# ------------------------------------------------------------
cat > "$USER_HOME/desinstalar-entorno.sh" <<'UNINSTALL'
#!/usr/bin/env bash
echo "DESINSTALADOR — esto BORRA tus bases de datos y volúmenes de Docker. No hay vuelta atrás."
read -rp "Escribe BORRAR para confirmar: " confirm
[ "$confirm" != "BORRAR" ] && { echo "Cancelado."; exit 0; }
sudo docker rm -f portainer 2>/dev/null || true
sudo systemctl stop apache2 mariadb postgresql redis-server mailpit docker 'php*-fpm' 2>/dev/null || true
sudo systemctl disable mailpit 2>/dev/null || true
sudo rm -f /etc/systemd/system/mailpit.service && sudo systemctl daemon-reload
sudo apt-get remove --purge -y 'apache2*' 'php*' 'mariadb-*' 'postgresql-*' redis-server \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
sudo apt-get autoremove --purge -y
sudo rm -rf /etc/apache2 /etc/php /var/lib/mysql /var/lib/postgresql /var/lib/mailpit /var/lib/docker /var/lib/containerd
sudo rm -f /etc/apt/sources.list.d/{sury-php,pgdg,docker}.sources
sudo rm -f /etc/apt/keyrings/{sury-php,pgdg,docker}.gpg
sudo rm -f /usr/local/bin/{composer,newsite,delsite,mailpit} /etc/dev-env.conf
echo "Listo. Tus proyectos en ~/proyectos NO se tocaron."
echo "NVM tampoco: para quitarlo borra ~/.nvm y sus líneas en ~/.bashrc"
UNINSTALL
chmod +x "$USER_HOME/desinstalar-entorno.sh"
chown "$USER_NAME":"$USER_GROUP" "$USER_HOME/desinstalar-entorno.sh"

# ------------------------------------------------------------
# RESUMEN
# ------------------------------------------------------------
{
    echo ""
    echo "========================================"
    echo "SERVICIOS"
    echo "========================================"
    for s in ${INSTALLED[@]+"${INSTALLED[@]}"}; do echo "  [OK] $s"; done
    if [ ${#FAILED[@]} -gt 0 ]; then
        echo ""
        echo "Con advertencias:"
        for s in "${FAILED[@]}"; do echo "  [!]  $s"; done
    fi
} >> "$CREDENTIALS_FILE"
chown "$USER_NAME":"$USER_GROUP" "$CREDENTIALS_FILE"

apt-get autoremove -y && apt-get autoclean

echo ""
echo "=================================================="
echo "  INSTALACIÓN COMPLETADA"
echo "=================================================="
cat "$CREDENTIALS_FILE"
echo "=================================================="
echo "Credenciales : $CREDENTIALS_FILE"
echo "Log          : $LOG_FILE"
echo "Desinstalador: $USER_HOME/desinstalar-entorno.sh"
echo "=================================================="
log_warn "Cierra esta terminal y abre una nueva (PATH de NVM y grupo docker)."
