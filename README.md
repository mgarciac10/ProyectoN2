# Proyecto N2 — Despliegue de Aplicaciones y Servicios en Red (SI3002)

Despliegue del sitio web corporativo de **XYZ S.A.** (cosméticos) en **WordPress** sobre una infraestructura en **AWS** con alta disponibilidad y escalado horizontal: VPC en dos zonas de disponibilidad, **NAT propio** sobre Linux, **balanceadores HAProxy** autogestionados, **DNS autoritativo BIND9** primario/secundario y una base de datos **MariaDB** compartida.

> Este documento recoge el diseño, la implementación y las pruebas. Es la base del informe final.

---

## 1. Arquitectura

### 1.1 Diagrama general

```
                                   Internet
                                       │
          Cliente ──DNS (UDP/TCP 53)──►│◄── Registrador .TLD (delegación NS + glue)
                                       │
                          ┌────────────┴────────────┐
                          │   Internet Gateway (IGW) │  NAT 1:1 IP pública ↔ IP privada
                          └────────────┬────────────┘
 VPC 10.0.0.0/16 (us-east-2)           │
┌──────────── AZ us-east-2a ──────────────┐   ┌──────────── AZ us-east-2b ──────────────┐
│ public-a 10.0.1.0/24   (0/0 → IGW)       │   │ public-b 10.0.2.0/24   (0/0 → IGW)       │
│   xyz-ns1  BIND9 primario   10.0.1.10 EIP│◄─►│   xyz-ns2  BIND9 secundario 10.0.2.10 EIP│ AXFR/NOTIFY
│   xyz-lb1  HAProxy          10.0.1.20 EIP│   │   xyz-lb2  HAProxy          10.0.2.20 EIP│
│   xyz-nat-a NAT nftables    10.0.1.30    │   │   xyz-nat-b NAT nftables    10.0.2.30    │
├──────────────────────────────────────────┤   ├──────────────────────────────────────────┤
│ private-a 10.0.11.0/24 (0/0 → nat-a)     │   │ private-b 10.0.12.0/24 (0/0 → nat-b)     │
│   xyz-wp1  Apache+PHP+WP    10.0.11.10   │   │   xyz-wp2  Apache+PHP+WP    10.0.12.10   │
│   xyz-db   MariaDB + NFS    10.0.11.20   │   │                                          │
└──────────────────────────────────────────┘   └──────────────────────────────────────────┘
        lb1 y lb2 balancean HTTP hacia wp1 y wp2 · wp1 y wp2 usan db (3306) y NFS (2049)
```

### 1.2 Flujo de una petición
1. El cliente resuelve `www.<dominio>`: su resolvedor recursivo sigue la delegación del TLD hacia `ns1`/`ns2` (BIND9), que responden con **dos registros A** (EIP de lb1 y lb2) → **DNS Round Robin**.
2. El cliente abre TCP:80 contra uno de los balanceadores. El IGW traduce la EIP a la IP privada del LB.
3. HAProxy elige un backend (`roundrobin`) entre wp1 y wp2, verificando su salud con health checks.
4. WordPress consulta MariaDB en `xyz-db` y lee archivos subidos desde el montaje NFS.
5. La respuesta muestra la **IP privada** del nodo WordPress que atendió la petición.

### 1.3 Plan de direccionamiento

| Subred | CIDR | AZ | Tipo | Ruta por defecto |
|---|---|---|---|---|
| xyz-public-a | 10.0.1.0/24 | us-east-2a | Pública | 0.0.0.0/0 → IGW |
| xyz-private-a | 10.0.11.0/24 | us-east-2a | Privada | 0.0.0.0/0 → ENI de xyz-nat-a |
| xyz-public-b | 10.0.2.0/24 | us-east-2b | Pública | 0.0.0.0/0 → IGW |
| xyz-private-b | 10.0.12.0/24 | us-east-2b | Privada | 0.0.0.0/0 → ENI de xyz-nat-b |

Todas las tablas incluyen la ruta implícita `10.0.0.0/16 → local`.

### 1.4 Inventario de instancias EC2 (9)

| Nombre | Rol | Subred | IP privada | IP pública | Instance ID |
|---|---|---|---|---|---|
| xyz-ns1 | DNS BIND9 primario | public-a | 10.0.1.10 | 3.134.251.219 (EIP) | |
| xyz-lb1 | Balanceador HAProxy | public-a | 10.0.1.20 | 18.190.31.183 (EIP) | |
| xyz-nat-a | NAT (nftables) | public-a | 10.0.1.30 | Automática | |
| xyz-ns2 | DNS BIND9 secundario | public-b | 10.0.2.10 | 3.131.134.77 (EIP) | |
| xyz-lb2 | Balanceador HAProxy | public-b | 10.0.2.20 | 13.58.14.10 (EIP) | |
| xyz-nat-b | NAT (nftables) | public-b | 10.0.2.30 | Automática | |
| xyz-wp1 | WordPress | private-a | 10.0.11.10 | — | |
| xyz-db | MariaDB + NFS | private-a | 10.0.11.20 | — | |
| xyz-wp2 | WordPress | private-b | 10.0.12.10 | — | |

Todas: Ubuntu Server 24.04 LTS, `t3.micro`, 8 GiB gp3, rol IAM `xyz-ec2-ssm-role`.

### 1.5 Grupos de seguridad (diseño)

| SG | Entrada permitida | Origen |
|---|---|---|
| xyz-sg-dns | UDP 53, TCP 53 | 0.0.0.0/0 |
| xyz-sg-lb | TCP 80 | 0.0.0.0/0 |
| | TCP 8404 (stats HAProxy) | IP del equipo /32 |
| xyz-sg-nat | Todo el tráfico | 10.0.11.0/24, 10.0.12.0/24 |
| xyz-sg-wp | TCP 80 | xyz-sg-lb |
| xyz-sg-db | TCP 3306 (MariaDB), TCP 2049 (NFS) | xyz-sg-wp |
| (todos) | ICMP (pruebas) | 10.0.0.0/16 |

Salida: todo permitido (por defecto). **Ningún SG abre SSH (22)**: la administración se hace con SSM Session Manager.

### 1.6 Decisiones de diseño y justificación

| Decisión | Justificación |
|---|---|
| Región us-east-2, dos AZ | Región fija del proyecto AWS (nueva experiencia, asignada por país); una AZ caída deja operativa la otra mitad (NAT, LB, DNS, WP). |
| t3.micro | Elegible en el plan gratuito; suficiente para carga académica. |
| NAT propio por AZ | Requisito; además evita tráfico entre AZ y que una AZ dependa de la otra para salir a Internet. |
| HAProxy | Health checks activos y página de estadísticas para evidenciar el balanceo. |
| Sin afinidad de sesión | Requisito B1: cada petición debe poder ir a cualquier nodo. |
| NFS en la instancia DB | Comparte `wp-content/uploads` sin instancia adicional (límite de 9). La DB ya es SPOF; concentrar ahí el estado lo hace explícito. |
| Salts idénticos en ambos WP | Las sesiones de WordPress se validan con cookies firmadas; con los mismos salts y la misma DB, cualquier nodo acepta la sesión. |
| EIP solo en ns1/ns2/lb1/lb2 | Necesitan IP fija (glue records y registros A). La cuota por defecto es 5 EIP. |
| SSM en lugar de SSH | Requisito; no se exponen puertos de administración. Las privadas alcanzan los endpoints de SSM a través de su NAT. |

### 1.7 Punto único de falla y estado compartido
_(Por completar en Fase 4–5.)_ La instancia `xyz-db` concentra la base de datos y los archivos subidos. Si falla, ambos WordPress dejan de servir contenido dinámico aunque los balanceadores y el DNS sigan operativos. Mitigaciones fuera de alcance: réplica MariaDB, Amazon RDS Multi-AZ, EFS/S3 para medios.

### 1.8 Estimación de costos

| Recurso | Cálculo | USD/hora |
|---|---|---|
| 9 × t3.micro | 9 × 0.0104 | 0.094 |
| 6 IPv4 públicas (4 EIP + 2 automáticas) | 6 × 0.005 | 0.030 |
| 9 × 8 GiB gp3 | 72 GiB × 0.08 / 730 | 0.008 |
| **Total** | | **≈ 0.13 USD/h ≈ 3.2 USD/día** |

Con ~5 días de despliegue el costo esperado es ≈ 16 USD, dentro de los 100 USD de crédito.

---

## 2. Implementación por fases

### Fase 0 — Preparación
_(Por documentar: seguridad de la cuenta, cuotas, dominio.)_

### Fase 1 — Red base

**VPC.** `xyz-vpc`, `10.0.0.0/16`, creada con la opción *VPC only* para controlar cada recurso a mano y evitar que el asistente cree un NAT Gateway, que el enunciado prohíbe. Tiene activados *DNS resolution* y *DNS hostnames*.

**Subredes.** Se crearon las cuatro de la tabla 1.3. En `xyz-public-a` y `xyz-public-b` se activó *auto-assign public IPv4*, de modo que las instancias NAT reciben IP pública sin consumir Elastic IP. Las privadas no asignan IP pública. En cada /24, AWS reserva 5 direcciones (`.0` red, `.1` router de la VPC, `.2` DNS de AWS, `.3` reservada y `.255` broadcast), así que quedan 251 utilizables.

**Direccionamiento privado e Internet Gateway.** Todas las subredes usan direcciones privadas RFC 1918. Lo que hace pública a una subred no es su rango, sino que su tabla de rutas envía `0.0.0.0/0` al IGW y que sus instancias tienen una IP pública asociada. Esa IP pública no está configurada en la instancia: el IGW traduce 1:1 entre IP pública e IP privada.

**Internet Gateway.** `xyz-igw`, adjunto a `xyz-vpc`.

**Tablas de rutas.**

| Tabla | Subredes asociadas | Rutas |
|---|---|---|
| xyz-rt-public | xyz-public-a, xyz-public-b | 10.0.0.0/16 → local; 0.0.0.0/0 → xyz-igw |
| xyz-rt-private-a | xyz-private-a | 10.0.0.0/16 → local (en la Fase 2 se agrega 0.0.0.0/0 → xyz-nat-a) |
| xyz-rt-private-b | xyz-private-b | 10.0.0.0/16 → local (en la Fase 2 se agrega 0.0.0.0/0 → xyz-nat-b) |
| main (sin nombre) | ninguna asociada explícitamente | 10.0.0.0/16 → local |

Se usa una tabla privada por AZ para que cada subred privada salga por el NAT de su misma zona.

**VPC por defecto.** La región trae una VPC default (`172.31.0.0/16`, una subred por AZ). Se deja sin usar; el proyecto no despliega nada en ella.

Evidencia: `evidencias/fase1/resource-map-vpc.png`.

**Security Groups** (todos en `xyz-vpc`; la regla de salida es la default, todo permitido):

| SG | ID | Entrada |
|---|---|---|
| xyz-sg-lb | sg-0c9f84365bae19198 | TCP 80 desde 0.0.0.0/0 · TCP 8404 desde la IP del equipo · ICMP desde 0.0.0.0/0 |
| xyz-sg-dns | sg-0bc2fea80ceaee124 | UDP/TCP 53 desde 0.0.0.0/0 · ICMP desde 0.0.0.0/0 |
| xyz-sg-nat | sg-07f939b9f763c23c9 | Todo el tráfico desde 10.0.11.0/24 y 10.0.12.0/24 |
| xyz-sg-wp | sg-0260dc2f52e738c66 | TCP 80 desde xyz-sg-lb · ICMP desde 10.0.0.0/16 |
| xyz-sg-db | sg-00410bb2e8ec6b83c | TCP 3306 y TCP 2049 desde xyz-sg-wp · ICMP desde 10.0.0.0/16 |

Los SG son *stateful*: el tráfico de respuesta de una conexión permitida pasa sin regla adicional. En wp y db el origen es otro SG (mínimo privilegio independiente de las IPs). El SG del NAT debe aceptar el tráfico de las subredes privadas porque los paquetes reenviados atraviesan su ENI. Ningún SG abre SSH.

Evidencia: `evidencias/fase1/security-groups.png`.

**Rol IAM.** `xyz-ec2-ssm-role` (entidad de confianza: EC2; política `AmazonSSMManagedInstanceCore`). Permite que el agente SSM se registre sin credenciales almacenadas en las instancias.

**Elastic IPs** (se reservan antes de lanzar las instancias para conocer de antemano las IPs que van en los glue records y en los registros A):

| Nombre | IPv4 pública | Allocation ID | Uso |
|---|---|---|---|
| xyz-eip-ns1 | 3.134.251.219 | eipalloc-04f4afdd13aefb7b8 | ns1 (glue record) |
| xyz-eip-ns2 | 3.131.134.77 | eipalloc-0683a0cd8afb72253 | ns2 (glue record) |
| xyz-eip-lb1 | 18.190.31.183 | eipalloc-0cce7e1847bcdb5ae | lb1 (registro A de www) |
| xyz-eip-lb2 | 13.58.14.10 | eipalloc-075b3a1be9327354a | lb2 (registro A de www) |

Evidencia: `evidencias/fase1/elastic-ips.png`.

**Presupuesto.** Se creó en AWS Budgets un presupuesto mensual de 30 USD con alertas por correo.

### Fase 2 — NAT

**Instancias.** Se lanzaron `xyz-nat-a` (public-a, 10.0.1.30) y `xyz-nat-b` (public-b, 10.0.2.30): Ubuntu 24.04 LTS, t3.micro, sin key pair (acceso por SSM), SG `xyz-sg-nat`, IP pública automática y rol `xyz-ec2-ssm-role`.

**Source/Destination Check deshabilitado.** Por defecto, AWS descarta los paquetes cuyo destino (al entrar) o cuyo origen (al salir) no es la IP de la instancia. Un NAT reenvía tráfico ajeno, como paquetes de 10.0.11.10 hacia Internet, así que esa verificación tiene que estar apagada.

**Configuración en Linux** (procedimiento en `scripts/nat/setup-nat.sh`):

1. `net.ipv4.ip_forward = 1`, persistente en `/etc/sysctl.d/99-nat.conf`, para que el kernel enrute paquetes que no van dirigidos a él.
2. `nftables` con dos tablas:

```
table inet filter {
  chain forward {
    type filter hook forward priority filter; policy drop;
    ct state established,related accept
    iifname "ens5" ip saddr 10.0.11.0/24 accept      # 10.0.12.0/24 en nat-b
  }
}
table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    ip saddr 10.0.11.0/24 oifname "ens5" masquerade  # 10.0.12.0/24 en nat-b
  }
}
```

- **`masquerade`** es un SNAT dinámico: reemplaza la IP de origen privada por la IP de la interfaz del NAT y, si hace falta, el puerto de origen (PAT). Así varias instancias comparten una sola dirección. La tabla de conntrack guarda cada asociación para deshacer la traducción en las respuestas.
- **Cadena `forward` con política `drop`:** solo se reenvían conexiones nuevas que vienen de la subred privada de la misma AZ, más las respuestas (`established,related`). Una conexión entrante no solicitada no tiene entrada en conntrack, así que se descarta.
- Las instancias tienen una sola interfaz (`ens5`), así que el tráfico entra y sale por ella.

**Rutas privadas.** `xyz-rt-private-a`: `0.0.0.0/0 → eni-0c87d0d9aa17892e9` (ENI de xyz-nat-a). `xyz-rt-private-b`: `0.0.0.0/0 → ENI de xyz-nat-b`. Al elegir la instancia como destino, AWS guarda en la ruta su interfaz de red (ENI).

**Doble traducción.** El tráfico de una instancia privada se traduce dos veces: primero en el NAT de Linux (N:1 con puertos, 10.0.11.10:p → 10.0.1.30:p') y luego en el IGW (1:1, 10.0.1.30 → IP pública de nat-a).

Evidencias: `evidencias/fase2/nat-a-nft-ruleset.png`, `nat-a-ip-forward.png`, `nat-b-nft-ruleset.png`, `nat-b-ip-forward.png`, `rt-private-a-routes.png`.

### Fase 3 — DNS BIND9
_(Por documentar.)_

### Fase 4 — Base de datos y NFS
_(Por documentar.)_

### Fase 5 — WordPress
_(Por documentar.)_

### Fase 6 — Balanceadores HAProxy
_(Por documentar.)_

---

## 3. Pruebas experimentales

Para cada prueba: procedimiento, comandos, evidencia, interpretación y protocolos involucrados.

| ID | Prueba | Estado |
|---|---|---|
| N1 | HTTP desde instancia privada a destino externo; IP pública observada | ✅ Realizada |
| N2 | conntrack: asociaciones de direcciones/puertos antes y después del NAT | ✅ Realizada |
| N3 | Deshabilitar IP forwarding y explicar la falla | ✅ Realizada |
| N4 | Conexión saliente vs. entrante no solicitada | ✅ Realizada (falta adjuntar el tcpdump de nat-a) |
| D1 | dig SOA/NS/A/CNAME a ambos autoritativos; delegación pública | Pendiente |
| D2 | Cambio en primario + serial SOA → transferencia al secundario | Pendiente |
| D3 | Primario caído; secundario responde autoritativamente | Pendiente |
| D4 | Consultas repetidas a `www`: orden de A, TTL/caché | Pendiente |
| D5 | Balanceador caído sigue anunciado por DNS | Pendiente |
| B1 | Peticiones sucesivas a cada LB muestran ambas IPs privadas | Pendiente |
| B2 | WordPress caído; ambos LB siguen atendiendo | Pendiente |

### Verificación previa: registro en SSM a través del NAT
Las tres instancias privadas (wp1, db y wp2) no tienen IP pública y aparecen **Online** en Systems Manager → Fleet Manager. El agente SSM se conecta por HTTPS (TCP 443) a endpoints públicos de AWS, y la única forma de llegar a ellos es la ruta `0.0.0.0/0 → ENI del NAT` de su subred. Esto confirma que el NAT de cada AZ funciona, incluido nat-b para wp2. Evidencia: `evidencias/fase2/ssm-managed-nodes.png`.

### N1 — Solicitud HTTP desde una instancia privada

**Procedimiento.** Se abren dos sesiones SSM. En `xyz-nat-a` se captura el tráfico HTTP de su interfaz y en `xyz-wp1` se inspecciona el direccionamiento y se hace una petición HTTP a un servicio que devuelve la IP pública del cliente.

```bash
# xyz-nat-a
sudo tcpdump -ni ens5 -c 12 'tcp port 80'
# xyz-wp1
ip -br addr
ip route
curl -s http://checkip.amazonaws.com
```

**Evidencia** (`evidencias/fase2/n1-wp1-addr-route-curl.png`, `evidencias/fase2/n1-nat-a-tcpdump.png`):

- Direccionamiento de wp1: `ens5 10.0.11.10/24`. La instancia no tiene ninguna IP pública configurada.
- Rutas de wp1:
  - `default via 10.0.11.1`: el siguiente salto es el router implícito de la VPC (primera IP utilizable de la subred). La decisión de enviar el tráfico al NAT la toma la tabla de rutas de AWS (`xyz-rt-private-a`: `0.0.0.0/0 → ENI de nat-a`), no la tabla de rutas de Linux.
  - `10.0.0.2 via 10.0.11.1`: el resolvedor DNS de la VPC (AmazonProvidedDNS, base de la VPC + 2).
  - `10.0.11.0/24`: la subred conectada directamente.
- IP pública que observa el destino: **3.128.168.127**, que es la IPv4 pública de xyz-nat-a, no una IP de wp1.
- Captura en nat-a (destino 52.5.79.118:80, que es checkip.amazonaws.com). Cada paquete aparece dos veces en la misma interfaz, antes y después del NAT:

| Fase | Paquete recibido de wp1 | Paquete reenviado por nat-a |
|---|---|---|
| SYN | `10.0.11.10.44862 > 52.5.79.118.80 [S]` | `10.0.1.30.44862 > 52.5.79.118.80 [S]` |
| SYN-ACK (respuesta) | `52.5.79.118.80 > 10.0.1.30.44862 [S.]` | `52.5.79.118.80 > 10.0.11.10.44862 [S.]` |
| ACK | `10.0.11.10.44862 > … [.]` | `10.0.1.30.44862 > … [.]` |
| HTTP GET | `10.0.11.10.44862 > … [P.] HTTP: GET / HTTP/1.1` | `10.0.1.30.44862 > … [P.] HTTP: GET / HTTP/1.1` |
| HTTP 200 | `52.5.79.118.80 > 10.0.1.30.44862 [P.] HTTP/1.1 200` | `52.5.79.118.80 > 10.0.11.10.44862 [P.] HTTP/1.1 200` |

**Interpretación.**
1. **NAT de Linux (masquerade, SNAT/PAT).** Al salir, nat-a reemplaza la IP de origen 10.0.11.10 por su propia IP privada, 10.0.1.30. Al volver la respuesta, conntrack deshace la traducción (DNAT inverso) y entrega a 10.0.11.10. El puerto de origen **44862 se conservó** porque no chocaba con ninguna otra asociación activa: masquerade solo cambia el puerto cuando la tupla resultante ya está en uso (eso se demuestra en N2).
2. **Internet Gateway.** En la captura el NAT aparece como 10.0.1.30, pero el destino vio 3.128.168.127. La segunda traducción, 1:1 y sin puertos, la hace el IGW de AWS fuera de la instancia, y por eso no se ve en el tcpdump. **Diferencia clave:** el NAT de Linux es N:1 con traducción de puertos y estado (conntrack), y lo configura el equipo. El IGW hace un mapeo 1:1 entre IP pública e IP privada de una ENI, y solo funciona para interfaces que tienen IP pública.
3. **Protocolos observados.** El *three-way handshake* TCP (SYN, SYN-ACK, ACK), seguido de la petición HTTP/1.1 `GET /` (85 bytes de carga) y la respuesta `200` (256 bytes). En el SYN de wp1 se anuncia `mss 8961`: la VPC usa *jumbo frames* (MTU 9001), y el servidor externo responde con `mss 1460` (MTU 1500 de Internet). TCP negocia el menor de los dos.

### N2 — Asociaciones de direcciones y puertos con conntrack

**Procedimiento.** Para provocar una traducción de puertos, dos clientes de la misma subred (wp1 y db, que salen ambos por nat-a) abren una conexión con **el mismo puerto de origen** hacia **el mismo destino**. Un tercer cliente (wp2) hace lo mismo desde la otra AZ.

```bash
# xyz-nat-a
sudo conntrack -F
# xyz-wp1, luego xyz-db (menos de 2 min de diferencia), y xyz-wp2
curl -s --local-port 40000 --resolve checkip.amazonaws.com:80:52.5.79.118 http://checkip.amazonaws.com
# xyz-nat-a y xyz-nat-b
sudo conntrack -L -p tcp --dport 80
```

**Evidencia** (`evidencias/fase2/n2-nat-a-conntrack.png`, `evidencias/fase2/n2-nat-b-conntrack.png`). Cada entrada tiene una tupla **original** (como salió el paquete del cliente, antes del NAT) y una tupla **de respuesta** (como vuelve desde Internet, después del NAT):

| NAT | Cliente | Tupla original (antes del NAT) | Tupla de respuesta (después del NAT) |
|---|---|---|---|
| nat-a | wp1 | `src=10.0.11.10 sport=40000 → dst=52.5.79.118 dport=80` | `src=52.5.79.118 sport=80 → dst=10.0.1.30 dport=40000` |
| nat-a | db | `src=10.0.11.20 sport=40000 → dst=52.5.79.118 dport=80` | `src=52.5.79.118 sport=80 → dst=10.0.1.30 dport=`**`42283`** |
| nat-b | wp2 | `src=10.0.12.10 sport=40000 → dst=52.5.79.118 dport=80` | `src=52.5.79.118 sport=80 → dst=10.0.2.30 dport=40000` |

**Interpretación.**
1. **Traducción de puertos (PAT).** Después del NAT, wp1 y db tendrían la misma tupla (`10.0.1.30:40000 → 52.5.79.118:80`), y el NAT no podría saber a quién entregar cada respuesta. Por eso masquerade conserva el puerto 40000 para la primera conexión (wp1) y le asigna a la segunda (db) el puerto libre **42283**. Al volver la respuesta a `10.0.1.30:42283`, conntrack la asocia con `10.0.11.20:40000` y deshace la traducción. Así muchas IPs privadas comparten una sola IP.
2. **Qué NAT atiende cada subred.** Las conexiones de `10.0.11.0/24` (wp1 y db) aparecen solo en **nat-a**, traducidas a 10.0.1.30. La de `10.0.12.0/24` (wp2) aparece solo en **nat-b**, traducida a 10.0.2.30. Coincide con las tablas `xyz-rt-private-a` y `xyz-rt-private-b`. Las IPs públicas que ve Internet son 3.128.168.127 (nat-a) y 3.17.143.42 (nat-b).
3. **Estado de las conexiones.** `TIME_WAIT` y `[ASSURED]` indican conexiones TCP ya cerradas, en las que se vio tráfico en ambos sentidos. El número junto al estado (101, 106, 108) son los segundos que quedan antes de borrar la entrada (`nf_conntrack_tcp_timeout_time_wait` = 120 s). Mientras la entrada exista, el puerto 40000 de nat-a sigue reservado para wp1. Por eso la conexión de db tuvo que hacerse dentro de esa ventana para que hubiera choque.
4. **Conexiones propias del NAT.** nat-b también muestra entradas `src=10.0.2.30 → dst=169.254.169.254:80`, sin traducción (la tupla de respuesta vuelve a la misma IP). Son consultas del agente SSM al *Instance Metadata Service* de la propia instancia. conntrack registra todas las conexiones de la máquina, no solo las que traduce.

### N3 — Deshabilitar IP forwarding en una instancia NAT

**Procedimiento.** En `xyz-wp2` se deja un ciclo que cada 2 s pide su IP pública (`curl -m 3`, con 3 s de timeout) y guarda el resultado en `/var/tmp/n3.log`. En `xyz-nat-b` se registra el contador `IpInAddrErrors`, se apaga el forwarding (`sysctl -w net.ipv4.ip_forward=0`) y se captura el tráfico de wp2. Después se restaura `ip_forward=1`.

```bash
# xyz-wp2
nohup bash -c 'for i in $(seq 1 30); do echo "$(date +%T) $(curl -s -m 3 http://checkip.amazonaws.com || echo FALLA)"; sleep 2; done' > /var/tmp/n3.log 2>&1 &
# xyz-nat-b
sudo nohup bash -c 'nstat -az IpInAddrErrors > /var/tmp/n3-natb.log; sysctl -w net.ipv4.ip_forward=0; timeout 15 tcpdump -ni ens5 "host 10.0.12.10 and tcp port 80" >> /var/tmp/n3-natb.log 2>&1; sysctl -w net.ipv4.ip_forward=1; nstat -az IpInAddrErrors >> /var/tmp/n3-natb.log' >/dev/null 2>&1 &
```

**Evidencia** (`evidencias/fase2/n3-wp2-log.png`, `evidencias/fase2/n3-natb-extracto.log`):

| Tramo | Hora | Lado de wp2 (`n3.log`) | Lado de nat-b (tcpdump) |
|---|---|---|---|
| Normal | hasta 21:06:11 | `3.17.143.42` (IP pública de nat-b) cada 2 s | — |
| Forwarding apagado | 21:06:13 a 21:07:24 | `FALLA` cada ~5 s (3 s de timeout + 2 s de espera) | Solo llegan **SYN** de `10.0.12.10`, retransmitidos con el mismo número de secuencia cada ~1 s. No hay SYN-ACK de vuelta |
| Restaurado | desde 21:07:29 | otra vez `3.17.143.42` | Intercambio completo: SYN, SYN-ACK, ACK, `GET /`, `200`, FIN |

Contador `IpInAddrErrors` en nat-b: **721** antes del corte y **1144** después de restaurar, es decir, **423 paquetes descartados** por no ir dirigidos a nat-b mientras el forwarding estuvo apagado. La cifra es mayor que la cantidad de SYN capturados porque el contador incluye todo el tráfico de wp2 hacia Internet (por ejemplo, el agente SSM por TCP 443), y la captura filtraba solo el puerto 80.

**Interpretación.**
1. **Por qué falla.** Los paquetes de wp2 siguen llegando a nat-b, porque la tabla de rutas de AWS los entrega a su ENI y el Source/Dest Check está apagado. Pero su IP de destino (por ejemplo, 44.195.197.190) no es una dirección de nat-b. Con `ip_forward=0`, Linux actúa como un host y no como un router: descarta todo paquete que no va dirigido a él, en vez de enrutarlo. El descarte ocurre en la decisión de ruteo, antes del hook `postrouting`, así que la regla `masquerade` nunca se evalúa. Por eso no aparece ningún paquete traducido a `10.0.2.30`, nada sale hacia Internet y nunca llega un SYN-ACK. El kernel cuenta estos descartes en `IpInAddrErrors`.
2. **Lo que ve el cliente.** TCP en wp2 retransmite el SYN con un RTO inicial de ~1 s (misma `seq`, distinto `TS val`) hasta que `curl` agota sus 3 s. Como `checkip.amazonaws.com` tiene varios registros A, curl prueba varias direcciones IP en paralelo, separadas unos 200 ms. Todas fallan igual.
3. **El DNS siguió funcionando.** wp2 seguía resolviendo `checkip.amazonaws.com` a direcciones distintas durante el corte. El resolvedor de la VPC (10.0.0.2) está dentro de la VPC y se alcanza por la ruta `local`, sin pasar por el NAT. Lo que se rompió fue solo la salida a Internet.
4. **El filtro de la captura.** El filtro `host 10.0.12.10` solo muestra el tráfico del lado privado. Después de restaurar, los paquetes traducidos (`10.0.2.30 ↔ Internet`) también existen, pero el filtro los excluye. En N1 se usó solo `tcp port 80` y por eso se veían los dos lados.
5. **Efecto colateral sobre la administración.** La sesión SSM de wp2 también se congeló durante el corte (ver problema P4). Toda la conectividad saliente de la subred privada, incluida la administrativa, depende del NAT de su AZ. Es un punto único de falla por AZ.
6. **Restauración.** Con `sysctl -w net.ipv4.ip_forward=1`, las conexiones nuevas vuelven a traducirse de inmediato. La configuración persistente (`/etc/sysctl.d/99-nat.conf`) nunca se modificó, así que un reinicio también habría restaurado el servicio.

### N4 — Conexión iniciada desde la subred privada vs. conexión entrante no solicitada

**Procedimiento.** Se intenta abrir una conexión TCP **desde Internet** (un PC externo) hacia la IP pública de nat-a, mientras se captura en nat-a todo el tráfico del puerto 80 que no sea de la VPC. El resultado se compara con la conexión **saliente** de N1.

```bash
# xyz-nat-a
sudo timeout 30 tcpdump -ni ens5 'tcp port 80 and not net 10.0.0.0/16'
# PC externo
curl -v -m 5 http://3.128.168.127/
```

**Evidencia** (`evidencias/fase2/n4-curl-externo-timeout.png`):
- PC externo: `Trying 3.128.168.127:80...` y luego `Connection timed out after 5001 milliseconds` (código 28). No hubo respuesta de ningún tipo, ni SYN-ACK ni RST.
- nat-a: la captura no registra ningún paquete del intento. *(Pendiente de adjuntar la salida.)*

**Comparación.**

| | Conexión saliente (N1) | Conexión entrante no solicitada (N4) |
|---|---|---|
| Quién la inicia | wp1 (10.0.11.10) | Un host de Internet |
| Security Group | `xyz-sg-nat` permite la entrada desde 10.0.11.0/24. La respuesta pasa porque los SG son *stateful* | `xyz-sg-nat` no tiene regla para 0.0.0.0/0. **El SYN se descarta en la infraestructura de AWS, antes de llegar a la instancia**, y por eso tcpdump no lo ve y el cliente no recibe ni un RST |
| Rutas | `xyz-rt-private-a` envía 0.0.0.0/0 a la ENI de nat-a | El IGW solo puede entregar a una ENI con IP pública. wp1 no tiene ninguna, así que **no hay forma de dirigirse a ella desde Internet** |
| NAT / conntrack | El SYN saliente crea la asociación `10.0.11.10:p ↔ 10.0.1.30:p'`, y las respuestas encajan en ella | No existe ninguna entrada de conntrack ni regla DNAT (*port forwarding*) que indique a qué host interno reenviar. Aunque el SG lo dejara pasar, el paquete iría dirigido a nat-a misma, sin ningún servicio escuchando en el puerto 80 |
| Filtro `forward` (nftables) | Acepta: conexión nueva desde 10.0.11.0/24 y luego `established` | `policy drop`: no se reenviaría una conexión nueva que no venga de la subred privada |
| Resultado | HTTP 200 | Timeout |

**Interpretación.** El NAT de origen (masquerade) es asimétrico por diseño: permite que la subred privada **inicie** conexiones y deja pasar solo las respuestas, gracias al estado guardado en conntrack. Para que algo de Internet llegue a un servidor privado haría falta un DNAT explícito o, como en esta arquitectura, un intermediario que inicie la conexión: el balanceador HAProxy de la Fase 6. La protección es en capas: (1) el Security Group filtra en el borde de la ENI; (2) la ausencia de IP pública y de rutas hace que los privados no sean direccionables; (3) conntrack/NAT no tiene asociación para tráfico no solicitado; (4) la cadena `forward` con política `drop` bloquea cualquier reenvío no autorizado.

## 4. Análisis de protocolos y capturas de tráfico
_(Por documentar: IP, ICMP, TCP, DNS, HTTP, traducción NAT.)_

## 5. Problemas encontrados y recomendaciones

| # | Problema | Causa | Solución / lección |
|---|---|---|---|
| P1 | La cuenta no permitía crear recursos en us-east-1 | La cuenta se creó con la nueva experiencia de AWS (proyectos en settings.aws.com), que fija la región según el país de contacto (Colombia → us-east-2) mediante SCP gestionadas | Se rediseñó en us-east-2 (Ohio) |
| P2 | La cuota de vCPU On-Demand Standard (16) no alcanzaba para 9 × t3.micro (18) | Límite por defecto en una cuenta nueva | Se pidió aumento a 20 en Service Quotas; AWS lo aprobó el mismo día |
| P3 | En N3 y N4, los comandos de `sysctl`/`tcpdump` no surtían efecto | Las sesiones de SSM Session Manager entran como `ssm-user`, no como root | Anteponer `sudo` a los comandos administrativos |
| P4 | Durante N3, wp2 perdió Internet y la sesión SSM de forma indefinida | Se apagó `ip_forward` en nat-b y la sesión se cortó antes de ejecutar el comando que lo restauraba. La sesión SSM de wp2 también viaja por nat-b, así que se congeló | Se restauró `ip_forward=1` desde nat-b, cuya sesión SSM sale directo por el IGW y no depende del forwarding. Lección: las pruebas que cortan conectividad deben ejecutarse desacopladas de la sesión (`nohup`), restaurar el servicio solas y escribir sus resultados en disco (`/var/tmp`, que sobrevive a reinicios) |
| P5 | En N3, `timeout 15 tcpdump` no se detuvo a los 15 s dentro del bloque `sudo nohup bash -c … &`, así que el `sysctl -w net.ipv4.ip_forward=1` automático nunca se ejecutó y el corte duró unos 75 s | No se determinó la causa exacta (tcpdump ejecutado en segundo plano a través de sudo/nohup/timeout) | Se restauró el forwarding a mano y se detuvo tcpdump. Lección: en pruebas destructivas, restaurar con un mecanismo independiente de la captura (por ejemplo, `sleep 15; sysctl -w …=1` en un proceso aparte, o `tcpdump -G 15 -W 1`) y comprobar siempre el estado final |

## 6. Referencias
_(Formato IEEE; se agregan a medida que se usan.)_
