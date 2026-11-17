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
 VPC 10.0.0.0/16 (us-east-1)           │
┌──────────── AZ us-east-1a ──────────────┐   ┌──────────── AZ us-east-1b ──────────────┐
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
| xyz-public-a | 10.0.1.0/24 | us-east-1a | Pública | 0.0.0.0/0 → IGW |
| xyz-private-a | 10.0.11.0/24 | us-east-1a | Privada | 0.0.0.0/0 → ENI de xyz-nat-a |
| xyz-public-b | 10.0.2.0/24 | us-east-1b | Pública | 0.0.0.0/0 → IGW |
| xyz-private-b | 10.0.12.0/24 | us-east-1b | Privada | 0.0.0.0/0 → ENI de xyz-nat-b |

Todas las tablas incluyen la ruta implícita `10.0.0.0/16 → local`.

### 1.4 Inventario de instancias EC2 (9)

| Nombre | Rol | Subred | IP privada | IP pública | Instance ID |
|---|---|---|---|---|---|
| xyz-ns1 | DNS BIND9 primario | public-a | 10.0.1.10 | EIP | |
| xyz-lb1 | Balanceador HAProxy | public-a | 10.0.1.20 | EIP | |
| xyz-nat-a | NAT (nftables) | public-a | 10.0.1.30 | Automática | |
| xyz-ns2 | DNS BIND9 secundario | public-b | 10.0.2.10 | EIP | |
| xyz-lb2 | Balanceador HAProxy | public-b | 10.0.2.20 | EIP | |
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
| Región us-east-1, dos AZ | Menor costo; una AZ caída deja operativa la otra mitad (NAT, LB, DNS, WP). |
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
_(Por documentar.)_

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
