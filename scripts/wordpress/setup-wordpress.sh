#!/usr/bin/env bash
# Configura un nodo WordPress (xyz-wp1 10.0.11.10 o xyz-wp2 10.0.12.10): Apache + PHP + WordPress,
# DB remota en xyz-db, uploads por NFS y mu-plugin que muestra la IP privada del nodo.
# Uso (como root), PRIMERO en wp1 y después en wp2:
#   sudo bash setup-wordpress.sh
# Requisitos:
#   - Fase 4 lista (MariaDB y NFS en 10.0.11.20).
#   - En wp1 se generan las claves/salts en /root/xyz-wp-salts.txt.
#     En wp2 ese MISMO archivo debe existir antes de ejecutar (copiarlo desde wp1).
#   El mu-plugin y el contenido de las páginas van incluidos en este mismo archivo
#   (un solo archivo que pegar por SSM).
set -euo pipefail

DOMINIO=xyzcosmetics.online
DB_HOST=10.0.11.20
DB_NAME=wordpress
DB_USER=wpuser
NFS_EXPORT="$DB_HOST:/srv/nfs/wp-uploads"
WP_DIR=/var/www/wordpress
SALTS=/root/xyz-wp-salts.txt

# --- Identificar el nodo por su IP privada ---
if   ip -4 -o addr show | grep -q "inet 10.0.11.10/"; then HOST=xyz-wp1; MY_IP=10.0.11.10
elif ip -4 -o addr show | grep -q "inet 10.0.12.10/"; then HOST=xyz-wp2; MY_IP=10.0.12.10
else echo "[!] Esta instancia no es wp1 (10.0.11.10) ni wp2 (10.0.12.10)"; exit 1; fi
echo "[*] Nodo: $HOST ($MY_IP)"

# --- Claves y salts: deben ser IDÉNTICAS en ambos nodos ---
if [[ ! -s "$SALTS" ]]; then
  if [[ "$HOST" == "xyz-wp1" ]]; then
    echo "[*] Generando claves y salts en $SALTS"
    umask 077
    for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
      printf "define('%s', '%s');\n" "$k" "$(openssl rand -base64 64 | tr -d '\n/+=' | cut -c1-64)"
    done > "$SALTS"
    umask 022
  else
    echo "[!] Falta $SALTS. Cópialo desde wp1 (sudo cat $SALTS) antes de continuar."; exit 1
  fi
fi
[[ $(grep -c "^define(" "$SALTS") -eq 8 ]] || { echo "[!] $SALTS no tiene las 8 constantes"; exit 1; }

# --- Contraseña de la DB (la misma de secrets.env) ---
if [[ -z "${DB_PASS:-}" ]]; then read -rsp "Contraseña de '$DB_USER' en MariaDB: " DB_PASS; echo; fi
[[ "$DB_PASS" =~ ^[A-Za-z0-9]{16,}$ ]] || { echo "[!] Contraseña inválida"; exit 1; }

hostnamectl set-hostname "$HOST"

# 1) Paquetes: Apache + PHP (mod_php) + extensiones que usa WordPress; clientes de DB y NFS
apt-get update -y
apt-get install -y apache2 libapache2-mod-php php-mysql php-curl php-gd php-mbstring \
  php-xml php-zip php-intl mariadb-client nfs-common curl tcpdump

# 2) Prueba de la DB antes de seguir
MYSQL_PWD="$DB_PASS" mariadb -h "$DB_HOST" -u "$DB_USER" -e "SELECT 1" "$DB_NAME" >/dev/null \
  || { echo "[!] No se pudo conectar a MariaDB en $DB_HOST"; exit 1; }

# 3) WP-CLI (herramienta oficial de línea de comandos de WordPress)
if ! command -v wp >/dev/null; then
  curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x /usr/local/bin/wp
fi
wpc() { wp --allow-root --path="$WP_DIR" "$@"; }

# 4) Código de WordPress en el disco local del nodo. Se descarga la versión base (en_US):
#    la API de WordPress no siempre ofrece el paquete completo en es_ES para la última
#    versión ("The requested locale (es_ES) was not found"). El español se instala en el paso 10.
mkdir -p "$WP_DIR"
if [[ ! -f "$WP_DIR/wp-includes/version.php" ]]; then
  wpc core download
fi

# 5) Uploads compartidos por NFS (persistente en /etc/fstab)
#    _netdev: montar cuando haya red · nofail: si la DB no responde, el nodo arranca igual
UPLOADS="$WP_DIR/wp-content/uploads"
mkdir -p "$UPLOADS"
if ! grep -q " $UPLOADS " /etc/fstab; then
  echo "$NFS_EXPORT $UPLOADS nfs4 defaults,_netdev,nofail,hard,timeo=600 0 0" >> /etc/fstab
fi
systemctl daemon-reload
mountpoint -q "$UPLOADS" || mount "$UPLOADS"

# 6) wp-config.php: igual en ambos nodos
{
cat <<EOF
<?php
/* wp-config.php — generado por setup-wordpress.sh. Idéntico en xyz-wp1 y xyz-wp2. */

/* Base de datos compartida en xyz-db */
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASSWORD', '$DB_PASS');
define('DB_HOST', '$DB_HOST');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

/* Claves y salts: idénticas en ambos nodos, así la cookie de sesión emitida por un nodo es válida en el otro */
EOF
cat "$SALTS"
cat <<'EOF'

$table_prefix = 'wp_';

/* URL dinámica: el sitio responde con el nombre o IP por el que se le llamó
 * (www, dominio raíz, tienda, lb1/lb2 o sus IPs). Lista blanca para evitar
 * inyección de cabecera Host; cualquier otro valor usa www. */
$xyz_hosts = array(
  'www.xyzcosmetics.online', 'xyzcosmetics.online', 'tienda.xyzcosmetics.online',
  'lb1.xyzcosmetics.online', 'lb2.xyzcosmetics.online', '18.190.31.183', '13.58.14.10',
);
$xyz_host = strtolower( isset( $_SERVER['HTTP_HOST'] ) ? $_SERVER['HTTP_HOST'] : '' );
if ( ! in_array( $xyz_host, $xyz_hosts, true ) ) {
  $xyz_host = 'www.xyzcosmetics.online';
}
define('WP_HOME', 'http://' . $xyz_host);
define('WP_SITEURL', 'http://' . $xyz_host);

/* Los dos nodos deben tener SIEMPRE el mismo código: no se instalan ni actualizan
 * plugins/temas/idiomas/núcleo desde el panel (quedarían solo en el nodo que atendió).
 * WP-CLI sí puede: el script lo ejecuta igual en ambos nodos. */
define('DISALLOW_FILE_MODS', ! ( defined('WP_CLI') && WP_CLI ));
define('AUTOMATIC_UPDATER_DISABLED', true);
define('WP_CACHE', false);
define('WP_DEBUG', false);

if ( ! defined('ABSPATH') ) {
  define('ABSPATH', __DIR__ . '/');
}
require_once ABSPATH . 'wp-settings.php';
EOF
} > "$WP_DIR/wp-config.php"
unset DB_PASS

# 7) mu-plugin: muestra el nodo y su IP privada (los mu-plugins se cargan siempre y no se
#    pueden desactivar desde el panel). La IP se lee EN CADA PETICIÓN de SERVER_ADDR, la
#    dirección local en la que Apache recibió la conexión: no está escrita a mano.
mkdir -p "$WP_DIR/wp-content/mu-plugins"
cat > "$WP_DIR/wp-content/mu-plugins/xyz-servidor.php" <<'EOF'
<?php
/*
 * Plugin Name: XYZ - Servidor que atendió
 * Description: Muestra en cada página el nodo WordPress y su IPv4 privada (prueba del balanceo).
 */
defined( 'ABSPATH' ) || exit;

/*
 * 1) SERVER_ADDR: IP local en la que Apache recibió ESTA conexión. Cuando la petición llega
 *    desde HAProxy es la IP privada del nodo (10.0.11.10 / 10.0.12.10).
 * 2) Si la conexión llegó por loopback (curl a 127.0.0.1 dentro del nodo), se obtiene la IP
 *    privada de la interfaz de salida: un socket UDP "conectado" al DNS de la VPC (10.0.0.2)
 *    hace que el kernel elija la ruta y la IP de origen, sin enviar ningún paquete.
 */
function xyz_servidor_ip() {
	$ip = isset( $_SERVER['SERVER_ADDR'] ) ? $_SERVER['SERVER_ADDR'] : '';
	if ( filter_var( $ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4 ) && strpos( $ip, '127.' ) !== 0 ) {
		return $ip;
	}
	$s = @stream_socket_client( 'udp://10.0.0.2:53', $errno, $errstr, 1 );
	if ( $s ) {
		$local = stream_socket_get_name( $s, false );   // "10.0.11.10:puerto"
		fclose( $s );
		if ( $local ) {
			return substr( $local, 0, strrpos( $local, ':' ) );
		}
	}
	return $ip;
}

add_action( 'wp_body_open', function () {
	if ( is_admin() ) {
		return;
	}
	printf(
		'<div id="xyz-servidor" style="background:#6b2c5f;color:#fff;text-align:center;padding:10px;font:16px/1.4 sans-serif">Página servida por <strong>%s</strong> · IPv4 privada <strong>%s</strong> · %s</div>',
		esc_html( gethostname() ),
		esc_html( xyz_servidor_ip() ),
		esc_html( wp_date( 'Y-m-d H:i:s' ) )
	);
} );
EOF

# Permisos: código de root (solo lectura para Apache); wp-config legible solo por root y www-data.
# Se excluye uploads: es el montaje NFS y allí todo pertenece a www-data (all_squash).
find "$WP_DIR" -path "$UPLOADS" -prune -o -exec chown root:root {} +
find "$WP_DIR" -path "$UPLOADS" -prune -o -type d -exec chmod 755 {} +
find "$WP_DIR" -path "$UPLOADS" -prune -o -type f -exec chmod 644 {} +
chown root:www-data "$WP_DIR/wp-config.php"
chmod 640 "$WP_DIR/wp-config.php"

# 8) Apache: VirtualHost propio. Las reglas de enlaces permanentes van aquí y no en .htaccess,
#    porque .htaccess es un archivo local que podría quedar distinto entre nodos.
cat > /etc/apache2/sites-available/xyz-wordpress.conf <<EOF
<VirtualHost *:80>
    ServerName www.$DOMINIO
    ServerAlias *
    DocumentRoot $WP_DIR

    <Directory $WP_DIR>
        Options FollowSymLinks
        AllowOverride None
        Require all granted
        DirectoryIndex index.php
        RewriteEngine On
        RewriteBase /
        RewriteRule ^index\.php$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteRule . /index.php [L]
    </Directory>

    # Nunca ejecutar PHP subido por usuarios
    <Directory $UPLOADS>
        php_admin_flag engine off
    </Directory>

    # Identifica el nodo en TODAS las respuestas (útil para B1/B2 con curl -I)
    Header always set X-Served-By "$HOST $MY_IP"
    # Sin caché en navegadores ni intermediarios: cada recarga llega al balanceador
    Header set Cache-Control "no-store"

    # %h = IP del balanceador; X-Forwarded-For = IP real del cliente (lo agrega HAProxy)
    LogFormat "%h %{X-Forwarded-For}i %l %u %t \"%r\" %>s %b \"%{Host}i\"" xyz
    CustomLog \${APACHE_LOG_DIR}/xyz-access.log xyz
    ErrorLog \${APACHE_LOG_DIR}/xyz-error.log
</VirtualHost>
EOF
a2enmod -q rewrite headers
a2dissite -q 000-default || true
a2ensite -q xyz-wordpress
apache2ctl configtest
systemctl enable apache2
systemctl reload apache2 || systemctl restart apache2

# 9) Instalación y contenido: SOLO la primera vez (la DB es compartida; en wp2 ya existe)
if wpc core is-installed 2>/dev/null; then
  echo "[*] WordPress ya está instalado en la DB compartida: se omite la instalación"
else
  read -rp  "Usuario administrador de WordPress [xyzadmin]: " WP_ADMIN; WP_ADMIN=${WP_ADMIN:-xyzadmin}
  read -rsp "Contraseña del administrador (solo letras y números, 16+): " WP_ADMIN_PASS; echo
  [[ "$WP_ADMIN_PASS" =~ ^[A-Za-z0-9]{16,}$ ]] || { echo "[!] Contraseña inválida"; exit 1; }
  wpc core install --url="http://www.$DOMINIO" --title="XYZ S.A." \
    --admin_user="$WP_ADMIN" --admin_password="$WP_ADMIN_PASS" \
    --admin_email="admin@$DOMINIO" --skip-email
  unset WP_ADMIN_PASS

  wpc option update blogdescription "Cosméticos con raíces colombianas"
  wpc option update timezone_string "America/Bogota"
  wpc option update date_format "j \d\e F \d\e Y"
  wpc rewrite structure '/%postname%/'
  wpc post delete 1 2 --force || true              # entrada y página de ejemplo

  CONT=$(mktemp -d)
  cat > "$CONT/inicio.html" <<'EOF'
<!-- wp:heading --><h2>Belleza que nace en Colombia</h2><!-- /wp:heading -->
<!-- wp:paragraph --><p>En <strong>XYZ S.A.</strong> fabricamos cosméticos para el cuidado de la piel, el cabello y el maquillaje, con ingredientes de origen natural y procesos responsables.</p><!-- /wp:paragraph -->
<!-- wp:paragraph --><p>Atendemos desde nuestras sedes de <strong>Medellín</strong>, <strong>Bogotá</strong> y <strong>Bucaramanga</strong>.</p><!-- /wp:paragraph -->
<!-- wp:paragraph --><p>La franja superior de esta página indica qué servidor de nuestra plataforma la generó. Recargue la página para ver cómo cambia.</p><!-- /wp:paragraph -->
EOF
  cat > "$CONT/nosotros.html" <<'EOF'
<!-- wp:paragraph --><p>XYZ S.A. es una empresa colombiana dedicada al desarrollo, fabricación y comercialización de productos cosméticos.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":3} --><h3>Misión</h3><!-- /wp:heading -->
<!-- wp:paragraph --><p>Ofrecer cosméticos de alta calidad, seguros y accesibles, que realcen la belleza natural de nuestros clientes.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":3} --><h3>Visión</h3><!-- /wp:heading -->
<!-- wp:paragraph --><p>Ser una marca de referencia en cosmética natural en Colombia y la región andina.</p><!-- /wp:paragraph -->
EOF
  cat > "$CONT/productos.html" <<'EOF'
<!-- wp:paragraph --><p>Nuestras líneas de producto:</p><!-- /wp:paragraph -->
<!-- wp:list --><ul>
<li><strong>Cuidado facial:</strong> limpiadores, hidratantes y protectores solares.</li>
<li><strong>Maquillaje:</strong> bases, labiales y sombras.</li>
<li><strong>Cuidado capilar:</strong> champús y acondicionadores sin sulfatos.</li>
<li><strong>Cuidado corporal:</strong> cremas y aceites con ingredientes naturales.</li>
</ul><!-- /wp:list -->
EOF
  cat > "$CONT/sedes.html" <<'EOF'
<!-- wp:heading {"level":3} --><h3>Medellín</h3><!-- /wp:heading -->
<!-- wp:paragraph --><p>Sede principal: oficinas administrativas y planta de producción.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":3} --><h3>Bogotá</h3><!-- /wp:heading -->
<!-- wp:paragraph --><p>Oficina comercial y centro de distribución para el centro del país.</p><!-- /wp:paragraph -->
<!-- wp:heading {"level":3} --><h3>Bucaramanga</h3><!-- /wp:heading -->
<!-- wp:paragraph --><p>Oficina comercial para la región nororiental.</p><!-- /wp:paragraph -->
EOF
  cat > "$CONT/contacto.html" <<'EOF'
<!-- wp:paragraph --><p>Escríbanos a <strong>contacto@xyzcosmetics.online</strong> o visítenos en cualquiera de nuestras sedes.</p><!-- /wp:paragraph -->
<!-- wp:paragraph --><p>Horario de atención: lunes a viernes, de 8:00 a. m. a 5:00 p. m.</p><!-- /wp:paragraph -->
EOF
  pagina() { wpc post create "$CONT/$2" --post_type=page --post_status=publish \
               --post_title="$1" --menu_order="$3" --porcelain; }
  INICIO=$(pagina "Inicio" inicio.html 0)
  pagina "Nosotros"  nosotros.html  1 >/dev/null
  pagina "Productos" productos.html 2 >/dev/null
  pagina "Sedes"     sedes.html     3 >/dev/null
  pagina "Contacto"  contacto.html  4 >/dev/null
  wpc option update show_on_front page
  wpc option update page_on_front "$INICIO"
  rm -rf "$CONT"
fi

# 10) Idioma español: los archivos .mo van en el disco LOCAL (wp-content/languages), así que
#     se instalan en cada nodo; la activación (opción WPLANG) queda en la DB compartida.
wpc language core install es_ES --activate   || echo "[!] No se pudo instalar es_ES; el panel quedará en inglés (el contenido sigue en español)"

# 11) Resumen
echo "[*] Versión de WordPress: $(wpc core version)"
echo "[*] Montaje NFS:"; findmnt "$UPLOADS" || true
echo "[*] Páginas:"; wpc post list --post_type=page --fields=ID,post_title,post_name,post_status
echo "[*] Prueba local:"
curl -s -o /dev/null -D - -H "Host: www.$DOMINIO" http://127.0.0.1/ | grep -iE "^HTTP|x-served-by|cache-control"
curl -s -H "Host: www.$DOMINIO" http://127.0.0.1/ | grep -o 'id="xyz-servidor".*</div>' | sed 's/<[^>]*>//g'
echo "[OK] $HOST listo"
