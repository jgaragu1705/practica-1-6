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

# Apagamos set -x para que no se vean las contraseñas del .env por pantalla
set +x
# Importamos las variables de entorno
source "$SCRIPT_DIR/.env"
set -x

#---------------------------------------------------------
# WP-CLI (herramienta para gestionar WordPress desde la terminal)
#---------------------------------------------------------

# Eliminamos descargas previas de WP-CLI
rm -f /tmp/wp-cli.phar

# Descargamos WP-CLI
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -P /tmp

# Le damos permisos de ejecución
chmod +x /tmp/wp-cli.phar

# Lo movemos a /usr/local/bin/wp para poder usar el comando "wp"
mv /tmp/wp-cli.phar /usr/local/bin/wp

#---------------------------------------------------------
# Descarga de WordPress
#---------------------------------------------------------

# Eliminamos instalaciones previas de WordPress (también el .htaccess, que está oculto)
rm -rf /var/www/html/*
rm -f /var/www/html/.htaccess

# Descargamos WordPress en español
# (descarga directa, porque wp core download falla con el locale en este servidor)
rm -f /tmp/latest-es_ES.tar.gz
wget https://es.wordpress.org/latest-es_ES.tar.gz -P /tmp

# Lo descomprimimos directamente en /var/www/html
# --strip-components=1 quita la carpeta "wordpress/" del principio y deja los archivos sueltos
tar -xzf /tmp/latest-es_ES.tar.gz -C /var/www/html --strip-components=1

# Borramos el archivo descargado
rm -f /tmp/latest-es_ES.tar.gz

#---------------------------------------------------------
# Base de datos
#---------------------------------------------------------

# Creamos la base de datos de WordPress (si ya existía la borramos antes)
mysql -u root -e "DROP DATABASE IF EXISTS $DB_NAME"
mysql -u root -e "CREATE DATABASE $DB_NAME"

# Creamos el usuario de la base de datos (si ya existía lo borramos antes)
# Apagamos set -x porque aquí va la contraseña
set +x
mysql -u root -e "DROP USER IF EXISTS '$DB_USER'@'$IP_CLIENTE_MYSQL'"
mysql -u root -e "CREATE USER '$DB_USER'@'$IP_CLIENTE_MYSQL' IDENTIFIED BY '$DB_PASSWORD'"
set -x

# Le damos todos los privilegios sobre la base de datos de WordPress
mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'$IP_CLIENTE_MYSQL'"

#---------------------------------------------------------
# Configuración e instalación de WordPress
#---------------------------------------------------------

# Apagamos set -x porque aquí van las contraseñas
set +x

# Creamos el wp-config.php con los datos de la base de datos
# (también genera automáticamente las security keys)
wp config create \
  --dbname="$DB_NAME" \
  --dbuser="$DB_USER" \
  --dbpass="$DB_PASSWORD" \
  --dbhost="$DB_HOST" \
  --path=/var/www/html \
  --allow-root

# Instalamos WordPress (título del sitio y usuario administrador)
wp core install \
  --url="https://$LETS_ENCRYPT_DOMAIN" \
  --title="$WORDPRESS_TITLE" \
  --admin_user="$WORDPRESS_ADMIN_USER" \
  --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
  --admin_email="$WORDPRESS_ADMIN_EMAIL" \
  --path=/var/www/html \
  --allow-root

set -x

# Configuramos los enlaces permanentes con el nombre de la entrada
wp rewrite structure '/%postname%/' \
  --path=/var/www/html \
  --allow-root

# Copiamos el .htaccess (wp rewrite no lo crea desde la terminal)
cp "$SCRIPT_DIR/../htaccess/.htaccess" /var/www/html/

#---------------------------------------------------------
# Plugin para ocultar la página de login
#---------------------------------------------------------

# Instalamos y activamos el plugin WPS Hide Login
wp plugin install wps-hide-login --activate \
  --path=/var/www/html \
  --allow-root

# Cambiamos la URL del login por la que pusimos en el .env
wp option update whl_page "$URL_HIDE_LOGIN" \
  --path=/var/www/html \
  --allow-root

#---------------------------------------------------------
# Permisos
#---------------------------------------------------------

# Cambiamos el propietario y el grupo de /var/www/html a www-data (el usuario de Apache)
chown -R www-data:www-data /var/www/html
