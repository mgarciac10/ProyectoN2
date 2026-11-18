#!/usr/bin/env bash
# Configura BIND9 como servidor DNS AUTORITATIVO (sin recursión) para la zona de XYZ S.A.
# Uso (como root):  ./setup-bind.sh <primario|secundario> <dominio>
#   xyz-ns1:  sudo ./setup-bind.sh primario   midominio.com
#   xyz-ns2:  sudo ./setup-bind.sh secundario midominio.com
# Ejecutar PRIMERO en ns1 (el secundario transfiere la zona desde él).
set -euo pipefail

ROL="${1:?falta el rol: primario|secundario}"
DOM="${2:?falta el dominio, p. ej. midominio.com}"
DOM="${DOM,,}"; DOM="${DOM%.}"          # minúsculas y sin punto final

# --- Direccionamiento del diseño (README §1.3 y §1.4) ---
NS1_PRIV=10.0.1.10;  NS1_PUB=3.134.251.219
NS2_PRIV=10.0.2.10;  NS2_PUB=3.131.134.77
LB1_PUB=18.190.31.183
LB2_PUB=13.58.14.10

case "$ROL" in
  primario)   HOST=xyz-ns1; MY_IP=$NS1_PRIV ;;
  secundario) HOST=xyz-ns2; MY_IP=$NS2_PRIV ;;
  *) echo "Rol inválido: $ROL (usa primario|secundario)"; exit 1 ;;
esac

# Evita ejecutar el rol equivocado en la instancia equivocada
if ! ip -4 -o addr show | grep -q "inet $MY_IP/"; then
  echo "[!] Esta instancia no tiene la IP $MY_IP: ¿rol equivocado?"; exit 1
fi

echo "[*] Host: $HOST | Rol: $ROL | Zona: $DOM | Escucha en: $MY_IP"
hostnamectl set-hostname "$HOST"

# 1) Paquetes: servidor, utilidades (named-checkzone, rndc), dig y tcpdump para las pruebas
apt-get update -y
apt-get install -y bind9 bind9-utils bind9-dnsutils tcpdump

# 2) Solo IPv4 (la VPC no tiene IPv6): evita intentos y errores por IPv6
sed -i 's/^OPTIONS=.*/OPTIONS="-u bind -4"/' /etc/default/named

# 3) Opciones globales: autoritativo puro
#    - listen-on: IP privada + loopback. NO "any": systemd-resolved ya usa 127.0.0.53:53.
#      Las consultas desde Internet llegan a la IP privada porque el IGW traduce EIP -> IP privada (1:1).
#    - recursion no: no es un resolvedor abierto (evita ataques de amplificación).
#    - allow-transfer none: por defecto nadie puede pedir AXFR; la zona del primario lo abre solo para ns2.
cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";

    listen-on port 53 { 127.0.0.1; $MY_IP; };
    listen-on-v6 { none; };

    recursion no;
    allow-query { any; };
    allow-transfer { none; };

    version "no disponible";
};
EOF

# 4) Declaración de la zona
if [[ "$ROL" == "primario" ]]; then
  mkdir -p /etc/bind/zones
  SERIAL="$(date +%Y%m%d)01"      # formato AAAAMMDDNN: subir NN en cada cambio

  # notify explicit + also-notify: el NOTIFY va a la IP PRIVADA de ns2.
  # Si se notificara a los NS de la zona, iría a la EIP de ns2, saldría por el IGW con origen
  # = EIP de ns1, y ns2 lo rechazaría por no venir de su primario (10.0.1.10).
  cat > /etc/bind/named.conf.local <<EOF
zone "$DOM" {
    type primary;
    file "/etc/bind/zones/db.$DOM";
    allow-transfer { $NS2_PRIV; };
    notify explicit;
    also-notify { $NS2_PRIV; };
};
EOF

  cat > "/etc/bind/zones/db.$DOM" <<EOF
\$TTL 300
\$ORIGIN $DOM.
; Zona autoritativa de XYZ S.A. — primario: xyz-ns1
@       IN  SOA ns1.$DOM. admin.$DOM. (
            $SERIAL ; serial (AAAAMMDDNN) — incrementar en cada cambio
            3600       ; refresh: cada cuánto el secundario revisa el serial
            600        ; retry: reintento si el primario no responde
            604800     ; expire: el secundario deja de responder tras 7 días sin primario
            300 )      ; TTL de respuestas negativas (NXDOMAIN)

; Servidores de nombres autoritativos (deben coincidir con la delegación en el registrador)
@       IN  NS      ns1.$DOM.
@       IN  NS      ns2.$DOM.

; Servidores DNS (estas mismas IPs son los glue records en el registrador)
ns1     IN  A       $NS1_PUB
ns2     IN  A       $NS2_PUB

; Balanceadores HAProxy
lb1     IN  A       $LB1_PUB
lb2     IN  A       $LB2_PUB

; Sitio web: DOS registros A = DNS Round Robin entre lb1 y lb2
www     IN  A       $LB1_PUB
www     IN  A       $LB2_PUB

; Dominio raíz (apex): también apunta a ambos balanceadores
@       IN  A       $LB1_PUB
@       IN  A       $LB2_PUB

; Alias
tienda  IN  CNAME   www
EOF
  chown root:bind "/etc/bind/zones/db.$DOM"
  chmod 644 "/etc/bind/zones/db.$DOM"
  named-checkzone "$DOM" "/etc/bind/zones/db.$DOM"
else
  # masterfile-format text: la copia transferida queda legible (por defecto es binaria "raw")
  # notify no: tras cada AXFR un secundario notifica a los NS de la zona, salvo al MNAME (ns1)
  #   y a sí mismo. Pero ns2 solo conoce su IP privada, no su EIP, así que se notificaba
  #   a sí mismo por la EIP (vía IGW) y luego rechazaba ese NOTIFY ("refused notify from non-primary").
  cat > /etc/bind/named.conf.local <<EOF
zone "$DOM" {
    type secondary;
    file "/var/cache/bind/db.$DOM";
    masterfile-format text;
    primaries { $NS1_PRIV; };
    allow-transfer { none; };
    notify no;
};
EOF
fi

# 5) Validar sintaxis y arrancar
named-checkconf
systemctl enable named
systemctl restart named
sleep 3

echo "[*] Estado del servicio:"
systemctl --no-pager --lines=0 status named || true
echo "[*] Sockets en el puerto 53:"
ss -lunp 'sport = :53' || true

if [[ "$ROL" == "secundario" ]]; then
  echo "[*] Esperando la transferencia de zona (AXFR) desde $NS1_PRIV..."
  for i in $(seq 1 10); do
    [[ -s "/var/cache/bind/db.$DOM" ]] && break
    sleep 2
  done
  journalctl -u named --no-pager | grep -iE "transfer|$DOM" | tail -n 5 || true
fi

echo "[*] SOA servido localmente:"
dig @"$MY_IP" "$DOM" SOA +norec +noall +answer +authority
echo "[OK] BIND9 $ROL configurado para $DOM en $HOST"
