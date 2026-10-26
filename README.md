# install-dev

Un solo script para dejar una notebook de desarrollo lista en **Debian** y **Ubuntu**:
Nginx + PHP 8.5, MariaDB, PostgreSQL 18, Redis, Node.js 24, Python (con `uv`), Mailpit,
HTTPS local con mkcert, DBeaver, VS Code y un prompt con Oh My Bash.

La idea: instalar, abrir una terminal nueva y empezar a programar.

> **Solo para máquinas de desarrollo personales.** El script corre como root, relaja
> permisos a propósito (PHP-FPM usa tu usuario, `dev` tiene todos los privilegios en
> MariaDB) y deja contraseñas en un archivo de texto. No lo uses en un servidor.

---

## Qué instala

| Componente | Detalle |
|---|---|
| **Base** | `curl`, `wget`, `git`, `unzip`, `zip`, `jq`, `tree`, `build-essential`, `ca-certificates`, `gnupg`, `openssl`, `acl` |
| **Nginx** | Sitio por defecto que lista `~/proyectos/php`, escuchando **solo en `127.0.0.1`** |
| **PHP 8.5** (FPM + CLI) | Extensiones: `mysql`, `pgsql`, `sqlite3`, `mbstring`, `xml`, `curl`, `zip`, `gd`, `intl`, `bcmath`, `readline`, `redis`, `imagick`, `xdebug` (las que existan en el repo). OPcache viene integrado en PHP |
| **Composer** | Instalador oficial verificando la firma SHA-384, más el instalador global de Laravel |
| **MariaDB** | La versión de tu distro. Usuario `dev` con contraseña, y un usuario con tu nombre de Linux por `unix_socket` |
| **PostgreSQL 18** | Rol y base con tu nombre de usuario, más el usuario `postgres` |
| **Redis** (o Valkey) | Limitado a 512 MB con política `allkeys-lru` |
| **Node.js 24** | Desde NodeSource, con `corepack` (`pnpm`/`yarn`) y `npm -g` sin sudo |
| **Python 3** | `venv`, `pip`, `pipx`, headers de desarrollo y `uv` |
| **Mailpit** | Captura todo el correo saliente (también `mail()` de PHP) |
| **mkcert** | CA local de confianza: tus sitios `.test` tienen HTTPS válido |
| **DBeaver CE** y **VS Code** | Solo si el script detecta un entorno gráfico |
| **Herramientas CLI** | `ripgrep`, `fd`, `bat`, `fzf`, `btop`, `ncdu`, `httpie`, `tmux` |
| **Git** | Configuración global, `.gitignore_global` y llave SSH ed25519 (si completas nombre y correo) |
| **Oh My Bash** | Tema `powerline-icon`, más las fuentes `fonts-powerline` y `fonts-noto-color-emoji` |

El menú inicial ofrece **1) TODO** o **2) PERSONALIZADO** (eliges bloque por bloque).
La base del sistema y mkcert se instalan siempre.

### De dónde sale cada cosa

Para PHP y PostgreSQL el script **prefiere los repositorios de tu distro** y solo agrega
uno externo si hace falta:

- **PHP:** si tu distro ya trae la versión pedida (Ubuntu 26.04 trae 8.5), no agrega nada.
  Si no: repo de [Sury](https://packages.sury.org/php/) en Debian; en Ubuntu, el PPA de
  Ondřej Surý o, si el PPA no soporta tu versión, `packages.sury.org`.
- **PostgreSQL:** repos de tu distro si traen la versión; si no, el repo oficial PGDG.
- **Node.js:** NodeSource. **VS Code:** repo de Microsoft.

---

## Compatibilidad

| Sistema | Estado |
|---|---|
| Ubuntu 26.04 LTS (`resolute`) | Objetivo principal |
| Debian 13 (`trixie`) | Objetivo principal |
| Ubuntu 24.04 LTS (`noble`) | Previsto (PHP vía PPA de Ondřej). Sin probar de punta a punta |
| Derivadas de Ubuntu (Mint, Pop!_OS, Zorin) | Se tratan como Ubuntu. Sin probar |
| Ubuntu 22.04 y anteriores | No soportado |
| Fedora, Arch, macOS, otros | No soportado (el script se detiene) |

Si algo falla en tu sistema, abre un *issue* con las últimas líneas del log (ver
[Solución de problemas](#solución-de-problemas)).

---

## Instalación

**1. Clona el repositorio**

```bash
git clone https://github.com/TU_USUARIO/TU_REPO.git
cd TU_REPO
```

**2. Revisa el script y edita la configuración**

Es un script que corre como root y descarga cosas de internet: léelo antes de ejecutarlo.
Luego edita el bloque `CONFIGURACIÓN` del inicio:

```bash
nano install-dev.sh
```

Como mínimo, completa `GIT_NAME`, `GIT_EMAIL` y `TIMEZONE`.

**3. Ejecútalo con `sudo`**

```bash
sudo bash install-dev.sh
```

Hazlo desde tu **usuario normal** con `sudo` delante, no desde una sesión de root
(`sudo su`): el script necesita saber cuál es tu usuario real y se detiene si no lo sabe.

Tarda entre 10 y 20 minutos según tu conexión. Los mensajes amarillos `[!]` son avisos
(por ejemplo, una extensión de PHP que no existe en tu repo), no errores.

**4. Abre una terminal nueva**

Es necesario para ver el prompt de Oh My Bash y para que el `PATH` nuevo tome efecto.

**5. Verifica**

```bash
cat ~/credenciales-dev.txt     # contraseñas y comandos útiles
php -v
node -v
mariadb -e "select version();"
psql -c "select version();"
redis-cli ping                 # PONG  (valkey-cli si usas Valkey)
```

Y en el navegador: `http://localhost` (índice de proyectos) y `http://localhost:8025`
(bandeja de Mailpit).

---

## Configuración

Todas las opciones están en el bloque `CONFIGURACIÓN` al inicio de `install-dev.sh`.

| Variable | Por defecto | Descripción |
|---|---|---|
| `GIT_NAME`, `GIT_EMAIL` | vacío | Si alguno está vacío, se omite la configuración de Git **y** la llave SSH |
| `GIT_EDITOR` | `nano` | `nano`, `vim` o `code` |
| `PHP_MAIN` | `8.5` | Versión de PHP a instalar |
| `WEB_ROOT_REL` | `proyectos/php` | Carpeta de proyectos, relativa a tu home |
| `TIMEZONE` | `America/Santiago` | Zona horaria de PHP |
| `MARIADB_DEV_USER` | `dev` | Usuario de aplicación de MariaDB |
| `MARIADB_DEV_PASSWORD` | `auto` | `auto` genera una contraseña aleatoria; o fija una |
| `POSTGRES_PASSWORD` | `auto` | Ídem para PostgreSQL |
| `NODE_MAJOR` | `24` | `22` o `24` |
| `PG_VERSION` | `18` | Versión de PostgreSQL |
| `INSTALL_XDEBUG` | `s` | `s` o `n` |
| `CACHE_ENGINE` | `redis` | `redis` o `valkey` (si tu distro no trae Valkey, usa Redis) |
| `INSTALL_VSCODE` | `s` | Solo se instala si hay entorno gráfico |
| `OMB_THEME` | `powerline-icon` | Tema de Oh My Bash (ver `~/.oh-my-bash/themes`) |

---

## Uso diario

### Sitios con HTTPS: `newsite` y `delsite`

```bash
cd ~/proyectos/php
laravel new tienda
sudo newsite tienda        # → https://tienda.test
sudo delsite tienda        # quita vhost, certificado y línea de /etc/hosts
```

- El *docroot* es `tienda/public` si existe; si no, la raíz del proyecto.
- `newsite` genera el certificado con mkcert y agrega `tienda.test` a `/etc/hosts`.
- `delsite` **no borra tus archivos**, solo la configuración del sitio.
- El vhost y el certificado también cubren `*.tienda.test`, pero `/etc/hosts` no admite
  comodines: para subdominios agrega la línea a mano o usa `dnsmasq`.

### Laravel: `.env`

```env
# MariaDB
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=dev
DB_PASSWORD=<ver ~/credenciales-dev.txt>

# PostgreSQL (alternativa)
# DB_CONNECTION=pgsql
# DB_PORT=5432
# DB_USERNAME=<tu usuario de Linux>

CACHE_STORE=redis          # Laravel 10 o anterior: CACHE_DRIVER=redis
QUEUE_CONNECTION=redis
REDIS_HOST=127.0.0.1

MAIL_MAILER=smtp
MAIL_HOST=127.0.0.1
MAIL_PORT=1025
```

### Bases de datos

| | Acceso rápido | Por red local |
|---|---|---|
| **MariaDB** | `mariadb` (tu usuario, sin contraseña) o `sudo mariadb` (root) | `mariadb -u dev -p -h 127.0.0.1` |
| **PostgreSQL** | `psql` (rol con tu nombre, sin contraseña) | `psql -U <tu_usuario> -h 127.0.0.1` |

DBeaver: conecta a `127.0.0.1:3306` (usuario `dev`) y `127.0.0.1:5432` (tu usuario).
Trae su propio driver JDBC para Oracle, no necesitas instalar nada más para consultarlo.

### Correo: Mailpit

Todo el correo que mande tu app (o `mail()` de PHP) queda en `http://localhost:8025`.
Nada sale a internet. SMTP en `127.0.0.1:1025`, sin autenticación ni TLS.

### Xdebug

Modo `trigger` (no frena nada hasta que se lo pidas), puerto `9003`:

```bash
XDEBUG_TRIGGER=1 php artisan tinker
```

En el navegador usa una extensión que envíe la cookie `XDEBUG_TRIGGER`.

### Python

Debian y Ubuntu recientes aplican PEP 668: `pip install` global **falla a propósito**
(`externally-managed-environment`). Usa:

```bash
uv init miapp && cd miapp && uv add requests     # proyecto nuevo
uv python install 3.12                           # otra versión de Python
python3 -m venv .venv && source .venv/bin/activate
pipx install ruff                                # herramientas de línea de comandos
```

### Node.js

`pnpm` y `yarn` funcionan directo (vía `corepack`), y `npm i -g paquete` instala en
`~/.npm-global` sin necesidad de `sudo`.

---

## Qué cambia en tu sistema

**Archivos que crea**

- `~/credenciales-dev.txt` (permisos 600): contraseñas y comandos útiles.
  **Se sobrescribe en cada ejecución.**
- `~/desinstalar-entorno.sh`
- `~/.oh-my-bash`, `~/.npm-global`, `~/.gitignore_global`, `~/.ssh/id_ed25519`
- `/usr/local/bin/newsite`, `delsite`, `composer`, `mailpit`; `/etc/dev-env.conf`
- Log completo en `/var/log/dev-setup/install-<fecha>.log`

**Configuración que modifica**

- `php.ini` (FPM y CLI): `memory_limit=512M`, `upload_max_filesize=64M`,
  `post_max_size=64M`, `max_execution_time=300`, zona horaria. Los originales quedan
  como `*.backup-<fecha>`.
- Pool de PHP-FPM: corre con **tu usuario** (así `storage/` y `cache/` de Laravel no
  dan problemas de permisos).
- `~/.bashrc`: **Oh My Bash lo reemplaza** por su plantilla. Tu archivo anterior queda en
  `~/.bashrc.omb-backup-<fecha>`. Después se agregan líneas de `PATH`.
- `/etc/hosts`: una línea por cada sitio que creas con `newsite`.
- Nginx: se elimina el sitio `default`.
- MariaDB: se eliminan los usuarios anónimos y la base `test`.
- Tu usuario de Linux queda como rol de PostgreSQL con permisos de superusuario.

**Código externo que descarga y ejecuta**

- Instalador de Mailpit, de su repositorio oficial en GitHub (como root)
- Instalador de Oh My Bash, rama `master` de su repositorio (como tu usuario)
- Instalador de `uv`, desde `astral.sh` (como tu usuario)
- Repositorios apt de NodeSource, Microsoft (VS Code) y, según tu sistema, Sury, el PPA
  de Ondřej o PGDG

---

## Seguridad

- **Léelo antes de correrlo.** Corre como root y ejecuta instaladores de terceros.
- **Es para desarrollo.** PHP-FPM con tu usuario y `dev` con todos los privilegios son
  cómodos en una notebook y malos en un servidor. No copies esta configuración a producción.
- **Nginx solo escucha en `127.0.0.1`.** MariaDB, PostgreSQL y Redis escuchan solo en
  localhost con la configuración por defecto de la distro, y Mailpit queda fijado a
  `127.0.0.1`. Puedes comprobarlo:

  ```bash
  sudo ss -tlnp | grep -E ':(80|443|3306|5432|6379|8025|1025)\b'
  ```

  Cada línea debe mostrar `127.0.0.1` (o `::1`), nunca `0.0.0.0` ni `*`.
- **Redis y Mailpit no tienen autenticación.** Es seguro mientras solo escuchen en localhost.
- **La llave SSH se genera sin passphrase.** Si quieres una: `ssh-keygen -p -f ~/.ssh/id_ed25519`.
- **Nunca subas `credenciales-dev.txt`** ni una copia del script con tu correo personal
  escrito en `GIT_EMAIL`.

---

## Volver a ejecutar el script

Se puede volver a correr: apt salta lo ya instalado y los repos se reescriben igual.
Pero ten presente:

- Con `MARIADB_DEV_PASSWORD="auto"` y `POSTGRES_PASSWORD="auto"` **las contraseñas se
  regeneran** en cada ejecución, y los `.env` que ya hayas configurado dejan de funcionar.
  Para que no cambien, fija una contraseña en esas variables.
- `~/credenciales-dev.txt` se vuelve a escribir desde cero: guarda una copia si la necesitas.
- Si Oh My Bash ya está instalado, no se reinstala, pero el tema se vuelve a fijar a
  `OMB_THEME`.

---

## Solución de problemas

**El script falla o se detiene.** Todo queda registrado en `/var/log/dev-setup/`. Para un
*issue*, adjunta las últimas líneas:

```bash
tail -n 60 "$(ls -t /var/log/dev-setup/install-*.log | head -n1)"
```

**`apt update` da error con un repositorio de terceros.** Corre `sudo apt update` y mira
cuál repo reporta `E:`. Si es un PPA de `ondrej` que no soporta tu versión de Ubuntu, el
script lo elimina solo al empezar.

**Nginx no arranca: el puerto 80 está ocupado.** Probablemente Apache:

```bash
sudo systemctl disable --now apache2
```

**El prompt muestra cuadritos o símbolos raros.** Cierra la terminal y ábrela de nuevo.
El tema usa los símbolos Powerline y emojis estándar; no necesita una Nerd Font. Si el
problema sigue, revisa que tu terminal no tenga una fuente fija sin esos símbolos.

**El navegador no confía en `https://miapp.test`.** Ejecuta `mkcert -install` como tu
usuario (sin `sudo`) y reinicia el navegador. Un navegador instalado como snap o flatpak
puede no leer el almacén de certificados normal del sistema.

**`pip install` dice `externally-managed-environment`.** Es PEP 668 y es intencional.
Usa `uv` o un entorno virtual (ver [Python](#python)).

---

## Desinstalar

```bash
~/desinstalar-entorno.sh
```

Pide que escribas `BORRAR` para confirmar. **Borra tus bases de datos** (`/var/lib/mysql`,
`/var/lib/postgresql`) y los paquetes de Nginx, PHP, MariaDB, PostgreSQL, Redis, Node.js,
DBeaver y VS Code, además de los repositorios que el script agregó.

**No toca:** tus proyectos, Oh My Bash (para quitarlo, en una terminal nueva ejecuta
`uninstall_oh_my_bash`), tu configuración de Git, tu llave SSH, las líneas de `PATH` en
`.bashrc`, `uv`/`pipx`, las herramientas CLI ni la CA de mkcert (`mkcert -uninstall`).
