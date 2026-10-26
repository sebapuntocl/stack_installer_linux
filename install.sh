#!/usr/bin/env bash
# ============================================================
# Entorno de Desarrollo â Debian 13 / Ubuntu 22.04+ (y derivadas)  Â· v3
# Nginx + PHP 8.5 + MariaDB + PostgreSQL 18 + Node 24 + Python
# Redis Â· Mailpit Â· DBeaver Â· mkcert (HTTPS local) Â· Oh My Bash
# Uso: sudo bash install-dev-debian13.sh
# ============================================================

set -euo pipefail

# ============================================================
# CONFIGURACIÃN
# ============================================================

GIT_NAME=""
GIT_EMAIL=""                      # tambiÃ©n se usa para la llave SSH
GIT_EDITOR="nano"                 # nano | vim | code

PHP_MAIN="8.5"                    # versiÃ³n de PHP a instalar
WEB_ROOT_REL="proyectos/php"
TIMEZONE="America/Santiago"

MARIADB_DEV_USER="dev"
MARIADB_DEV_PASSWORD="auto"
POSTGRES_PASSWORD="auto"

NODE_MAJOR="24"                   # 22 | 24
PG_VERSION="18"

INSTALL_XDEBUG="s"
CACHE_ENGINE="redis"              # redis | valkey
INSTALL_VSCODE="s"                # s | n

OMB_THEME="powerline-icon"        # tema de Oh My Bash (ver ~/.oh-my-bash/themes)

# ============================================================
# FIN CONFIGURACIÃN
# ============================================================

[ "$EUID" -ne 0 ] && { echo "Ejecuta con sudo: sudo bash $0"; exit 1; }
[ -z "${SUDO_USER:-}" ] && { echo "Ejecuta con sudo desde tu usuario normal, no como root."; exit 1; }

USER_NAME="$SUDO_USER"
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_GROUP=$(id -gn "$USER_NAME")
WEB_ROOT="$USER_HOME/$WEB_ROOT_REL"
CERT_DIR="/etc/nginx/certs"

# --- DetecciÃ³n de distro: Debian, Ubuntu y derivadas (Mint, Pop!_OS, Zorin...) ---
OS_ID=$(. /etc/os-release && echo "$ID")
OS_LIKE=$(. /etc/os-release && echo "${ID_LIKE:-}")
OS_PRETTY=$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
# En derivadas de Ubuntu, UBUNTU_CODENAME trae el codename base (noble, etc.)
CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
# Ubuntu primero: su ID_LIKE es "debian", asÃ­ que el orden importa.
case " ${OS_ID} ${OS_LIKE} " in
    *" ubuntu "*) DISTRO="ubuntu" ;;
    *" debian "*) DISTRO="debian" ;;
    *) echo "Distro no soportada: $OS_PRETTY (solo Debian/Ubuntu y derivadas)"; exit 1 ;;
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

add_bashrc_line() {
    grep -qF "$1" "$USER_HOME/.bashrc" 2>/dev/null || echo "$1" >> "$USER_HOME/.bashrc"
}

declare -a INSTALLED=()
declare -a FAILED=()

verify_service() {
    if systemctl is-active --quiet "$1"; then
        log "$1 corriendo"; INSTALLED+=("$1")
    else
        log_warn "$1 no estÃ¡ activo â revisa: systemctl status $1"; FAILED+=("$1")
    fi
}

# Â¿Responde esta URL (200)? Sirve para saber si un repo publica para tu versiÃ³n.
url_ok() { curl -fsS -o /dev/null --max-time 20 "$1" 2>/dev/null; }

# Â¿Existe el paquete en los repos configurados?
# LC_ALL=C es OBLIGATORIO: apt traduce su salida ("Candidate:" â "Candidato:" en
# espaÃ±ol). Sin esto, en un sistema que no estÃ© en inglÃ©s la funciÃ³n respondÃ­a
# "no existe" para TODO paquete.
pkg_exists() {
    local cand
    cand=$(LC_ALL=C apt-cache policy "$1" 2>/dev/null | awk '/^ *Candidate:/{print $2}') || cand=""
    [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

# Instala solo los paquetes que existen y avisa de los que no.
# Necesario porque las versiones nuevas de PHP no siempre traen todas
# las extensiones empaquetadas con el mismo nombre.
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

has_desktop() {
    # Sin pipes a propÃ³sito: con "set -o pipefail", "cmd | grep -q" puede dar
    # falso aunque haya coincidencia (SIGPIPE). Y GNOME reciente es solo Wayland.
    [ "$(systemctl get-default 2>/dev/null)" = "graphical.target" ] && return 0
    compgen -G "/usr/share/xsessions/*.desktop" >/dev/null && return 0
    compgen -G "/usr/share/wayland-sessions/*.desktop" >/dev/null && return 0
    return 1
}

# ------------------------------------------------------------
# MENÃ
# ------------------------------------------------------------
clear
cat <<BANNER
==================================================
  ENTORNO DEV â $OS_PRETTY Â· $ARCH
  Usuario: $USER_NAME
==================================================
  PHP $PHP_MAIN Â· Node $NODE_MAJOR Â· PostgreSQL $PG_VERSION
  MariaDB (repo de tu distro) Â· Python + uv Â· $CACHE_ENGINE
  Mailpit Â· DBeaver Â· mkcert (HTTPS) Â· Oh My Bash ($OMB_THEME)
==================================================
1) TODO
2) PERSONALIZADO
BANNER
read -rp "OpciÃ³n [1-2]: " MODO

case "$MODO" in
    1) INS_WEB=s; INS_MARIA=s; INS_POSTGRES=s; INS_NODE=s; INS_PYTHON=s
       INS_CACHE=s; INS_MAILPIT=s; INS_DBEAVER=s; INS_TOOLS=s; INS_OMB=s; INS_GIT=s ;;
    2)
        read -rp "â¢ Nginx + PHP-FPM $PHP_MAIN?      [s/n]: " INS_WEB
        read -rp "â¢ MariaDB?                        [s/n]: " INS_MARIA
        read -rp "â¢ PostgreSQL $PG_VERSION?         [s/n]: " INS_POSTGRES
        read -rp "â¢ Node.js $NODE_MAJOR?            [s/n]: " INS_NODE
        read -rp "â¢ Toolchain Python?               [s/n]: " INS_PYTHON
        read -rp "â¢ $CACHE_ENGINE (cachÃ©/colas)?    [s/n]: " INS_CACHE
        read -rp "â¢ Mailpit (captura de correos)?   [s/n]: " INS_MAILPIT
        read -rp "â¢ DBeaver (GUI de bases)?         [s/n]: " INS_DBEAVER
        read -rp "â¢ Herramientas CLI (rg, fd, bat)? [s/n]: " INS_TOOLS
        read -rp "â¢ Oh My Bash ($OMB_THEME)?  [s/n]: " INS_OMB
        read -rp "â¢ Git global + llave SSH?         [s/n]: " INS_GIT
        ;;
    *) log_error "OpciÃ³n invÃ¡lida"; exit 1 ;;
esac

{
    echo "========================================"
    echo "CREDENCIALES â ENTORNO DE DESARROLLO"
    echo "Generado: $(date)"
    echo "$OS_PRETTY ($CODENAME) â $(hostname)"
    echo "========================================"
} > "$CREDENTIALS_FILE"
chown "$USER_NAME":"$USER_GROUP" "$CREDENTIALS_FILE"; chmod 600 "$CREDENTIALS_FILE"

# ------------------------------------------------------------
# BASE
# ------------------------------------------------------------
# Si una corrida anterior dejÃ³ el PPA de ondrej en una versiÃ³n de Ubuntu que ya no
# lo soporta (26.04+), "apt-get update" falla con 404. Lo quitamos antes de actualizar.
if [ "$DISTRO" = "ubuntu" ] && compgen -G "/etc/apt/sources.list.d/ondrej-ubuntu-php*" >/dev/null; then
    if ! url_ok "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${CODENAME}/InRelease"; then
        log_warn "El PPA ondrej/php no soporta ${CODENAME} â lo elimino"
        rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php* \
              /etc/apt/keyrings/ondrej-ubuntu-php* /etc/apt/trusted.gpg.d/ondrej-ubuntu-php*
    fi
fi

log "Actualizando sistema..."
apt-get update || log_warn "apt update reportÃ³ errores (Â¿algÃºn repo de terceros caÃ­do?) â continÃºo"
apt-get upgrade -y

log "Instalando utilidades base..."
apt-get install -y curl wget git unzip zip jq tree build-essential \
    ca-certificates gnupg lsb-release openssl apt-transport-https acl

# ------------------------------------------------------------
# OH MY BASH + tema powerline-icon
# IMPORTANTE: va ANTES de cualquier add_bashrc_line. El instalador de
# Oh My Bash respalda ~/.bashrc y lo REEMPLAZA por su plantilla; si
# escribiÃ©ramos el PATH antes, esas lÃ­neas se perderÃ­an.
# ------------------------------------------------------------
if [[ "$INS_OMB" =~ ^[Ss]$ ]]; then
    OMB_DIR="$USER_HOME/.oh-my-bash"

    if has_desktop; then
        log "Instalando fuentes para el prompt (sÃ­mbolos Powerline + emojis)..."
        apt_install_available fonts-powerline fonts-noto-color-emoji
    fi

    if [ -d "$OMB_DIR" ]; then
        log_warn "Oh My Bash ya estaba instalado â solo reviso el tema"
    else
        log "Instalando Oh My Bash..."
        if curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh \
                -o /tmp/omb-install.sh; then
            chmod 644 /tmp/omb-install.sh
            # --unattended: sin esto el instalador hace "exec bash" y el script se cuelga
            ( cd "$USER_HOME" && as_user bash /tmp/omb-install.sh --unattended ) \
                || { log_error "FallÃ³ el instalador de Oh My Bash"; FAILED+=("oh-my-bash"); }
            rm -f /tmp/omb-install.sh
        else
            log_error "No pude descargar el instalador de Oh My Bash"
            FAILED+=("oh-my-bash")
        fi
    fi

    if [ -d "$OMB_DIR/themes/$OMB_THEME" ] && grep -q '^OSH_THEME=' "$USER_HOME/.bashrc" 2>/dev/null; then
        as_user sed -i "s|^OSH_THEME=.*|OSH_THEME=\"${OMB_THEME}\"|" "$USER_HOME/.bashrc"
        log "Oh My Bash listo con el tema ${OMB_THEME}"
        INSTALLED+=("oh-my-bash")

        save_credential ""
        save_credential "OH MY BASH (tema ${OMB_THEME})"
        save_credential "  Abre una terminal NUEVA para verlo."
        save_credential "  Cambiar tema: edita OSH_THEME en ~/.bashrc (temas en ~/.oh-my-bash/themes)"
        save_credential "  Tu .bashrc anterior quedÃ³ respaldado en ~/.bashrc.omb-backup-*"
        save_credential "  Si ves cuadritos o sÃ­mbolos raros: cierra y reabre la terminal."
        save_credential "  Desinstalar: uninstall_oh_my_bash"
    else
        log_warn "No pude fijar el tema '${OMB_THEME}' (Â¿existe en ~/.oh-my-bash/themes?)"
        FAILED+=("oh-my-bash-theme")
    fi
fi

add_bashrc_line 'export PATH="$HOME/.local/bin:$PATH"'

# ------------------------------------------------------------
# mkcert â CA local para HTTPS en .test
# ------------------------------------------------------------
log "Instalando mkcert (certificados locales de confianza)..."
if apt-get install -y mkcert libnss3-tools 2>/dev/null; then
    as_user mkcert -install >/dev/null 2>&1 || log_warn "mkcert -install fallÃ³ (Â¿sin navegador aÃºn?). Corre 'mkcert -install' despuÃ©s."
    mkdir -p "$CERT_DIR"; chmod 755 "$CERT_DIR"
    MKCERT_OK=1
    log "mkcert listo â los sitios .test tendrÃ¡n HTTPS vÃ¡lido"
else
    MKCERT_OK=0
    log_warn "mkcert no disponible en los repos â los sitios quedarÃ¡n solo en HTTP"
fi

# ------------------------------------------------------------
# NGINX + PHP-FPM
# ------------------------------------------------------------
if [[ "$INS_WEB" =~ ^[Ss]$ ]]; then
    log "Instalando Nginx..."
    apt-get install -y nginx

    # Orden de preferencia para conseguir PHP ${PHP_MAIN}:
    #  1) Los repos que ya tienes, si traen esa versiÃ³n (Ubuntu 26.04 trae PHP 8.5
    #     de fÃ¡brica â cero repos externos, cero cosas que se puedan romper).
    #  2) Debian: repo de Sury (packages.sury.org).
    #  3) Ubuntu: PPA de OndÅej (22.04/24.04) o, si el PPA no soporta tu versiÃ³n,
    #     packages.sury.org (su canal nuevo).
    if pkg_exists "php${PHP_MAIN}-fpm"; then
        log "PHP ${PHP_MAIN} ya estÃ¡ disponible en tus repos â no agrego repo externo"
    elif [ "$DISTRO" = "debian" ]; then
        log "AÃ±adiendo repositorio Sury (PHP para Debian $CODENAME)..."
        add_repo "sury-php" "https://packages.sury.org/php/apt.gpg" \
                 "https://packages.sury.org/php/" "$CODENAME" "main"
        apt-get update
    elif url_ok "https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${CODENAME}/InRelease"; then
        log "AÃ±adiendo PPA ondrej/php (PHP para Ubuntu $CODENAME)..."
        apt-get install -y software-properties-common
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
        apt-get update
    elif url_ok "https://packages.sury.org/php/dists/${CODENAME}/InRelease"; then
        log "El PPA no soporta $CODENAME â uso packages.sury.org"
        add_repo "sury-php" "https://packages.sury.org/php/apt.gpg" \
                 "https://packages.sury.org/php/" "$CODENAME" "main"
        apt-get update
    else
        log_warn "No encontrÃ© un repo externo con PHP para $CODENAME â pruebo con los de tu distro"
    fi

    PHP_VERSIONS=("$PHP_MAIN")

    for V in "${PHP_VERSIONS[@]}"; do
        log "Instalando PHP $V (nÃºcleo)..."
        # Estos SÃ o SÃ tienen que existir. Si fallan, no hay PHP.
        if ! pkg_exists "php${V}-fpm"; then
            log_error "php${V}-fpm no existe en el repo de PHP para $OS_PRETTY ($CODENAME)."
            log_error "Versiones disponibles: $(apt-cache search --names-only '^php[0-9]\.[0-9]+-fpm$' | awk '{print $1}' | tr '\n' ' ')"
            exit 1
        fi
        apt-get install -y "php${V}-fpm" "php${V}-cli" "php${V}-common"

        log "Instalando extensiones de PHP $V..."
        # opcache, redis, imagick y otras pueden venir integradas o no estar
        # empaquetadas aÃºn segÃºn la versiÃ³n: se instalan solo si existen.
        apt_install_available \
            "php${V}-opcache"  "php${V}-mysql"   "php${V}-pgsql"  "php${V}-sqlite3" \
            "php${V}-mbstring" "php${V}-xml"     "php${V}-curl"   "php${V}-zip" \
            "php${V}-gd"       "php${V}-intl"    "php${V}-bcmath" "php${V}-readline" \
            "php${V}-redis"    "php${V}-imagick"

        # Comprobar que las extensiones crÃ­ticas quedaron cargadas
        for EXT in pdo_mysql pgsql mbstring curl; do
            "php${V}" -m 2>/dev/null | grep -qi "^${EXT}$" \
                || log_warn "PHP $V: la extensiÃ³n '${EXT}' no quedÃ³ cargada"
        done
        "php${V}" -m 2>/dev/null | grep -qi 'Zend OPcache\|opcache' \
            && log "PHP $V: OPcache activo" \
            || log_warn "PHP $V: OPcache no estÃ¡ cargado"

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

        # Pool FPM con TU usuario â sin peleas de permisos en storage/, cache/
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
    done

    mkdir -p "$WEB_ROOT"
    chown -R "$USER_NAME":"$USER_GROUP" "$WEB_ROOT"
    chmod 755 "$USER_HOME" "$WEB_ROOT"

    PHP_SOCK="/run/php/php${PHP_MAIN}-fpm.sock"
    cat > /etc/nginx/sites-available/dev-default.conf <<EOF
server {
    listen 80 default_server;
    server_name localhost;
    root ${WEB_ROOT};
    index index.php index.html;
    autoindex on;

    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
    }
    location ~ /\.(?!well-known) { deny all; }
}
EOF
    ln -sf /etc/nginx/sites-available/dev-default.conf /etc/nginx/sites-enabled/dev-default.conf
    rm -f /etc/nginx/sites-enabled/default

    nginx -t
    systemctl enable --now nginx
    systemctl reload nginx
    verify_service nginx

    # --- Composer con verificaciÃ³n de firma ---
    log "Instalando Composer..."
    EXPECTED=$(curl -fsSL https://composer.github.io/installer.sig)
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
    ACTUAL=$(php -r "echo hash_file('sha384','/tmp/composer-setup.php');")
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        log_error "Hash de Composer NO coincide. InstalaciÃ³n abortada por seguridad."
    else
        php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
        log "Composer $(composer --version 2>/dev/null | awk '{print $3}') instalado"
        add_bashrc_line 'export PATH="$HOME/.config/composer/vendor/bin:$PATH"'
        as_user composer global require laravel/installer --quiet 2>/dev/null \
            || log_warn "No se pudo instalar el laravel/installer global (puedes hacerlo despuÃ©s)"
    fi
    rm -f /tmp/composer-setup.php

    # --- Config compartida para el comando newsite ---
    cat > /etc/dev-env.conf <<EOF
DEV_USER="${USER_NAME}"
DEV_GROUP="${USER_GROUP}"
DEV_WEB_ROOT="${WEB_ROOT}"
DEV_PHP_DEFAULT="${PHP_MAIN}"
DEV_CERT_DIR="${CERT_DIR}"
DEV_MKCERT="${MKCERT_OK}"
EOF

    cat > /usr/local/bin/newsite <<'NEWSITE'
#!/usr/bin/env bash
# newsite <nombre>  â crea http(s)://<nombre>.test
set -euo pipefail
[ "$EUID" -ne 0 ] && { echo "Usa: sudo newsite <nombre>"; exit 1; }
source /etc/dev-env.conf

NAME="${1:?Uso: sudo newsite <nombre>}"
PHPV="$DEV_PHP_DEFAULT"
ROOT="$DEV_WEB_ROOT/$NAME"
DOCROOT="$ROOT/public"; [ -d "$DOCROOT" ] || DOCROOT="$ROOT"
mkdir -p "$DOCROOT"; chown -R "$DEV_USER":"$DEV_GROUP" "$ROOT"

SSL_BLOCK=""
SCHEME="http"
if [ "$DEV_MKCERT" = "1" ]; then
    mkdir -p "$DEV_CERT_DIR"
    if [ ! -f "$DEV_CERT_DIR/$NAME.test.pem" ]; then
        sudo -u "$DEV_USER" -H mkcert -cert-file "/tmp/$NAME.pem" -key-file "/tmp/$NAME-key.pem" \
            "$NAME.test" "*.$NAME.test" >/dev/null 2>&1
        mv "/tmp/$NAME.pem"     "$DEV_CERT_DIR/$NAME.test.pem"
        mv "/tmp/$NAME-key.pem" "$DEV_CERT_DIR/$NAME.test-key.pem"
        chmod 644 "$DEV_CERT_DIR/$NAME.test.pem"
        chmod 640 "$DEV_CERT_DIR/$NAME.test-key.pem"
        chgrp www-data "$DEV_CERT_DIR/$NAME.test-key.pem"
    fi
    # "http2 on;" solo existe desde nginx 1.25.1. Ubuntu 24.04 trae 1.24.
    NGX_VER=$(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -n1)
    if [ "$(printf '%s\n1.25.1\n' "$NGX_VER" | sort -V | head -n1)" = "1.25.1" ]; then
        LISTEN_SSL="    listen 443 ssl;
    http2 on;"
    else
        LISTEN_SSL="    listen 443 ssl http2;"
    fi
    SSL_BLOCK="$LISTEN_SSL
    ssl_certificate     $DEV_CERT_DIR/$NAME.test.pem;
    ssl_certificate_key $DEV_CERT_DIR/$NAME.test-key.pem;"
    SCHEME="https"
fi

cat > "/etc/nginx/sites-available/$NAME.conf" <<CONF
server {
    listen 80;
$SSL_BLOCK
    server_name $NAME.test *.$NAME.test;
    root $DOCROOT;
    index index.php index.html;

    client_max_body_size 64M;

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHPV-fpm.sock;
        fastcgi_read_timeout 300;
    }
    location ~ /\.(?!well-known) { deny all; }
}
CONF

ln -sf "/etc/nginx/sites-available/$NAME.conf" "/etc/nginx/sites-enabled/$NAME.conf"
grep -q "[[:space:]]$NAME.test\$" /etc/hosts || echo "127.0.0.1   $NAME.test" >> /etc/hosts
nginx -t && systemctl reload nginx
echo "Listo â $SCHEME://$NAME.test"
echo "  docroot: $DOCROOT   PHP: $PHPV"
NEWSITE
    chmod +x /usr/local/bin/newsite

    cat > /usr/local/bin/delsite <<'DELSITE'
#!/usr/bin/env bash
# delsite <nombre> â borra el vhost (NO borra tus archivos)
set -euo pipefail
[ "$EUID" -ne 0 ] && { echo "Usa: sudo delsite <nombre>"; exit 1; }
source /etc/dev-env.conf
NAME="${1:?Uso: sudo delsite <nombre>}"
rm -f "/etc/nginx/sites-enabled/$NAME.conf" "/etc/nginx/sites-available/$NAME.conf"
rm -f "$DEV_CERT_DIR/$NAME.test.pem" "$DEV_CERT_DIR/$NAME.test-key.pem"
sed -i "/[[:space:]]$NAME\.test\$/d" /etc/hosts
nginx -t && systemctl reload nginx
echo "Vhost $NAME eliminado. Los archivos en $DEV_WEB_ROOT/$NAME siguen ahÃ­."
DELSITE
    chmod +x /usr/local/bin/delsite

    save_credential ""
    save_credential "NGINX + PHP-FPM"
    save_credential "  PHP: ${PHP_MAIN}"
    save_credential "  Webroot: ${WEB_ROOT}   Â·   Ãndice: http://localhost"
    save_credential "  Nuevo sitio:  sudo newsite miapp        -> https://miapp.test"
    save_credential "  Borrar sitio: sudo delsite miapp"
    save_credential "  Xdebug: modo trigger, puerto 9003 (XDEBUG_TRIGGER=1 php artisan ...)"
fi

# ------------------------------------------------------------
# MARIADB
# ------------------------------------------------------------
if [[ "$INS_MARIA" =~ ^[Ss]$ ]]; then
    log "Instalando MariaDB (versiÃ³n del repo de $OS_PRETTY)..."
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
    save_credential "  ContraseÃ±a:     ${MARIADB_DEV_PASSWORD}"
    save_credential "  .env Laravel:   DB_HOST=127.0.0.1 DB_PORT=3306 DB_USERNAME=${MARIADB_DEV_USER}"
fi

# ------------------------------------------------------------
# POSTGRESQL
# ------------------------------------------------------------
if [[ "$INS_POSTGRES" =~ ^[Ss]$ ]]; then
    PG_PKG="postgresql-${PG_VERSION}"
    if pkg_exists "$PG_PKG"; then
        log "PostgreSQL ${PG_VERSION} ya estÃ¡ en tus repos â no agrego PGDG"
    elif url_ok "https://apt.postgresql.org/pub/repos/apt/dists/${CODENAME}-pgdg/InRelease"; then
        log "AÃ±adiendo repositorio PGDG..."
        add_repo "pgdg" "https://www.postgresql.org/media/keys/ACCC4CF8.asc" \
                 "https://apt.postgresql.org/pub/repos/apt" "${CODENAME}-pgdg" "main"
        apt-get update
    else
        log_warn "PGDG no publica para ${CODENAME} y tu distro no trae PostgreSQL ${PG_VERSION} â instalo el 'postgresql' de tu distro"
        PG_PKG="postgresql"
    fi

    log "Instalando ${PG_PKG}..."
    # contrib ya viene dentro del paquete principal (postgresql-contrib-NN no existe)
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
    save_credential "  ContraseÃ±a:     ${POSTGRES_PASSWORD}"
    save_credential "  .env Laravel:   DB_HOST=127.0.0.1 DB_PORT=5432 DB_USERNAME=${USER_NAME}"
fi

# ------------------------------------------------------------
# REDIS / VALKEY
# ------------------------------------------------------------
if [[ "$INS_CACHE" =~ ^[Ss]$ ]]; then
    # Valkey no existe en todas las versiones (p.ej. Ubuntu 24.04): fallback a Redis
    if [ "$CACHE_ENGINE" = "valkey" ] && ! pkg_exists valkey-server; then
        log_warn "valkey no estÃ¡ en los repos de $OS_PRETTY â uso Redis"
        CACHE_ENGINE="redis"
    fi

    if [ "$CACHE_ENGINE" = "valkey" ]; then
        log "Instalando Valkey (fork libre de Redis)..."
        apt-get install -y valkey-server valkey-tools
        CACHE_SVC="valkey-server"; CACHE_CLI="valkey-cli"
        CACHE_CONF="/etc/valkey/valkey.conf"
    else
        log "Instalando Redis..."
        apt-get install -y redis-server redis-tools
        CACHE_SVC="redis-server"; CACHE_CLI="redis-cli"
        CACHE_CONF="/etc/redis/redis.conf"
    fi

    if [ -f "$CACHE_CONF" ]; then
        backup_config "$CACHE_CONF"
        # En una notebook no queremos que se coma la RAM
        sed -i 's|^#*\s*maxmemory\s.*|maxmemory 512mb|'                          "$CACHE_CONF"
        sed -i 's|^#*\s*maxmemory-policy\s.*|maxmemory-policy allkeys-lru|'      "$CACHE_CONF"
        grep -q '^maxmemory '        "$CACHE_CONF" || echo "maxmemory 512mb"                >> "$CACHE_CONF"
        grep -q '^maxmemory-policy'  "$CACHE_CONF" || echo "maxmemory-policy allkeys-lru"   >> "$CACHE_CONF"
    fi

    systemctl enable --now "$CACHE_SVC"
    systemctl restart "$CACHE_SVC"
    verify_service "$CACHE_SVC"

    save_credential ""
    save_credential "$(echo "$CACHE_ENGINE" | tr '[:lower:]' '[:upper:]')"
    save_credential "  Host: 127.0.0.1:6379   Â·   sin password (solo local)"
    save_credential "  Cliente: ${CACHE_CLI}       Â·   probar: ${CACHE_CLI} ping"
    save_credential "  maxmemory 512mb / allkeys-lru (para no ahogar la notebook)"
    save_credential "  .env Laravel: REDIS_HOST=127.0.0.1  CACHE_STORE=redis  QUEUE_CONNECTION=redis"
fi

# ------------------------------------------------------------
# MAILPIT â captura TODO el correo saliente
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

        # Que mail() de PHP tambiÃ©n caiga en Mailpit
        if [[ "$INS_WEB" =~ ^[Ss]$ ]]; then
            for V in "${PHP_VERSIONS[@]}"; do
                for SAPI in fpm cli; do
                    INI="/etc/php/${V}/${SAPI}/php.ini"
                    [ -f "$INI" ] && sed -i \
                        "s|^;*\s*sendmail_path\s*=.*|sendmail_path = /usr/local/bin/mailpit sendmail --smtp-addr localhost:1025|" "$INI"
                done
                systemctl restart "php${V}-fpm" 2>/dev/null || true
            done
        fi

        save_credential ""
        save_credential "MAILPIT (captura de correos)"
        save_credential "  Bandeja web: http://localhost:8025"
        save_credential "  SMTP:        127.0.0.1:1025 (sin auth, sin TLS)"
        save_credential "  .env Laravel: MAIL_MAILER=smtp MAIL_HOST=127.0.0.1 MAIL_PORT=1025"
        save_credential "                MAIL_USERNAME=null MAIL_PASSWORD=null MAIL_ENCRYPTION=null"
        save_credential "  PHP mail() tambiÃ©n queda redirigido a Mailpit."
    else
        log_error "FallÃ³ la instalaciÃ³n de Mailpit"
        FAILED+=("mailpit")
    fi
fi

# ------------------------------------------------------------
# NODE.JS
# ------------------------------------------------------------
if [[ "$INS_NODE" =~ ^[Ss]$ ]]; then
    log "AÃ±adiendo repositorio NodeSource (Node ${NODE_MAJOR})..."
    add_repo "nodesource" "https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key" \
             "https://deb.nodesource.com/node_${NODE_MAJOR}.x" "nodistro" "main"
    cat > /etc/apt/preferences.d/nodesource <<'PREF'
Package: nodejs
Pin: origin deb.nodesource.com
Pin-Priority: 700
PREF
    apt-get update
    apt-get install -y nodejs
    corepack enable >/dev/null 2>&1 || true

    as_user mkdir -p "$USER_HOME/.npm-global"
    as_user npm config set prefix "$USER_HOME/.npm-global"
    add_bashrc_line 'export PATH="$HOME/.npm-global/bin:$PATH"'

    log "Node $(node --version) / npm $(npm --version)"
    save_credential ""
    save_credential "NODE.JS"
    save_credential "  Node: $(node --version)   npm: $(npm --version)"
    save_credential "  corepack activo â 'pnpm' y 'yarn' funcionan directo"
    save_credential "  npm global sin sudo â ~/.npm-global/bin"
fi

# ------------------------------------------------------------
# PYTHON
# ------------------------------------------------------------
if [[ "$INS_PYTHON" =~ ^[Ss]$ ]]; then
    log "Instalando toolchain de Python..."
    apt-get install -y python3-full python3-venv python3-dev python3-pip pipx \
        libpq-dev default-libmysqlclient-dev pkg-config

    as_user pipx ensurepath >/dev/null 2>&1 || true

    log "Instalando uv..."
    as_user bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' >/dev/null 2>&1 \
        || log_warn "uv fallÃ³ â instÃ¡lalo luego: curl -LsSf https://astral.sh/uv/install.sh | sh"

    save_credential ""
    save_credential "PYTHON $(python3 --version | awk '{print $2}')"
    save_credential "  OJO: tu distro usa PEP 668 â 'pip install' global FALLA. Es normal."
    save_credential "  Proyecto nuevo:   uv init miapp && cd miapp && uv add requests"
    save_credential "  Otra version py:  uv python install 3.12"
    save_credential "  Venv clasico:     python3 -m venv .venv && source .venv/bin/activate"
    save_credential "  CLI tools:        pipx install ruff   (black, poetry, httpie...)"
fi

# ------------------------------------------------------------
# DBEAVER
# ------------------------------------------------------------
if [[ "$INS_DBEAVER" =~ ^[Ss]$ ]]; then
    if has_desktop; then
        log "Instalando DBeaver Community..."
        DEB="/tmp/dbeaver-ce.deb"
        if curl -fsSL "https://dbeaver.io/files/dbeaver-ce_latest_${ARCH}.deb" -o "$DEB"; then
            apt-get install -y "$DEB" && INSTALLED+=("dbeaver-ce") || { log_error "DBeaver fallÃ³"; FAILED+=("dbeaver-ce"); }
            rm -f "$DEB"
            save_credential ""
            save_credential "DBEAVER CE"
            save_credential "  Lanzador en el menÃº de aplicaciones, o comando: dbeaver"
            save_credential "  MariaDB:    127.0.0.1:3306  usuario ${MARIADB_DEV_USER:-dev}"
            save_credential "  PostgreSQL: 127.0.0.1:5432  usuario ${USER_NAME}"
            save_credential "  Oracle: DBeaver trae el driver JDBC, no necesitas instantclient."
        else
            log_error "No se pudo descargar DBeaver"; FAILED+=("dbeaver-ce")
        fi
    else
        log_warn "No detectÃ© entorno grÃ¡fico â omitiendo DBeaver"
    fi
fi

# ------------------------------------------------------------
# VS CODE
# ------------------------------------------------------------
if [[ "$INSTALL_VSCODE" =~ ^[Ss]$ ]] && has_desktop; then
    log "Instalando Visual Studio Code..."
    add_repo "vscode" "https://packages.microsoft.com/keys/microsoft.asc" \
             "https://packages.microsoft.com/repos/code" "stable" "main"
    apt-get update
    apt-get install -y code && INSTALLED+=("vscode") || log_warn "VS Code fallÃ³"
fi

# ------------------------------------------------------------
# HERRAMIENTAS CLI
# ------------------------------------------------------------
if [[ "$INS_TOOLS" =~ ^[Ss]$ ]]; then
    log "Instalando herramientas CLI..."
    apt-get install -y ripgrep fd-find bat fzf btop ncdu httpie tmux

    # Debian renombra estos binarios; los dejamos con el nombre real
    as_user mkdir -p "$USER_HOME/.local/bin"
    [ -x /usr/bin/batcat ] && as_user ln -sf /usr/bin/batcat "$USER_HOME/.local/bin/bat"
    [ -x /usr/bin/fdfind ] && as_user ln -sf /usr/bin/fdfind "$USER_HOME/.local/bin/fd"

    save_credential ""
    save_credential "HERRAMIENTAS CLI"
    save_credential "  rg 'texto'     buscar en el proyecto (ignora node_modules/vendor solo)"
    save_credential "  fd nombre      buscar archivos"
    save_credential "  bat archivo    cat con colores y numeros de linea"
    save_credential "  btop           monitor de recursos"
    save_credential "  ncdu           que se esta comiendo el disco"
    save_credential "  http GET url   cliente HTTP decente para probar APIs"
fi

# ------------------------------------------------------------
# GIT + LLAVE SSH
# ------------------------------------------------------------
if [[ "$INS_GIT" =~ ^[Ss]$ ]]; then
    if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
        log_warn "GIT_NAME/GIT_EMAIL vacÃ­os â omitiendo configuraciÃ³n de Git y llave SSH"
    else
        log "Configurando Git global para $GIT_NAME..."
        as_user git config --global user.name  "$GIT_NAME"
        as_user git config --global user.email "$GIT_EMAIL"
        as_user git config --global core.editor "$GIT_EDITOR"
        as_user git config --global init.defaultBranch main
        as_user git config --global pull.rebase false
        as_user git config --global push.autoSetupRemote true
        as_user git config --global rerere.enabled true
        as_user git config --global diff.algorithm histogram

        cat > "$USER_HOME/.gitignore_global" <<'GITIGNORE'
.DS_Store
Thumbs.db
.idea/
.vscode/
.env
.env.local
node_modules/
vendor/
__pycache__/
.venv/
*.log
dist/
build/
GITIGNORE
        chown "$USER_NAME":"$USER_GROUP" "$USER_HOME/.gitignore_global"
        as_user git config --global core.excludesfile "$USER_HOME/.gitignore_global"

        SSH_KEY="$USER_HOME/.ssh/id_ed25519"
        if [ ! -f "$SSH_KEY" ]; then
            log "Generando llave SSH ed25519..."
            as_user mkdir -p "$USER_HOME/.ssh"
            as_user chmod 700 "$USER_HOME/.ssh"
            as_user ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N "" -q
        fi

        save_credential ""
        save_credential "GIT"
        save_credential "  $GIT_NAME <$GIT_EMAIL> Â· editor $GIT_EDITOR"
        save_credential ""
        save_credential "  Llave SSH pÃºblica (pÃ©gala en GitHub/GitLab â Settings â SSH Keys):"
        save_credential "  $(cat "${SSH_KEY}.pub")"
        save_credential "  Probar: ssh -T git@github.com"
    fi
fi

# ------------------------------------------------------------
# DESINSTALADOR
# ------------------------------------------------------------
cat > "$USER_HOME/desinstalar-entorno.sh" <<'UNINSTALL'
#!/usr/bin/env bash
echo "DESINSTALADOR â esto BORRA tus bases de datos. No hay vuelta atrÃ¡s."
read -rp "Escribe BORRAR para confirmar: " confirm
[ "$confirm" != "BORRAR" ] && { echo "Cancelado."; exit 0; }
sudo systemctl stop nginx mariadb postgresql redis-server valkey-server mailpit 'php*-fpm' 2>/dev/null || true
sudo systemctl disable mailpit 2>/dev/null || true
sudo rm -f /etc/systemd/system/mailpit.service && sudo systemctl daemon-reload
sudo apt-get remove --purge -y 'nginx*' 'php*' 'mariadb-*' 'postgresql-*' \
    nodejs redis-server valkey-server dbeaver-ce code 2>/dev/null || true
sudo apt-get autoremove --purge -y
sudo rm -rf /etc/nginx /etc/php /var/lib/mysql /var/lib/postgresql /var/lib/mailpit
sudo add-apt-repository -y -r ppa:ondrej/php 2>/dev/null || true
sudo rm -f /etc/apt/sources.list.d/{sury-php,pgdg,nodesource,vscode}.sources
sudo rm -f /etc/apt/keyrings/{sury-php,pgdg,nodesource,vscode}.gpg
sudo rm -f /usr/local/bin/{composer,newsite,delsite,mailpit} /etc/dev-env.conf
echo "Listo. Tus proyectos en ~/proyectos NO se tocaron."
echo "Oh My Bash tampoco: para quitarlo, en una terminal nueva ejecuta: uninstall_oh_my_bash"
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

apt-get autoremove -y && apt-get autoclean

echo ""
echo "=================================================="
echo "  INSTALACIÃN COMPLETADA"
echo "=================================================="
cat "$CREDENTIALS_FILE"
echo "=================================================="
echo "Credenciales : $CREDENTIALS_FILE"
echo "Log          : $LOG_FILE"
echo "Desinstalador: $USER_HOME/desinstalar-entorno.sh"
echo "=================================================="
log_warn "Cierra esta terminal y abre una nueva para ver el prompt nuevo y el PATH."
