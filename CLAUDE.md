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

## Gotcha: server_default con string plano en SQLAlchemy (bug real, 2026-07-07)

NUNCA usar `server_default="now()"` (string Python plano) para expresiones SQL
en mapped_column. SQLAlchemy puede grabarlo en el DDL como un valor LITERAL
congelado (la hora exacta en que corrió la migración), no como la función
now() real — Postgres queda con `DEFAULT '2026-07-07 22:41:32...'::timestamp`
en vez de `DEFAULT now()`. Efecto: todas las filas insertadas después
comparten el mismo timestamp fijo, para siempre, hasta corregir el DEFAULT.

Correcto: `server_default=text("now()")` (requiere `from sqlalchemy import text`).

Se detectó porque los audit_logs de una prueba real (grant/revoke consentimiento
con ~4 min de diferencia real) mostraban el mismo created_at en las 3 filas.
Afectó 8 columnas en 8 tablas (todos los created_at/granted_at del proyecto).
Fix: migración 7933b4efe343 (ALTER COLUMN ... SET DEFAULT now() en las 8) +
corrección del modelo. Los valores ya insertados con el bug quedan mal para
siempre (eran datos de prueba, sin impacto real) — el fix es solo hacia adelante.

Regla general: cualquier server_default/server_onupdate que sea una expresión
SQL (no un literal string/número real) debe ir envuelto en text().

## Decisión: adaptadores de dispositivos sin hardware real (2026-07-08)

Mód. 8 (relojes marcadores) se construyó con alcance dividido a propósito:
inventario de dispositivos (`Device`) 100% real e implementado, pero la capa
de comunicación (`DeviceAdapter` — heartbeat, sync biométrico, firmware) NO
se implementó, porque no hay un Tiandy/Hikvision/ZKTeco físico accesible en
red para probarla de verdad. Implementar esa capa sin hardware real violaría
la regla "cero mock" (no simular respuestas de algo que no existe).

Cada adaptador (`app/modules/devices/adapters/{tiandy,hikvision,zkteco}.py`)
levanta `NotImplementedError` explícito en sus 3 métodos. Cuando haya un
dispositivo físico disponible (empezando probablemente por un ZKTeco
SenseFace 4A, specs ya cargadas en el modelo `Device`), implementar el
adaptador correspondiente contra el SDK real del fabricante (ZKBio para
ZKTeco) y probarlo end-to-end antes de marcarlo como completo.

Esto mismo aplica en cascada a mód. 10 (enrolamiento biométrico) y mód. 12
(marcación): su modelo de datos y flujo de negocio se pueden construir y
probar, pero la comunicación real con el dispositivo queda con la misma
limitación hasta tener hardware de prueba.

## Decisión: PDF de contrato con cláusulas de referencia, pendiente revisión legal (2026-07-08)

Mód. 9 genera un PDF real bilingüe (ES/EN) del contrato de trabajo con datos
reales del empleado (`app/core/contracts_pdf.py`, reportlab). Las cláusulas
generales (jornada, aguinaldo, vacaciones) son un modelo de referencia basado
en elementos comunes del Código de Trabajo de Costa Rica — NO son asesoría
legal. Mismo tratamiento que el motor de renta: pendiente de revisión por un
abogado laboral antes de usarse como contrato oficial con un cliente real. El
aviso queda impreso en el propio documento generado.

## Excepción explícita a "cero mock": captura biométrica del mód. 10 (2026-07-08)

Único mock autorizado en el proyecto hasta ahora, y por decisión explícita
del usuario, no por defecto. Mód. 10 (enrolamiento biométrico) simula
únicamente la CAPTURA del dato biométrico (no hay hardware Tiandy/Hikvision/
ZKTeco real conectado — ver mód. 8). Todo lo demás en mód. 10 es real:
validación de consentimiento vigente, validación de sucursal, validación de
capacidad del dispositivo, auditoría.

Cómo identificar el mock en código y datos: `BiometricEnrollment.is_simulated`
(siempre `true` hoy), `template_reference` con prefijo literal `SIMULATED-`,
y el audit log de `biometric_enrollment.created` incluye `is_simulated: true`
en su `extra`. Nunca remover ese prefijo/flag ni mezclar con datos reales.

Cuándo reemplazar: cuando exista un dispositivo físico accesible (ver
decisión de mód. 8 en este mismo archivo) y su `DeviceAdapter` esté
implementado de verdad. En ese momento, `is_simulated` debe pasar a `false`
para los enrolamientos hechos contra hardware real, y el mock deja de usarse
salvo que se pida explícitamente de nuevo para demos.

## Patrón: feature flags con default por categoría (2026-07-08)

Mód. 11 agrega `FeatureFlag` (catálogo público, sin RLS, igual que
`tenants`) y `TenantFeatureFlag` (override con RLS, opcionalmente por
sucursal vía `branch_id` nullable). Regla de default cuando NO hay fila de
override: `category='core'` → habilitado, cualquier otra categoría
(`addon`/`premium`) → deshabilitado. Resolución de precedencia: override de
sucursal > override de tenant > default por categoría — ver
`core/feature_flags.py: is_feature_enabled()`.

Cualquier módulo futuro que necesite gatear una funcionalidad por plan debe
usar ese helper en vez de reimplementar la lógica. El seed inicial de
`feature_flags` reflejó los módulos ya construidos y probados (no son
placeholders) — agregar una fila nueva al catálogo (vía migración) cada vez
que un módulo nuevo llegue a un punto demostrable.

## Corrección de orden: mód. 12 antes que 17a (2026-07-08)

El plan original (WORKFORCE_AI_OS_PROYECTO.md sección 5.3) ponía el mód.
17a (Motor de Confianza Operativa™ heurístico) antes que el mód. 12
(control de acceso/marcación). Al llegar a construirlo se detectó que las
reglas del 17a (marcaciones duplicadas, patrones imposibles, ausencia de
biometría en marcaciones críticas) necesitan datos reales de
`AttendanceRecord`, tabla que crea justamente el mód. 12. Se invirtió el
orden: 12 primero (ya completo y verificado), 17a evalúa sus reglas sobre
esas marcaciones reales.

Lección general: al llegar a un módulo, verificar si sus reglas/lógica
dependen de datos que otro módulo posterior en el orden todavía no genera
— no asumir que el orden del plan original es siempre el correcto una vez
que se conoce el detalle real de implementación.

## Bug de Alembic: constraints agregados a mano no declarados en el modelo (2026-07-08)

Cuando se agrega un constraint (UniqueConstraint, CheckConstraint, etc.) a
mano dentro de una migración (op.execute o sa.UniqueConstraint directo en
create_table) SIN declararlo también en el modelo SQLAlchemy correspondiente
(__table_args__), la PRÓXIMA vez que corras `alembic revision --autogenerate`
Alembic va a comparar el estado real de la BD contra los metadatos del
modelo, ver ese constraint como "no debería existir" (porque el modelo no
lo menciona), y proponer un `op.drop_constraint(...)` para borrarlo.

Pasó con `uq_attendance_device_employee_recorded_at` (mód. 12): se agregó
en la migración de attendance_records pero no en `AttendanceRecord.__table_args__`,
y la siguiente migración (mód. 17a) casi lo borra automáticamente. Se
detectó revisando el contenido generado ANTES de aplicar — como con todo
en este proyecto, nunca correr `alembic upgrade head` a ciegas sin mirar
qué generó `--autogenerate` primero.

Regla: cualquier constraint agregado a mano en una migración debe
reflejarse también en `__table_args__` del modelo, en el mismo commit.


## Migraciones: el contenedor `api` no ve cambios de host hasta hacer rebuild (2026-07-08)

`alembic revision --autogenerate` corre DENTRO del contenedor `api`, contra
la imagen ya construida — no contra los archivos del host en tiempo real
(el Dockerfile hace `COPY . .` en build time, no hay bind mount). Si
editás `models.py` en el host y corrés `docker compose exec api alembic
revision --autogenerate` sin reconstruir antes, Alembic compara los
metadatos de un `models.py` viejo contra la base de datos real y genera
una migración vacía (`pass` en `upgrade()`) sin ningún error visible que
lo delate — hay que revisar el contenido generado para notarlo.

Pasó en mód. 14: se generó una migración vacía para `TimeException` porque
el contenedor corría con la imagen de antes del cambio. Se detectó
revisando el archivo antes de aplicar (regla ya establecida), se borró la
revisión vacía (host + contenedor) para no dejar un hueco en la cadena, se
corrió `docker compose build --no-cache api && docker compose up -d api`,
y recién ahí se regeneró correctamente.

Regla: después de editar `models.py` (o cualquier código del backend),
reconstruir la imagen (`docker compose build --no-cache api && docker
compose up -d api`) ANTES de correr `alembic revision --autogenerate` — no
alcanza con guardar el archivo en el host.


## Estandar de pantallas con listado (obligatorio)

Toda pantalla nueva que liste datos por empleado y/o sucursal (empleados,
marcacion, excepciones, confianza operativa, dispositivos, reportes, etc.)
debe cumplir, sin excepcion, dado que el sistema opera a escala de ~1400
empleados en 54+ sucursales:

1. Busqueda de texto libre (nombre, codigo, lo que aplique).
2. Filtro por sucursal (dropdown poblado desde /api/branches) cuando los
   registros se puedan asociar a una sucursal via employee.branch_id.
3. Toast de exito/error en toda accion de creacion/edicion/eliminacion,
   usando el hook useToast (lib/toast.js) - nunca solo un estado local.
4. Autorefresh: recargar la lista (load()/loadX()) despues de cualquier
   mutacion exitosa - nunca dejar que el usuario tenga que refrescar
   manualmente.
5. Estados de carga y vacio (LoadingState / EmptyState de lib/ui.js).
6. Acciones de escritura ocultas/deshabilitadas segun permisos reales
   (hasPermission de lib/permissions.js), nunca visibles a todos.

Antes de dar por cerrada una pantalla nueva, correr:
  bash scripts/audit_ui_standards.sh
y revisar que no falte ninguno de los 6 puntos.
