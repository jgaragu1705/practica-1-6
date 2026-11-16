#!/bin/bash

# -e: para el script si un comando falla
# -x: enseña cada comando antes de ejecutarlo
set -ex

# Comprobamos que el script se ejecuta como root (con sudo)
if [ "$EUID" -ne 0 ]; then
  echo "Este script debe ejecutarse con sudo"
  exit 1
fi

# Guardamos la carpeta donde está el script para usar rutas a partir de ella
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Evitamos que apt haga preguntas durante la instalación
export DEBIAN_FRONTEND=noninteractive

# Actualizamos los repositorios
apt update

# Instalamos el servidor web Apache
apt install apache2 -y

# Copiamos nuestro archivo de configuración de Apache
cp "$SCRIPT_DIR/../conf/000-default.conf" /etc/apache2/sites-available

# Habilitamos el módulo de reescritura (lo necesitan los enlaces permanentes de WordPress)
a2enmod rewrite

# Instalamos PHP, el módulo de PHP para Apache y la extensión para conectar con MySQL
apt install php libapache2-mod-php php-mysql -y

# Instalamos las extensiones de PHP que recomienda WordPress
apt install php-curl php-gd php-xml php-mbstring php-zip php-intl -y

# Instalamos MySQL Server
apt install mysql-server -y

# Eliminamos la página por defecto de Apache
rm -f /var/www/html/index.html

# Copiamos el index.php de prueba (phpinfo) a la carpeta del servidor web
cp "$SCRIPT_DIR/../php/index.php" /var/www/html

# Cambiamos el propietario y el grupo de /var/www/html a www-data (el usuario de Apache)
chown -R www-data:www-data /var/www/html

# Reiniciamos Apache para que cargue PHP y todos los cambios
systemctl restart apache2
