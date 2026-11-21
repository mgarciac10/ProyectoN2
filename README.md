# Proyecto N2 — Despliegue de Aplicaciones y Servicios en Red

**Despliegue en AWS del sitio web de XYZ S.A. sobre una infraestructura de red propia**

| | |
|---|---|
| Curso | SI3002 — Telemática |
| Integrantes | Mateo García Carreño · Victor Infante |
| Docente | juan Carlos Montoya |
| Institución | Universidad EAFIT |
| Fecha | 20 de noviembre de 2026 |
| Dominio | `xyzcosmetics.online` |
| Repositorio | https://github.com/mgarciac10/ProyectoN2 |

---

## Tabla de contenido

- [Introducción](#introducción)
- [1. Arquitectura](#1-arquitectura)
  - [1.1 Diagrama general](#11-diagrama-general)
  - [1.2 Flujo de una petición](#12-flujo-de-una-petición)
  - [1.3 Plan de direccionamiento](#13-plan-de-direccionamiento)
  - [1.4 Inventario de instancias EC2 (9)](#14-inventario-de-instancias-ec2-9)
  - [1.5 Grupos de seguridad (diseño)](#15-grupos-de-seguridad-diseño)
  - [1.6 Decisiones de diseño y justificación](#16-decisiones-de-diseño-y-justificación)
  - [1.7 Punto único de falla y estado compartido](#17-punto-único-de-falla-y-estado-compartido)
  - [1.8 Estimación de costos](#18-estimación-de-costos)
- [2. Implementación por fases](#2-implementación-por-fases)
  - [Fase 0 — Preparación](#fase-0--preparación)
  - [Fase 1 — Red base](#fase-1--red-base)
  - [Fase 2 — NAT](#fase-2--nat)
  - [Fase 3 — DNS BIND9](#fase-3--dns-bind9)
  - [Fase 4 — Base de datos y NFS](#fase-4--base-de-datos-y-nfs)
  - [Fase 5 — WordPress](#fase-5--wordpress)
  - [Fase 6 — Balanceadores HAProxy](#fase-6--balanceadores-haproxy)
- [3. Pruebas experimentales](#3-pruebas-experimentales)
  - [Verificación previa: registro en SSM a través del NAT](#verificación-previa-registro-en-ssm-a-través-del-nat)
  - [N1 — Solicitud HTTP desde una instancia privada](#n1--solicitud-http-desde-una-instancia-privada)
  - [N2 — Asociaciones de direcciones y puertos con conntrack](#n2--asociaciones-de-direcciones-y-puertos-con-conntrack)
  - [N3 — Deshabilitar IP forwarding en una instancia NAT](#n3--deshabilitar-ip-forwarding-en-una-instancia-nat)
  - [N4 — Conexión iniciada desde la subred privada vs. conexión entrante no solicitada](#n4--conexión-iniciada-desde-la-subred-privada-vs-conexión-entrante-no-solicitada)
  - [D1 — Consultas autoritativas (SOA, NS, A, CNAME) y delegación pública](#d1--consultas-autoritativas-soa-ns-a-cname-y-delegación-pública)
  - [D2 — Actualización de zona en primario y transferencia al secundario](#d2--actualización-de-zona-en-primario-y-transferencia-al-secundario)
  - [D3 — Caída del servidor DNS primario y continuidad del secundario](#d3--caída-del-servidor-dns-primario-y-continuidad-del-secundario)
  - [D4 — Consultas repetidas a www: orden de registros A, TTL y caché](#d4--consultas-repetidas-a-www-orden-de-registros-a-ttl-y-caché)
  - [D5 — Balanceador caído sigue anunciado por DNS](#d5--balanceador-caído-sigue-anunciado-por-dns)
  - [B1 — Distribución de solicitudes entre las dos instancias WordPress](#b1--distribución-de-solicitudes-entre-las-dos-instancias-wordpress)
  - [B2 — Una instancia WordPress deja de estar disponible](#b2--una-instancia-wordpress-deja-de-estar-disponible)
- [4. Análisis de protocolos y capturas de tráfico](#4-análisis-de-protocolos-y-capturas-de-tráfico)
  - [4.1 Resolución DNS (UDP/53) y consulta interna a AmazonProvidedDNS](#41-resolución-dns-udp53-y-consulta-interna-a-amazonprovideddns)
  - [4.2 Handshake TCP, petición HTTP y cierre de conexión (Cliente ↔ Balanceador ↔ Backend)](#42-handshake-tcp-petición-http-y-cierre-de-conexión-cliente--balanceador--backend)
  - [4.3 Trazabilidad de IP real del cliente (X-Forwarded-For)](#43-trazabilidad-de-ip-real-del-cliente-x-forwarded-for)
  - [4.4 Conectividad ICMP y aislamiento por Security Groups](#44-conectividad-icmp-y-aislamiento-por-security-groups)
  - [4.5 Traducción de direcciones (NAT / PAT)](#45-traducción-de-direcciones-nat--pat)
- [5. Problemas encontrados y recomendaciones](#5-problemas-encontrados-y-recomendaciones)
- [6. Conclusiones](#6-conclusiones)
- [7. Referencias](#7-referencias)
- [Lista de tablas](#lista-de-tablas)
- [Lista de figuras](#lista-de-figuras)

## Lista de tablas

- Tabla 1. 1.3 Plan de direccionamiento
- Tabla 2. 1.4 Inventario de instancias EC2 (9)
- Tabla 3. 1.5 Grupos de seguridad (diseño)
- Tabla 4. 1.6 Decisiones de diseño y justificación
- Tabla 5. 1.7 Punto único de falla y estado compartido
- Tabla 6. 1.8 Estimación de costos
- Tabla 7. Fase 1 — Red base — Tablas de rutas
- Tabla 8. Fase 1 — Red base — Security Groups
- Tabla 9. Fase 1 — Red base — Elastic IPs
- Tabla 10. Fase 3 — DNS BIND9 — Opciones globales
- Tabla 11. Fase 3 — DNS BIND9 — Primario/secundario y transferencia de zona
- Tabla 12. Fase 3 — DNS BIND9 — Verificación
- Tabla 13. Fase 4 — Base de datos y NFS
- Tabla 14. Fase 4 — Base de datos y NFS — Tres capas de control de acceso a la DB
- Tabla 15. Fase 4 — Base de datos y NFS — Verificación
- Tabla 16. Fase 5 — WordPress — Estado compartido
- Tabla 17. Fase 5 — WordPress — Apache
- Tabla 18. Fase 5 — WordPress — Verificación
- Tabla 19. Fase 6 — Balanceadores HAProxy — Configuración
- Tabla 20. 3. Pruebas experimentales
- Tabla 21. N1 — Solicitud HTTP desde una instancia privada
- Tabla 22. N2 — Asociaciones de direcciones y puertos con conntrack — Evidencia
- Tabla 23. N3 — Deshabilitar IP forwarding en una instancia NAT — Evidencia
- Tabla 24. N4 — Conexión iniciada desde la subred privada vs. conexión entrante no solicitada — Comparación
- Tabla 25. 5. Problemas encontrados y recomendaciones

## Lista de figuras

Las figuras son las capturas de la carpeta `evidencias/`, numeradas en el orden en que se citan por primera vez.

- Figura 1. Fase 1 — Red base — `evidencias/fase1/resource-map-vpc.png`
- Figura 2. Fase 1 — Red base — `evidencias/fase1/security-groups.png`
- Figura 3. Fase 1 — Red base — `evidencias/fase1/elastic-ips.png`
- Figura 4. Fase 2 — NAT — `evidencias/fase2/nat-a-nft-ruleset.png`
- Figura 5. Fase 2 — NAT — `evidencias/fase2/nat-a-ip-forward.png`
- Figura 6. Fase 2 — NAT — `evidencias/fase2/nat-b-nft-ruleset.png`
- Figura 7. Fase 2 — NAT — `evidencias/fase2/nat-b-ip-forward.png`
- Figura 8. Fase 2 — NAT — `evidencias/fase2/rt-private-a-routes.png`
- Figura 9. Fase 3 — DNS BIND9 — `evidencias/fase3/godaddy-hostnames-glue.png`
- Figura 10. Fase 3 — DNS BIND9 — `evidencias/fase3/godaddy-nameservers.png`
- Figura 11. Fase 3 — DNS BIND9 — `evidencias/fase3/tld-delegacion-dig.png`
- Figura 12. Fase 3 — DNS BIND9 — `evidencias/fase3/ns1-soa.png`
- Figura 13. Fase 3 — DNS BIND9 — `evidencias/fase3/ns1-ns.png`
- Figura 14. Fase 3 — DNS BIND9 — `evidencias/fase3/ns1-www.png`
- Figura 15. Fase 3 — DNS BIND9 — `evidencias/fase3/ns1-tienda-cname.png`
- Figura 16. Fase 3 — DNS BIND9 — `evidencias/fase3/ns2-soa.png`
- Figura 17. Fase 3 — DNS BIND9 — `evidencias/fase3/ns2-www.png`
- Figura 18. Fase 3 — DNS BIND9 — `evidencias/fase3/axfr-denegado-y-sin-recursion.png`
- Figura 19. Fase 4 — Base de datos y NFS — `evidencias/fase4/db-setup-resumen.png`
- Figura 20. Fase 4 — Base de datos y NFS — `evidencias/fase4/wp1-conexion-db.png`
- Figura 21. Fase 4 — Base de datos y NFS — `evidencias/fase4/wp2-conexion-db.png`
- Figura 22. Fase 4 — Base de datos y NFS — `evidencias/fase4/nfs-compartido-wp2.png`
- Figura 23. Fase 4 — Base de datos y NFS — `evidencias/fase4/ns1-db-timeout.png`
- Figura 24. Fase 5 — WordPress — `evidencias/fase5/wp1-setup-resumen.png`
- Figura 25. Fase 5 — WordPress — `evidencias/fase5/wp2-setup-resumen.png`
- Figura 26. Fase 5 — WordPress — `evidencias/fase5/wp1-media-import.png`
- Figura 27. Fase 5 — WordPress — `evidencias/fase5/wp2-media-compartida.png`
- Figura 28. Fase 5 — WordPress — `evidencias/fase5/wp1-setup-resumen-v1.png`
- Figura 29. Fase 5 — WordPress — `evidencias/fase5/wp2-setup-resumen-v1.png`
- Figura 30. Fase 6 — Balanceadores HAProxy — `evidencias/fase6/lb1-setup-resumen.png`
- Figura 31. Fase 6 — Balanceadores HAProxy — `evidencias/fase6/lb2-setup-resumen.png`
- Figura 32. Fase 6 — Balanceadores HAProxy — `evidencias/fase6/ec2-9-instancias.png`
- Figura 33. Fase 6 — Balanceadores HAProxy — `evidencias/fase6/ssm-9-nodos-online.png`
- Figura 34. Verificación previa: registro en SSM a través del NAT — `evidencias/fase2/ssm-managed-nodes.png`
- Figura 35. N1 — Solicitud HTTP desde una instancia privada — `evidencias/fase2/n1-wp1-addr-route-curl.png`
- Figura 36. N1 — Solicitud HTTP desde una instancia privada — `evidencias/fase2/n1-nat-a-tcpdump.png`
- Figura 37. N2 — Asociaciones de direcciones y puertos con conntrack — `evidencias/fase2/n2-nat-a-conntrack.png`
- Figura 38. N2 — Asociaciones de direcciones y puertos con conntrack — `evidencias/fase2/n2-nat-b-conntrack.png`
- Figura 39. N3 — Deshabilitar IP forwarding en una instancia NAT — `evidencias/fase2/n3-wp2-log.png`
- Figura 40. N4 — Conexión iniciada desde la subred privada vs. conexión entrante no solicitada — `evidencias/fase2/n4-curl-externo-timeout.png`
- Figura 41. N4 — Conexión iniciada desde la subred privada vs. conexión entrante no solicitada — `evidencias/fase2/n4-tcpdump-nat-a.png`
- Figura 42. D1 — Consultas autoritativas (SOA, NS, A, CNAME) y delegación pública — `evidencias/fase7/dig.png`
- Figura 43. D1 — Consultas autoritativas (SOA, NS, A, CNAME) y delegación pública — `evidencias/fase7/dig-trace.png`
- Figura 44. D1 — Consultas autoritativas (SOA, NS, A, CNAME) y delegación pública — `evidencias/fase3/dig-trace-www.png`
- Figura 45. D2 — Actualización de zona en primario y transferencia al secundario — `evidencias/fase7/d2-antes.png`
- Figura 46. D2 — Actualización de zona en primario y transferencia al secundario — `evidencias/fase7/d2-ns1-serial.png`
- Figura 47. D2 — Actualización de zona en primario y transferencia al secundario — `evidencias/fase7/d2-prueba-serial.png`
- Figura 48. D2 — Actualización de zona en primario y transferencia al secundario — `evidencias/fase7/d2-journal-ns1.png`
- Figura 49. D2 — Actualización de zona en primario y transferencia al secundario — `evidencias/fase7/d2-journal-ns2.png`
- Figura 50. D3 — Caída del servidor DNS primario y continuidad del secundario — `evidencias/fase7/d3-ns1-stoped.png`
- Figura 51. D3 — Caída del servidor DNS primario y continuidad del secundario — `evidencias/fase7/d3-dig-ns1-timeout.png`
- Figura 52. D3 — Caída del servidor DNS primario y continuidad del secundario — `evidencias/fase7/d3-restablished.png`
- Figura 53. D4 — Consultas repetidas a www: orden de registros A, TTL y caché — `evidencias/fase7/d4recursive-autoritary-ttl.png`
- Figura 54. D4 — Consultas repetidas a www: orden de registros A, TTL y caché — `evidencias/fase7/DNStest.png`
- Figura 55. D5 — Balanceador caído sigue anunciado por DNS — `evidencias/fase7/d5-lb1-failed.png`
- Figura 56. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b1-curl-lb1-lb2.png`
- Figura 57. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b1-curl-www-dns.png`
- Figura 58. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b1-navegador-lb1.png`
- Figura 59. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b1-navegador-lb2.png`
- Figura 60. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b1-stats-lb1.png`
- Figura 61. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b1-stats-lb2.png`
- Figura 62. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b2-stats-wp1-down-lb1.png`
- Figura 63. B1 — Distribución de solicitudes entre las dos instancias WordPress — `evidencias/fase6/b2-stats-wp1-down-lb2.png`
- Figura 64. B2 — Una instancia WordPress deja de estar disponible — `evidencias/fase6/b2-curl-con-wp1-caido.png`
- Figura 65. B2 — Una instancia WordPress deja de estar disponible — `evidencias/fase6/b2-journal-down-up-stats-restaurado.png`
- Figura 66. 4.2 Handshake TCP, petición HTTP y cierre de conexión (Cliente ↔ Balanceador ↔ Backend) — `evidencias/fase7/d6-tcp-handshake.png`
- Figura 67. 4.2 Handshake TCP, petición HTTP y cierre de conexión (Cliente ↔ Balanceador ↔ Backend) — `evidencias/fase7/handshake-tcp.webp`
- Figura 68. 4.2 Handshake TCP, petición HTTP y cierre de conexión (Cliente ↔ Balanceador ↔ Backend) — `evidencias/fase7/tcp-wp1.png`
- Figura 69. 4.3 Trazabilidad de IP real del cliente (X-Forwarded-For) — `evidencias/fase7/Forwarded-for_wp1.png`
- Figura 70. 4.4 Conectividad ICMP y aislamiento por Security Groups — `evidencias/fase7/icmp-tcp-lb1.png`

---

## Introducción

XYZ S.A. es una empresa colombiana ficticia de cosméticos, con sedes en Medellín, Bogotá y Bucaramanga, que necesita publicar su sitio web corporativo con alta disponibilidad. Este proyecto despliega ese sitio en **WordPress** [1] sobre **Amazon Web Services** [2], pero sin usar los servicios gestionados que resuelven la red por el usuario (NAT Gateway, Elastic Load Balancing, Route 53). En su lugar, cada función de red se construye y configura sobre instancias EC2 con Ubuntu Server: una VPC con dos zonas de disponibilidad, **NAT propio** con `nftables`, **balanceadores HAProxy** [3] autogestionados y **DNS autoritativo BIND9** [4] primario/secundario con delegación pública de un dominio real.

El objetivo es entender en la práctica cómo interactúan los protocolos de la pila TCP/IP en una arquitectura de varias capas: direccionamiento IP privado y público, traducción de direcciones, resolución de nombres, establecimiento de conexiones TCP, peticiones HTTP y estado compartido entre servidores. Para ello, además de desplegar el servicio, se ejecutan pruebas controladas de falla y recuperación (N1–N4, D1–D5, B1–B2) y se capturan y analizan paquetes en cada capa.

El documento está organizado así: la sección 1 presenta la arquitectura y las decisiones de diseño; la sección 2, la implementación por fases; la sección 3, las pruebas experimentales; la sección 4, el análisis de protocolos con capturas de tráfico; la sección 5, los problemas encontrados y las recomendaciones; la sección 6, las conclusiones, y la sección 7, las referencias.

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
1. El cliente resuelve `www.<dominio>`: su resolvedor recursivo sigue la delegación del TLD hacia `ns1`/`ns2` (BIND9), que responden con **dos registros A** (EIP de lb1 y lb2) → **DNS Round Robin** [5], [6].
2. El cliente abre TCP:80 contra uno de los balanceadores. El IGW traduce la EIP a la IP privada del LB.
3. HAProxy elige un backend (`roundrobin`) entre wp1 y wp2, verificando su salud con health checks.
4. WordPress consulta MariaDB en `xyz-db` y lee archivos subidos desde el montaje NFS.
5. La respuesta muestra la **IP privada** del nodo WordPress que atendió la petición.

### 1.3 Plan de direccionamiento

*Tabla 1. 1.3 Plan de direccionamiento.*

| Subred | CIDR | AZ | Tipo | Ruta por defecto |
|---|---|---|---|---|
| xyz-public-a | 10.0.1.0/24 | us-east-2a | Pública | 0.0.0.0/0 → IGW |
| xyz-private-a | 10.0.11.0/24 | us-east-2a | Privada | 0.0.0.0/0 → ENI de xyz-nat-a |
| xyz-public-b | 10.0.2.0/24 | us-east-2b | Pública | 0.0.0.0/0 → IGW |
| xyz-private-b | 10.0.12.0/24 | us-east-2b | Privada | 0.0.0.0/0 → ENI de xyz-nat-b |

Todas las tablas incluyen la ruta implícita `10.0.0.0/16 → local`. El bloque 10.0.0.0/16 pertenece al espacio de direcciones privadas definido en el RFC 1918 [7].

### 1.4 Inventario de instancias EC2 (9)

*Tabla 2. 1.4 Inventario de instancias EC2 (9).*

| Nombre | Rol | Subred | IP privada | IP pública | Instance ID |
|---|---|---|---|---|---|
| xyz-ns1 | DNS BIND9 primario | public-a | 10.0.1.10 | 3.134.251.219 (EIP) | `i-016e94435b5dc5f0f` |
| xyz-lb1 | Balanceador HAProxy | public-a | 10.0.1.20 | 18.190.31.183 (EIP) | `i-0cf9c37d19eeb7b64` |
| xyz-nat-a | NAT (nftables) | public-a | 10.0.1.30 | 3.128.168.127 (automática) | `i-0e9ad2248a4fa9fc1` |
| xyz-ns2 | DNS BIND9 secundario | public-b | 10.0.2.10 | 3.131.134.77 (EIP) | `i-0ff8c50a0b9d12536` |
| xyz-lb2 | Balanceador HAProxy | public-b | 10.0.2.20 | 13.58.14.10 (EIP) | `i-0c61ff216ed4a27fb` |
| xyz-nat-b | NAT (nftables) | public-b | 10.0.2.30 | 3.17.143.42 (automática) | `i-01f8ddaa75f967797` |
| xyz-wp1 | WordPress | private-a | 10.0.11.10 | — | `i-052cd6e9a86b0cf57` |
| xyz-db | MariaDB + NFS | private-a | 10.0.11.20 | — | `i-02be960ca2dc2e1bb` |
| xyz-wp2 | WordPress | private-b | 10.0.12.10 | — | `i-061324fe87f5417c6` |

Todas: Ubuntu Server 26.04 LTS (AMI Quick Start de Canonical; el enunciado exige 24.04 o superior), `t3.micro`, 8 GiB gp3, rol IAM `xyz-ec2-ssm-role`.

### 1.5 Grupos de seguridad (diseño)

*Tabla 3. 1.5 Grupos de seguridad (diseño).*

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

*Tabla 4. 1.6 Decisiones de diseño y justificación.*

| Decisión | Justificación |
|---|---|
| Región us-east-2, dos AZ | Región fija del proyecto AWS (nueva experiencia, asignada por país); una AZ caída deja operativa la otra mitad (NAT, LB, DNS, WP). |
| t3.micro | Elegible en el plan gratuito; suficiente para carga académica. |
| Ubuntu Server 26.04 LTS | Es la AMI de Ubuntu que ofrece por defecto el *Quick Start* de EC2. Cumple el requisito "24.04 o superior", es LTS (soporte estándar hasta 2031) y trae versiones recientes (p. ej. PHP 8.5; nftables como firewall por defecto). Las 9 instancias usan la misma AMI [8]. |
| NAT propio por AZ | Requisito; además evita tráfico entre AZ y que una AZ dependa de la otra para salir a Internet. |
| HAProxy | Health checks activos y página de estadísticas para evidenciar el balanceo. |
| Sin afinidad de sesión | Requisito B1: cada petición debe poder ir a cualquier nodo. |
| NFS en la instancia DB | Comparte `wp-content/uploads` sin instancia adicional (límite de 9). La DB ya es SPOF; concentrar ahí el estado lo hace explícito. |
| Salts idénticos en ambos WP | Las sesiones de WordPress se validan con cookies firmadas; con los mismos salts y la misma DB, cualquier nodo acepta la sesión. |
| EIP solo en ns1/ns2/lb1/lb2 | Necesitan IP fija (glue records y registros A). La cuota por defecto es 5 EIP. |
| SSM en lugar de SSH | Requisito; no se exponen puertos de administración [9]. Las privadas alcanzan los endpoints de SSM a través de su NAT. |

### 1.7 Punto único de falla y estado compartido

Para que dos nodos WordPress sirvan el mismo sitio, todo su **estado** debe estar fuera de ellos o ser idéntico en ambos:

*Tabla 5. 1.7 Punto único de falla y estado compartido.*

| Estado | Dónde vive | Cómo se comparte |
|---|---|---|
| Contenido (páginas, entradas, usuarios, opciones, sesiones de login) | MariaDB en `xyz-db` | Ambos nodos usan la misma base `wordpress` |
| Archivos subidos (`wp-content/uploads`) | `/srv/nfs/wp-uploads` en `xyz-db` | Montaje NFSv4 en ambos nodos |
| Claves y salts (`AUTH_KEY`, …) | `wp-config.php` de cada nodo | Valores **idénticos** en ambos, para que la cookie emitida por un nodo sea válida en el otro |
| Código de WordPress, temas y plugins | Disco local de cada nodo | Misma versión instalada por el mismo script |

**Punto único de falla:** `xyz-db` concentra la base de datos y los archivos. Si falla, ambos WordPress dejan de servir contenido dinámico, aunque el DNS, los balanceadores y los nodos web sigan en pie. Además, la DB está en la AZ `us-east-2a`: una falla de esa zona afecta al sitio completo, aunque wp2 y lb2 estén en `us-east-2b`. La redundancia del diseño cubre la capa de presentación (DNS, LB, web), no la de datos. Mitigaciones fuera de alcance: replicación MariaDB primario/réplica (o Galera) en la otra AZ, Amazon RDS Multi-AZ, Amazon EFS o S3 para los medios, y copias de seguridad programadas (`mariadb-dump` + snapshots EBS).

### 1.8 Estimación de costos

*Tabla 6. 1.8 Estimación de costos.*

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

- **Cuenta y seguridad:** proyecto creado en `settings.aws.com` con región fijada en `us-east-2` (Ohio) mediante SCP gestionada de AWS (ver problema P1) y autenticación MFA habilitada en el AWS Builder ID.
- **Control de costos:** presupuesto mensual de 30 USD configurado en AWS Budgets con alertas por correo electrónico.
- **Cuotas de servicio:** verificación de Elastic IPs (cuota por defecto: 5, suficientes para las 4 EIP del diseño) y solicitud de aumento de cuota de vCPU *On-Demand Standard* de 16 a **20 vCPU** (caso `179488388000677`, aprobado el 2026-11-16), permitiendo desplegar las 9 instancias `t3.micro` (18 vCPU en total).
- **Dominio y repositorio:** dominio `xyzcosmetics.online` adquirido en GoDaddy (con soporte para *glue records*) y repositorio Git en `https://github.com/mgarciac10/ProyectoN2` (rama `main`, excluyendo credenciales y claves mediante `.gitignore`).

### Fase 1 — Red base

**VPC.** `xyz-vpc`, `10.0.0.0/16`, creada con la opción *VPC only* para controlar cada recurso a mano y evitar que el asistente cree un NAT Gateway, que el enunciado prohíbe. Tiene activados *DNS resolution* y *DNS hostnames*.

**Subredes.** Se crearon las cuatro de la tabla 1.3. En `xyz-public-a` y `xyz-public-b` se activó *auto-assign public IPv4*, de modo que las instancias NAT reciben IP pública sin consumir Elastic IP. Las privadas no asignan IP pública. En cada /24, AWS reserva 5 direcciones (`.0` red, `.1` router de la VPC, `.2` DNS de AWS, `.3` reservada y `.255` broadcast), así que quedan 251 utilizables.

**Direccionamiento privado e Internet Gateway.** Todas las subredes usan direcciones privadas RFC 1918. Lo que hace pública a una subred no es su rango, sino que su tabla de rutas envía `0.0.0.0/0` al IGW y que sus instancias tienen una IP pública asociada. Esa IP pública no está configurada en la instancia: el IGW traduce 1:1 entre IP pública e IP privada.

**Internet Gateway.** `xyz-igw`, adjunto a `xyz-vpc`.

**Tablas de rutas.**

*Tabla 7. Fase 1 — Red base — Tablas de rutas.*

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

*Tabla 8. Fase 1 — Red base — Security Groups.*

| SG | ID | Entrada |
|---|---|---|
| xyz-sg-lb | sg-0c9f84365bae19198 | TCP 80 desde 0.0.0.0/0 · TCP 8404 desde la IP del equipo · ICMP desde 0.0.0.0/0 |
| xyz-sg-dns | sg-0bc2fea80ceaee124 | UDP/TCP 53 desde 0.0.0.0/0 · ICMP desde 0.0.0.0/0 |
| xyz-sg-nat | sg-07f939b9f763c23c9 | Todo el tráfico desde 10.0.11.0/24 y 10.0.12.0/24 |
| xyz-sg-wp | sg-0260dc2f52e738c66 | TCP 80 desde xyz-sg-lb · ICMP desde 10.0.0.0/16 |
| xyz-sg-db | sg-00410bb2e8ec6b83c | TCP 3306 y TCP 2049 desde xyz-sg-wp · ICMP desde 10.0.0.0/16 |

Los SG son *stateful* [2]: el tráfico de respuesta de una conexión permitida pasa sin regla adicional. En wp y db el origen es otro SG (mínimo privilegio independiente de las IPs). El SG del NAT debe aceptar el tráfico de las subredes privadas porque los paquetes reenviados atraviesan su ENI. Ningún SG abre SSH.

Evidencia: `evidencias/fase1/security-groups.png`.

**Rol IAM.** `xyz-ec2-ssm-role` (entidad de confianza: EC2; política `AmazonSSMManagedInstanceCore`). Permite que el agente SSM se registre sin credenciales almacenadas en las instancias.

**Elastic IPs** (se reservan antes de lanzar las instancias para conocer de antemano las IPs que van en los glue records y en los registros A):

*Tabla 9. Fase 1 — Red base — Elastic IPs.*

| Nombre | IPv4 pública | Allocation ID | Uso |
|---|---|---|---|
| xyz-eip-ns1 | 3.134.251.219 | eipalloc-04f4afdd13aefb7b8 | ns1 (glue record) |
| xyz-eip-ns2 | 3.131.134.77 | eipalloc-0683a0cd8afb72253 | ns2 (glue record) |
| xyz-eip-lb1 | 18.190.31.183 | eipalloc-0cce7e1847bcdb5ae | lb1 (registro A de www) |
| xyz-eip-lb2 | 13.58.14.10 | eipalloc-075b3a1be9327354a | lb2 (registro A de www) |

Evidencia: `evidencias/fase1/elastic-ips.png`.

**Presupuesto.** Se creó en AWS Budgets un presupuesto mensual de 30 USD con alertas por correo.

### Fase 2 — NAT

**Instancias.** Se lanzaron `xyz-nat-a` (public-a, 10.0.1.30) y `xyz-nat-b` (public-b, 10.0.2.30): Ubuntu 26.04 LTS, t3.micro, sin key pair (acceso por SSM), SG `xyz-sg-nat`, IP pública automática y rol `xyz-ec2-ssm-role`.

**Source/Destination Check deshabilitado.** Por defecto, AWS descarta los paquetes cuyo destino (al entrar) o cuyo origen (al salir) no es la IP de la instancia. Un NAT reenvía tráfico ajeno, como paquetes de 10.0.11.10 hacia Internet, así que esa verificación tiene que estar apagada.

**Configuración en Linux** (procedimiento en `scripts/nat/setup-nat.sh`):

1. `net.ipv4.ip_forward = 1`, persistente en `/etc/sysctl.d/99-nat.conf`, para que el kernel enrute paquetes IP [10] que no van dirigidos a él.
2. `nftables` [11] con dos tablas:

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

- **`masquerade`** es un SNAT dinámico (NAPT) [12]: reemplaza la IP de origen privada por la IP de la interfaz del NAT y, si hace falta, el puerto de origen (PAT). Así varias instancias comparten una sola dirección. La tabla de conntrack guarda cada asociación para deshacer la traducción en las respuestas.
- **Cadena `forward` con política `drop`:** solo se reenvían conexiones nuevas que vienen de la subred privada de la misma AZ, más las respuestas (`established,related`). Una conexión entrante no solicitada no tiene entrada en conntrack, así que se descarta.
- Las instancias tienen una sola interfaz (`ens5`), así que el tráfico entra y sale por ella.

**Rutas privadas.** `xyz-rt-private-a`: `0.0.0.0/0 → eni-0c87d0d9aa17892e9` (ENI de xyz-nat-a). `xyz-rt-private-b`: `0.0.0.0/0 → ENI de xyz-nat-b`. Al elegir la instancia como destino, AWS guarda en la ruta su interfaz de red (ENI).

**Doble traducción.** El tráfico de una instancia privada se traduce dos veces: primero en el NAT de Linux (N:1 con puertos, 10.0.11.10:p → 10.0.1.30:p') y luego en el IGW (1:1, 10.0.1.30 → IP pública de nat-a).

Evidencias: `evidencias/fase2/nat-a-nft-ruleset.png`, `nat-a-ip-forward.png`, `nat-b-nft-ruleset.png`, `nat-b-ip-forward.png`, `rt-private-a-routes.png`.

### Fase 3 — DNS BIND9

**Dominio.** `xyzcosmetics.online`, registrado en GoDaddy.

**Instancias.** `xyz-ns1` (public-a, 10.0.1.10, EIP 3.134.251.219) y `xyz-ns2` (public-b, 10.0.2.10, EIP 3.131.134.77): Ubuntu 26.04 LTS, t3.micro, SG `xyz-sg-dns` y rol `xyz-ec2-ssm-role`. La configuración se hizo con `scripts/bind/setup-bind.sh <primario|secundario> xyzcosmetics.online`.

**Delegación pública (registrador).** En GoDaddy se configuraron dos cosas:

1. **Hostnames (glue records):** `ns1` → 3.134.251.219 y `ns2` → 3.131.134.77. Los nameservers están *dentro* de la zona que delegan (dependencia circular: para hallar `ns1.xyzcosmetics.online` habría que preguntarle a `ns1`). El glue hace que el TLD entregue sus IPs junto con la delegación.
2. **Nameservers personalizados:** `ns1.xyzcosmetics.online` y `ns2.xyzcosmetics.online`.

El servidor del TLD `.online` (`ns10.trs-dns.org`) responde **sin** el flag `aa`, porque no es autoritativo para la zona. En la sección AUTHORITY entrega los dos NS y en ADDITIONAL los glue, con un TTL de 900 s fijado por el registro del TLD.

**Opciones globales** [4] (`/etc/bind/named.conf.options`, iguales en ambos servidores):

*Tabla 10. Fase 3 — DNS BIND9 — Opciones globales.*

| Opción | Valor | Motivo |
|---|---|---|
| `listen-on` | `127.0.0.1` + IP privada | `systemd-resolved` ya ocupa `127.0.0.53:53`. Las consultas de Internet llegan a la IP privada porque el IGW traduce 1:1 EIP ↔ IP privada |
| `listen-on-v6` / `-4` | `none` / `OPTIONS="-u bind -4"` | La VPC no tiene IPv6 |
| `recursion` | `no` | Servidor solo autoritativo: no puede usarse como resolvedor abierto ni para amplificación |
| `allow-transfer` | `none` (global) | Nadie puede pedir la zona completa, salvo lo que cada zona permita |
| `version` | `"no disponible"` | Oculta la versión de BIND (`dig CH TXT version.bind`) |

**Zona primaria** (`/etc/bind/zones/db.xyzcosmetics.online` en ns1):

```
$TTL 300
@       IN SOA ns1.xyzcosmetics.online. admin.xyzcosmetics.online. (
            2026111801 ; serial AAAAMMDDNN
            3600       ; refresh
            600        ; retry
            604800     ; expire
            300 )      ; TTL negativo
@       IN NS    ns1.xyzcosmetics.online.
@       IN NS    ns2.xyzcosmetics.online.
ns1     IN A     3.134.251.219
ns2     IN A     3.131.134.77
lb1     IN A     18.190.31.183
lb2     IN A     13.58.14.10
www     IN A     18.190.31.183     ; DNS Round Robin:
www     IN A     13.58.14.10       ; dos A para www
@       IN A     18.190.31.183
@       IN A     13.58.14.10
tienda  IN CNAME www
```

- **TTL de 300 s:** los cambios (D2) y la caída de un balanceador (D5) se reflejan en minutos en las cachés.
- **SOA:** el secundario revisa el serial cada hora (`refresh`), reintenta cada 10 min si el primario no responde (`retry`) y sigue respondiendo hasta 7 días sin primario (`expire`, relevante para D3).
- **`www` con dos A:** cada cliente recibe ambas IPs de los balanceadores y elige una. Es la base del reparto de carga por DNS.

**Primario/secundario y transferencia de zona.**

*Tabla 11. Fase 3 — DNS BIND9 — Primario/secundario y transferencia de zona.*

| | ns1 (primario) | ns2 (secundario) |
|---|---|---|
| Declaración | `type primary; file "/etc/bind/zones/db.…";` | `type secondary; primaries { 10.0.1.10; }; file "/var/cache/bind/db.…"; masterfile-format text;` |
| AXFR | `allow-transfer { 10.0.2.10; };` | `allow-transfer { none; };` |
| NOTIFY | `notify explicit; also-notify { 10.0.2.10; };` | `notify no;` |

La transferencia (AXFR/IXFR) [13] y el NOTIFY [14] usan las **IPs privadas** (red local de la VPC). Si se usaran los NS de la zona, el tráfico iría a la EIP, saldría por el IGW con la EIP del remitente como origen, y el secundario lo rechazaría por no venir de su primario declarado (ver problema P6). `masterfile-format text` deja legible la copia del secundario, que por defecto se guarda en formato binario `raw`.

Log de ns2 al arrancar: `Transfer started` → `transfer of 'xyzcosmetics.online/IN' from 10.0.1.10#53: connected using 10.0.1.10#53` → `Transfer completed: 1 messages, 13 records, 323 bytes` → `transferred serial 2026111801`.

**Verificación** (desde un PC externo, con `+norec` para exigir una respuesta autoritativa):

*Tabla 12. Fase 3 — DNS BIND9 — Verificación.*

| Consulta | Servidor | Resultado |
|---|---|---|
| `xyzcosmetics.online SOA` | ns1 y ns2 | `flags: qr aa`, serial **2026111801** en ambos |
| `xyzcosmetics.online NS` | ns1 | ns1 y ns2; sus A como datos adicionales |
| `www.xyzcosmetics.online A` | ns1 y ns2 | **2 registros A**: 18.190.31.183 y 13.58.14.10 |
| `tienda.xyzcosmetics.online A` | ns1 | `CNAME www.xyzcosmetics.online.` + los dos A (el autoritativo resuelve el alias dentro de su zona) |
| `xyzcosmetics.online AXFR` | ns1 y ns2 | `Transfer failed`. En ns2 queda el log `zone transfer … denied` para la IP del cliente |
| `google.com A` | ns1 | `status: REFUSED`, `recursion requested but not available`, `EDE 20 (Not Authoritative)` |
| `xyzcosmetics.online NS` | `ns10.trs-dns.org` (TLD) | Delegación a ns1/ns2 con glue (sin `aa`) |

Evidencias: `evidencias/fase3/godaddy-hostnames-glue.png`, `godaddy-nameservers.png`, `tld-delegacion-dig.png`, `tld-delegacion.txt`, `ns1-soa.png`, `ns1-ns.png`, `ns1-www.png`, `ns1-tienda-cname.png`, `ns2-soa.png`, `ns2-www.png`, `axfr-denegado-y-sin-recursion.png`, `ns2-transferencia-zona.txt`.

### Fase 4 — Base de datos y NFS

**Instancia.** `xyz-db` (private-a, 10.0.11.20, sin IP pública, SG `xyz-sg-db`). Accede a Internet (paquetes y SSM) a través de nat-a. La configuración se hizo con `scripts/db/setup-db.sh`. La contraseña de `wpuser` se pide por teclado y se guarda solo en `secrets.env` (no versionado; plantilla en `secrets.env.example`).

**MariaDB** [15] (`/etc/mysql/mariadb.conf.d/60-xyz.cnf`, que se lee después de `50-server.cnf` y sobrescribe sus valores):

```
[mysqld]
bind-address      = 10.0.11.20
skip-name-resolve = 1
```

- `bind-address`: por defecto MariaDB solo escucha en 127.0.0.1. Se configura en la IP privada (no en `0.0.0.0`).
- `skip-name-resolve`: autoriza por IP, sin hacer DNS inverso de cada cliente.
- Base `wordpress` (`utf8mb4`). Se crea el usuario `wpuser` **dos veces**, `wpuser@10.0.11.10` y `wpuser@10.0.12.10`, con `ALL PRIVILEGES` solo sobre `wordpress.*`. MariaDB identifica a un usuario por *nombre + host de origen*, así que desde cualquier otra IP el usuario no existe.
- `root` conserva la autenticación `unix_socket`: solo entra con `sudo mariadb` desde la propia instancia. Se eliminan los usuarios anónimos y la base `test`.

**NFS (NFSv4)** [16] — `/etc/exports`:

```
/srv/nfs/wp-uploads 10.0.11.10(rw,sync,no_subtree_check,all_squash,anonuid=33,anongid=33) \
                    10.0.12.10(rw,sync,no_subtree_check,all_squash,anonuid=33,anongid=33)
```

*Tabla 13. Fase 4 — Base de datos y NFS.*

| Opción | Efecto |
|---|---|
| `rw,sync` | Escritura, confirmada en disco antes de responder al cliente |
| `all_squash,anonuid=33,anongid=33` | Toda escritura, incluso la de root del cliente, queda a nombre de `www-data` (uid/gid 33). Los archivos que sube wp1 se pueden leer y modificar desde wp2 |
| `no_subtree_check` | Recomendado al exportar un directorio completo; evita errores cuando se renombran archivos abiertos |
| `nfsconf --set nfsd vers3 n` | Solo NFSv4 (`-3 +4 +4.1 +4.2`): todo el tráfico va por **TCP 2049**. NFSv3 requeriría además rpcbind (111) y `mountd` en puertos dinámicos, difíciles de filtrar con Security Groups |

**Tres capas de control de acceso a la DB:**

*Tabla 14. Fase 4 — Base de datos y NFS — Tres capas de control de acceso a la DB.*

| Capa | 3306 (MariaDB) | 2049 (NFS) |
|---|---|---|
| Security Group `xyz-sg-db` | Solo desde instancias con `xyz-sg-wp` | Solo desde instancias con `xyz-sg-wp` |
| Servicio | `wpuser` solo existe para 10.0.11.10 y 10.0.12.10 | `/etc/exports` solo para 10.0.11.10 y 10.0.12.10 |
| Red | Subred privada sin IP pública: no es direccionable desde Internet | Ídem |

**Verificación:**

*Tabla 15. Fase 4 — Base de datos y NFS — Verificación.*

| Prueba | Desde | Resultado |
|---|---|---|
| Puertos en escucha | xyz-db | `10.0.11.20:3306` (mariadbd) y `*:2049` (nfsd) |
| `nc -zv 10.0.11.20 3306` / `2049` | wp1 y wp2 | `succeeded` |
| `SELECT CURRENT_USER(), @@hostname` | wp1 | `wpuser@10.0.11.10`, `xyz-db`; bases `information_schema` y `wordpress` |
| ídem | wp2 | `wpuser@10.0.12.10`, `xyz-db` |
| Archivo escrito en wp1, leído en wp2 por NFS | wp2 | `escrito desde xyz-wp1`, propietario `33 33` aunque se escribió con `sudo` (efecto de `all_squash`) |
| `nc -zv -w 5 10.0.11.20 3306` | xyz-ns1 (SG `xyz-sg-dns`) | `timed out`: el SG descarta el SYN en silencio (no hay RST) |

Evidencias: `evidencias/fase4/db-setup-resumen.png`, `wp1-conexion-db.png`, `wp2-conexion-db.png`, `nfs-compartido-wp2.png`, `ns1-db-timeout.png`.

### Fase 5 — WordPress

**Instancias.** `xyz-wp1` (private-a, 10.0.11.10) y `xyz-wp2` (private-b, 10.0.12.10), sin IP pública y con SG `xyz-sg-wp` (TCP 80 solo desde `xyz-sg-lb`). Se configuraron con `scripts/wordpress/setup-wordpress.sh`, un único archivo que incluye el mu-plugin y el contenido. Se ejecuta primero en wp1, que instala WordPress en la DB compartida, y después en wp2, que detecta la instalación existente y solo configura el nodo.

**Pila de software:** Apache 2.4 con `mod_php` (PHP 8.5, MPM prefork) y WordPress **7.1.5** en español (`es_ES`) [1], instalado con **WP-CLI** [17]. El mismo código está en el disco local de cada nodo.

**Estado compartido** (ver §1.7):

*Tabla 16. Fase 5 — WordPress — Estado compartido.*

| Elemento | Implementación |
|---|---|
| Base de datos | `DB_HOST = 10.0.11.20`, base `wordpress`, usuario `wpuser` (la contraseña solo está en `secrets.env` y en `wp-config.php`, con permisos `640 root:www-data`) |
| Archivos subidos | `/etc/fstab`: `10.0.11.20:/srv/nfs/wp-uploads /var/www/wordpress/wp-content/uploads nfs4 defaults,_netdev,nofail,hard,timeo=600 0 0`. Montado con `vers=4.2,proto=tcp` |
| Claves y salts | Las 8 constantes (`AUTH_KEY` … `NONCE_SALT`) se generan una vez en wp1 (`/root/xyz-wp-salts.txt`, `openssl rand`) y se copian a wp2. Con valores idénticos, la cookie de sesión firmada por un nodo es válida en el otro |

**`wp-config.php`** (idéntico en ambos nodos):

- **URL dinámica:** `WP_HOME`/`WP_SITEURL` = `http://` + la cabecera `Host` de la petición, solo si está en una lista blanca (`www`, dominio raíz, `tienda`, `lb1`, `lb2` y las EIP de los balanceadores). Cualquier otro valor usa `www.xyzcosmetics.online`, lo que evita la inyección de la cabecera `Host`. El sitio funciona igual al entrar por `www`, por `lb1` o por la IP de cualquiera de los balanceadores.
- **`DISALLOW_FILE_MODS`** (activo salvo en WP-CLI) y **`AUTOMATIC_UPDATER_DISABLED`:** desde el panel no se pueden instalar ni actualizar plugins, temas, idiomas ni el núcleo. Un cambio así solo llegaría al nodo que atendió la petición y los nodos dejarían de ser iguales. Los cambios de código se hacen con el script, en ambos nodos.
- **`WP_CACHE = false`** y sin plugins de caché.

**Apache** (`/etc/apache2/sites-available/xyz-wordpress.conf`; se deshabilitó `000-default`):

*Tabla 17. Fase 5 — WordPress — Apache.*

| Directiva | Propósito |
|---|---|
| Reglas `RewriteRule` de enlaces permanentes en el `VirtualHost`, `AllowOverride None` | Sin `.htaccess`, que es un archivo local y podría quedar distinto entre nodos. Las URL son `/nosotros/`, `/sedes/`, etc. |
| `Header always set X-Served-By "xyz-wpN 10.0.1N.10"` | Identifica el nodo en todas las respuestas, incluidas las estáticas. Permite verificar el balanceo con `curl -I` |
| `Header set Cache-Control "no-store"` | Ni el navegador ni un intermediario guardan la página, así que cada recarga pasa por el balanceador |
| `php_admin_flag engine off` en `uploads` | Un `.php` subido nunca se ejecuta |
| `LogFormat` con `%{X-Forwarded-For}i` | Registra la IP real del cliente detrás de HAProxy (Fase 6) |

**mu-plugin `xyz-servidor.php`** (en `wp-content/mu-plugins`, se carga siempre y no se puede desactivar). Con el hook `wp_body_open` imprime en cada página una franja con el **nombre del nodo**, su **IPv4 privada** y la **hora de generación**. La hora prueba que la página se generó en esa petición y no salió de una caché. La IP se calcula en cada petición:

1. `$_SERVER['SERVER_ADDR']`: la IP local en la que Apache recibió la conexión. Detrás de HAProxy es 10.0.11.10 o 10.0.12.10.
2. Si esa IP es de loopback (`127.x`, en una prueba local), el plugin abre un socket UDP "conectado" hacia `10.0.0.2` (DNS de la VPC) y lee la IP de origen que elige el kernel. `connect()` en UDP no envía paquetes: solo resuelve la ruta y la interfaz de salida (`ens5`).

**Contenido:** página de inicio estática "Inicio" y las páginas Nosotros, Productos, Sedes (Medellín, Bogotá y Bucaramanga) y Contacto. El título del sitio es "XYZ S.A." y la zona horaria `America/Bogota`. Se eliminaron la entrada y la página de ejemplo.

**Verificación:**

*Tabla 18. Fase 5 — WordPress — Verificación.*

| Prueba | wp1 | wp2 |
|---|---|---|
| `wp core version` | 7.1.5 | 7.1.5 |
| `findmnt …/uploads` | `10.0.11.20:/srv/nfs/wp-uploads nfs4 vers=4.2, clientaddr=10.0.11.10` | Ídem, `clientaddr=10.0.12.10` |
| `wp post list --post_type=page` | IDs 4–8 publicados | Los mismos IDs (misma DB) |
| `curl -I` local | `200 OK`, `X-Served-By: xyz-wp1 10.0.11.10`, `Cache-Control: no-store` | `200 OK`, `X-Served-By: xyz-wp2 10.0.12.10`, `Cache-Control: no-store` |
| Franja del home | `Página servida por xyz-wp1 · IPv4 privada 10.0.11.10` | `Página servida por xyz-wp2 · IPv4 privada 10.0.12.10` |
| `wp media import` en wp1 → `wp post list` + `ls -ln` en wp2 | Attachment ID 10 creado | wp2 lo ve en la DB y en disco: original + 3 miniaturas, dueño `33:33` |

Las peticiones de prueba se hicieron con `curl` local en cada nodo (`-H "Host: www.xyzcosmetics.online" http://127.0.0.1/`), porque `xyz-sg-wp` solo admite tráfico desde los balanceadores.

Evidencias: `evidencias/fase5/wp1-setup-resumen.png`, `wp2-setup-resumen.png`, `wp1-media-import.png`, `wp2-media-compartida.png` y, antes de corregir P8, `wp1-setup-resumen-v1.png` y `wp2-setup-resumen-v1.png`.

### Fase 6 — Balanceadores HAProxy

**Instancias.** `xyz-lb1` (public-a, 10.0.1.20, EIP 18.190.31.183) y `xyz-lb2` (public-b, 10.0.2.20, EIP 13.58.14.10): Ubuntu 26.04 LTS, `t3.micro`, sin key pair (acceso por SSM), SG `xyz-sg-lb`, rol `xyz-ec2-ssm-role`. Con ellas se completan las **9 instancias** (18 de los 20 vCPU de la cuota). Se lanzaron clonando `xyz-ns1` y `xyz-ns2` (misma subred pública, AMI y rol) y cambiando nombre, SG e IP privada fija; la EIP se asoció después. Se configuraron con `scripts/haproxy/setup-haproxy.sh` (HAProxy 3.2.25 [3]), que identifica el nodo por su IP privada y pide la contraseña de la página de estadísticas (no se guarda en el repositorio).

**Configuración** (`/etc/haproxy/haproxy.cfg`, igual en ambos salvo el nombre):

*Tabla 19. Fase 6 — Balanceadores HAProxy — Configuración.*

| Directiva | Propósito |
|---|---|
| `frontend http_in` · `bind *:80` | Recibe las peticiones HTTP de los clientes (SG: TCP 80 desde 0.0.0.0/0) |
| `backend wordpress` · `balance roundrobin` | Reparte las peticiones alternando wp1 y wp2. **Sin cookies ni `balance source`**: no hay afinidad de sesión (requisito de B1) |
| `option httpchk` + `http-check send meth GET uri / ver HTTP/1.1 hdr Host www.xyzcosmetics.online` + `http-check expect status 200` | Health check de capa 7: pide la página de inicio de WordPress (que también consulta la DB) y exige un 200 |
| `default-server inter 2s fall 2 rise 2` | Verifica cada 2 s; marca `DOWN` tras 2 fallos seguidos y `UP` tras 2 aciertos (detección en unos 4–6 s) |
| `option redispatch` + `retries 3` | Si el servidor elegido falla al conectar, reintenta la petición en el otro |
| `option forwardfor` | Agrega `X-Forwarded-For` con la IP real del cliente (Apache la registra, Fase 5) |
| `http-response set-header X-Balanced-By xyz-lbN` | Identifica el balanceador que respondió; junto con `X-Served-By` (de Apache) muestra el camino completo en `curl -I` |
| `listen stats` · `bind *:8404` · `stats auth admin:…` | Página de estadísticas con usuario y contraseña. El SG `xyz-sg-lb` solo permite el 8404 desde la IP del equipo (/32) |

**Flujo.** HAProxy actúa como *proxy inverso*: termina la conexión TCP del cliente (cliente ↔ LB) y abre **otra** conexión TCP hacia el WordPress elegido (LB ↔ wp, `xyz-sg-wp` solo admite TCP 80 desde `xyz-sg-lb`). Por eso los servidores privados nunca son direccionables desde Internet y cada balanceador solo necesita su EIP.

**Verificación.** El script imprime un resumen: HAProxy `active`, escuchando en `0.0.0.0:80` y `0.0.0.0:8404`, wp1 y wp2 responden `200` por conexión directa, y 4 peticiones locales alternan `x-served-by: xyz-wp1 10.0.11.10` / `xyz-wp2 10.0.12.10` con `x-balanced-by` del propio nodo.

Evidencias: `evidencias/fase6/lb1-setup-resumen.png`, `lb2-setup-resumen.png`, `ec2-9-instancias.png`, `ssm-9-nodos-online.png`.

---

## 3. Pruebas experimentales

Para cada prueba: procedimiento, comandos, evidencia, interpretación y protocolos involucrados.

*Tabla 20. 3. Pruebas experimentales.*

| ID | Prueba | Estado |
|---|---|---|
| N1 | HTTP desde instancia privada a destino externo; IP pública observada | ✅ Realizada |
| N2 | conntrack: asociaciones de direcciones/puertos antes y después del NAT | ✅ Realizada |
| N3 | Deshabilitar IP forwarding y explicar la falla | ✅ Realizada |
| N4 | Conexión saliente vs. entrante no solicitada | ✅ Realizada |
| D1 | dig SOA/NS/A/CNAME a ambos autoritativos; delegación pública | ✅ Realizada |
| D2 | Cambio en primario + serial SOA → transferencia al secundario | ✅ Realizada |
| D3 | Primario caído; secundario responde autoritativamente | ✅ Realizada |
| D4 | Consultas repetidas a `www`: orden de A, TTL/caché | ✅ Realizada |
| D5 | Balanceador caído sigue anunciado por DNS | ✅ Realizada |
| B1 | Peticiones sucesivas a cada LB muestran ambas IPs privadas | ✅ Realizada |
| B2 | WordPress caído; ambos LB siguen atendiendo | ✅ Realizada |

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

*Tabla 21. N1 — Solicitud HTTP desde una instancia privada.*

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

*Tabla 22. N2 — Asociaciones de direcciones y puertos con conntrack — Evidencia.*

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

*Tabla 23. N3 — Deshabilitar IP forwarding en una instancia NAT — Evidencia.*

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

**Evidencia** (`evidencias/fase2/n4-curl-externo-timeout.png`, `evidencias/fase2/n4-tcpdump-nat-a.png`):
- PC externo: `Trying 3.128.168.127:80...` y luego `Connection timed out after 5001 milliseconds` (código 28). No hubo respuesta de ningún tipo, ni SYN-ACK ni RST.
- nat-a: mientras el PC externo repetía `curl -4 -m 5 -I http://3.128.168.127/`, la captura `sudo timeout -s INT 20 tcpdump -ni ens5 'tcp dst port 80 and not src net 10.0.0.0/16'` terminó con `0 packets captured`: ningún paquete del cliente llegó a la interfaz `ens5`, porque el Security Group descarta el SYN antes de entregarlo a la instancia.

**Comparación.**

*Tabla 24. N4 — Conexión iniciada desde la subred privada vs. conexión entrante no solicitada — Comparación.*

| | Conexión saliente (N1) | Conexión entrante no solicitada (N4) |
|---|---|---|
| Quién la inicia | wp1 (10.0.11.10) | Un host de Internet |
| Security Group | `xyz-sg-nat` permite la entrada desde 10.0.11.0/24. La respuesta pasa porque los SG son *stateful* | `xyz-sg-nat` no tiene regla para 0.0.0.0/0. **El SYN se descarta en la infraestructura de AWS, antes de llegar a la instancia**, y por eso tcpdump no lo ve y el cliente no recibe ni un RST |
| Rutas | `xyz-rt-private-a` envía 0.0.0.0/0 a la ENI de nat-a | El IGW solo puede entregar a una ENI con IP pública. wp1 no tiene ninguna, así que **no hay forma de dirigirse a ella desde Internet** |
| NAT / conntrack | El SYN saliente crea la asociación `10.0.11.10:p ↔ 10.0.1.30:p'`, y las respuestas encajan en ella | No existe ninguna entrada de conntrack ni regla DNAT (*port forwarding*) que indique a qué host interno reenviar. Aunque el SG lo dejara pasar, el paquete iría dirigido a nat-a misma, sin ningún servicio escuchando en el puerto 80 |
| Filtro `forward` (nftables) | Acepta: conexión nueva desde 10.0.11.0/24 y luego `established` | `policy drop`: no se reenviaría una conexión nueva que no venga de la subred privada |
| Resultado | HTTP 200 | Timeout |

**Interpretación.** El NAT de origen (masquerade) es asimétrico por diseño: permite que la subred privada **inicie** conexiones y deja pasar solo las respuestas, gracias al estado guardado en conntrack. Para que algo de Internet llegue a un servidor privado haría falta un DNAT explícito o, como en esta arquitectura, un intermediario que inicie la conexión: el balanceador HAProxy de la Fase 6. La protección es en capas: (1) el Security Group filtra en el borde de la ENI; (2) la ausencia de IP pública y de rutas hace que los privados no sean direccionables; (3) conntrack/NAT no tiene asociación para tráfico no solicitado; (4) la cadena `forward` con política `drop` bloquea cualquier reenvío no autorizado.

### D1 — Consultas autoritativas (SOA, NS, A, CNAME) y delegación pública

**Procedimiento.** Desde un cliente externo (WSL) se consultan directamente las EIP de `xyz-ns1` (`3.134.251.219`) y `xyz-ns2` (`3.131.134.77`) para los registros `SOA`, `NS`, `A` (`www`) y `CNAME` (`tienda`), y se ejecuta `dig -4 +trace www.xyzcosmetics.online @1.1.1.1` para verificar la cadena de delegación completa desde los servidores raíz hasta nuestros autoritativos.

```bash
for NS in 3.134.251.219 3.131.134.77; do
  echo "===== @$NS ====="
  for T in SOA NS A CNAME; do
    N=xyzcosmetics.online; [ $T = A ] && N=www.xyzcosmetics.online; [ $T = CNAME ] && N=tienda.xyzcosmetics.online
    dig -4 +noall +comments +answer +authority @$NS $N $T | grep -E 'flags|ANSWER|^[a-z]'
  done
done
dig -4 +trace www.xyzcosmetics.online @1.1.1.1 | tail -15
```

**Evidencia** (`evidencias/fase7/dig.png`, `evidencias/fase7/dig-trace.png`, `evidencias/fase3/dig-trace-www.png`):
- Ambos servidores (`3.134.251.219` y `3.131.134.77`) responden con `flags: qr aa rd` (bit `aa` *Authoritative Answer* activo) y exactamente los mismos registros y TTL (`300`):
  - `SOA`: `ns1.xyzcosmetics.online. admin.xyzcosmetics.online. 2026111801 3600 600 604800 300`.
  - `NS`: `ns1.xyzcosmetics.online.` y `ns2.xyzcosmetics.online.`.
  - `A` (`www.xyzcosmetics.online`): dos registros `18.190.31.183` y `13.58.14.10`.
  - `CNAME` (`tienda.xyzcosmetics.online`): apunta a `www.xyzcosmetics.online.`.
- La traza (`dig -4 +trace`) muestra la resolución jerárquica: servidores raíz (`.`) → servidores del TLD `.online` (`ns10.trs-dns.info`, que delegan a `ns1`/`ns2.xyzcosmetics.online` con TTL 900 y registros NSEC3 que confirman ausencia de DS/DNSSEC) → respuesta autoritativa final desde `3.134.251.219#53(ns1.xyzcosmetics.online)` con ambos registros `A`.

**Interpretación.** El flag `aa` confirma que tanto el primario como el secundario sirven la zona con autoridad directa (no desde caché). El TLD `.online` entrega los *glue records* configurados en GoDaddy, rompiendo la dependencia circular de nombres dentro de la propia zona.

**Protocolos.** DNS sobre UDP puerto 53 (consultas iterativas en `+trace` y consultas directas autoritativas).

### D2 — Actualización de zona en primario y transferencia al secundario

**Procedimiento.** Se consulta el registro `SOA` antes del cambio, se añade un registro `TXT` de prueba (`d2 IN TXT "prueba D2"`) en `/etc/bind/zones/db.xyzcosmetics.online` en `xyz-ns1`, se valida con `named-checkzone` y se recarga sin incrementar el serial (`2026111801`). Luego se incrementa el serial a `2026111901`, se recarga nuevamente (`rndc reload`) y se inspeccionan los logs (`journalctl -u named`) en ambos servidores.

```bash
# xyz-ns1
echo 'd2 IN TXT "prueba D2"' | sudo tee -a /etc/bind/zones/db.xyzcosmetics.online
sudo named-checkzone xyzcosmetics.online /etc/bind/zones/db.xyzcosmetics.online
sudo rndc reload xyzcosmetics.online
# Incremento de serial
sudo sed -i 's/2026111801/2026111901/' /etc/bind/zones/db.xyzcosmetics.online
sudo named-checkzone xyzcosmetics.online /etc/bind/zones/db.xyzcosmetics.online
sudo rndc reload xyzcosmetics.online
# Logs en ns1 y ns2
sudo journalctl -u named --since "-10min" --no-pager | grep -iE 'notify|transfer|xfer'
```

**Evidencia** (`evidencias/fase7/d2-antes.png`, `d2-ns1-serial.png`, `d2-prueba-serial.png`, `d2-journal-ns1.png`, `d2-journal-ns2.png`):
- **Antes:** `ns1` y `ns2` tienen serial `2026111801` y `d2.xyzcosmetics.online TXT` devuelve vacío.
- **Sin incrementar el serial:** `ns1` responde `"prueba D2"`, pero `ns2` mantiene el serial `2026111801` y **no** tiene el registro `TXT`, porque BIND9 solo dispara notificaciones/transferencias cuando detecta un serial mayor.
- **Tras subir el serial a `2026111901` (20:32:10 UTC):**
  - En `ns1`: `sending notify to 10.0.2.10#53`, seguido de `AXFR-style IXFR started (serial 2026111901)` y `AXFR-style IXFR ended: 1 messages, 14 records, 348 bytes, 0.001 secs`.
  - En `ns2`: `received notify for zone 'xyzcosmetics.online'` desde `10.0.1.10`, `Transfer started`, `transferred serial 2026111901` (`14 records, 348 bytes, 0.004 secs`).
  - La consulta externa a ambos servidores devuelve `2026111901` y `"prueba D2"`. (Posteriormente se limpió el registro temporal subiendo el serial a `2026111902`.)

**Interpretación.** El número de serie del registro `SOA` es el mecanismo de control de versiones en DNS: sin incrementarlo, el secundario asume que su copia sigue vigente. Al incrementarlo, el primario envía un mensaje `DNS NOTIFY` por la red privada (`10.0.1.10 → 10.0.2.10`), logrando la sincronización en 4 milisegundos sin esperar el temporizador `refresh` de 3600 s.

**Protocolos.** DNS `NOTIFY` (UDP 53) y transferencia de zona `IXFR/AXFR` sobre **TCP 53** entre IPs privadas.

### D3 — Caída del servidor DNS primario y continuidad del secundario

**Procedimiento.** En `xyz-ns1` se programa una recuperación automática a los 300 s con `nohup` y se detiene el servicio `named` (`21:01:55`). Durante la caída se consulta `xyzcosmetics.online SOA` y `www.xyzcosmetics.online` contra `ns1` (`3.134.251.219`), contra `ns2` (`3.131.134.77`) y contra un resolvedor público (`1.1.1.1`). Luego se verifica el restablecimiento.

```bash
# xyz-ns1
sudo nohup bash -c 'sleep 300; systemctl start named' >/dev/null 2>&1 &
sudo systemctl stop named
# Cliente externo (WSL)
dig -4 +time=3 +tries=1 @3.134.251.219 xyzcosmetics.online SOA
for NS in 3.134.251.219 3.131.134.77; do dig -4 +noall +comments +answer @$NS xyzcosmetics.online SOA | grep -E 'flags|^xyz'; done
for LB in 18.190.31.183 13.58.14.10; do curl -s -m 5 -o /dev/null -w "$LB %{http_code}
" http://$LB/; done
```

**Evidencia** (`evidencias/fase7/d3-ns1-stoped.png`, `d3-dig-ns1-timeout.png`, `d3-restablished.png`):
- Con `named` detenido (`inactive`) en `ns1`, la consulta directa a `3.134.251.219` falla (`communications error to 3.134.251.219#53: connection refused`, `no servers could be reached`).
- Simultáneamente, `ns2` (`3.131.134.77`) responde con `flags: qr aa rd` (autoritativo) entregando el `SOA` vigente (`serial 2026111902`) y los registros `A` de `www`, permitiendo resolver el dominio y alcanzar los balanceadores con `HTTP 200`.
- Pasados los 5 minutos, `ns1` arranca automáticamente y ambos servidores vuelven a responder `SOA` con el mismo serial (`2026111902`).

**Interpretación.** Gracias a la delegación dual configurada en GoDaddy (`ns1` y `ns2` en distintas AZ) y al parámetro `expire = 604800` (7 días) del `SOA`, el secundario es completamente autónomo para responder consultas autoritativas durante una caída del primario, garantizando alta disponibilidad en la capa de resolución de nombres.

**Protocolos.** DNS (UDP/TCP 53) e **ICMP**: con `named` detenido, el kernel de `ns1` responde a la consulta UDP con un ICMP *destination unreachable / port unreachable* (tipo 3, código 3), que `dig` reporta como `connection refused`. En TCP, el equivalente sería un segmento RST.

### D4 — Consultas repetidas a `www`: orden de registros A, TTL y caché

**Procedimiento.** Se realizan 20 consultas seguidas a `www.xyzcosmetics.online` tanto contra el resolvedor recursivo `1.1.1.1` como directamente contra el autoritativo `ns1` (`3.134.251.219`), combinando con peticiones HTTP (`--resolve`) para observar el reparto y el comportamiento de la caché (TTL).

```bash
for i in $(seq 1 20); do
  IP=$(dig -4 +time=2 +tries=2 +short @1.1.1.1 www.xyzcosmetics.online | grep -v '^;;' | head -1)
  echo "$IP $(curl -s -m 5 -I --resolve www.xyzcosmetics.online:80:$IP http://www.xyzcosmetics.online/ | grep -i x-balanced-by | tr -d '
')"
done | sort | uniq -c
```

**Evidencia** (`evidencias/fase7/d4recursive-autoritary-ttl.png`, `evidencias/fase7/DNStest.png`):
- Contra el resolvedor recursivo (`@1.1.1.1`), en 20 consultas se obtuvo un reparto de **9** respuestas hacia `13.58.14.10` (`x-balanced-by: xyz-lb2`) y **9** hacia `18.190.31.183` (`x-balanced-by: xyz-lb1`) (más 2 transitorias durante inicialización/caché).
- Contra el servidor autoritativo directo (`@3.134.251.219`), en 20 consultas se obtuvo **11** hacia `13.58.14.10` (`xyz-lb2`) y **9** hacia `18.190.31.183` (`xyz-lb1`), alternando el orden de los dos registros `A` (`13.58.14.10` / `18.190.31.183`) en respuestas consecutivas con TTL fijo de `300` s.
- En un resolvedor recursivo, el TTL observado decrece segundo a segundo desde `300` hasta `0` mientras la respuesta permanece cacheada [6], y aunque el recursivo reordena (round-robin) los registros en caché, no vuelve a consultar al autoritativo hasta que el TTL expira.

**Interpretación.** El DNS autoritativo implementa *DNS Round Robin* entregando **ambos** registros `A` y variando su orden entre respuestas. El reparto no es una alternancia estricta (11/9 en 20 consultas, y varias respuestas seguidas con el mismo orden en la Fase 3), lo que coincide con un orden aleatorio más que con uno cíclico. El orden lo controla la opción `rrset-order` de BIND9 [4], que no se modificó. Los clientes suelen usar la primera dirección de la lista, así que el orden variable es lo que reparte la carga. Sin embargo, la granularidad del balanceo por DNS está limitada por el caching de los resolvedores intermedios y del sistema operativo cliente durante la ventana del TTL (300 s).

**Protocolos.** DNS (UDP 53) y HTTP/1.1 (TCP 80).

### D5 — Balanceador caído sigue anunciado por DNS

**Procedimiento.** Se detiene `haproxy` en `xyz-lb1` (`18.190.31.183`), se consulta `www.xyzcosmetics.online` en `ns1` y se ejecuta un bucle de 20 solicitudes resolviendo el nombre y conectando a la IP devuelta.

```bash
# xyz-lb1
sudo systemctl stop haproxy
# Cliente externo (WSL)
curl -s -m 5 -I http://18.190.31.183/ ; echo "exit=$?"
curl -s -m 5 -I http://13.58.14.10/ | head -1
for i in $(seq 1 20); do
  IP=$(dig -4 +time=2 +tries=2 +short @3.134.251.219 www.xyzcosmetics.online | grep -v '^;;' | head -1)
  echo "$IP $(curl -s -m 4 -o /dev/null -w '%{http_code}' --resolve www.xyzcosmetics.online:80:$IP http://www.xyzcosmetics.online/)"
done | sort | uniq -c
```

**Evidencia** (`evidencias/fase7/d5-lb1-failed.png`):
- `dig` contra `3.134.251.219` sigue entregando **ambas direcciones IP** (`13.58.14.10` y `18.190.31.183`).
- `curl` directo a `18.190.31.183` falla con `exit=7` (*Failed to connect / Connection refused*), mientras `13.58.14.10` (`lb2`) responde `HTTP/1.1 200 OK`.
- En el bucle de 20 peticiones: **9** cayeron en `13.58.14.10` y devolvieron **`200`**; **10** cayeron en `18.190.31.183` y devolvieron **`000`** (fallo de conexión), y en **1** la consulta `dig` no obtuvo respuesta a tiempo (IP vacía, `000`). Tras volver a iniciar HAProxy **en `xyz-lb1`** (sesión SSM), el servicio respondió `200`.
- Nota sobre la captura: el `sudo systemctl start haproxy` que aparece con el error `Unit haproxy.service not found` se ejecutó por error en el WSL del PC y no en `xyz-lb1`; por eso la siguiente línea muestra `lb1 000`. El servicio se restableció después desde la sesión SSM de `xyz-lb1`.

**Interpretación.** El DNS estándar (BIND9) es un protocolo de resolución de nombres estático sin *health checks* activos sobre los destinos de los registros `A`: desconoce si el servicio HTTP en `18.190.31.183:80` está operativo. Por ello sigue anunciando la IP caída y aproximadamente el 50 % de los intentos de conexión nuevos fallan (a menos que el navegador/cliente aplique *Happy Eyeballs* o reintentos sobre la segunda IP de la respuesta DNS). Esto contrasta directamente con B2, donde HAProxy sí realiza comprobaciones L4/L7 y retira automáticamente el backend fallido.

**Protocolos.** DNS (UDP 53) y TCP (SYN hacia `18.190.31.183:80` rechazado con `RST` al estar cerrado el puerto).

### B1 — Distribución de solicitudes entre las dos instancias WordPress

**Procedimiento.** Desde un cliente externo (WSL en el PC del equipo, sin cookies) se hacen 10 solicitudes sucesivas a cada balanceador por su EIP y se extrae del home la franja "servida por xyz-wpN · IPv4 privada …". Se repite por el nombre `www` (DNS Round Robin) y desde el navegador (F5). No hay caché: WordPress envía `Cache-Control: no-store` y la franja incluye la hora de generación.

```bash
for LB in 18.190.31.183 13.58.14.10; do
  echo "== $LB =="
  for i in $(seq 1 10); do
    curl -s http://$LB/ | sed 's/<[^>]*>//g' | grep -o 'servida por.*IPv4 privada *[0-9.]*' | head -1
  done
done
curl -sI http://18.190.31.183/ | grep -iE '^HTTP|x-served-by|x-balanced-by|cache-control'
curl -sI http://13.58.14.10/   | grep -iE '^HTTP|x-served-by|x-balanced-by|cache-control'
dig -4 +short www.xyzcosmetics.online
```

**Evidencia** (`evidencias/fase6/b1-curl-lb1-lb2.png`, `b1-curl-www-dns.png`, `b1-navegador-lb1.png`, `b1-navegador-lb2.png`, `b1-stats-lb1.png`, `b1-stats-lb2.png`):
- Cada balanceador devolvió 10 respuestas alternando `xyz-wp1 · 10.0.11.10` y `xyz-wp2 · 10.0.12.10` (5 y 5).
- `curl -I`: `200 OK`, `cache-control: no-store`, `x-served-by: xyz-wp… ` y `x-balanced-by: xyz-lb1` / `xyz-lb2` según el balanceador consultado.
- `dig -4 +short www.xyzcosmetics.online` devuelve las dos EIP (18.190.31.183 y 13.58.14.10). Seis solicitudes a `www` dieron wp2, wp2, wp1, wp1, wp2, wp2: sin patrón estricto, porque el cliente elige una de las dos IP y cada balanceador lleva **su propio contador** de roundrobin.
- Estadísticas de HAProxy al terminar B1 (`evidencias/fase6/b1-stats-lb1.png`, `b1-stats-lb2.png`, columna *Sessions → Total*): lb1 wp1 = 82 y wp2 = 81 (163 en total); lb2 wp1 = 61 y wp2 = 61 (122). Ambos servidores `UP` con `L7OK/200`. Justo antes de que wp1 cayera en B2 los contadores eran lb1 86/86 y lb2 66/67 (`b2-stats-wp1-down-lb1.png`, `b2-stats-wp1-down-lb2.png`). El reparto fue prácticamente exacto en ambos balanceadores.

**Interpretación.**
1. Con un solo cliente, `roundrobin` alterna en cada solicitud porque cada una abre una conexión nueva y no hay afinidad (sin cookies ni hash de IP). Si hubiera varios clientes simultáneos, el orden se entremezclaría, pero el reparto total seguiría siendo parejo.
2. Que ambas IPs aparezcan en el **home** (generado por PHP en cada petición con `SERVER_ADDR`) demuestra que la petición llegó realmente a cada nodo y no salió de una caché.
3. `x-balanced-by` y `x-served-by` muestran los dos saltos: cliente → LB → WordPress.

**Protocolos.** DNS (UDP 53) para resolver `www`; **TCP** (handshake SYN/SYN-ACK/ACK) cliente ↔ LB:80 y, como segunda conexión independiente, LB ↔ WP:80; **HTTP/1.1** `GET /` con respuesta `200` y cabeceras `Cache-Control`, `X-Served-By`, `X-Balanced-By`; HAProxy agrega `X-Forwarded-For` hacia el backend. El IGW traduce 1:1 la EIP del balanceador a su IP privada (10.0.1.20 / 10.0.2.20).

### B2 — Una instancia WordPress deja de estar disponible

**Procedimiento.** Con las páginas de estadísticas abiertas, se detuvo Apache en wp1 (`sudo systemctl stop apache2`, sesión SSM) y se repitió el bucle de B1 contra ambos balanceadores. Después se restauró (`sudo systemctl start apache2`) y se repitió.

```bash
# xyz-wp1
sudo systemctl stop apache2        # corte
sudo systemctl start apache2       # restauración
# PC externo: bucle de B1 con marca de tiempo contra lb1 y lb2
for i in $(seq 1 45); do
  a=$(curl -s -m 3 http://18.190.31.183/ | sed 's/<[^>]*>//g' | grep -o 'xyz-wp[12] · IPv4 privada *[0-9.]*' | head -1)
  b=$(curl -s -m 3 http://13.58.14.10/   | sed 's/<[^>]*>//g' | grep -o 'xyz-wp[12] · IPv4 privada *[0-9.]*' | head -1)
  printf "%s lb1: %-34s lb2: %s\n" "$(date +%T)" "$a" "$b"; sleep 1
done
# lb1 / lb2: registro de HAProxy
sudo journalctl --since "-4hours" --no-pager | grep -iE 'haproxy.*wp1'
```

**Evidencia** (`evidencias/fase6/b2-stats-wp1-down-lb1.png`, `b2-stats-wp1-down-lb2.png`, `b2-curl-con-wp1-caido.png`, `b2-journal-down-up-stats-restaurado.png`). Las horas de esta prueba son hora local de Colombia (UTC−5); los registros de las instancias están en UTC (por ejemplo, `17:12` UTC = `12:12` local):
- En las estadísticas de **ambos** balanceadores wp1 pasó a `DOWN` (rojo) con `LastChk = L4CON in 0ms` (la conexión TCP al puerto 80 fue rechazada, porque Apache estaba detenido) y wp2 siguió en `UP` (`L7OK/200`). El backend quedó en `1/1` servidores activos. Las capturas muestran wp1 `DOWN` desde hacía 1m53s (lb1) y 2m24s (lb2): el `DOWN` se registró hacia las 12:08.
- Con wp1 caído (`12:11:18`), las 20 solicitudes consecutivas (10 a `18.190.31.183` y 10 a `13.58.14.10`) fueron servidas al 100 % por `xyz-wp2 · IPv4 privada 10.0.12.10`, sin errores ni timeouts para el cliente (`evidencias/fase6/b2-curl-con-wp1-caido.png`).
- El panel de lb1 después de iniciar Apache (`evidencias/fase6/b2-journal-down-up-stats-restaurado.png`) muestra wp1 de nuevo activo, sin intervención en HAProxy. En la columna *Total*, wp1 se quedó en 86 (el valor del momento de la caída) y wp2 pasó de 86 a 96: las 10 solicitudes que recibió lb1 durante la caída fueron todas a wp2. El fragmento de `journalctl` de esa captura solo muestra los accesos a `/stats`; la transición `DOWN → UP` se lee en el panel.
- Tras restaurar, wp1 volvió a `UP` y a recibir solicitudes en round-robin. Según el panel consultado más tarde (esa captura no está en el repositorio), wp1 registra `Dwn = 1` y `Dwntme = 6m18s` (lb1) y `6m17s` (lb2), y los totales posteriores (lb1: wp1 96 / wp2 107; lb2: wp1 78 / wp2 82) muestran que wp2 absorbió todo el tráfico durante la ventana de indisponibilidad.

**Interpretación.**
1. **Detección.** HAProxy verifica cada 2 s (`inter 2s`); tras 2 fallos seguidos (`fall 2`) marca el servidor `DOWN`, así que tarda unos 4–6 s. Una petición que llegue justo antes de esa marca podría elegir wp1, pero `option redispatch` + `retries 3` la reintentan en wp2 y el cliente no ve el error.
2. **Recuperación.** Con `rise 2`, wp1 vuelve a recibir tráfico tras 2 checks exitosos (unos 4 s), sin intervención.
3. **Dos tipos de check.** `L4CON` significa que ni siquiera se completó el handshake TCP (puerto cerrado: el kernel responde RST). Si Apache respondiera pero WordPress/MariaDB fallaran, se vería `L7STS/5xx`. El check usa `GET /`, que ejecuta PHP y consulta la DB, por lo que detecta fallos de la aplicación y no solo del proceso.
4. **Alta disponibilidad real.** Los dos balanceadores comparten el mismo backend: la caída de un WordPress se oculta a los clientes en ambos. A diferencia del DNS Round Robin (D5), HAProxy **retira automáticamente** el nodo fallido.
5. **Límite.** Si cae `xyz-db` ambos WordPress fallan (ver §1.7): HAProxy balancea la capa web, no la de datos.

**Protocolos.** TCP (el check intenta el handshake con wp1 y recibe RST) y HTTP/1.1 (`GET /` con `Host: www.xyzcosmetics.online`, respuesta esperada `200`).

## 4. Análisis de protocolos y capturas de tráfico

Se realizaron capturas de paquetes con `tcpdump` en las interfaces `ens5` de los nodos clave y pruebas de conectividad ICMP/TCP para analizar cada capa de la pila TCP/IP:

### 4.1 Resolución DNS (UDP/53) y consulta interna a AmazonProvidedDNS
- **Evidencia:** `evidencias/fase7/DNStest.png` (captura en `xyz-ns1`, `sudo tcpdump -ni ens5 -c 2 'udp port 53 and not host 10.0.0.2'`).
- **Análisis:** Se observa la consulta entrante `186.87.10.152.3999 > 10.0.1.10.53: 34288+ [1au] A? www.xyzcosmetics.online. (64)` (el IGW ya tradujo la EIP `3.134.251.219` a `10.0.1.10`) y la respuesta autoritativa `10.0.1.10.53 > 186.87.10.152.3999: 34288*- 2/0/1 A 13.58.14.10, A 18.190.31.183 (112)`, donde el asterisco (`*`) indica el bit `AA` (*Authoritative Answer*) y `-` indica `RA=0` (recursión deshabilitada). Previamente se observó cómo las consultas internas de la propia instancia (`ssm.us-east-2.amazonaws.com`) van hacia `10.0.0.2:53` (DNS de la VPC).

### 4.2 Handshake TCP, petición HTTP y cierre de conexión (Cliente ↔ Balanceador ↔ Backend)
- **Evidencia:** `evidencias/fase7/d6-tcp-handshake.png`, `evidencias/fase7/handshake-tcp.webp`, `evidencias/fase7/tcp-wp1.png`.
- **Análisis en `xyz-lb1` (`d6-tcp-handshake.png`):**
  1. **Three-way handshake (Cliente ↔ LB)** [18]**:**
     - `SYN`: `186.87.10.152.4031 > 10.0.1.20.80: Flags [S], seq 2167957936, win 64240, options [mss 1460,...]`.
     - `SYN-ACK`: `10.0.1.20.80 > 186.87.10.152.4031: Flags [S.], seq 474272013, ack 2167957937, win 62643, options [mss 8961,...]`.
     - `ACK`: `186.87.10.152.4031 > 10.0.1.20.80: Flags [.], ack 1`.
  2. **Capa de aplicación HTTP/1.1** [19], [20]**:** El cliente envía `HTTP: HEAD / HTTP/1.1` (`78` bytes de payload) y HAProxy devuelve `HTTP/1.1 200 OK` (`429` bytes) incluyendo las cabeceras `x-served-by: xyz-wp1 10.0.11.10`, `cache-control: no-store` y `x-balanced-by: xyz-lb1`.
  3. **Cierre ordenado (Four-way teardown):** Intercambio de segmentos `FIN-ACK` (`Flags [F.]`) y `ACK` en ambos sentidos (`seq 79, ack 430` y `seq 430, ack 80`).
- **Análisis en `xyz-wp1` (`tcp-wp1.png`):** Confirma que HAProxy abre una **segunda conexión TCP independiente** desde su IP privada `10.0.1.20` hacia `10.0.11.10:80` (y `10.0.12.10:80`) con `mss 8961` (Jumbo Frames internos de la VPC), realizando peticiones `GET / HTTP/1.1` con respuestas `200 OK`.

### 4.3 Trazabilidad de IP real del cliente (`X-Forwarded-For`)
- **Evidencia:** `evidencias/fase7/Forwarded-for_wp1.png`.
- **Análisis:** Dado que la conexión TCP en Apache proviene de la IP privada del balanceador (`10.0.1.20` o `10.0.2.20`), HAProxy inserta la cabecera HTTP `X-Forwarded-For` (`option forwardfor`). Apache la registra en `/var/log/apache2/xyz-access.log` mediante el `LogFormat` personalizado `xyz` del VirtualHost (`%h %{X-Forwarded-For}i …`, Fase 5), conservando la IP pública original del cliente (`186.87.10.152`) para auditoría.

### 4.4 Conectividad ICMP y aislamiento por Security Groups
- **Evidencia:** `evidencias/fase7/icmp-tcp-lb1.png` (y pruebas desde `xyz-wp1`).
- **Análisis:**
  - **ICMP (`ping`)** [21]**:** Desde `xyz-lb1` hacia `10.0.11.10` (`wp1`) y `10.0.12.10` (`wp2`) se obtiene 0 % de pérdida de paquetes con latencias promedio de `0.237 ms` (misma AZ `us-east-2a`) y `0.798 ms` (inter-AZ hacia `us-east-2b`). Desde `xyz-wp1` hacia `10.0.12.10`, `10.0.11.20` (`db`), `10.0.1.20` (`lb1`) y `1.1.1.1` (a través de `nat-a`), 0 % de pérdida (`1.968 ms` hacia Internet).
  - **TCP y aislamiento:** `lb1` conecta por TCP 80 a `wp1` y `wp2` (`http 200`), pero el intento TCP hacia `10.0.11.20:3306` (`db`) resulta `BLOQUEADO`, demostrando que `xyz-sg-db` solo admite conexiones provenientes de `xyz-sg-wp` y cumple el principio de mínimo privilegio entre capas.

### 4.5 Traducción de direcciones (NAT / PAT)
- **Evidencia:** `evidencias/fase2/n1-nat-a-tcpdump.png`, `n2-nat-a-conntrack.png`.
- **Análisis:** Documentado en detalle en las pruebas N1 y N2: traducción N:1 en `nftables` (`masquerade` + `conntrack`) de las subredes privadas `10.0.11.0/24` y `10.0.12.0/24` hacia las interfaces privadas de `nat-a` (`10.0.1.30`) y `nat-b` (`10.0.2.30`), seguida de traducción 1:1 en el Internet Gateway de AWS hacia sus IPs públicas.


## 5. Problemas encontrados y recomendaciones

*Tabla 25. 5. Problemas encontrados y recomendaciones.*

| # | Problema | Causa | Solución / lección |
|---|---|---|---|
| P1 | La cuenta no permitía crear recursos en us-east-1 | La cuenta se creó con la nueva experiencia de AWS (proyectos en settings.aws.com), que fija la región según el país de contacto (Colombia → us-east-2) mediante SCP gestionadas | Se rediseñó en us-east-2 (Ohio) |
| P2 | La cuota de vCPU On-Demand Standard (16) no alcanzaba para 9 × t3.micro (18) | Límite por defecto en una cuenta nueva | Se pidió aumento a 20 en Service Quotas; AWS lo aprobó el mismo día |
| P3 | En N3 y N4, los comandos de `sysctl`/`tcpdump` no surtían efecto | Las sesiones de SSM Session Manager entran como `ssm-user`, no como root | Anteponer `sudo` a los comandos administrativos |
| P4 | Durante N3, wp2 perdió Internet y la sesión SSM de forma indefinida | Se apagó `ip_forward` en nat-b y la sesión se cortó antes de ejecutar el comando que lo restauraba. La sesión SSM de wp2 también viaja por nat-b, así que se congeló | Se restauró `ip_forward=1` desde nat-b, cuya sesión SSM sale directo por el IGW y no depende del forwarding. Lección: las pruebas que cortan conectividad deben ejecutarse desacopladas de la sesión (`nohup`), restaurar el servicio solas y escribir sus resultados en disco (`/var/tmp`, que sobrevive a reinicios) |
| P5 | En N3, `timeout 15 tcpdump` no se detuvo a los 15 s dentro del bloque `sudo nohup bash -c … &`, así que el `sysctl -w net.ipv4.ip_forward=1` automático nunca se ejecutó y el corte duró unos 75 s | No se determinó la causa exacta (tcpdump ejecutado en segundo plano a través de sudo/nohup/timeout) | Se restauró el forwarding a mano y se detuvo tcpdump. Lección: en pruebas destructivas, restaurar con un mecanismo independiente de la captura (por ejemplo, `sleep 15; sysctl -w …=1` en un proceso aparte, o `tcpdump -G 15 -W 1`) y comprobar siempre el estado final |
| P6 | ns2 registraba `refused notify from non-primary: 3.131.134.77` justo después de cada transferencia | Tras un AXFR, un secundario notifica a los NS de la zona, excepto al MNAME del SOA y a sus propias direcciones. ns2 solo conoce su IP privada, no su EIP (la traduce el IGW), así que se notificaba a sí mismo por la EIP y luego rechazaba el aviso por no venir de 10.0.1.10 | `notify no;` en la zona secundaria. En el primario, `notify explicit` + `also-notify` hacia la IP privada. Lección: con NAT 1:1 (EIP) la instancia desconoce su IP pública, así que la comunicación interna entre servidores debe usar IPs privadas |
| P7 | `wp core download --locale=es_ES` fallaba con `The requested locale (es_ES) was not found` | Para la versión más reciente (7.1.5), la API de WordPress solo ofrecía el paquete completo en `en_US`, aunque el paquete de idioma `es_ES` sí existía | Descargar la versión base y luego `wp language core install es_ES --activate` en cada nodo (los `.mo` son locales; la opción `WPLANG` va en la DB). `DISALLOW_FILE_MODS` se limita al panel web para que WP-CLI pueda instalar el idioma |
| P8 | La franja del home mostraba `IPv4 privada 127.0.0.1` | La prueba local se conectaba a 127.0.0.1, y `SERVER_ADDR` es la dirección local de esa conexión | Si `SERVER_ADDR` es loopback, el mu-plugin obtiene la IP de la interfaz de salida con un socket UDP conectado a 10.0.0.2. Lección: la IP "del servidor" depende de por cuál interfaz llegó la conexión |
| P9 | `http://<EIP>:8404/stats` daba `ERR_CONNECTION_TIMED_OUT` aunque HAProxy escuchaba en `0.0.0.0:8404` y el puerto 80 respondía | El SG `xyz-sg-lb` solo permite el 8404 desde la IP pública del equipo (/32) y la regla no coincidía con la IP vigente (las IP públicas del equipo cambian). Un SG descarta sin responder, por eso se ve un timeout y no un `connection refused` | Se actualizó la regla con la IP actual. `curl -4 -m 5 -I http://<EIP>:8404/stats` debe responder `401 Unauthorized` (puerto abierto, falta autenticación). Lección: si cambia la red o la IP, hay que actualizar la regla; no se abrió el 8404 a 0.0.0.0/0 |

## 6. Conclusiones

1. **Es posible reemplazar los servicios de red gestionados de AWS por componentes propios** sobre EC2, con las 9 instancias exigidas: dos NAT con `nftables`, dos balanceadores HAProxy y dos servidores BIND9 sirven el sitio WordPress con redundancia en dos zonas de disponibilidad. El precio es más configuración y más responsabilidad operativa, por ejemplo deshabilitar *Source/Destination Check* o mantener las reglas de los Security Groups.
2. **El NAT de origen es asimétrico por diseño** (N1–N4): permite que las subredes privadas inicien conexiones hacia Internet gracias al estado de `conntrack`, e impide las conexiones entrantes no solicitadas. Junto con los Security Groups, la ausencia de IP pública y la cadena `forward` con política `drop`, forma una defensa en capas. Cada subred privada depende del NAT de su propia AZ: si falla ese NAT, como en N3, solo pierde salida esa mitad de la infraestructura.
3. **El DNS autoritativo propio funciona con delegación pública real**: los *glue records* rompen la dependencia circular de `ns1`/`ns2.xyzcosmetics.online`, el secundario se sincroniza por NOTIFY y transferencia de zona en milisegundos cuando sube el serial (D2), y sigue respondiendo con autoridad cuando cae el primario (D3).
4. **El DNS Round Robin reparte la carga, pero no da alta disponibilidad por sí solo** (D4–D5): BIND sigue anunciando la IP de un balanceador caído, y cerca de la mitad de las conexiones nuevas fallan mientras dure el TTL. HAProxy, en cambio, detecta la caída de un WordPress con *health checks* en segundos y la oculta por completo a los clientes (B2). Las dos técnicas se complementan: el DNS distribuye entre balanceadores y los balanceadores distribuyen y protegen el *backend*.
5. **Escalar horizontalmente la capa web exige sacar el estado de los nodos**: base de datos compartida, uploads por NFS, *salts* idénticos y código igual en ambos nodos (sin cambios desde el panel). Así cualquier nodo puede atender cualquier petición sin afinidad de sesión, y la franja con la IP privada lo demuestra en cada recarga (B1).
6. **La alta disponibilidad lograda cubre la presentación, no los datos**: `xyz-db` es un punto único de falla para todo el sitio. Es la principal limitación del diseño, y la primera mejora sería replicar la base de datos y el almacenamiento de archivos en la otra zona.
7. **Lecciones operativas**: con IP elásticas (NAT 1:1 en el IGW) las instancias no conocen su IP pública, así que la comunicación interna debe usar IPs privadas (problema P6). Las pruebas que cortan conectividad deben ejecutarse desacopladas de la sesión de administración (P4). SSM Session Manager permite administrar las 9 instancias sin exponer SSH ni usar un *bastion*.

Como trabajo futuro se recomienda: replicación de MariaDB y almacenamiento compartido redundante, **HTTPS** en los balanceadores (el sitio hoy solo sirve HTTP), firma DNSSEC de la zona, comprobaciones de salud externas que retiren del DNS un balanceador caído, y automatizar la infraestructura como código.

## 7. Referencias

[1] WordPress.org, "Advanced Administration Handbook," WordPress Developer Resources, 2026. [En línea]. Disponible: https://developer.wordpress.org/advanced-administration/

[2] Amazon Web Services, "Amazon Virtual Private Cloud User Guide," AWS Documentation, 2026. [En línea]. Disponible: https://docs.aws.amazon.com/vpc/latest/userguide/

[3] W. Tarreau, "HAProxy Configuration Manual (Version 3.2)," HAProxy Technologies, 2026. [En línea]. Disponible: https://docs.haproxy.org/

[4] Internet Systems Consortium (ISC), "BIND 9 Administrator Reference Manual," ISC Documentation, 2026. [En línea]. Disponible: https://bind9.readthedocs.io/

[5] P. Mockapetris, "Domain Names - Concepts and Facilities," Internet Engineering Task Force (IETF), RFC 1034, Nov. 1987. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc1034

[6] P. Mockapetris, "Domain Names - Implementation and Specification," Internet Engineering Task Force (IETF), RFC 1035, Nov. 1987. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc1035

[7] Y. Rekhter, B. Moskowitz, D. Karrenberg, G. J. de Groot y E. Lear, "Address Allocation for Private Internets," Internet Engineering Task Force (IETF), RFC 1918, Feb. 1996. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc1918

[8] Canonical Ltd., "Ubuntu Server documentation," 2026. [En línea]. Disponible: https://documentation.ubuntu.com/server/

[9] Amazon Web Services, "AWS Systems Manager Session Manager," AWS Systems Manager User Guide, 2026. [En línea]. Disponible: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html

[10] J. Postel, "Internet Protocol," Internet Engineering Task Force (IETF), RFC 791, Sep. 1981. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc791

[11] The Netfilter Project, "nftables wiki," 2026. [En línea]. Disponible: https://wiki.nftables.org/

[12] P. Srisuresh y M. Holdrege, "IP Network Address Translator (NAT) Terminology and Considerations," Internet Engineering Task Force (IETF), RFC 2663, Ago. 1999. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc2663

[13] E. Lewis y A. Hoenes, "DNS Zone Transfer Protocol (AXFR)," Internet Engineering Task Force (IETF), RFC 5936, Jun. 2010. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc5936

[14] P. Vixie, "A Mechanism for Prompt Notification of Zone Changes (DNS NOTIFY)," Internet Engineering Task Force (IETF), RFC 1996, Ago. 1996. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc1996

[15] MariaDB Foundation, "MariaDB Server Documentation," 2026. [En línea]. Disponible: https://mariadb.com/kb/en/documentation/

[16] T. Haynes y D. Noveck, "Network File System (NFS) Version 4 Protocol," Internet Engineering Task Force (IETF), RFC 7530, Mar. 2015. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc7530

[17] WP-CLI, "WP-CLI Commands," WordPress Developer Resources, 2026. [En línea]. Disponible: https://developer.wordpress.org/cli/commands/

[18] W. Eddy, Ed., "Transmission Control Protocol (TCP)," Internet Engineering Task Force (IETF), RFC 9293, Ago. 2022. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc9293

[19] R. Fielding, M. Nottingham y J. Reschke, Eds., "HTTP Semantics," Internet Engineering Task Force (IETF), RFC 9110, Jun. 2022. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc9110

[20] R. Fielding, M. Nottingham y J. Reschke, Eds., "HTTP/1.1," Internet Engineering Task Force (IETF), RFC 9112, Jun. 2022. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc9112

[21] J. Postel, "Internet Control Message Protocol," Internet Engineering Task Force (IETF), RFC 792, Sep. 1981. [En línea]. Disponible: https://www.rfc-editor.org/rfc/rfc792
