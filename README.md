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
_(Por documentar.)_

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
| N1 | HTTP desde instancia privada a destino externo; IP pública observada | Pendiente |
| N2 | conntrack: asociaciones de direcciones/puertos antes y después del NAT | Pendiente |
| N3 | Deshabilitar IP forwarding y explicar la falla | Pendiente |
| N4 | Conexión saliente vs. entrante no solicitada | Pendiente |
| D1 | dig SOA/NS/A/CNAME a ambos autoritativos; delegación pública | Pendiente |
| D2 | Cambio en primario + serial SOA → transferencia al secundario | Pendiente |
| D3 | Primario caído; secundario responde autoritativamente | Pendiente |
| D4 | Consultas repetidas a `www`: orden de A, TTL/caché | Pendiente |
| D5 | Balanceador caído sigue anunciado por DNS | Pendiente |
| B1 | Peticiones sucesivas a cada LB muestran ambas IPs privadas | Pendiente |
| B2 | WordPress caído; ambos LB siguen atendiendo | Pendiente |

## 4. Análisis de protocolos y capturas de tráfico
_(Por documentar: IP, ICMP, TCP, DNS, HTTP, traducción NAT.)_

## 5. Problemas encontrados y recomendaciones
_(Se registran a medida que aparecen.)_

## 6. Referencias
_(Formato IEEE; se agregan a medida que se usan.)_
