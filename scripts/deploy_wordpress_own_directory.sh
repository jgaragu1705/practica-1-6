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

# Carpeta donde vamos a instalar WordPress
WP_DIR=/var/www/html/wordpress

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
# Descarga de WordPress en su propio directorio
#---------------------------------------------------------

# Eliminamos instalaciones previas (también el .htaccess, que está oculto)
rm -rf /var/www/html/*
rm -f /var/www/html/.htaccess

# Creamos la carpeta donde irá WordPress
mkdir -p $WP_DIR

# Descargamos WordPress en español
rm -f /tmp/latest-es_ES.tar.gz
wget https://es.wordpress.org/latest-es_ES.tar.gz -P /tmp

# Lo descomprimimos en /var/www/html/wordpress
# --strip-components=1 quita la carpeta "wordpress/" del tar para que no quede wordpress/wordpress
tar -xzf /tmp/latest-es_ES.tar.gz -C $WP_DIR --strip-components=1

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
  --path=$WP_DIR \
  --allow-root

set -x

# Añadimos WP_SITEURL al wp-config.php: la URL donde está el código de WordPress
wp config set WP_SITEURL "https://$LETS_ENCRYPT_DOMAIN/wordpress" \
  --path=$WP_DIR \
  --allow-root

# Añadimos WP_HOME al wp-config.php: la URL que usan los visitantes
wp config set WP_HOME "https://$LETS_ENCRYPT_DOMAIN" \
  --path=$WP_DIR \
  --allow-root

# Apagamos set -x porque aquí va la contraseña del administrador
set +x

# Instalamos WordPress (la URL es la de la carpeta donde está el código)
wp core install \
  --url="https://$LETS_ENCRYPT_DOMAIN/wordpress" \
  --title="$WORDPRESS_TITLE" \
  --admin_user="$WORDPRESS_ADMIN_USER" \
  --admin_password="$WORDPRESS_ADMIN_PASSWORD" \
  --admin_email="$WORDPRESS_ADMIN_EMAIL" \
  --path=$WP_DIR \
  --allow-root

set -x

# Guardamos también en la base de datos las dos direcciones
# (así coinciden con lo que hemos puesto en el wp-config.php)
wp option update siteurl "https://$LETS_ENCRYPT_DOMAIN/wordpress" --path=$WP_DIR --allow-root
wp option update home "https://$LETS_ENCRYPT_DOMAIN" --path=$WP_DIR --allow-root

#---------------------------------------------------------
# index.php en la raíz
#---------------------------------------------------------

# Copiamos el index.php de WordPress a la raíz del servidor web
cp $WP_DIR/index.php /var/www/html/

# Le cambiamos la ruta para que cargue el WordPress de la carpeta wordpress
# (usamos # como separador en sed porque la ruta lleva /)
sed -i "s#wp-blog-header.php#wordpress/wp-blog-header.php#" /var/www/html/index.php

#---------------------------------------------------------
# Enlaces permanentes
#---------------------------------------------------------

# Configuramos los enlaces permanentes con el nombre de la entrada
wp rewrite structure '/%postname%/' \
  --path=$WP_DIR \
  --allow-root

# Copiamos el .htaccess a la RAÍZ (es donde llegan las peticiones y donde está el index.php)
cp "$SCRIPT_DIR/../htaccess/.htaccess" /var/www/html/

#---------------------------------------------------------
# Plugin para ocultar la página de login
#---------------------------------------------------------

# Instalamos y activamos el plugin WPS Hide Login
wp plugin install wps-hide-login --activate \
  --path=$WP_DIR \
  --allow-root

# Cambiamos la URL del login por la que pusimos en el .env
wp option update whl_page "$URL_HIDE_LOGIN" \
  --path=$WP_DIR \
  --allow-root

#---------------------------------------------------------
# Permisos
#---------------------------------------------------------

# Cambiamos el propietario y el grupo de /var/www/html a www-data (el usuario de Apache)
chown -R www-data:www-data /var/www/html
