# 🚀 LAMP Stack Installer

Script automatizado para instalación de entorno de desarrollo web profesional en Debian/Ubuntu/Linux Mint.

[![Bash](https://img.shields.io/badge/bash-5.0%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Debian](https://img.shields.io/badge/debian-11%2B-red.svg)](https://www.debian.org/)
[![Ubuntu](https://img.shields.io/badge/ubuntu-20.04%2B-orange.svg)](https://ubuntu.com/)

## 📋 Descripción

Script bash profesional que automatiza la instalación y configuración de un entorno completo de desarrollo web LAMP (Linux, Apache, MariaDB, PHP) con herramientas modernas como Docker, Node.js, Redis, PostgreSQL y más.

Ideal para configurar rápidamente una estación de trabajo de desarrollo después de una instalación limpia del sistema operativo.

## ✨ Características

### Stack Principal
- ⚡ **Apache 2** - Servidor web con módulos esenciales (rewrite, headers, SSL)
- 🐘 **PHP 8.4+** - Con 15+ extensiones (mbstring, xml, curl, mysql, pgsql, redis, etc.)
- 🗄️ **MariaDB** - Sistema de gestión de bases de datos (fork de MySQL)
- 🐘 **PostgreSQL** - Base de datos relacional avanzada
- 🔴 **Redis** - Sistema de caché en memoria

### Herramientas de Desarrollo
- 📦 **Composer** - Gestor de dependencias PHP
- 🐳 **Docker + Docker Compose** - Plataforma de contenedores
- 🎛️ **Portainer CE** - Interfaz web para gestionar Docker
- 🟢 **Node.js (LTS)** - Runtime JavaScript con npm (vía nvm)
- 🐍 **Python 3** - Con pip y venv para entornos virtuales
- 📧 **Mailpit** - Capturador de emails para testing
- 💾 **Adminer** - Gestor web de bases de datos (alternativa ligera a phpMyAdmin)
- 📊 **Supervisor** - Gestor de procesos en segundo plano

### Utilidades del Sistema
- `git` - Control de versiones
- `curl`, `wget` - Descarga de archivos
- `htop` - Monitor de procesos
- `ncdu` - Análisis de espacio en disco
- `build-essential` - Compiladores C/C++
- `net-tools` - Herramientas de red
- VLC Media Player
- FileZilla (cliente FTP)

## 🖥️ Sistemas Soportados

- ✅ **Debian 11** (Bullseye)
- ✅ **Debian 12** (Bookworm)
- ✅ **Debian 13** (Trixie/Testing)
- ✅ **Ubuntu 20.04 LTS** (Focal)
- ✅ **Ubuntu 22.04 LTS** (Jammy)
- ✅ **Ubuntu 24.04 LTS** (Noble)
- ✅ **Linux Mint 21.x** (basado en Ubuntu 22.04)
- ✅ **Linux Mint 22.x** (basado en Ubuntu 24.04)

## 📥 Instalación

### Descarga directa
```bash
# Descargar el script
wget https://raw.githubusercontent.com/TU_USUARIO/lamp-installer/main/install.sh

# Dar permisos de ejecución
chmod +x install.sh

# Ejecutar
./install.sh
```

### Clonar repositorio
```bash
git clone https://github.com/TU_USUARIO/lamp-installer.git
cd lamp-installer
chmod +x install.sh
./install.sh
```

## ⚙️ Configuración

Antes de ejecutar el script, puedes ajustar estas variables en la parte superior del archivo:
```bash
TIMEZONE="America/Santiago"  # Cambia según tu zona horaria
```

Zonas horarias comunes:
- `America/Santiago` (Chile)
- `America/Argentina/Buenos_Aires` (Argentina)
- `America/Bogota` (Colombia)
- `America/Lima` (Perú)
- `America/Mexico_City` (México)
- `America/New_York` (USA Este)
- `Europe/Madrid` (España)

El script detecta automáticamente:
- ✅ Usuario del sistema (no necesitas editar `USER_NAME`)
- ✅ Sistema operativo (Debian/Ubuntu/Mint)
- ✅ Versión de PHP instalada
- ✅ Servicios ya instalados (evita reinstalaciones)

## 📂 Estructura de Archivos
```
/home/TU_USUARIO/
└── proyectos/
    └── php/
        ├── index.php              # Archivo de prueba (phpinfo)
        └── adminer/
            └── index.php          # Adminer 4.8.1

/etc/apache2/sites-available/
└── proyecto-ejemplo.conf          # Template de VirtualHost
```

## 🔐 Credenciales por Defecto

### MariaDB
```
Usuario desarrollo: TU_USUARIO
Contraseña: dev2024

Usuario root: root
Contraseña: root
```

### PostgreSQL
```
Usuario desarrollo: TU_USUARIO
Contraseña: root

Usuario sistema: postgres
Contraseña: root
```

### Portainer
```
URL: https://localhost:9443
Nota: Crear usuario administrador en el primer acceso
```

### Adminer
```
URL: http://localhost/adminer/
Nota: Usar credenciales de MariaDB o PostgreSQL
```

⚠️ **ADVERTENCIA**: Estas contraseñas son **SOLO para desarrollo local**. Nunca uses estas configuraciones en producción.

## 🌐 URLs de Acceso

| Servicio | URL | Descripción |
|----------|-----|-------------|
| Apache | http://localhost | Servidor web principal |
| PHP Info | http://localhost/index.php | Información de PHP |
| Adminer | http://localhost/adminer/ | Gestor de bases de datos |
| Mailpit | http://localhost:8025 | Capturador de emails |
| Portainer | https://localhost:9443 | Gestor de Docker |

## 🔧 Comandos Útiles

### Gestión de Servicios
```bash
# Reiniciar Apache
sudo systemctl restart apache2

# Reiniciar PHP-FPM
sudo systemctl restart php8.4-fpm

# Ver estado de servicios
sudo systemctl status apache2
sudo systemctl status mariadb
sudo systemctl status postgresql
sudo systemctl status redis-server
sudo systemctl status docker

# Ver logs de Apache
sudo tail -f /var/log/apache2/error.log
```

### Bases de Datos
```bash
# Conectar a MariaDB
mariadb -u TU_USUARIO -p

# Conectar como root
sudo mariadb -u root -p

# Conectar a PostgreSQL
psql -U TU_USUARIO

# Cliente Redis
redis-cli
```

### PHP y Composer
```bash
# Instalar dependencias
composer install

# Agregar paquete
composer require vendor/package

# Crear proyecto Laravel
composer create-project laravel/laravel mi-proyecto

# Servidor de desarrollo Laravel
cd mi-proyecto
php artisan serve
```

### Docker
```bash
# Ver contenedores activos
docker ps

# Ver todos los contenedores
docker ps -a

# Iniciar proyecto con Docker Compose
docker compose up -d

# Ver logs de contenedor
docker logs nombre_contenedor

# Detener todos los contenedores
docker stop $(docker ps -aq)
```

### Python
```bash
# Crear entorno virtual
python3 -m venv mi_entorno

# Activar entorno virtual
source mi_entorno/bin/activate

# Desactivar entorno
deactivate
```

### Node.js
```bash
# Ver versión
node --version
npm --version

# Instalar paquetes globalmente
npm install -g package-name

# Cambiar versión de Node.js
nvm install 18
nvm use 18
```

## 🎯 Crear un Proyecto

### Proyecto Laravel
```bash
cd ~/proyectos/php
composer create-project laravel/laravel mi-app
cd mi-app

# Configurar base de datos en .env
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=mi_base_de_datos
DB_USERNAME=TU_USUARIO
DB_PASSWORD=dev2024

# Crear base de datos
mariadb -u TU_USUARIO -p
CREATE DATABASE mi_base_de_datos;
exit;

# Ejecutar migraciones
php artisan migrate

# Servidor de desarrollo
php artisan serve
```

### VirtualHost Personalizado
```bash
# 1. Crear directorio del proyecto
mkdir -p ~/proyectos/php/mi-proyecto

# 2. Copiar y editar el VirtualHost de ejemplo
sudo cp /etc/apache2/sites-available/proyecto-ejemplo.conf \
        /etc/apache2/sites-available/mi-proyecto.conf

sudo nano /etc/apache2/sites-available/mi-proyecto.conf

# 3. Activar el sitio
sudo a2ensite mi-proyecto.conf

# 4. Recargar Apache
sudo systemctl reload apache2

# 5. Agregar a /etc/hosts
echo "127.0.0.1 mi-proyecto.local" | sudo tee -a /etc/hosts

# 6. Acceder en el navegador
# http://mi-proyecto.local
```

## 🔍 Solución de Problemas

### Apache no inicia
```bash
# Ver error específico
sudo systemctl status apache2
sudo journalctl -xe

# Verificar puertos en uso
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443

# Verificar configuración
sudo apache2ctl configtest
```

### PHP no funciona
```bash
# Verificar PHP-FPM
sudo systemctl status php8.4-fpm

# Reiniciar PHP-FPM
sudo systemctl restart php8.4-fpm

# Ver versión de PHP
php -v

# Ver módulos instalados
php -m
```

### MariaDB no acepta conexiones
```bash
# Verificar estado
sudo systemctl status mariadb

# Reiniciar servicio
sudo systemctl restart mariadb

# Acceder como root para diagnóstico
sudo mariadb
```

### Docker sin permisos
```bash
# Verificar que estás en el grupo docker
groups

# Si no aparece 'docker', cerrar y abrir terminal
# O ejecutar:
newgrp docker

# Verificar que funciona
docker ps
```

### Portainer no carga
```bash
# Verificar que el contenedor está corriendo
sudo docker ps | grep portainer

# Ver logs
sudo docker logs portainer

# Reiniciar contenedor
sudo docker restart portainer

# Puede tardar 1-2 minutos en estar disponible
```

## 📊 Verificación Post-Instalación
```bash
# Ver todos los servicios
systemctl list-units --type=service --state=running | grep -E 'apache|mariadb|postgresql|redis|docker'

# Verificar versiones
php -v
composer --version
python3 --version
node --version
npm --version
docker --version
mariadb --version
psql --version
```

## 🔄 Actualizar Componentes
```bash
# Actualizar sistema
sudo apt update && sudo apt upgrade -y

# Actualizar Composer
sudo composer self-update

# Actualizar npm globalmente
npm install -g npm@latest

# Actualizar Node.js (vía nvm)
nvm install --lts
nvm alias default 'lts/*'
```

## 🗑️ Desinstalación

Si necesitas desinstalar algún componente:
```bash
# Detener y deshabilitar servicios
sudo systemctl stop apache2 mariadb postgresql redis-server docker
sudo systemctl disable apache2 mariadb postgresql redis-server docker

# Desinstalar paquetes (ejemplo con Apache)
sudo apt remove --purge apache2 apache2-utils
sudo apt autoremove -y

# Eliminar directorios de configuración
sudo rm -rf /etc/apache2
sudo rm -rf /var/www/html

# Eliminar directorio de proyectos
rm -rf ~/proyectos/php
```

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/mejora`)
3. Commit tus cambios (`git commit -am 'Agrega nueva funcionalidad'`)
4. Push a la rama (`git push origin feature/mejora`)
5. Abre un Pull Request

## 📝 Changelog

### v2.2 (2024)
- ✨ Detección automática del usuario del sistema
- ✨ Mensajes más descriptivos y específicos
- ✨ Verificación de servicios ya instalados (evita reinstalaciones)
- ✨ Soporte para Debian 13 (Trixie)
- ✨ Mejoras en detección de sistema operativo
- 🐛 Correcciones en instalación de Portainer
- 🐛 Manejo de errores mejorado

### v2.1
- ✨ Cambio de MySQL a MariaDB
- ✨ Agregado Composer, Adminer, Python, Node.js
- ✨ Soporte para Docker y Portainer

### v2.0
- 🎉 Versión inicial pública

## ⚠️ Advertencias Importantes

1. **Solo para desarrollo local**: Este script configura un entorno con contraseñas simples y permisos relajados. NO usar en producción.

2. **Backup antes de ejecutar**: Aunque el script es seguro, siempre haz backup de datos importantes antes de ejecutar scripts de instalación masiva.

3. **Compatibilidad**: Probado principalmente en instalaciones limpias de Debian/Ubuntu. En sistemas con configuraciones personalizadas, pueden surgir conflictos.

4. **Permisos de Docker**: Después de la instalación, necesitas cerrar y abrir la terminal para usar Docker sin `sudo`.

## 📄 Licencia

MIT License - ver archivo [LICENSE](LICENSE) para más detalles.

## 👤 Autor

**Sebastian Sotelo**


Este script utiliza las siguientes tecnologías open source:
- Apache Software Foundation
- PHP Development Team
- MariaDB Foundation
- PostgreSQL Global Development Group
- Docker Inc.
- Node.js Foundation
- Y muchos otros proyectos open source

## 📞 Soporte

Si encuentras algún problema:
1. Revisa la sección [Solución de Problemas](#-solución-de-problemas)
2. Busca en [Issues](https://github.com/TU_USUARIO/lamp-installer/issues)
3. Abre un nuevo Issue con detalles del problema

---

⭐ Si este script te fue útil, considera darle una estrella al repositorio!
