#!/usr/bin/env bash
# Configura xyz-db (10.0.11.20): MariaDB para WordPress + servidor NFSv4 para wp-content/uploads.
# Uso (como root):  sudo bash setup-db.sh
#   La contraseña del usuario de WordPress se pide por teclado (no queda en el historial).
#   Guárdala en secrets.env de tu PC (no versionado): la necesitarás en la Fase 5.
set -euo pipefail

DB_IP=10.0.11.20
WP1_IP=10.0.11.10
WP2_IP=10.0.12.10
DB_NAME=wordpress
DB_USER=wpuser
NFS_DIR=/srv/nfs/wp-uploads
WWW_UID=33   # uid/gid de www-data en Ubuntu (igual en wp1 y wp2)

if ! ip -4 -o addr show | grep -q "inet $DB_IP/"; then
  echo "[!] Esta instancia no tiene la IP $DB_IP: ¿es xyz-db?"; exit 1
fi

if [[ -z "${DB_PASS:-}" ]]; then
  read -rsp "Contraseña para '$DB_USER' (solo letras y números, 16+ caracteres): " DB_PASS; echo
fi
if [[ ! "$DB_PASS" =~ ^[A-Za-z0-9]{16,}$ ]]; then
  echo "[!] La contraseña debe tener 16+ caracteres alfanuméricos"; exit 1
fi

hostnamectl set-hostname xyz-db

# 1) Paquetes
apt-get update -y
apt-get install -y mariadb-server nfs-kernel-server tcpdump

# 2) MariaDB: escuchar SOLO en la IP privada (por defecto escucha en 127.0.0.1)
#    skip-name-resolve: autoriza por IP sin hacer DNS inverso de cada cliente
#    Un archivo 60-* se lee después de 50-server.cnf y sobrescribe sus valores.
cat > /etc/mysql/mariadb.conf.d/60-xyz.cnf <<EOF
[mysqld]
bind-address      = $DB_IP
skip-name-resolve = 1
EOF
systemctl enable mariadb
systemctl restart mariadb

# 3) Base de datos y usuario. Mínimo privilegio: el usuario solo existe para las IPs
#    de wp1 y wp2, y solo tiene permisos sobre la base 'wordpress'.
#    root sigue usando unix_socket: solo entra con 'sudo mariadb' desde la propia instancia.
mariadb <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'$WP1_IP' IDENTIFIED BY '$DB_PASS';
CREATE USER IF NOT EXISTS '$DB_USER'@'$WP2_IP' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'$WP1_IP' IDENTIFIED BY '$DB_PASS';
ALTER USER '$DB_USER'@'$WP2_IP' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$WP1_IP';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'$WP2_IP';
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF
unset DB_PASS

# 4) NFS: directorio compartido de uploads, propiedad de www-data (uid 33)
mkdir -p "$NFS_DIR"
chown "$WWW_UID:$WWW_UID" "$NFS_DIR"
chmod 775 "$NFS_DIR"

#  rw,sync          escritura con confirmación en disco antes de responder
#  no_subtree_check recomendado cuando se exporta un directorio completo
#  all_squash + anonuid/anongid=33: todo cliente escribe como www-data, así los
#                   archivos subidos por wp1 son legibles/editables por wp2 y viceversa
cat > /etc/exports <<EOF
$NFS_DIR $WP1_IP(rw,sync,no_subtree_check,all_squash,anonuid=$WWW_UID,anongid=$WWW_UID) $WP2_IP(rw,sync,no_subtree_check,all_squash,anonuid=$WWW_UID,anongid=$WWW_UID)
EOF

# Solo NFSv4: usa únicamente TCP 2049 (lo que abre xyz-sg-db). NFSv3 necesitaría además
# rpcbind (111) y mountd con puertos dinámicos.
nfsconf --set nfsd vers3 n
systemctl enable nfs-server
systemctl restart nfs-server
exportfs -ra

# 5) Resumen
echo "[*] Puertos en escucha (3306 MariaDB, 2049 NFS):"
ss -ltnp | grep -E ':(3306|2049)\b' || true
echo "[*] Usuarios de MariaDB:"
mariadb -e "SELECT User, Host FROM mysql.user WHERE User='$DB_USER';"
echo "[*] Exportaciones NFS:"
exportfs -v
echo "[*] Versiones NFS activas:"
cat /proc/fs/nfsd/versions
echo "[OK] xyz-db listo: MariaDB en $DB_IP:3306 y NFS $NFS_DIR"
