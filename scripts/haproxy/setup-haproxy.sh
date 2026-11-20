#!/usr/bin/env bash
# Configura un balanceador HAProxy (xyz-lb1 10.0.1.20 o xyz-lb2 10.0.2.20) hacia wp1 y wp2.
# Uso (como root), en lb1 y en lb2:
#   sudo bash setup-haproxy.sh
# Requisitos: Fase 5 lista (wp1 y wp2 sirven en el puerto 80) y SG xyz-sg-lb con TCP 80 abierto.
set -euo pipefail

WP1=10.0.11.10
WP2=10.0.12.10
DOMINIO=xyzcosmetics.online
STATS_USER=admin

# --- Identificar el nodo por su IP privada ---
if   ip -4 -o addr show | grep -q "inet 10.0.1.20/"; then HOST=xyz-lb1; MY_IP=10.0.1.20
elif ip -4 -o addr show | grep -q "inet 10.0.2.20/"; then HOST=xyz-lb2; MY_IP=10.0.2.20
else echo "[!] Esta instancia no es lb1 (10.0.1.20) ni lb2 (10.0.2.20)"; exit 1; fi
echo "[*] Nodo: $HOST ($MY_IP)"

# --- Contraseña de la página de estadísticas (no se guarda en el repo) ---
if [[ -z "${STATS_PASS:-}" ]]; then read -rsp "Contraseña para la página de stats (16+ letras/números): " STATS_PASS; echo; fi
[[ "$STATS_PASS" =~ ^[A-Za-z0-9]{16,}$ ]] || { echo "[!] Contraseña inválida"; exit 1; }

hostnamectl set-hostname "$HOST"

# 1) Paquetes (lb1/lb2 están en subred pública: salen a Internet por el IGW)
apt-get update -y
apt-get install -y haproxy curl tcpdump

# 2) Configuración
cp -n /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.orig || true
cat > /etc/haproxy/haproxy.cfg <<EOF
# haproxy.cfg — generado por setup-haproxy.sh ($HOST)
global
    log /dev/log local0
    maxconn 2000
    user haproxy
    group haproxy
    daemon

defaults
    mode http
    log global
    option httplog
    option dontlognull
    option forwardfor                # agrega X-Forwarded-For con la IP real del cliente
    option redispatch                # si el servidor elegido falla, reintenta en otro
    retries 3
    timeout connect 3s
    timeout client  30s
    timeout server  30s

# Página de estadísticas: el SG solo permite 8404 desde la IP del equipo
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 5s
    stats realm "XYZ HAProxy"
    stats auth $STATS_USER:$STATS_PASS

frontend http_in
    bind *:80
    http-response set-header X-Balanced-By $HOST
    default_backend wordpress

backend wordpress
    balance roundrobin               # sin cookies ni source: sin afinidad de sesión
    option httpchk
    http-check send meth GET uri / ver HTTP/1.1 hdr Host www.$DOMINIO
    http-check expect status 200
    default-server inter 2s fall 2 rise 2
    server wp1 $WP1:80 check
    server wp2 $WP2:80 check
EOF
chmod 640 /etc/haproxy/haproxy.cfg
chown root:haproxy /etc/haproxy/haproxy.cfg
unset STATS_PASS

# 3) Validar, habilitar y arrancar
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl enable haproxy
systemctl restart haproxy
sleep 6

# 4) Resumen de verificación
echo; echo "=== Resumen $HOST ==="
haproxy -v | head -1
systemctl is-active haproxy
ss -ltnp | grep -E ':(80|8404) ' || true
echo "--- Backends (curl directo a wp1 y wp2) ---"
for ip in $WP1 $WP2; do
    printf "%s -> " "$ip"; curl -s -o /dev/null -w "%{http_code}\n" -H "Host: www.$DOMINIO" "http://$ip/"
done
echo "--- 4 peticiones por este balanceador ---"
for i in 1 2 3 4; do
    curl -s -D - -o /dev/null -H "Host: www.$DOMINIO" http://127.0.0.1/ | grep -iE "^HTTP|x-served-by|x-balanced-by" | tr -d '\r' | paste -sd' '
done
echo "[OK] HAProxy listo en $HOST"