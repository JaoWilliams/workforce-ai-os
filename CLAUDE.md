# WORKFORCE AI OS — CLAUDE.md

> Fuente de contexto para Claude Code en este proyecto — refleja el estado del
> WORKFORCE_AI_OS_PROYECTO.md (documento maestro, 9/9 bloqueantes resueltos, aprobado).

## Qué es este proyecto

WORKFORCE AI OS — plataforma de gestión de fuerza laboral con evidencia biométrica,
motor de excepciones y Motor de Confianza Operativa™ (detección de fraude/empleados
fantasma). 26 módulos, MVP reducido primero (ver sección MVP más abajo).

## Estándares no negociables

- Full PWA — instalable en Windows/macOS/iPad/iPhone/Android
- Full Bilingüe — i18n real (ES/EN) desde el primer commit
- Full Multimoneda — default CRC, extensible (USD, GTQ, HNL, NIO, PAB)
- Cero hardcode — todo parametrizable vía catálogos/config
- Cero mock — nada de datos falsos en producción
- Base de datos: PostgreSQL nativo — NO Supabase
- NO se usa Lovable.dev en este proyecto (excepción explícita a las preferencias
  generales del usuario, que sí usa Lovable/Supabase en otros proyectos — ese
  estándar NO aplica acá)

## Stack técnico

- Backend: FastAPI (Python)
- Frontend: Next.js (React), PWA vía next-pwa
- Base de datos: PostgreSQL nativo (contenedor Docker)
- Cache/colas: Redis (contenedor Docker)
- Orquestación: Docker Compose (no K8s)
- Reverse proxy: Traefik, nuevo e independiente
- Exposición pública: Cloudflare Tunnel (cloudflared) — NO bind directo a 80/443

## Infraestructura del servidor compartido (SOLO PARA EL MVP)

- Servidor: root@178.104.93.178 — Ubuntu 24.04.4 LTS, Hestia CP instalado
- Regla dura: nunca tocar vía panel.williamshosting.com
- Repo A cvg-autotech (otro proyecto, en producción, NO se toca): Postgres Docker
  en puerto host 5433 (cvg-postgres), Redis Docker en puerto host 6380 (cvg-redis)
  — puertos ya ocupados, no usarlos.
- Repo B: otro proyecto en Docker Compose — patrón de referencia, no se toca.
- WORKFORCE AI OS es un repo nuevo, ubicado en /opt/workforce-ai-os, sin relación
  de código con los anteriores.
- Repo: https://github.com/JaoWilliams/workforce-ai-os (privado)
- **Este servidor compartido es SOLO para el MVP** (mods. 1-11 + 17a). Apenas se
  valida el checkpoint MVP con las empresas piloto, antes de seguir con F3,
  WORKFORCE AI OS migra completo a un servidor Hetzner nuevo y dedicado.
  Monitorear `df -h` / `docker system df` durante Sprint 0-F2.

### Puertos asignados a WORKFORCE AI OS (confirmados libres vía ss -tulpn)

- Postgres: 5434 (host) → 5432 (contenedor)
- Redis: 6381 (host) → 6379 (contenedor)
- 80/443: no aplican — todo el tráfico público entra vía Cloudflare Tunnel

### Despliegue

100% Docker Compose. Reinicio: `docker compose build --no-cache && docker compose up -d`.
Nunca `systemctl` en este proyecto.

### Dominio

- Temporal: Cloudflare Tunnel modo rápido (`cloudflared tunnel --url`) → URL efímera *.trycloudflare.com
- NO usar cvgelectronics.com (ni por subdominio) — es la zona DNS de producción de cvg-autotech.
- Dominio dedicado real: pendiente, sin urgencia.

## Arquitectura de datos

### Multi-tenant

Row-based: tablas compartidas con columna tenant_id + Row-Level Security (RLS) de
PostgreSQL como capa de aislamiento forzada a nivel de base de datos. Toda query
pasa por una sesión con el tenant_id seteado antes de cada query. Cada tabla con
datos de tenant necesita su política RLS desde que se crea.

### Modelo de conceptos (catálogo maestro de nómina, mód. 6)

Cada concepto de nómina se parametriza en 3 dimensiones:
1. Método de cálculo: monto fijo | porcentaje | cantidad
2. Naturaleza: ingreso | deducción
3. Origen: patronal | del empleado

Ejemplo: aguinaldo = provisión contable, método porcentaje, naturaleza ingreso, origen patronal.

### Motor de renta (mód. 23) — mecánica confirmada

- Base de cálculo: salario bruto
- Créditos: monto fijo por cónyuge + monto fijo por cada hijo menor de 25 años cumplidos
- Primera quincena: tabla mensual de tramos dividida entre 2, IR sobre el bruto de esa quincena
- Segunda quincena: se suman los brutos de ambas quincenas, se calcula el IR real del
  mes con la tabla completa, se resta lo retenido en la primera quincena. Si el
  resultado es negativo, devolución de renta al colaborador en esa misma quincena.
- Aguinaldo excluido del cálculo de renta (no es ingreso gravable)
- Tramos, tasas y montos de crédito son datos de catálogo — valores exactos vigentes
  de Hacienda se cargan al construir este módulo.

### Offline / dispositivos biométricos

Tiandy, Hikvision y ZKTeco ya bufferizan marcaciones localmente cuando se cae la red.
No construir una cola custom desde cero — el backend reconcilia al reconectar,
sincronizando por rango de timestamp con clave única dispositivo+timestamp+empleado.

Seguridad: el dispositivo nunca se expone directo a internet — toda gestión pasa
por el backend propio, con su propia autenticación.

## MVP (checkpoint reducido)

- Marcación + evidencia biométrica (mód. 8, 9, 10, 12)
- Panel básico de excepciones (parte del mód. 14)
- Motor de Confianza Operativa™ versión heurística (mód. 17a — reglas: marcaciones
  duplicadas, patrones imposibles, ausencia de biometría en marcaciones críticas)
- Calendario dual completo y nómina avanzada quedan fuera del MVP

## Modelo de ejecución

Usuario + Claude Code — no el equipo de ~10 roles del cronograma original. Ese
cronograma es referencia de planificación, no fecha comprometida.

## Fuente de verdad

El documento completo vive en docs/WORKFORCE_AI_OS_PROYECTO.md. Ante cualquier
duda o conflicto, ese documento manda sobre cualquier suposición.
