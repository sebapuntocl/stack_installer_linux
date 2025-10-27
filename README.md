# 🚀 Stack er v2.0

Script de instalación automatizada de entorno completo de desarrollo web para Debian/Ubuntu.

## 📦 ¿Qué instala?

- **Apache 2** - Servidor web con módulos esenciales habilitados
- **PHP** (detección automática de versión) - Con todas las extensiones necesarias
- **MySQL** - Sistema de base de datos relacional
- **PostgreSQL** - Base de datos avanzada
- **Redis** - Base de datos en memoria y caché
- **Mailpit** - Servidor SMTP de testing para desarrollo
- **Supervisor** - Gestor de procesos
- **Python 3** - Con pip, venv y herramientas de desarrollo
- **Node.js** (última LTS vía nvm) - Con npm incluido
- **Docker** - Plataforma de contenedores con Docker Compose
- **Portainer** - Interfaz web para gestionar Docker

## ✨ Características

- ✅ Detección automática de versión de PHP instalada
- ✅ Manejo inteligente de bloqueos de apt
- ✅ Configuración segura de MySQL (root sin tocar)
- ✅ PHP optimizado para desarrollo
- ✅ Timeouts y reintentos en descargas
- ✅ Logs coloridos y informativos
- ✅ Continúa aunque algún componente falle

## 📋 Requisitos

- Debian 12+ o Ubuntu 22.04+
- Acceso sudo
- Conexión a internet

## 🔧 Instalación

```bash
# Descargar el script
wget https://raw.githubusercontent.com/TU_USUARIO/TU_REPO/main/install.sh

# Dar permisos de ejecución
chmod +x install.sh

# Ejecutar
./install.sh
```

## ⚙️ Configuración

Edita estas variables al inicio del script según tus necesidades:

```bash
USER_NAME="sebastian"              # Tu usuario del sistema
WEB_ROOT="/home/${USER_NAME}/proyectos/php"  # Carpeta de proyectos
```

## 🔐 Credenciales por defecto

### MySQL
- **Usuario desarrollo:** `sebastian` / `dev2024`
- **Root:** Accesible solo con `sudo mysql` (auth_socket)

### PostgreSQL
- **Usuario postgres:** `postgres` / `root`
- **Usuario desarrollo:** `sebastian` / `root`

### Mailpit
- **Web UI:** http://localhost:8025
- **SMTP:** localhost:1025

## 📂 Estructura de carpetas

```
/home/sebastian/proyectos/php/
└── index.php (archivo de prueba con phpinfo())
```

## 🛠️ Comandos útiles

```bash
# Reiniciar servicios
sudo systemctl restart apache2
sudo systemctl restart php8.3-fpm
sudo systemctl restart mysql

# Ver logs
sudo tail -f /var/log/apache2/error.log
sudo journalctl -u php8.3-fpm -f

# Conectarse a bases de datos
mysql -u sebastian -p          # MySQL (password: dev2024)
psql -U sebastian              # PostgreSQL (password: root)
redis-cli                      # Redis

# Python
python3 -m venv mi_entorno     # Crear entorno virtual
source mi_entorno/bin/activate # Activar entorno
pip  paquete            # Instalar paquetes

# Node.js
node --version                 # Ver versión de Node
npm --version                  # Ver versión de npm
npm  -g paquete         # Instalar paquetes globales
```

## 🧪 Verificar instalación

```bash
# Ver estado de servicios
sudo systemctl status apache2
sudo systemctl status mysql
sudo systemctl status postgresql
sudo systemctl status redis-server
sudo systemctl status mailpit

# Probar PHP
curl http://localhost/index.php

# Verificar Python
python3 --version
pip3 --version

# Verificar Node.js (requiere reiniciar terminal)
node --version
npm --version
```

## 🐛 Solución de problemas

### apt está bloqueado
El script espera automáticamente hasta 5 minutos. Si persiste:
```bash
sudo kill $(sudo lsof -t /var/lib/dpkg/lock-frontend)
sudo dpkg --configure -a
```

### PHP-FPM no inicia
```bash
# Verificar versión instalada
php -v

# Ajustar en Apache
sudo a2enconf php8.3-fpm
sudo systemctl restart apache2
```

### Mailpit no se instala
```bash
# Instalación manual
curl -sL https://raw.githubusercontent.com/axllent/mailpit/develop/.sh | sudo bash
```

### Node.js no aparece después de instalar
```bash
# Reinicia tu terminal o ejecuta:
source ~/.bashrc

# Verifica nvm
nvm --version

# Instala Node.js LTS manualmente si es necesario
nvm  --lts
nvm use --lts
```

### Crear entorno virtual de Python
```bash
# En tu carpeta de proyecto
python3 -m venv venv
source venv/bin/activate
pip  django  # o cualquier paquete que necesites
```

## 📝 Configuración PHP

El script configura automáticamente:
- `upload_max_filesize = 64M`
- `post_max_size = 64M`
- `memory_limit = 256M`
- `max_execution_time = 300`

## 🔒 Seguridad

- MySQL root usa `auth_socket` (solo accesible con sudo)
- Usuario de desarrollo con privilegios completos
- PostgreSQL con autenticación por contraseña
- Redis sin autenticación (solo localhost)

## 🤝 Contribuciones

¡Las contribuciones son bienvenidas! Por favor:
1. Fork el proyecto
2. Crea una rama para tu feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit tus cambios (`git commit -am 'Agrega nueva funcionalidad'`)
4. Push a la rama (`git push origin feature/nueva-funcionalidad`)
5. Abre un Pull Request

## 📄 Licencia

MIT License - Siéntete libre de usar, modificar y distribuir.

## ✍️ Autor

**Seba** - Desarrollo y mantenimiento

## 🙏 Agradecimientos

- Comunidad de Debian/Ubuntu
- Proyecto Mailpit
- Todos los contribuidores

---

💡 **Tip:** Recuerda cambiar las contraseñas por defecto en entornos de producción.

🐛 **Reportar bugs:** [Issues](https://github.com/TU_USUARIO/TU_REPO/issues)
