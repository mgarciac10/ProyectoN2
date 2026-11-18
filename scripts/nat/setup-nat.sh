#!/usr/bin/env bash
# Configura una instancia EC2 Ubuntu 26.04 LTS (válido para 24.04+) como NAT (PAT/masquerade) con nftables.
# Uso (como root):  ./setup-nat.sh <nombre-host> <cidr-subred-privada>
#   xyz-nat-a:  ./setup-nat.sh xyz-nat-a 10.0.11.0/24
#   xyz-nat-b:  ./setup-nat.sh xyz-nat-b 10.0.12.0/24
# Requisito en AWS: Source/Destination Check DESHABILITADO en la instancia.
set -euo pipefail

HOST="${1:?falta nombre de host}"
PRIV_CIDR="${2:?falta CIDR de la subred privada}"
# Interfaz de salida (en instancias Nitro/t3 suele ser ens5)
WAN_IF="$(ip -o -4 route show to default | awk '{print $5}' | head -n1)"

echo "[*] Host: $HOST | Subred privada: $PRIV_CIDR | Interfaz: $WAN_IF"

hostnamectl set-hostname "$HOST"

# 1) Herramientas: nftables (NAT), conntrack (prueba N2), tcpdump (capturas)
apt-get update -y
apt-get install -y nftables conntrack tcpdump

# 2) IP forwarding persistente: el kernel reenvía paquetes que no son para él
cat > /etc/sysctl.d/99-nat.conf <<EOF
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-nat.conf

# 3) Reglas nftables
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset

# Filtrado del tráfico reenviado (atraviesa el NAT, no va dirigido a él)
table inet filter {
  chain forward {
    type filter hook forward priority filter; policy drop;
    # Respuestas de conexiones iniciadas desde la subred privada
    ct state established,related accept
    # Conexiones nuevas solo si las inicia la subred privada de esta AZ
    iifname "$WAN_IF" ip saddr $PRIV_CIDR accept
  }
}

# Traducción de direcciones y puertos (SNAT dinámico = masquerade)
table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr $PRIV_CIDR oifname "$WAN_IF" masquerade
  }
}
EOF

systemctl enable nftables
systemctl restart nftables

echo "[*] ip_forward = $(sysctl -n net.ipv4.ip_forward)"
nft list ruleset
echo "[OK] NAT configurado en $HOST para $PRIV_CIDR"
