#!/usr/bin/env bash
# ============================================================
# Entorno de Desarrollo con Docker — Debian 13 / Ubuntu 24.04+ (y derivadas) · v4
#
# Opción 1 (TODO)
#   Docker + Nginx, PHP-FPM, MariaDB, PostgreSQL, Redis y Mailpit en contenedores.
#   Composer, Node y Python también corren en contenedores, con wrappers
#   (php, composer, node, npm, python, uv...) para usarlos como siempre.
#   Más: mkcert (HTTPS local), DBeaver, VS Code, Git + SSH, Oh My Bash, herramientas CLI.
#
# Opción 2 (BÁSICO)
#   Solo Git global + llave SSH, Oh My Bash y herramientas CLI. Sin Docker.
#
# Uso: sudo bash install-dev.sh
# ============================================================

set -euo pipefail

# ============================================================
# CONFIGURACIÓN
# ============================================================

# --- GIT (déjalo vacío para no configurar Git ni crear llave SSH) ---
GIT_NAME=""
GIT_EMAIL=""                      # también se usa como comentario de la llave SSH
GIT_EDITOR="nano"                 # nano | vim | code

# --- CARPETAS (relativas a tu home) ---
PROJECTS_DIR_REL="proyectos"      # se monta con la MISMA ruta dentro de los contenedores
STACK_DIR_REL="dev-stack"         # docker-compose, Dockerfiles y configuración
TIMEZONE="America/Santiago"

# --- VERSIONES (en contenedores) ---
PHP_VERSION="8.5"
NODE_MAJOR="24"
PYTHON_VERSION="3.13"

# --- IMÁGENES DE LOS SERVICIOS ---
IMG_NGINX="nginx:stable-alpine"
IMG_MARIADB="mariadb:11.8"
IMG_POSTGRES="postgres:18"
IMG_REDIS="redis:8-alpine"
IMG_MAILPIT="axllent/mailpit:latest"

# --- BASES DE DATOS ---
# "auto" genera contraseñas aleatorias. Si ya existen en ~/dev-stack/.env se conservan
# (las bases solo aplican la contraseña al crearse). Solo letras, números y . _ @ % + = : , -
DB_USER="dev"                     # usuario de MariaDB y de PostgreSQL
DB_PASSWORD="auto"
MARIADB_ROOT_PASSWORD="auto"

# --- OTROS ---
INSTALL_XDEBUG="s"                # s | n
INSTALL_VSCODE="s"                # s | n  (solo con entorno gráfico)
OMB_THEME="powerline-icon"        # tema de Oh My Bash (ver ~/.oh-my-bash/themes)

# ============================================================
# FIN CONFIGURACIÓN
# ============================================================

declare -a INSTALLED=()
declare -a FAILED=()
declare -a DC=()                  # comando de compose: (docker compose) o (docker-compose)

# ------------------------------------------------------------
# UTILIDADES
# ------------------------------------------------------------
log()       { echo -e "\e[1;32m[OK]\e[0m $1"; }
log_warn()  { echo -e "\e[1;33m[!]\e[0m  $1"; }
log_error() { echo -e "\e[1;31m[X]\e[0m  $1"; }

as_user() { sudo -u "$USER_NAME" -H "$@"; }

save_credential() {
    echo "$1" >> "$CREDENTIALS_FILE"
    chmod 600 "$CREDENTIALS_FILE"
    chown "$USER_NAME":"$USER_GROUP" "$CREDENTIALS_FILE"
}

gen_password() { openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-20; }

add_bashrc_line() {
    grep -qF "$1" "$USER_HOME/.bashrc" 2>/dev/null || echo "$1" >> "$USER_HOME/.bashrc"
}

verify_service() {
    if systemctl is-active --quiet "$1"; then
        log "$1 corriendo"; INSTALLED+=("$1")
    else
        log_warn "$1 no está activo — revisa: systemctl status $1"; FAILED+=("$1")
    fi
}

# ¿Responde esta URL (200)? Sirve para saber si un repo publica para tu versión.
url_ok() { curl -fsS -o /dev/null --max-time 20 "$1" 2>/dev/null; }

# ¿Existe el paquete en los repos configurados?
# LC_ALL=C es OBLIGATORIO: apt traduce su salida ("Candidate:" → "Candidato:" en
# español). Sin esto, en un sistema que no esté en inglés la función respondía
# "no existe" para TODO paquete.
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
    if [ ${#have[@]} -gt 0 ]; then apt-get install -y "${have[@]}"; fi
    if [ ${#missing[@]} -gt 0 ]; then log_warn "No existen en el repo (se omiten): ${missing[*]}"; fi
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
    # Sin pipes a propósito: con "set -o pipefail", "cmd | grep -q" puede dar
    # falso aunque haya coincidencia (SIGPIPE). Y GNOME reciente es solo Wayland.
    [ "$(systemctl get-default 2>/dev/null)" = "graphical.target" ] && return 0
    compgen -G "/usr/share/xsessions/*.desktop" >/dev/null && return 0
    compgen -G "/usr/share/wayland-sessions/*.desktop" >/dev/null && return 0
    return 1
}

# ------------------------------------------------------------
# CONTEXTO: root, usuario, distro, log, credenciales, menú
# ------------------------------------------------------------
require_root() {
    if [ "$EUID" -ne 0 ]; then echo "Ejecuta con sudo: sudo bash $0"; exit 1; fi
    if [ -z "${SUDO_USER:-}" ]; then echo "Ejecuta con sudo desde tu usuario normal, no como root."; exit 1; fi
    return 0
}

# Debian, Ubuntu y derivadas (Mint, Pop!_OS, Zorin...)
detect_distro() {
    OS_ID=$(. /etc/os-release && echo "$ID")
    OS_LIKE=$(. /etc/os-release && echo "${ID_LIKE:-}")
    OS_PRETTY=$(. /etc/os-release && echo "${PRETTY_NAME:-$ID}")
    # En derivadas de Ubuntu, UBUNTU_CODENAME trae el codename base (noble, etc.)
    CODENAME=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")
    # Ubuntu primero: su ID_LIKE es "debian", así que el orden importa.
    case " ${OS_ID} ${OS_LIKE} " in
        *" ubuntu "*) DISTRO="ubuntu" ;;
        *" debian "*) DISTRO="debian" ;;
        *) echo "Distro no soportada: $OS_PRETTY (solo Debian/Ubuntu y derivadas)"; exit 1 ;;
    esac
    if [ -z "$CODENAME" ]; then echo "No pude detectar el codename de tu distro."; exit 1; fi
}

init_context() {
    USER_NAME="$SUDO_USER"
    USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
    USER_GROUP=$(id -gn "$USER_NAME")
    DEV_UID=$(id -u "$USER_NAME")
    DEV_GID=$(id -g "$USER_NAME")
    PROJECTS_DIR="$USER_HOME/$PROJECTS_DIR_REL"
    STACK_DIR="$USER_HOME/$STACK_DIR_REL"
    CREDENTIALS_FILE="$USER_HOME/credenciales-dev.txt"

    # Estas rutas terminan en archivos .env y en volúmenes de Docker: nada de espacios ni rarezas.
    if ! [[ "$PROJECTS_DIR$STACK_DIR" =~ ^[A-Za-z0-9._/@+-]+$ ]]; then
        echo "Las rutas $PROJECTS_DIR y $STACK_DIR tienen caracteres no permitidos (espacios, acentos...)."
        echo "Ajusta PROJECTS_DIR_REL / STACK_DIR_REL en la configuración."
        exit 1
    fi

    detect_distro
    ARCH=$(dpkg --print-architecture)
    export DEBIAN_FRONTEND=noninteractive
}

setup_logging() {
    LOG_DIR="/var/log/dev-setup"; mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
}

init_credentials() {
    # Cada ejecución reescribe el archivo; guardamos el anterior por si tenía algo que necesites.
    if [ -f "$CREDENTIALS_FILE" ]; then cp -a "$CREDENTIALS_FILE" "${CREDENTIALS_FILE}.anterior"; fi
    {
        echo "========================================"
        echo "CREDENCIALES — ENTORNO DE DESARROLLO"
        echo "Generado: $(date)"
        echo "$OS_PRETTY ($CODENAME) — $(hostname)"
        echo "========================================"
    } > "$CREDENTIALS_FILE"
    chown "$USER_NAME":"$USER_GROUP" "$CREDENTIALS_FILE"; chmod 600 "$CREDENTIALS_FILE"
}

choose_mode() {
    clear 2>/dev/null || true
    cat <<BANNER
==================================================
  ENTORNO DEV — $OS_PRETTY · $ARCH
  Usuario: $USER_NAME
==================================================
1) TODO
     Docker + Nginx, PHP $PHP_VERSION, MariaDB, PostgreSQL, Redis y Mailpit
     (Composer, Node $NODE_MAJOR y Python $PYTHON_VERSION también en contenedores)
     + mkcert (HTTPS local), DBeaver, VS Code
     + Git y llave SSH, Oh My Bash ($OMB_THEME), herramientas CLI
2) BÁSICO
     Solo Git global + llave SSH, Oh My Bash y herramientas CLI (sin Docker)
==================================================
BANNER
    read -rp "Opción [1-2]: " MODO
    case "$MODO" in
        1) MODE="full" ;;
        2) MODE="basic" ;;
        *) log_error "Opción inválida"; exit 1 ;;
    esac
}

# ------------------------------------------------------------
# BASE DEL SISTEMA (ambas opciones)
# ------------------------------------------------------------
setup_base() {
    # Si una corrida anterior dejó el PPA de ondrej en una versión de Ubuntu que ya no
    # lo soporta (26.04+), "apt-get update" falla con 404. Lo quitamos antes de actualizar.
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

    log "Instalando utilidades base..."
    apt-get install -y curl git ca-certificates gnupg openssl openssh-client
}

# ------------------------------------------------------------
# OH MY BASH + tema powerline-icon
# IMPORTANTE: va ANTES de cualquier add_bashrc_line. El instalador de
# Oh My Bash respalda ~/.bashrc y lo REEMPLAZA por su plantilla; si
# escribiéramos el PATH antes, esas líneas se perderían.
# ------------------------------------------------------------
setup_omb() {
    local OMB_DIR="$USER_HOME/.oh-my-bash"

    if has_desktop; then
        log "Instalando fuentes para el prompt (símbolos Powerline + emojis)..."
        apt_install_available fonts-powerline fonts-noto-color-emoji
    fi

    if [ -d "$OMB_DIR" ]; then
        log_warn "Oh My Bash ya estaba instalado — solo reviso el tema"
    else
        log "Instalando Oh My Bash..."
        if curl -fsSL https://raw.githubusercontent.com/ohmybash/oh-my-bash/master/tools/install.sh \
                -o /tmp/omb-install.sh; then
            chmod 644 /tmp/omb-install.sh
            # --unattended: sin esto el instalador hace "exec bash" y el script se cuelga
            ( cd "$USER_HOME" && as_user bash /tmp/omb-install.sh --unattended ) \
                || { log_error "Falló el instalador de Oh My Bash"; FAILED+=("oh-my-bash"); }
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
        save_credential "  Tu .bashrc anterior quedó respaldado en ~/.bashrc.omb-backup-*"
        save_credential "  Si ves cuadritos o símbolos raros: cierra y reabre la terminal."
        save_credential "  Desinstalar: uninstall_oh_my_bash"
    else
        log_warn "No pude fijar el tema '${OMB_THEME}' (¿existe en ~/.oh-my-bash/themes?)"
        FAILED+=("oh-my-bash-theme")
    fi
}

setup_path() {
    as_user mkdir -p "$USER_HOME/.local/bin"
    add_bashrc_line 'export PATH="$HOME/.local/bin:$PATH"'
}

# ------------------------------------------------------------
# HERRAMIENTAS CLI
# ------------------------------------------------------------
setup_tools() {
    log "Instalando herramientas CLI..."
    apt_install_available ripgrep fd-find bat fzf btop ncdu httpie tmux jq tree unzip zip wget

    # Debian renombra estos binarios; los dejamos con el nombre real
    as_user mkdir -p "$USER_HOME/.local/bin"
    if [ -x /usr/bin/batcat ]; then as_user ln -sf /usr/bin/batcat "$USER_HOME/.local/bin/bat"; fi
    if [ -x /usr/bin/fdfind ]; then as_user ln -sf /usr/bin/fdfind "$USER_HOME/.local/bin/fd"; fi

    save_credential ""
    save_credential "HERRAMIENTAS CLI"
    save_credential "  rg 'texto'     buscar en el proyecto (ignora node_modules/vendor solo)"
    save_credential "  fd nombre      buscar archivos"
    save_credential "  bat archivo    cat con colores y numeros de linea"
    save_credential "  btop           monitor de recursos"
    save_credential "  ncdu           que se esta comiendo el disco"
    save_credential "  http GET url   cliente HTTP decente para probar APIs"
    INSTALLED+=("herramientas-cli")
}

# ------------------------------------------------------------
# GIT + LLAVE SSH
# ------------------------------------------------------------
setup_git() {
    if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
        log_warn "GIT_NAME/GIT_EMAIL vacíos — omitiendo configuración de Git y llave SSH"
        return 0
    fi

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

    local SSH_KEY="$USER_HOME/.ssh/id_ed25519"
    if [ ! -f "$SSH_KEY" ]; then
        log "Generando llave SSH ed25519..."
        as_user mkdir -p "$USER_HOME/.ssh"
        as_user chmod 700 "$USER_HOME/.ssh"
        as_user ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N "" -q
    fi

    save_credential ""
    save_credential "GIT"
    save_credential "  $GIT_NAME <$GIT_EMAIL> · editor $GIT_EDITOR"
    save_credential ""
    save_credential "  Llave SSH pública (pégala en GitHub/GitLab → Settings → SSH Keys):"
    save_credential "  $(cat "${SSH_KEY}.pub")"
    save_credential "  Probar: ssh -T git@github.com"
    INSTALLED+=("git+ssh")
}

# ------------------------------------------------------------
# mkcert — CA local para HTTPS en .test (corre en el host)
# ------------------------------------------------------------
setup_mkcert() {
    log "Instalando mkcert (certificados locales de confianza)..."
    if apt-get install -y mkcert libnss3-tools 2>/dev/null; then
        as_user mkcert -install >/dev/null 2>&1 \
            || log_warn "mkcert -install falló (¿sin navegador aún?). Corre 'mkcert -install' después."
        MKCERT_OK=1
        log "mkcert listo — los sitios .test tendrán HTTPS válido"
    else
        MKCERT_OK=0
        log_warn "mkcert no disponible en los repos — los sitios quedarán solo en HTTP"
    fi
}

# ------------------------------------------------------------
# APPS GRÁFICAS: DBeaver y VS Code (en el host: no tienen sentido en Docker)
# ------------------------------------------------------------
setup_gui_apps() {
    if ! has_desktop; then
        log_warn "No detecté entorno gráfico — omito DBeaver y VS Code"
        return 0
    fi

    log "Instalando DBeaver Community..."
    local DEB="/tmp/dbeaver-ce.deb"
    if curl -fsSL "https://dbeaver.io/files/dbeaver-ce_latest_${ARCH}.deb" -o "$DEB"; then
        if apt-get install -y "$DEB"; then INSTALLED+=("dbeaver-ce"); else log_error "DBeaver falló"; FAILED+=("dbeaver-ce"); fi
        rm -f "$DEB"
        save_credential ""
        save_credential "DBEAVER CE"
        save_credential "  Lanzador en el menú de aplicaciones, o comando: dbeaver"
        save_credential "  MariaDB:    127.0.0.1:3306  usuario ${DB_USER}"
        save_credential "  PostgreSQL: 127.0.0.1:5432  usuario ${DB_USER}  base ${DB_USER}"
        save_credential "  Oracle: DBeaver trae el driver JDBC, no necesitas instantclient."
    else
        log_error "No se pudo descargar DBeaver"; FAILED+=("dbeaver-ce")
    fi

    if [[ "$INSTALL_VSCODE" =~ ^[Ss]$ ]]; then
        log "Instalando Visual Studio Code..."
        add_repo "vscode" "https://packages.microsoft.com/keys/microsoft.asc" \
                 "https://packages.microsoft.com/repos/code" "stable" "main"
        apt-get update
        if apt-get install -y code; then INSTALLED+=("vscode"); else log_warn "VS Code falló"; fi
    fi
}

# ------------------------------------------------------------
# DOCKER ENGINE + COMPOSE
# ------------------------------------------------------------
# Detecta cómo invocar compose v2: plugin ("docker compose") o binario ("docker-compose" v2).
detect_compose() {
    DC=()
    if docker compose version >/dev/null 2>&1; then
        DC=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1 && [[ "$(docker-compose version --short 2>/dev/null || true)" == 2* ]]; then
        DC=(docker-compose)
    fi
    [ ${#DC[@]} -gt 0 ]
}

setup_docker_engine() {
    if command -v docker >/dev/null 2>&1 && detect_compose; then
        log "Docker y compose ya están instalados"
    else
        # Orden: repo oficial de Docker si publica para tu versión; si no, paquetes de tu distro.
        if url_ok "https://download.docker.com/linux/${DISTRO}/dists/${CODENAME}/InRelease"; then
            log "Instalando Docker CE (repo oficial)..."
            add_repo "docker" "https://download.docker.com/linux/${DISTRO}/gpg" \
                     "https://download.docker.com/linux/${DISTRO}" "$CODENAME" "stable"
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        else
            log_warn "El repo oficial de Docker no publica para ${CODENAME} — uso los paquetes de ${OS_PRETTY}"
            apt-get install -y docker.io
            apt_install_available docker-compose-v2 docker-buildx
            if ! detect_compose; then apt_install_available docker-compose; fi
        fi
    fi

    systemctl enable --now docker
    usermod -aG docker "$USER_NAME"

    if ! detect_compose; then
        log_error "Docker quedó instalado pero no encuentro Compose v2."
        log_error "Instálalo (en Ubuntu: docker-compose-v2; en Debian: docker-compose) y vuelve a correr el script."
        FAILED+=("docker-compose")
        exit 1
    fi
    verify_service docker
    log "Compose: ${DC[*]}"
}

# ------------------------------------------------------------
# STACK: ARCHIVOS DE CONFIGURACIÓN
# ------------------------------------------------------------
# env_get CLAVE ARCHIVO → valor sin comillas, o vacío si no existe
env_get() {
    if [ -f "$2" ]; then
        grep -E "^$1=" "$2" | tail -n1 | cut -d= -f2- | sed 's/^"//; s/"$//' || true
    fi
}

validate_password() {
    if ! [[ "$2" =~ ^[A-Za-z0-9._@%+=:,-]+$ ]]; then
        log_error "$1 tiene caracteres no permitidos. Usa solo letras, números y . _ @ % + = : , -"
        exit 1
    fi
}

# resolve_password NOMBRE VALOR_CONFIG VALOR_EXISTENTE
# Las bases solo aplican su contraseña al CREAR el volumen: si ya existe una, se conserva.
resolve_password() {
    local name="$1" cfg="$2" cur="$3"
    if [ -n "$cur" ]; then
        if [ "$cfg" != "auto" ] && [ "$cfg" != "$cur" ]; then
            log_warn "$name: las bases ya se crearon con otra contraseña; conservo la actual (ver $STACK_DIR/.env)." >&2
        fi
        echo "$cur"
    elif [ "$cfg" = "auto" ]; then
        gen_password
    else
        echo "$cfg"
    fi
}

write_env_file() {
    local envf="$STACK_DIR/.env" db_pass root_pass
    # Validar aquí, fuera de $(...): dentro de una sustitución un "exit" no detiene el script
    # y el mensaje de error terminaría guardado en la variable.
    if [ "$DB_PASSWORD" != "auto" ]; then validate_password DB_PASSWORD "$DB_PASSWORD"; fi
    if [ "$MARIADB_ROOT_PASSWORD" != "auto" ]; then validate_password MARIADB_ROOT_PASSWORD "$MARIADB_ROOT_PASSWORD"; fi
    db_pass=$(resolve_password DB_PASSWORD "$DB_PASSWORD" "$(env_get DB_PASSWORD "$envf")")
    root_pass=$(resolve_password MARIADB_ROOT_PASSWORD "$MARIADB_ROOT_PASSWORD" "$(env_get MARIADB_ROOT_PASSWORD "$envf")")

    cat > "$envf" <<EOF
# Generado por install-dev.sh — contiene contraseñas. No lo subas a Git.
COMPOSE_PROJECT_NAME=dev-stack
PROJECTS_DIR="${PROJECTS_DIR}"
DEV_UID=${DEV_UID}
DEV_GID=${DEV_GID}
TZ="${TIMEZONE}"
PHP_VERSION="${PHP_VERSION}"
NODE_MAJOR="${NODE_MAJOR}"
PYTHON_VERSION="${PYTHON_VERSION}"
INSTALL_XDEBUG="${INSTALL_XDEBUG}"
IMG_NGINX="${IMG_NGINX}"
IMG_MARIADB="${IMG_MARIADB}"
IMG_POSTGRES="${IMG_POSTGRES}"
IMG_REDIS="${IMG_REDIS}"
IMG_MAILPIT="${IMG_MAILPIT}"
DB_USER="${DB_USER}"
DB_PASSWORD="${db_pass}"
MARIADB_ROOT_PASSWORD="${root_pass}"
EOF
    chmod 600 "$envf"
}

write_compose_file() {
    cat > "$STACK_DIR/docker-compose.yml" <<'COMPOSE_YML'
# Generado por install-dev.sh — las variables vienen de .env
# Todos los puertos se publican SOLO en 127.0.0.1 (no quedan expuestos a tu red).

x-logging: &logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  nginx:
    image: ${IMG_NGINX}
    container_name: dev-nginx
    restart: unless-stopped
    depends_on:
      - php
    ports:
      - "127.0.0.1:80:80"
      - "127.0.0.1:443:443"
    volumes:
      # Los proyectos se montan con la MISMA ruta que en tu host
      - ${PROJECTS_DIR}:${PROJECTS_DIR}:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/certs:/etc/nginx/certs:ro
    logging: *logging

  php:
    build:
      context: ./php
      args:
        PHP_VERSION: ${PHP_VERSION}
        DEV_UID: ${DEV_UID}
        DEV_GID: ${DEV_GID}
        INSTALL_XDEBUG: ${INSTALL_XDEBUG}
    image: dev-php:${PHP_VERSION}
    container_name: dev-php
    restart: unless-stopped
    working_dir: ${PROJECTS_DIR}
    environment:
      TZ: ${TZ}
    volumes:
      - ${PROJECTS_DIR}:${PROJECTS_DIR}
      - php_cache:/cache
    extra_hosts:
      - "host.docker.internal:host-gateway"
    logging: *logging

  mariadb:
    image: ${IMG_MARIADB}
    container_name: dev-mariadb
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${MARIADB_ROOT_PASSWORD}
      MARIADB_USER: ${DB_USER}
      MARIADB_PASSWORD: ${DB_PASSWORD}
      TZ: ${TZ}
    ports:
      - "127.0.0.1:3306:3306"
    volumes:
      - mariadb_data:/var/lib/mysql
      - ./mariadb/init:/docker-entrypoint-initdb.d:ro
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s
    logging: *logging

  postgres:
    image: ${IMG_POSTGRES}
    container_name: dev-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      TZ: ${TZ}
    ports:
      - "127.0.0.1:5432:5432"
    volumes:
      # PostgreSQL 18+ guarda los datos en /var/lib/postgresql/<versión>/; montar
      # /var/lib/postgresql (y no .../data) funciona también con versiones anteriores.
      - postgres_data:/var/lib/postgresql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 10s
    logging: *logging

  redis:
    image: ${IMG_REDIS}
    container_name: dev-redis
    restart: unless-stopped
    command: ["redis-server", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru"]
    ports:
      - "127.0.0.1:6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 6
    logging: *logging

  mailpit:
    image: ${IMG_MAILPIT}
    container_name: dev-mailpit
    restart: unless-stopped
    environment:
      MP_MAX_MESSAGES: "2000"
      MP_DATABASE: /data/mailpit.db
      MP_SMTP_AUTH_ACCEPT_ANY: "1"
      MP_SMTP_AUTH_ALLOW_INSECURE: "1"
      TZ: ${TZ}
    ports:
      - "127.0.0.1:8025:8025"
      - "127.0.0.1:1025:1025"
    volumes:
      - mailpit_data:/data
    logging: *logging

volumes:
  mariadb_data:
  postgres_data:
  redis_data:
  mailpit_data:
  php_cache:
COMPOSE_YML
}

write_php_files() {
    mkdir -p "$STACK_DIR/php"

    cat > "$STACK_DIR/php/Dockerfile" <<'PHP_DOCKERFILE'
# Imagen de PHP para desarrollo (FPM + CLI). Generada por install-dev.sh
ARG PHP_VERSION=8.5
FROM php:${PHP_VERSION}-fpm

ARG PHP_VERSION=8.5
ARG DEV_UID=1000
ARG DEV_GID=1000
ARG INSTALL_XDEBUG=s

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/install-php-extensions
RUN chmod +x /usr/local/bin/install-php-extensions

RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip msmtp \
 && rm -rf /var/lib/apt/lists/*

# Extensiones imprescindibles (Laravel, Symfony, WordPress...) y Composer
RUN install-php-extensions @composer pdo_mysql mysqli pdo_pgsql pgsql zip gd intl bcmath exif pcntl redis

# Opcionales: si aún no existen para esta versión de PHP, se omiten sin romper el build
RUN install-php-extensions imagick || echo ">> imagick no disponible para PHP ${PHP_VERSION}: se omite"
RUN if [ "${INSTALL_XDEBUG}" = "s" ]; then \
        install-php-extensions xdebug || echo ">> xdebug no disponible para PHP ${PHP_VERSION}: se omite"; \
    fi

# Instalador de Laravel disponible globalmente (comando: laravel)
RUN COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_HOME=/opt/composer \
    composer global require laravel/installer --no-interaction --no-progress

# www-data pasa a tener TU uid/gid: los archivos que cree PHP (storage/, cache/) serán tuyos
RUN groupmod -o -g ${DEV_GID} www-data \
 && usermod -o -u ${DEV_UID} -g ${DEV_GID} www-data \
 && mkdir -p /cache/composer /home/dev \
 && chown -R ${DEV_UID}:${DEV_GID} /cache /home/dev /opt/composer

RUN cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
COPY dev.ini /usr/local/etc/php/conf.d/99-dev.ini
COPY msmtprc /etc/msmtprc

ENV HOME=/home/dev \
    COMPOSER_HOME=/opt/composer \
    COMPOSER_CACHE_DIR=/cache/composer \
    PATH=/opt/composer/vendor/bin:$PATH
PHP_DOCKERFILE

    cat > "$STACK_DIR/php/dev.ini" <<EOF
; Ajustes de desarrollo (install-dev.sh)
date.timezone = ${TIMEZONE}
memory_limit = 512M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
sendmail_path = "/usr/bin/msmtp -t"

; Xdebug: modo trigger (no frena nada hasta que se lo pidas). Si la extensión no está, se ignora.
xdebug.mode = develop,debug
xdebug.start_with_request = trigger
xdebug.client_host = host.docker.internal
xdebug.client_port = 9003
EOF

    # mail() de PHP → Mailpit
    cat > "$STACK_DIR/php/msmtprc" <<'EOF'
defaults
auth off
tls off
logfile /dev/null

account mailpit
host mailpit
port 1025
from dev@localhost

account default : mailpit
EOF
}

write_node_python_files() {
    mkdir -p "$STACK_DIR/node" "$STACK_DIR/python"

    cat > "$STACK_DIR/node/Dockerfile" <<'NODE_DOCKERFILE'
# Node para desarrollo. Generada por install-dev.sh
ARG NODE_MAJOR=24
FROM node:${NODE_MAJOR}

# HOME compartido (volumen dev-node-home): cachés de npm/pnpm/corepack persisten entre ejecuciones.
# El contenedor corre con TU uid, que no existe en la imagen, por eso HOME es escribible por todos.
ENV HOME=/home/dev \
    npm_config_prefix=/home/dev/.npm-global \
    PATH=/home/dev/.npm-global/bin:$PATH \
    COREPACK_HOME=/home/dev/.cache/corepack \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

RUN (corepack enable || (npm install -g corepack && corepack enable)) \
 && mkdir -p /home/dev \
 && chmod 777 /home/dev
NODE_DOCKERFILE

    cat > "$STACK_DIR/python/Dockerfile" <<'PY_DOCKERFILE'
# Python + uv para desarrollo. Generada por install-dev.sh
ARG PYTHON_VERSION=3.13
FROM python:${PYTHON_VERSION}

ENV HOME=/home/dev \
    PATH=/home/dev/.local/bin:$PATH \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_CACHE_DIR=/home/dev/.cache/pip \
    UV_CACHE_DIR=/home/dev/.cache/uv \
    UV_LINK_MODE=copy

RUN pip install --no-cache-dir uv \
 && mkdir -p /home/dev \
 && chmod 777 /home/dev
PY_DOCKERFILE
}

write_nginx_files() {
    mkdir -p "$STACK_DIR/nginx/conf.d" "$STACK_DIR/nginx/certs"

    # Resolución de nombres en tiempo de ejecución: nginx no se cae si php se reinicia
    cat > "$STACK_DIR/nginx/conf.d/00-resolver.conf" <<'EOF'
resolver 127.0.0.11 valid=10s ipv6=off;
EOF

    # Sitio por defecto: índice de tus proyectos PHP (solo accesible desde tu máquina)
    cat > "$STACK_DIR/nginx/conf.d/00-default.conf" <<EOF
server {
    listen 80 default_server;
    server_name localhost;
    root ${PROJECTS_DIR}/php;
    autoindex on;

    location / { try_files \$uri \$uri/ =404; }
    location ~ /\.(?!well-known) { deny all; }
}
EOF
}

write_mariadb_init() {
    mkdir -p "$STACK_DIR/mariadb/init"
    # Se ejecuta SOLO la primera vez que se crea el volumen de MariaDB.
    cat > "$STACK_DIR/mariadb/init/01-grants.sh" <<'INIT_GRANTS'
#!/bin/bash
# El usuario de la app queda con todos los privilegios (es una base de desarrollo).
mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
GRANT ALL PRIVILEGES ON *.* TO '${MARIADB_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
INIT_GRANTS
    chmod +x "$STACK_DIR/mariadb/init/01-grants.sh"
}

# ------------------------------------------------------------
# STACK: COMANDOS (bin/)
# ------------------------------------------------------------
write_bin_scripts() {
    mkdir -p "$STACK_DIR/bin"

    # ---------- _lib.sh: funciones comunes ----------
    cat > "$STACK_DIR/bin/_lib.sh" <<'LIB_SH'
# _lib.sh — funciones comunes de los comandos de dev-stack (no se ejecuta directamente)
dev_err() { echo "[dev] $*" >&2; }

BIN_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
STACK_DIR="$(dirname "$BIN_DIR")"
ENV_FILE="$STACK_DIR/.env"
[ -f "$ENV_FILE" ] || { dev_err "No encuentro $ENV_FILE"; exit 1; }
set -a; . "$ENV_FILE"; set +a

DOCKER_SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"

docker_ready() {
    if [ -n "${DOCKER_HOST:-}" ]; then return 0; fi
    if [ ! -S "$DOCKER_SOCK" ]; then
        dev_err "Docker no está corriendo. Inícialo con: sudo systemctl start docker"
        return 1
    fi
    if [ ! -w "$DOCKER_SOCK" ]; then
        if getent group docker | grep -qw "$(id -un)"; then
            dev_err "Tu usuario ya está en el grupo 'docker', pero esta sesión aún no lo ve: cierra sesión y vuelve a entrar."
        else
            dev_err "Tu usuario no está en el grupo 'docker'. Ejecuta: sudo usermod -aG docker \$USER  y vuelve a iniciar sesión."
        fi
        return 1
    fi
    return 0
}

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose --project-directory "$STACK_DIR" "$@"
    else
        docker-compose --project-directory "$STACK_DIR" "$@"
    fi
}

is_running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" = "true" ]; }

# ensure_running <contenedor> <servicio>
ensure_running() {
    if ! is_running "$1"; then
        dev_err "Iniciando $2..."
        compose up -d "$2" >&2
    fi
}

require_image() {
    if ! docker image inspect "$1" >/dev/null 2>&1; then
        dev_err "Falta la imagen $1. Constrúyela con: devstack rebuild"
        exit 1
    fi
}

set_tty_flags() {
    TTY_FLAGS=(-i)
    if [ -t 0 ] && [ -t 1 ]; then TTY_FLAGS=(-it); fi
}

# Los proyectos se montan con la MISMA ruta que en tu host: no hay que traducir nada.
resolve_workdir() {
    case "$PWD/" in
        "$PROJECTS_DIR"/*) WORKDIR="$PWD" ;;
        *)
            WORKDIR="$PROJECTS_DIR"
            if [ -t 2 ]; then dev_err "Aviso: estás fuera de $PROJECTS_DIR; el comando corre en esa carpeta."; fi
            ;;
    esac
}
LIB_SH

    # ---------- dev-wrapper: php, node, python... (según el nombre con que se invoque) ----------
    cat > "$STACK_DIR/bin/dev-wrapper" <<'WRAPPER_SH'
#!/usr/bin/env bash
# dev-wrapper — ejecuta php, composer, node, python... dentro de contenedores Docker.
# Se invoca mediante enlaces simbólicos (php, composer, npm, python...): el
# comportamiento depende del nombre con que se llame.
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

NAME="$(basename "$0")"
docker_ready || exit 1
set_tty_flags

case "$NAME" in
    php|composer|laravel)
        resolve_workdir
        ensure_running dev-php php
        exec docker exec "${TTY_FLAGS[@]}" -u "$DEV_UID:$DEV_GID" -w "$WORKDIR" \
            -e HOME=/home/dev -e TERM -e XDEBUG_TRIGGER -e XDEBUG_SESSION -e XDEBUG_MODE -e XDEBUG_CONFIG \
            dev-php "$NAME" "$@"
        ;;
    node|npm|npx|pnpm|yarn|corepack)
        resolve_workdir
        require_image "dev-node:$NODE_MAJOR"
        # --network host: los servidores de desarrollo (Vite, etc.) quedan en localhost, como si fueran nativos
        exec docker run --rm "${TTY_FLAGS[@]}" --init --network host \
            -u "$DEV_UID:$DEV_GID" -e HOME=/home/dev -e TERM \
            -v dev-node-home:/home/dev -v "$PROJECTS_DIR:$PROJECTS_DIR" -w "$WORKDIR" \
            "dev-node:$NODE_MAJOR" "$NAME" "$@"
        ;;
    python|pip|uv|uvx)
        resolve_workdir
        require_image "dev-python:$PYTHON_VERSION"
        exec docker run --rm "${TTY_FLAGS[@]}" --init --network host \
            -u "$DEV_UID:$DEV_GID" -e HOME=/home/dev -e TERM \
            -v dev-python-home:/home/dev -v "$PROJECTS_DIR:$PROJECTS_DIR" -w "$WORKDIR" \
            "dev-python:$PYTHON_VERSION" "$NAME" "$@"
        ;;
    mariadb)
        ensure_running dev-mariadb mariadb
        # La contraseña va por variable de entorno, no en los argumentos (que se ven en `ps`)
        export MYSQL_PWD="$DB_PASSWORD"
        exec docker exec "${TTY_FLAGS[@]}" -e MYSQL_PWD dev-mariadb mariadb -u"$DB_USER" "$@"
        ;;
    psql)
        ensure_running dev-postgres postgres
        export PGPASSWORD="$DB_PASSWORD"
        exec docker exec "${TTY_FLAGS[@]}" -e PGPASSWORD dev-postgres psql -U "$DB_USER" "$@"
        ;;
    redis-cli)
        ensure_running dev-redis redis
        exec docker exec "${TTY_FLAGS[@]}" dev-redis redis-cli "$@"
        ;;
    *)
        dev_err "Comando desconocido: $NAME"
        exit 1
        ;;
esac
WRAPPER_SH

    # ---------- devstack: gestionar el stack ----------
    cat > "$STACK_DIR/bin/devstack" <<'DEVSTACK_SH'
#!/usr/bin/env bash
# devstack — gestiona los contenedores del entorno de desarrollo
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

docker_ready || exit 1

CMD="${1:-help}"
if [ $# -gt 0 ]; then shift; fi

case "$CMD" in
    up)       compose up -d "$@" ;;
    down)     compose down "$@" ;;
    restart)  compose restart "$@" ;;
    ps|status) compose ps "$@" ;;
    logs)     compose logs -f --tail=100 "$@" ;;
    shell)
        set_tty_flags; resolve_workdir
        ensure_running dev-php php
        exec docker exec "${TTY_FLAGS[@]}" -u "$DEV_UID:$DEV_GID" -w "$WORKDIR" -e HOME=/home/dev -e TERM dev-php bash
        ;;
    rebuild)
        compose build --pull php
        docker build --pull -t "dev-node:$NODE_MAJOR" --build-arg "NODE_MAJOR=$NODE_MAJOR" "$STACK_DIR/node"
        docker build --pull -t "dev-python:$PYTHON_VERSION" --build-arg "PYTHON_VERSION=$PYTHON_VERSION" "$STACK_DIR/python"
        compose up -d
        ;;
    info)
        echo "Proyectos:   $PROJECTS_DIR  (los sitios PHP van en $PROJECTS_DIR/php)"
        echo "Stack:       $STACK_DIR"
        echo "Índice:      http://localhost"
        echo "Mailpit:     http://localhost:8025   (SMTP 127.0.0.1:1025)"
        echo "MariaDB:     127.0.0.1:3306  usuario $DB_USER  contraseña $DB_PASSWORD"
        echo "PostgreSQL:  127.0.0.1:5432  usuario $DB_USER  contraseña $DB_PASSWORD"
        echo "Redis:       127.0.0.1:6379"
        echo "MariaDB root (solo dentro del contenedor): $MARIADB_ROOT_PASSWORD"
        ;;
    help|-h|--help|*)
        cat <<'HELP'
Uso: devstack <comando>

  up [servicio]       Levanta los contenedores
  down                Los detiene y elimina (los datos se conservan en volúmenes)
  restart [servicio]  Reinicia
  ps                  Estado de los contenedores
  logs [servicio]     Logs en vivo (nginx, php, mariadb, postgres, redis, mailpit)
  shell               Terminal dentro del contenedor de PHP (en la carpeta actual)
  rebuild             Reconstruye las imágenes de PHP, Node y Python con la base más nueva
  info                Direcciones y credenciales
HELP
        ;;
esac
DEVSTACK_SH

    # ---------- newsite ----------
    cat > "$STACK_DIR/bin/newsite" <<'NEWSITE_SH'
#!/usr/bin/env bash
# newsite <nombre> — crea https://<nombre>.test para ~/proyectos/php/<nombre>
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

NAME="${1:-}"
if [ -z "$NAME" ]; then echo "Uso: newsite <nombre>" >&2; exit 1; fi
if ! [[ "$NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
    dev_err "Nombre inválido: usa minúsculas, números y guiones (ej: mi-tienda)."; exit 1
fi
docker_ready || exit 1

HOSTS_FILE="${DEV_HOSTS_FILE:-/etc/hosts}"
CONF_DIR="$STACK_DIR/nginx/conf.d"
CERT_DIR="$STACK_DIR/nginx/certs"
ROOT="$PROJECTS_DIR/php/$NAME"

if [ ! -d "$ROOT" ]; then
    dev_err "No existe $ROOT"
    dev_err "Crea el proyecto primero (ej: cd $PROJECTS_DIR/php && laravel new $NAME)"
    dev_err "o una carpeta vacía:  mkdir -p $ROOT"
    exit 1
fi
if [ -d "$ROOT/public" ]; then DOCROOT="$ROOT/public"; else DOCROOT="$ROOT"; fi

# Certificado local de confianza (mkcert corre en tu host)
USE_SSL=0
if command -v mkcert >/dev/null 2>&1; then
    mkdir -p "$CERT_DIR"
    if [ ! -f "$CERT_DIR/$NAME.test.pem" ]; then
        mkcert -cert-file "$CERT_DIR/$NAME.test.pem" -key-file "$CERT_DIR/$NAME.test-key.pem" \
            "$NAME.test" "*.$NAME.test" >/dev/null 2>&1 || true
    fi
    if [ -f "$CERT_DIR/$NAME.test.pem" ] && [ -f "$CERT_DIR/$NAME.test-key.pem" ]; then USE_SSL=1; fi
fi

if [ "$USE_SSL" = 1 ]; then
    LISTEN_SSL="    listen 443 ssl;
    http2 on;
    ssl_certificate     /etc/nginx/certs/$NAME.test.pem;
    ssl_certificate_key /etc/nginx/certs/$NAME.test-key.pem;"
    SCHEME="https"
else
    LISTEN_SSL=""
    SCHEME="http"
    dev_err "mkcert no disponible o falló: el sitio quedará solo en HTTP."
fi

cat > "$CONF_DIR/$NAME.conf" <<CONF
server {
    listen 80;
$LISTEN_SSL
    server_name $NAME.test *.$NAME.test;
    root $DOCROOT;
    index index.php index.html;

    client_max_body_size 64M;

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }

    location ~ \.php\$ {
        set \$php_upstream php:9000;
        fastcgi_pass \$php_upstream;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        fastcgi_read_timeout 300;
    }

    location ~ /\.(?!well-known) { deny all; }
}
CONF

# /etc/hosts necesita permisos de administrador
if ! grep -qE "[[:space:]]${NAME}\.test([[:space:]]|\$)" "$HOSTS_FILE"; then
    if [ -w "$HOSTS_FILE" ]; then
        echo "127.0.0.1   $NAME.test # dev-stack" >> "$HOSTS_FILE"
    else
        echo "127.0.0.1   $NAME.test # dev-stack" | sudo tee -a "$HOSTS_FILE" >/dev/null
    fi
fi

ensure_running dev-nginx nginx
if docker exec dev-nginx nginx -t >/dev/null 2>&1; then
    docker exec dev-nginx nginx -s reload >/dev/null 2>&1
else
    dev_err "La configuración de nginx tiene errores:"
    docker exec dev-nginx nginx -t || true
    exit 1
fi

echo "Listo → $SCHEME://$NAME.test"
echo "  docroot: $DOCROOT"
if [ "$DOCROOT" = "$ROOT" ]; then
    echo "  (si tu proyecto usa la carpeta public/, vuelve a correr 'newsite $NAME' cuando exista)"
fi
NEWSITE_SH

    # ---------- delsite ----------
    cat > "$STACK_DIR/bin/delsite" <<'DELSITE_SH'
#!/usr/bin/env bash
# delsite <nombre> — quita el sitio (NO borra tus archivos)
set -euo pipefail
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/_lib.sh"

NAME="${1:-}"
if [ -z "$NAME" ]; then echo "Uso: delsite <nombre>" >&2; exit 1; fi
if ! [[ "$NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then dev_err "Nombre inválido."; exit 1; fi
docker_ready || exit 1

HOSTS_FILE="${DEV_HOSTS_FILE:-/etc/hosts}"
rm -f "$STACK_DIR/nginx/conf.d/$NAME.conf" \
      "$STACK_DIR/nginx/certs/$NAME.test.pem" "$STACK_DIR/nginx/certs/$NAME.test-key.pem"

if grep -qE "[[:space:]]${NAME}\.test([[:space:]]|\$)" "$HOSTS_FILE"; then
    if [ -w "$HOSTS_FILE" ]; then
        sed -i "/[[:space:]]${NAME}\.test[[:space:]]*#* *dev-stack\$/d" "$HOSTS_FILE"
    else
        sudo sed -i "/[[:space:]]${NAME}\.test[[:space:]]*#* *dev-stack\$/d" "$HOSTS_FILE"
    fi
fi

if is_running dev-nginx; then docker exec dev-nginx nginx -s reload >/dev/null 2>&1 || true; fi
echo "Sitio $NAME eliminado. Los archivos en $PROJECTS_DIR/php/$NAME siguen ahí."
DELSITE_SH

    chmod +x "$STACK_DIR/bin/dev-wrapper" "$STACK_DIR/bin/devstack" \
             "$STACK_DIR/bin/newsite" "$STACK_DIR/bin/delsite"
}

write_stack_files() {
    log "Escribiendo la configuración del stack en $STACK_DIR ..."
    mkdir -p "$STACK_DIR" "$PROJECTS_DIR/php"
    write_env_file
    write_compose_file
    write_php_files
    write_node_python_files
    write_nginx_files
    write_mariadb_init
    write_bin_scripts
    cat > "$STACK_DIR/.gitignore" <<'EOF'
.env
nginx/certs/
EOF
    chown -R "$USER_NAME":"$USER_GROUP" "$STACK_DIR" "$PROJECTS_DIR"
}

# ------------------------------------------------------------
# STACK: construir y levantar
# ------------------------------------------------------------
check_ports() {
    local busy=() p
    for p in 80 443 3306 5432 6379 8025 1025; do
        if [ -n "$(ss -ltnH "sport = :$p" 2>/dev/null)" ]; then busy+=("$p"); fi
    done
    if [ ${#busy[@]} -gt 0 ]; then
        log_error "Estos puertos ya están en uso en tu máquina: ${busy[*]}"
        log_error "Los contenedores necesitan 80, 443, 3306, 5432, 6379, 8025 y 1025."
        log_error "Mira quién los usa:  sudo ss -ltnp | grep -E ':(80|443|3306|5432|6379|8025|1025)\\b'"
        log_error "Causas típicas: Apache, o MariaDB/PostgreSQL/Redis instalados antes con apt."
        exit 1
    fi
}

build_failed() {
    log_error "Falló la construcción de la imagen '$1'."
    log_error "El detalle está arriba y en el log: $LOG_FILE"
    log_error "Corrige la causa y vuelve a correr el script (es seguro repetirlo)."
    FAILED+=("imagen-$1")
    exit 1
}

build_images() {
    log "Construyendo imágenes (PHP $PHP_VERSION, Node $NODE_MAJOR, Python $PYTHON_VERSION)..."
    log "La primera vez tarda varios minutos y descarga varios GB."
    "${DC[@]}" --project-directory "$STACK_DIR" build --pull php || build_failed php
    docker build --pull -t "dev-node:${NODE_MAJOR}" --build-arg "NODE_MAJOR=${NODE_MAJOR}" \
        "$STACK_DIR/node" || build_failed node
    docker build --pull -t "dev-python:${PYTHON_VERSION}" --build-arg "PYTHON_VERSION=${PYTHON_VERSION}" \
        "$STACK_DIR/python" || build_failed python
}

# Espera a que todos los contenedores estén corriendo (y sanos, si tienen healthcheck)
wait_for_containers() {
    local timeout="${1:-180}" waited=0 c st hs
    local names=(dev-nginx dev-php dev-mariadb dev-postgres dev-redis dev-mailpit)
    STACK_PENDING=()
    while [ "$waited" -lt "$timeout" ]; do
        STACK_PENDING=()
        for c in "${names[@]}"; do
            st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)
            hs=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null || true)
            if [ "$st" != "running" ] || { [ -n "$hs" ] && [ "$hs" != "healthy" ]; }; then
                STACK_PENDING+=("$c")
            fi
        done
        if [ ${#STACK_PENDING[@]} -eq 0 ]; then return 0; fi
        sleep "${WAIT_STEP:-3}"
        waited=$((waited + ${WAIT_STEP:-3}))
    done
    return 1
}

start_stack() {
    # Si ya hay contenedores dev-* corriendo (re-ejecución), los puertos son nuestros.
    if [ -z "$(docker ps -q --filter 'name=^dev-' 2>/dev/null)" ]; then check_ports; fi

    log "Levantando los servicios..."
    "${DC[@]}" --project-directory "$STACK_DIR" up -d \
        || { log_error "No pude levantar los contenedores (mira el error de arriba)."; exit 1; }

    log "Esperando a que los servicios estén sanos (MariaDB puede tardar en el primer arranque)..."
    if wait_for_containers 180; then
        log "Los 6 contenedores están corriendo"
        INSTALLED+=("stack-docker")
    else
        log_warn "Estos contenedores no quedaron sanos: ${STACK_PENDING[*]}"
        log_warn "Revisa con:  docker compose -f $STACK_DIR/docker-compose.yml logs <servicio>"
        FAILED+=("stack: ${STACK_PENDING[*]}")
    fi

    local url
    for url in http://127.0.0.1/ http://127.0.0.1:8025/; do
        if curl -fsS -m 5 -o /dev/null "$url"; then log "Responde $url"; else log_warn "No responde $url"; fi
    done
}

# Enlaces en ~/.local/bin → bin/dev-wrapper (y los demás comandos)
install_wrappers() {
    local bin="$STACK_DIR/bin" dest="$USER_HOME/.local/bin" n
    as_user mkdir -p "$dest"
    for n in php composer laravel node npm npx pnpm yarn corepack python pip uv uvx mariadb psql redis-cli; do
        # Si ya hay un binario real tuyo con ese nombre (p.ej. uv), lo respaldamos en vez de pisarlo
        if [ -e "$dest/$n" ] || [ -L "$dest/$n" ]; then
            if [ "$(readlink -f "$dest/$n")" != "$(readlink -f "$bin/dev-wrapper")" ]; then
                as_user mv "$dest/$n" "$dest/$n.host-backup"
                log_warn "Ya existía $dest/$n — lo respaldé como $n.host-backup"
            fi
        fi
        as_user ln -sf "$bin/dev-wrapper" "$dest/$n"
    done
    for n in devstack newsite delsite; do
        as_user ln -sf "$bin/$n" "$dest/$n"
    done
    log "Comandos instalados en $dest (php, composer, node, npm, python, uv, devstack, newsite...)"
}

write_stack_credentials() {
    local envf="$STACK_DIR/.env" dbp rootp
    dbp=$(env_get DB_PASSWORD "$envf")
    rootp=$(env_get MARIADB_ROOT_PASSWORD "$envf")

    save_credential ""
    save_credential "DOCKER — STACK DE DESARROLLO"
    save_credential "  Carpeta del stack: $STACK_DIR   (contraseñas en .env)"
    save_credential "  Proyectos:         $PROJECTS_DIR   (sitios PHP en $PROJECTS_DIR/php)"
    save_credential "  Contenedores:      nginx, php ${PHP_VERSION}, mariadb, postgres, redis, mailpit"
    save_credential "  Gestionar:         devstack up | down | restart | ps | logs | shell | rebuild | info"
    save_credential "  Importante: cierra sesión y vuelve a entrar una vez (grupo 'docker')."
    save_credential ""
    save_credential "SITIOS"
    save_credential "  Índice:       http://localhost"
    save_credential "  Nuevo sitio:  cd $PROJECTS_DIR/php && laravel new tienda && newsite tienda  -> https://tienda.test"
    save_credential "  Borrar sitio: delsite tienda   (no borra tus archivos)"
    save_credential ""
    save_credential "COMANDOS (corren dentro de contenedores, desde cualquier carpeta de $PROJECTS_DIR)"
    save_credential "  php, composer, laravel      -> contenedor php"
    save_credential "  node, npm, npx, pnpm, yarn  -> contenedor node ${NODE_MAJOR}"
    save_credential "  python, pip, uv, uvx        -> contenedor python ${PYTHON_VERSION}"
    save_credential "  mariadb, psql, redis-cli    -> clientes de cada base (ya autenticados)"
    save_credential "  En 'laravel new' responde NO a instalar npm; luego corre: npm install && npm run build"
    save_credential ""
    save_credential "MARIADB"
    save_credential "  Desde el host (DBeaver): 127.0.0.1:3306  usuario ${DB_USER}  contraseña ${dbp}"
    save_credential "  Root (solo dentro del contenedor): ${rootp}"
    save_credential "  Cliente rápido: mariadb"
    save_credential ""
    save_credential "POSTGRESQL"
    save_credential "  Desde el host: 127.0.0.1:5432  usuario ${DB_USER}  contraseña ${dbp}  base ${DB_USER}"
    save_credential "  Cliente rápido: psql"
    save_credential ""
    save_credential "REDIS: 127.0.0.1:6379 (sin contraseña, solo local, 512 MB)   ·   Cliente: redis-cli"
    save_credential "MAILPIT: bandeja http://localhost:8025   ·   SMTP 127.0.0.1:1025"
    save_credential ""
    save_credential ".ENV DE LARAVEL (la app corre dentro de Docker: usa el NOMBRE del servicio como host)"
    save_credential "  DB_CONNECTION=mysql   DB_HOST=mariadb   DB_PORT=3306  DB_USERNAME=${DB_USER}  DB_PASSWORD=${dbp}"
    save_credential "  (PostgreSQL: DB_CONNECTION=pgsql  DB_HOST=postgres  DB_PORT=5432)"
    save_credential "  REDIS_HOST=redis  CACHE_STORE=redis  QUEUE_CONNECTION=redis"
    save_credential "  MAIL_MAILER=smtp  MAIL_HOST=mailpit  MAIL_PORT=1025"
    save_credential "  Apps de Node/Python (usan la red del host): usa 127.0.0.1 como host."
    save_credential ""
    save_credential "XDEBUG: modo trigger, puerto 9003, host host.docker.internal"
    save_credential "  Ej: XDEBUG_TRIGGER=1 php artisan tinker   (tu IDE debe escuchar en 0.0.0.0:9003)"
    save_credential "  Las rutas dentro del contenedor son IGUALES a las de tu host: no hace falta 'path mapping'."
}

# ------------------------------------------------------------
# DESINSTALADOR
# ------------------------------------------------------------
write_uninstaller() {
    local target="$USER_HOME/desinstalar-entorno.sh"
    {
        echo '#!/usr/bin/env bash'
        printf 'STACK_DIR=%q\n' "$STACK_DIR"
        printf 'BIN_LINK_DIR=%q\n' "$USER_HOME/.local/bin"
        cat <<'UNINSTALL'
echo "DESINSTALADOR — esto BORRA tus bases de datos (volúmenes de Docker) y la carpeta $STACK_DIR."
echo "No toca tus proyectos, ni Docker, ni Oh My Bash, ni Git/SSH, ni DBeaver/VS Code."
read -rp "Escribe BORRAR para confirmar: " confirm
[ "$confirm" != "BORRAR" ] && { echo "Cancelado."; exit 0; }

D=docker
if ! docker info >/dev/null 2>&1; then D="sudo docker"; fi

if command -v docker >/dev/null 2>&1; then
    if [ -f "$STACK_DIR/docker-compose.yml" ]; then
        (cd "$STACK_DIR" && $D compose down -v --remove-orphans) \
            || (cd "$STACK_DIR" && docker-compose down -v --remove-orphans) || true
    fi
    $D volume rm dev-node-home dev-python-home 2>/dev/null || true
    $D image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^dev-(php|node|python):' | xargs -r $D image rm 2>/dev/null || true
fi

for n in php composer laravel node npm npx pnpm yarn corepack python pip uv uvx mariadb psql redis-cli devstack newsite delsite; do
    l="$BIN_LINK_DIR/$n"
    if [ -L "$l" ] && [[ "$(readlink -f "$l")" == "$STACK_DIR"/bin/* ]]; then
        rm -f "$l"
        # Si el instalador había respaldado un binario tuyo con ese nombre, lo devolvemos a su lugar
        if [ -e "$l.host-backup" ]; then mv "$l.host-backup" "$l"; fi
    fi
done

sudo sed -i '/# dev-stack$/d' /etc/hosts
rm -rf "$STACK_DIR"
echo "Listo. Si quieres quitar Docker: sudo apt purge docker-ce docker-ce-cli containerd.io docker.io"
echo "Para quitar Oh My Bash, en una terminal nueva: uninstall_oh_my_bash"
UNINSTALL
    } > "$target"
    chmod +x "$target"
    chown "$USER_NAME":"$USER_GROUP" "$target"
}

# ------------------------------------------------------------
# RESUMEN
# ------------------------------------------------------------
show_summary() {
    {
        echo ""
        echo "========================================"
        echo "RESUMEN"
        echo "========================================"
        local s
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
    echo "  INSTALACIÓN COMPLETADA"
    echo "=================================================="
    cat "$CREDENTIALS_FILE"
    echo "=================================================="
    echo "Credenciales : $CREDENTIALS_FILE"
    echo "Log          : $LOG_FILE"
    if [ "$MODE" = "full" ]; then
        echo "Stack        : $STACK_DIR   (comando: devstack)"
        echo "Desinstalador: $USER_HOME/desinstalar-entorno.sh"
    fi
    echo "=================================================="
    if [ "$MODE" = "full" ]; then
        log_warn "CIERRA SESIÓN Y VUELVE A ENTRAR: hasta entonces php, composer, node... no podrán usar Docker."
    else
        log_warn "Cierra esta terminal y abre una nueva para ver el prompt nuevo."
    fi
}

# ------------------------------------------------------------
# PRINCIPAL
# ------------------------------------------------------------
main() {
    require_root
    init_context
    setup_logging
    choose_mode
    init_credentials

    setup_base
    setup_omb
    setup_path
    setup_tools
    setup_git

    if [ "$MODE" = "full" ]; then
        setup_gui_apps
        setup_mkcert
        setup_docker_engine
        write_stack_files
        build_images
        start_stack
        install_wrappers
        write_stack_credentials
        write_uninstaller
    fi

    show_summary
}

# Se ejecuta solo si corres el archivo (no si lo cargas con "source" para pruebas)
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
