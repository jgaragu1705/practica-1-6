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

# set -a hace que todas las variables que se carguen a continuación se exporten
# (envsubst es un programa aparte y solo ve las variables exportadas)
set -a

# Importamos las variables de entorno
source "$SCRIPT_DIR/.env"

# Desactivamos set -a y volvemos a activar set -x
set +a
set -x

# Comprobamos que las variables necesarias tienen valor (si no, el script se para)
: "${LETS_ENCRYPT_DOMAIN:?Asigne un valor a LETS_ENCRYPT_DOMAIN en .env}"
: "${LETS_ENCRYPT_EMAIL:?Asigne un valor a LETS_ENCRYPT_EMAIL en .env}"

# Instalamos y actualizamos snapd
snap install core
snap refresh core

# Eliminamos certbot si estaba instalado con apt (lo vamos a instalar con snap)
apt remove certbot -y

# Instalamos el cliente de Certbot con snap
snap install --classic certbot

# Creamos un enlace para poder usar el comando certbot directamente
ln -fs /snap/bin/certbot /usr/bin/certbot

# Deshabilitamos los virtual hosts por defecto de Apache
a2dissite 000-default.conf
a2dissite default-ssl.conf

# Creamos el virtual host de nuestro dominio a partir de la plantilla
# (envsubst solo cambia las dos variables que le indicamos)
envsubst '${LETS_ENCRYPT_DOMAIN} ${LETS_ENCRYPT_EMAIL}' \
  < "$SCRIPT_DIR/../conf/virtualhost.conf.template" \
  > "/etc/apache2/sites-available/${LETS_ENCRYPT_DOMAIN}.conf"

# Habilitamos el virtual host de nuestro dominio
a2ensite "${LETS_ENCRYPT_DOMAIN}.conf"

# Reiniciamos Apache para aplicar los cambios
systemctl restart apache2

# Pedimos el certificado a Let's Encrypt y lo configuramos en Apache
# --redirect: redirige todo el tráfico HTTP a HTTPS
# --keep-until-expiring: si ya hay un certificado válido lo reutiliza en vez de pedir otro
certbot --apache \
  -m "$LETS_ENCRYPT_EMAIL" \
  --agree-tos \
  --no-eff-email \
  -d "$LETS_ENCRYPT_DOMAIN" \
  --non-interactive \
  --redirect \
  --keep-until-expiring
