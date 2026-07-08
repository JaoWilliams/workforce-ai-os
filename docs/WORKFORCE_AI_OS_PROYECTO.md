# WORKFORCE AI OS — Documento Maestro del Proyecto

**Estado: DOCUMENTO APROBADO Y COMPLETO · 9/9 bloqueantes resueltos · listo para iniciar Sprint 0**
**Bloqueantes para Sprint 1: 9/9 resueltos** 🟢🟢🟢🟢🟢🟢🟢🟢🟢
Última actualización: todos los bloqueantes de la sección 5.1 quedaron resueltos. Los pendientes técnicos no bloqueantes de la sección 5.2 siguen abiertos (se resuelven antes de sus módulos correspondientes, no antes de arrancar).

---

## 0. Registro de cambios (esta actualización)

- ✅ **Método de renta (mód. 23) — RESUELTO. Último bloqueante cerrado, documento 9/9.** Validado por vos (pendiente de tu contador para los valores exactos de tabla vigente, pero la mecánica queda confirmada):
  - **Créditos:** monto fijo por cónyuge + monto fijo por cada hijo menor de 25 años cumplidos.
  - **Base de cálculo:** salario bruto.
  - **Mecánica quincenal (refinada):** la tabla mensual de tramos se **divide entre 2** para calcular la retención de la primera quincena. En la segunda quincena se suman los ingresos brutos de ambas quincenas, se calcula el IR real del mes con la tabla mensual completa, se resta lo ya retenido en la primera quincena, y si el resultado es negativo se hace **devolución de renta** al colaborador en esa misma quincena.
  - **Aguinaldo:** confirmado como provisión contable, calculada por **%** igual que las demás provisiones — no es un monto fijo.
  - **Modelo general de conceptos (aplica a mód. 6 y a todo el motor de nómina):** cada concepto es parametrizable en 3 dimensiones — método de cálculo (**monto fijo | porcentaje | cantidad**), naturaleza (**ingreso | deducción**) y origen (**patronal | del empleado**). Esto refuerza el estándar "cero hardcode" ya declarado en la sección 2, ahora con la estructura concreta de datos que necesita el catálogo.
  - **Pendiente no bloqueante:** los valores exactos de la tabla de tramos, tasas y montos de crédito vigentes de Hacienda se cargan como datos de catálogo cuando se construya el módulo 6/23 — no es necesario tenerlos en este documento.
- ✅ **Los 3 bloqueantes estratégicos — RESUELTOS.** Multi-tenant, offline y modelo de equipo, ver detalle en sección 4 y 5.1. Contador pasó de 5/9 a **8/9 resueltos** — solo falta la validación contable de renta.
- ⚠️ **Nota de realismo de cronograma:** el modelo de equipo elegido es vos + asistencia de IA (Claude Code), no el equipo de ~10 roles que asume el cronograma de 62 semanas del documento original. Las horas/semanas de la sección 6 siguen como referencia de planificación de un equipo completo — no como compromiso de fecha. Se recomienda recalibrar el cronograma con datos reales de velocidad después de las primeras 2-3 semanas de Sprint 0/1 ejecutando con este modelo, en vez de asumir de entrada que se sostiene el ritmo original.
- ✅ **Puertos — RESUELTO.** Verificado en el servidor (`ss -tulpn`): **5433 y 6379 NO estaban libres** (5433 ocupado por `cvg-postgres` de cvg-autotech; 6379 ocupado por un `redis-server` nativo del host; 6380 también tomado por `cvg-redis`). Decisión: WORKFORCE AI OS usa **5434** (Postgres) y **6381** (Redis) — confirmados libres. Bueno haberlo verificado antes: con los puertos originales, `docker compose up` habría fallado el primer día.
- Contador pasó de 4/9 a **5/9 resueltos**.
- ✅ **Repo GitHub — RESUELTO.** `workforce-ai-os` confirmado: https://github.com/JaoWilliams/workforce-ai-os
- ✅ **Confirmado explícitamente: NO usar `cvgelectronics.com`** (ni siquiera por subdominio) para WORKFORCE AI OS, aunque ya está en tu cuenta de Cloudflare y tenés Namecheap disponible. Es la zona DNS de producción de cvg-autotech (correo Zoho, `facturas.`/`pagos.` con SPF activo) — mezclar marca y zona con un SaaS nuevo que se va a vender a otras empresas no conviene. Dominio dedicado nuevo queda como decisión abierta, sin urgencia.
- ✅ **Dominio temporal — RESUELTO.** Se descarta `sslip.io` (expone la IP literalmente en el nombre). Decisión: **Cloudflare Tunnel** (`cloudflared`) — arranca con el modo rápido `cloudflared tunnel --url` (URL efímera `*.trycloudflare.com`, sin cuenta ni dominio) y migra a túnel nombrado/persistente cuando se confirme el dominio real. Ningún puerto público 80/443 queda expuesto y la IP del Hetzner no aparece en ningún registro DNS.
- **Bonus:** esta decisión reduce el bloqueante de "puertos libres" — Traefik no necesita bind público a 80/443 si el tráfico entra vía túnel saliente, así que no compite con lo que Hestia ya ocupe ahí.
- Contador pasó de 2/9 a **3/9 resueltos**.

*(Cambios de actualizaciones anteriores, ya incorporados: aprobación final del documento, MVP reducido, Motor de Confianza Operativa™ heurístico adelantado a F1/F2, 3 bloqueantes estratégicos nuevos, subsección 5.2 de pendientes no bloqueantes.)*

---

## 1. Qué es este proyecto

WORKFORCE AI OS — plataforma de gestión de fuerza laboral con evidencia biométrica, motor de excepciones y Motor de Confianza Operativa™. Desarrollado por TechSupport. Basado en el Plan de Desarrollo v4/v5 (25 módulos) y el Master Product Blueprint (visión, E³ Framework, arquitectura de 9 pilares).

---

## 2. Estándares no negociables (aplican a todo el proyecto, sin excepción)

- **Full PWA** — instalable en Windows/macOS/iPad/iPhone/Android
- **Full Bilingüe** — i18n real (ES/EN) desde el primer commit, no agregado después
- **Full Multimoneda** — default CRC, extensible (USD, GTQ, HNL, NIO, PAB)
- **Cero hardcode** — todo parametrizable vía catálogos/config
- **Cero mock** — nada de datos falsos en producción
- **Base de datos: PostgreSQL nativo** — NO Supabase
- **NO se usa Lovable.dev en este proyecto** — excepción explícita: tus preferencias generales guardadas (Lovable/React-vía-Lovable/Supabase) aplican a *otros* proyectos tuyos, no a este. Esa distinción ya quedó registrada solo para esta conversación.

---

## 3. Infraestructura existente en el servidor — CONTEXTO, no parte de este proyecto

- **Servidor:** `root@178.104.93.178` — Ubuntu 24.04.4 LTS
- Tiene Hestia CP instalado. **Regla dura: nunca tocar vía `panel.williamshosting.com`.**

**Repo A — `cvg-autotech`** (otro proyecto, ya en producción, no se toca):
- FastAPI + Next.js, corriendo **fuera de Docker**
- Backend: `systemctl restart cvg-backend.service` — `WorkingDirectory=/opt/cvg-autotech/backend`
- Frontend: obligatorio `npm run build` antes de `systemctl restart cvg-frontend.service` — `WorkingDirectory=/opt/cvg-autotech/apps/web`
- Base de datos vía `Base.metadata.create_all()` — **sin Alembic** → columnas nuevas requieren `ALTER TABLE` manual
- **Confirmado: no tiene repositorio git** (`fatal: not a git repository` en ambos paths)

**Repo B** — otro proyecto ya en Docker Compose (contenedores: api, worker, postgres, redis, frontend). Reinicio: `docker compose build --no-cache && docker compose up -d`. Nunca `systemctl` aquí. Sirve como patrón de referencia probado en este mismo servidor, nada más.

**Confirmado explícitamente:** WORKFORCE AI OS es un repositorio **nuevo**, sin relación de código con ninguno de los dos anteriores. Lo de arriba es solo para no chocar con lo que ya vive en ese servidor (puertos, nombres de contenedor, mecanismos de despliegue).

---

## 4. Decisiones ya tomadas para WORKFORCE AI OS 🟢

| Decisión | Elegido | Por qué |
|---|---|---|
| Estructura de repo 🟢 | **Monorepo** | El propio plan técnico lo pide; evita PRs cruzados backend/frontend |
| Orquestación 🟢 | **Docker Compose** (no K8s) | Un solo servidor, sin clúster — K8s no da beneficio real aún. Revisar en Fase 4 (expansión regional) si hay multi-servidor |
| Reverse proxy 🟢 | **Traefik**, nuevo e independiente | Auto-descubre contenedores por labels, gestiona TLS solo, aislado de todo lo demás en el servidor |
| Git host 🟢 | **GitHub**, repo privado `workforce-ai-os` | Gratis para privados, integración directa con GitHub Actions para CI/CD, el más usado si se suma más gente al equipo |
| Marcas de reloj marcador 🟢 | **Tiandy + Hikvision + ZKTeco**, vía adaptador propio por marca (mód. 8) | Las tres más usadas en control de acceso/asistencia biométrica en la región; agregar una cuarta marca es un adaptador más, no reescribir el módulo |
| **Alcance del MVP 🟢 (NUEVO)** | **MVP reducido**: marcación + evidencia biométrica + panel básico de excepciones + Motor de Confianza Operativa™ (versión heurística) — se deja el calendario dual completo y catálogos avanzados de nómina para después del piloto | Validar mercado y el diferenciador real (detección de fraude) en meses, no esperar ~15 meses de catálogos avanzados antes de tener feedback de una empresa real |
| **Priorización del Motor de Confianza Operativa™ 🟢 (NUEVO)** | Versión **heurística** (reglas: marcaciones duplicadas, patrones imposibles, ausencia de biometría en marcaciones críticas) se adelanta a F1/F2, disponible para el checkpoint MVP. Versión **ML completa** se mantiene en F5 | Es el WoW factor real de venta — "detectamos fraude de nómina desde el primer mes" convierte pilotos mejor que "control de asistencia con huella", que es commodity |
| **Modelo multi-tenant en Postgres 🟢 (NUEVO)** | **Row-based**: una tabla compartida por entidad con `tenant_id` + **Row-Level Security** de Postgres como capa de aislamiento forzada a nivel de base de datos | Una sola migración por cambio en vez de una por schema/tenant. RLS da aislamiento real (no solo filtro en el código de la app), con mucha menos carga operativa para un equipo chico |
| **Estrategia offline de marcadores 🟢 (NUEVO)** | **Buffer nativo del dispositivo** (Tiandy/Hikvision/ZKTeco ya guardan marcaciones localmente sin red) + **reconciliación desde el backend** al reconectar, con clave única dispositivo+timestamp+empleado para evitar duplicados | Aprovecha algo que el hardware ya resuelve en vez de reinventar una cola de encolado/reintento propia |
| **Modelo de ejecución del equipo 🟢 (NUEVO)** | **Vos + asistencia de IA** (Claude Code) — no el equipo de ~10 roles especializados que asume el cronograma original | Es como trabajás siempre; el diferencial ahora es la velocidad con Claude Code. **Importante:** el cronograma de 62 semanas de la sección 6 sigue siendo la referencia de un equipo completo, no una fecha comprometida — se recalibra con datos reales después de las primeras semanas |
| **Stack técnico 🟢 (NUEVO)** | **Backend: FastAPI (Python)** · **Frontend: Next.js (React)** | Mismo patrón que `cvg-autotech` — aprovechás experiencia ya construida en ese stack. FastAPI tiene el mejor ecosistema para el ML del Motor de Confianza Operativa™ (mód. 17/18). Next.js da soporte PWA vía `next-pwa` y SSR para el dashboard ejecutivo (mód. 19) |
| **Alcance del servidor compartido / migración 🟢 (ACTUALIZADO)** | En el servidor Hetzner actual (compartido con cvg-autotech, Repo B, chatwoot) **solo se despliega el MVP** de WORKFORCE AI OS (mods. 1-11 + 17a). Apenas se valida el checkpoint MVP con las empresas piloto, **antes de seguir con F3 en adelante**, se migra todo el proyecto a un **servidor Hetzner nuevo, dedicado exclusivamente a WORKFORCE AI OS** | El servidor actual (38GB disco, 20GB libres) ya sostiene 4 stacks. Es más limpio migrar apenas se valida el MVP (mientras el proyecto todavía es chico) que esperar a F5 con ML y biometría real de varias empresas ya acumulada — evita tener que migrar datos de producción en caliente |

*(Dominio y puertos libres todavía NO están aquí — están abajo, en Pendientes, hasta que se confirmen)*

---

## 5. Bloqueantes para iniciar Sprint 1

### 5.1 Bloqueantes originales + estratégicos (deben resolverse antes de Sprint 1)

**Infraestructura (heredados de Sprint 0):**
- 🟢 **RESUELTO** — Repo `workforce-ai-os` en GitHub: https://github.com/JaoWilliams/workforce-ai-os
- 🟢 **RESUELTO** — Puertos: 5433 y 6379 estaban ocupados (cvg-postgres y redis-server nativo del host). WORKFORCE AI OS usa **5434** (Postgres) y **6381** (Redis), confirmados libres vía `ss -tulpn`. 80/443 no aplican (Cloudflare Tunnel)
- 🟢 **RESUELTO** — Dominio temporal: **Cloudflare Tunnel** (no `sslip.io`) — modo rápido `trycloudflare.com` ahora, migración a túnel nombrado cuando se confirme dominio real (el dominio real en sí sigue abierto, pero ya no bloquea: el proyecto puede arrancar sin él). **Decisión explícita:** NO se usa `cvgelectronics.com` (zona de producción de cvg-autotech, con correo/facturación activos) ni por subdominio — WORKFORCE AI OS necesita marca e identidad DNS propia de cara a clientes piloto. Dominio real dedicado (vía Namecheap → Cloudflare) queda pendiente para más adelante, sin bloquear Sprint 0/1

**Datos maestros / decisiones de negocio:**
- 🟢 **RESUELTO** — Marca/modelo real del reloj marcador: **Tiandy + Hikvision + ZKTeco**, vía adaptador propio por marca (mód. 8)
- 🟢 **RESUELTO** — Método de acumulado quincenal de renta (mód. 23): tabla mensual dividida entre 2 en la primera quincena, reconciliación real en la segunda quincena con devolución si aplica. Ver detalle completo en sección 0 y en la fila del módulo 23 (sección 6.1)

**Estratégicos (identificados en revisión):**
- 🟢 **RESUELTO** — Modelo multi-tenant en PostgreSQL: **row-based** con `tenant_id` + Row-Level Security (ver sección 4)
- 🟢 **RESUELTO** — Estrategia offline de marcadores: **buffer nativo del dispositivo + reconciliación desde el backend al reconectar** (ver sección 4)
- 🟢 **RESUELTO** — Modelo de ejecución del equipo: **vos + asistencia de IA (Claude Code)**. Cronograma de 62 semanas queda como referencia de equipo completo, a recalibrar con velocidad real (ver nota en sección 0 y sección 4)

- 🟢 **RESUELTO** — Aprobación final de este documento completo (26 módulos, 8 fases, con las decisiones nuevas incorporadas)

### 5.2 Pendientes técnicos no bloqueantes (no detienen Sprint 1, pero resolver antes del módulo correspondiente)

- 🟡 **Antes del mód. 22 (DevOps)** — Pila de observabilidad: sugerido Prometheus + Grafana + Loki sobre el mismo Docker Compose, dado que es servidor propio sin red de seguridad de un PaaS gestionado
- 🟡 **Antes del mód. 10 (enrolamiento biométrico)** — Capacidad de cómputo para reconocimiento facial: ¿corre en el mismo Hetzner o en un servicio aparte? Definir techo estimado de empresas/dispositivos concurrentes antes de que el primer cliente piloto grande lo exija
- 🟡 **Antes del mód. 1 (infraestructura base)** — Estrategia de backup y recuperación ante desastres: frecuencia, retención y prueba de restauración, dado que un único servidor sin clúster va a alojar nómina y biometría de múltiples empresas
- 🟡 **Inmediatamente después del checkpoint MVP, antes de F3** — Migrar WORKFORCE AI OS a servidor Hetzner nuevo y dedicado (decisión confirmada en sección 4). En el servidor compartido actual **solo se despliega el MVP**, nada más. Monitorear disco (`df -h` / `docker system df`) durante Sprint 0-F2 para llegar con margen — al 07/07/2026 había 20GB libres de 38GB en el servidor compartido. **Nuevo dato (07/07/2026):** el servidor es chico (2 vCPU, 3.7GB RAM) y ya tenía **swap al 75% usado (1.5GB/2GB)** antes de sumar WORKFORCE — presión de memoria preexistente por Hestia (correo/DNS/panel) + chatwoot + cvg-autotech, no por nuestro stack (que pesa ~178MB). No es urgente hoy, pero refuerza no demorar la migración planeada

- 🟡 **Antes de uso oficial de contratos (mód. 9)** — El PDF de contrato de trabajo (bilingüe, generado con datos reales) usa cláusulas de referencia general del Código de Trabajo de Costa Rica. Igual que el motor de renta (fila anterior), necesita revisión de un abogado laboral antes de usarse como contrato real con un cliente piloto — el aviso ya queda impreso en el propio PDF

⏸️ **Sprint 0 (scaffold) y Sprint 1 (mód. 1 en adelante) quedan en pausa hasta resolver lo anterior.**

---

## 5.3 Progreso real de implementación (se actualiza a medida que se construye)

**Ya construido y verificado en el servidor (rama `main`, repo `workforce-ai-os`):**
- 🟢 Infraestructura base — Docker Compose, Postgres 5434, Redis 6381, Traefik (ruteo por archivo estático), Cloudflare Tunnel (`https://watershed-bloggers-karen-presentations.trycloudflare.com`)
- 🟢 Mód. 1 (parte DB) — Alembic configurado, modelo multi-tenant row-based + RLS **verificado con prueba real** (dos tenants, mismo email, aislamiento confirmado). Rol `workforce_app` sin bypass de RLS (fix crítico — `workforce` es superuser y RLS nunca se aplicaba)
- 🟢 Mód. 2 (parte auth) — JWT, login por `tenant_slug` + email + password, registro, endpoint `/api/auth/me` protegido
- 🟢 Mód. 2 (RBAC) — Branch/Role/UserRole/UserBranch con RLS, `require_permission()`, seed de rol admin al registrar tenant. **Verificado con escenario real Burger King** (multi-sucursal, permisos por endpoint)
- 🟢 Mód. 3 — i18n ES/EN real: backend (`Accept-Language` + catálogos JSON), frontend (`next-intl`, rutas `/es` `/en`)
- 🟢 Mód. 4 — Cumplimiento legal (Ley 8968): `ConsentRecord`/`AuditLog` con RLS, `log_audit()`, endpoints de consentimiento y bitácora. **Verificado end-to-end** (grant/revoke real con auditoría). Incluyó fix crítico de un bug real: `server_default="now()"` (string plano en SQLAlchemy) grababa un DEFAULT literal congelado en vez de la función `now()` — afectaba 8 columnas en 8 tablas, corregido y documentado en `CLAUDE.md`
- 🟢 Mód. 6 — Catálogos maestros: `PayrollConcept` parametrizado en 3 dimensiones (método de cálculo, naturaleza, origen), cuenta contable y supervisor en `Branch`. **Verificado con concepto real** (Aguinaldo 8.33% patronal)
- 🟢 Mód. 8 (alcance definido) — Inventario real de dispositivos (`Device`: marca/modelo/serie/IP/sucursal, capacidades del datasheet). **Verificado con specs reales** de un ZKTeco SenseFace 4A. La capa de comunicación (`DeviceAdapter`: heartbeat, sync biométrico, firmware) queda **deliberadamente sin implementar** — no hay dispositivo físico accesible en red para probarla, y el proyecto sigue la regla "cero mock": no se simula hardware que no existe. Cada adaptador levanta `NotImplementedError` explícito, verificado en pruebas. ⚠️ Esto afecta directamente a los mód. 9-12 siguientes: cualquier parte que dependa de hablar con el dispositivo real (enrolamiento biométrico del mód. 10, marcación del mód. 12) queda en el mismo estado — modelo de datos y flujo completos, comunicación real pendiente — hasta que haya un dispositivo físico disponible para pruebas

- 🟢 Mód. 9 — Personal y onboarding: `Employee` (identificación tipada cédula física/jurídica/DIMEX/pasaporte, asignación a sucursal del mód. 6) y `Contract` (indefinido/plazo fijo/por obra, multimoneda). Genera **PDF real bilingüe ES/EN** del contrato (`reportlab`) con datos reales del empleado. **Verificado end-to-end** (empleado real, validaciones de cédula duplicada y fecha de fin por tipo de contrato, PDF descargado y confirmado con `pdftotext`). ⚠️ **Pendiente**: las cláusulas del contrato son un modelo de referencia general (Código de Trabajo CR) — requieren revisión legal antes de uso oficial, mismo tratamiento que el motor de renta (ver 5.2)

- 🟢 Mód. 10 — Enrolamiento biométrico: `BiometricEnrollment` con validación real de consentimiento vigente (empleado, no cuenta de login), validación real de sucursal del dispositivo, validación real de capacidad (`Device.max_faces`/etc. del mód. 8). ⚠️ **Mock explícitamente autorizado por el usuario** (2026-07-08) solo para la captura biométrica en sí (`template_reference` con prefijo `SIMULATED-`, campo `is_simulated=true` en cada registro y en el audit log) — excepción puntual a la regla "cero mock" ante ausencia de hardware físico, para poder demostrar el flujo completo en el MVP. Corrección de diseño incluida: `ConsentRecord` ahora referencia `employee_id` (sujeto real del consentimiento), no solo `user_id` (cuentas de login). **Verificado end-to-end** (rechazo real sin consentimiento, consentimiento y enrolamiento exitoso, auditoría)

- 🟢 Mód. 11 — Feature flags por tenant/sucursal: catálogo público `FeatureFlag` (sin RLS) con seed real de las 6 funcionalidades ya construidas, override `TenantFeatureFlag` (con RLS) por tenant y opcionalmente por sucursal. Default sin override: categoría `core` habilitada, `addon`/`premium` deshabilitada. Helper `is_feature_enabled()` reutilizable para módulos futuros. **Verificado end-to-end** (default por categoría, toggle de tenant, override de sucursal sin filtrarse al nivel general, auditoría)

- 🟢 Mód. 12 — Control de acceso/marcación: `AttendanceRecord` (entrada/salida, verificación facial/fingerprint/card/manual, link opcional a `BiometricEnrollment`). Implementa como **constraint real de base de datos** (no solo intención en el doc) la estrategia offline de la sección 4: clave única dispositivo+empleado+timestamp para evitar duplicados de reconciliación. `is_simulated=true` (mismo patrón que mód. 10, sin captura real por hardware). **Verificado end-to-end** (marcación real, rechazo real de duplicado exacto simulando reconciliación offline, auditoría)

- 🟢 Mód. 17a — Motor de Confianza Operativa™ heurístico: `TrustFlag` sobre `AttendanceRecord` real, evaluado en tiempo real al crear cada marcación (no rescan histórico). 3 reglas sin ML: `missing_biometric` (marcación sin verificación biométrica), `consecutive_same_type` (dos entradas/salidas seguidas sin contraparte), `impossible_travel` (dos sucursales distintas en menos tiempo del físicamente posible, umbral configurable vía `Settings.confianza_impossible_travel_minutes`, no hardcodeado). Corrección de diseño en mód. 12: se quitó el bloqueo duro de sucursal distinta en marcación — bloquearlo ahí impedía que `impossible_travel` pudiera existir; ahora es una señal, no un error. **Verificado end-to-end**: las 3 reglas dispararon correctamente con datos reales de Burger King (segundo dispositivo real en BK Cartago), filtro resuelto/no-resuelto funcional, auditoría completa

**Orden confirmado para llegar al checkpoint MVP** (basado en las dependencias que el propio documento ya identifica — mód. 10/12 no se pueden probar sin mód. 8, mód. 9 necesita centro de costo del mód. 6, mód. 10 necesita consentimiento biométrico del mód. 4 antes de tocar datos biométricos):

1. ✅ Mód. 2 (resto) — RBAC real: roles y permisos por sucursal/centro de costo
2. ✅ Mód. 4 — Cumplimiento legal (Ley 8968, consentimiento biométrico, auditoría de accesos)
3. ✅ Mód. 6 — Catálogos maestros (centros de costo = sucursales, conceptos de ingreso/deducción)
4. ✅ Mód. 8 — Plataforma de relojes marcadores (inventario real; adaptador de comunicación pendiente de hardware, ver nota arriba)
5. ✅ Mód. 9 — Personal y onboarding (ficha + contrato con PDF real; cláusulas pendientes de revisión legal)
6. ✅ Mód. 10 — Enrolamiento biométrico (flujo real completo; captura en sí simulada con autorización explícita, ver nota arriba)
7. ✅ Mód. 11 — Feature flags por tenant/sucursal (catálogo real con seed de las funcionalidades ya construidas)
8. ✅ Mód. 12 — Control de acceso/marcación (**orden invertido con el 17a**: el motor heurístico necesita marcaciones reales para evaluar sus reglas, así que 12 se adelantó — ver nota abajo)
9. ✅ Mód. 17a — Motor de Confianza Operativa™ heurístico (3 reglas reales verificadas: missing_biometric, consecutive_same_type, impossible_travel)
10. 🔲 Mód. 14 (parte) — Excepciones básicas
11. ◆ **Checkpoint MVP** — validación con 2-3 empresas piloto reales (falta el mód. 14 parte para llegar acá)

*Corrección de orden (2026-07-08): el plan original ponía 17a antes que 12, pero las reglas heurísticas del 17a (marcaciones duplicadas, patrones imposibles, ausencia de biometría) requieren datos reales de marcación que solo existen después de construir el mód. 12. Se invirtió el orden para seguir el flujo real de dependencias.*

*Mód. 5 (API versionada `/v1`) no es un paso aparte — se aplica de forma incremental en cada endpoint nuevo que se construya de acá en adelante, no bloquea la secuencia. Mód. 7 (calendario completo) queda fuera del MVP por decisión ya tomada.*

---

## 6. Plan técnico — módulos y fases

Basado en Plan_Desarrollo v4 → en actualización a **v5** (módulo 7: calendario de nómina; módulo 23: motor de renta; módulo 24: gestión de relojes marcadores).

⚠️ **Nota de seguridad (módulo 24):** dispositivos tipo Tiandy tienen vulnerabilidades documentadas de recuperación remota de contraseña de administrador vía su mecanismo P2P/nube de fábrica. Regla dura: el dispositivo **nunca** se expone directo a internet — toda gestión pasa por el backend propio de WORKFORCE AI OS, con su propia autenticación.

### 6.1 Tabla completa — 26 módulos

| # | Módulo | Capa | Perfil | Hrs base | Hrs +20% |
|---|---|---|---|---|---|
| 1 | Infraestructura y arquitectura base — monorepo, CI/CD, Docker Compose, PostgreSQL multiempresa, Redis. **Incluye ahora la decisión de aislamiento multi-tenant (ver 5.1) y estrategia de backup/DR (ver 5.2)** | Core | Arquitecto + DevOps | 300 | 360 |
| 2 | Autenticación, roles y multiempresa — JWT, OAuth2, RBAC por módulo/sucursal/país | Core | Backend senior | 200 | 240 |
| 3 | Internacionalización, multimoneda y localización — i18n ES/EN, tipo de cambio CRC/USD/GTQ/HNL/NIO/PAB | Core | Backend senior + Frontend | 260 | 312 |
| 4 | Cumplimiento legal y protección de datos — Ley 8968 CR, consentimiento biométrico, auditoría de accesos | Core | Legal/Compliance + Backend | 180 | 216 |
| 5 | API REST, webhooks e integraciones — endpoints versionados /v1, SDK de integración | Core | Backend senior | 200 | 240 |
| 6 | **Catálogos maestros de nómina** — centros de costo → cuenta contable, conceptos de ingreso/deducción, supervisor por equipo/turno. **Modelo de concepto (validado):** cada concepto se parametriza en 3 dimensiones — método de cálculo (monto fijo / porcentaje / cantidad), naturaleza (ingreso / deducción) y origen (patronal / del empleado). Aguinaldo y demás provisiones viven aquí como conceptos por % | Core | Backend senior + Contador | 240 | 288 |
| **7** | **Calendario de nómina explícito (NUEVO)** — calendario dual admin. (mensual) vs. turno (semanal/quincenal), cortes/procesamiento/pago, ajuste por feriados, rollover anual, notificaciones | **Core** | Backend senior + Contador | **~220** | **~264** |
| **8** | **Plataforma de gestión de relojes marcadores (NUEVO — movido aquí)** — inventario y alta/baja de dispositivos por sucursal, aprovisionamiento vía SDK sin exponer el dispositivo a internet, monitoreo online/offline, sync de plantillas biométricas server→dispositivo, actualización de firmware controlada. **Multi-marca desde el día 1:** catálogo de "tipos de dispositivo" con adaptador propio por marca — **Tiandy, Hikvision y ZKTeco** soportados de entrada, agregar una marca nueva es un adaptador más, no reescribir el módulo. **Incluye la estrategia offline de marcación (ver 5.1).** Va aquí y no al final porque los módulos 10 (enrolamiento) y 12 (control de acceso) no se pueden probar sin dispositivos ya gestionables | **Core** (extiende Workforce Capture™) | Backend + IoT/SecEng | **~320** | **~384** |
| 9 | Gestión de personal y onboarding — ficha, contratos bilingües, asignación de centro de costo (del mód. 6) | Core | Backend + Frontend | 300 | 360 |
| 10 | Enrolamiento biométrico integrado al onboarding — huella, reconocimiento facial, NFC/RFID *(depende del mód. 8 — dispositivos ya deben estar gestionables; ver capacidad de cómputo en 5.2)* | Core | Backend + Mobile + SDK | 240 | 288 |
| 11 | Asignación y habilitación de módulos por plan — feature flags por tenant/sucursal | Core | Backend + Frontend | 160 | 192 |
| **17a** | **Motor de Confianza Operativa™ — versión heurística (ADELANTADO)** — reglas sin ML: marcaciones duplicadas, patrones imposibles, ausencia de biometría en marcaciones críticas. Se adelanta aquí para estar disponible en el checkpoint MVP como diferenciador demostrable ante clientes piloto | **Core (adelantado)** | Backend senior | ~120 | ~144 |
| **◆ HITO — Checkpoint MVP (REDEFINIDO)** — **MVP reducido**: marcación + evidencia biométrica + excepciones básicas + Motor de Confianza Operativa™ heurístico. Validación con usuarios reales tras onboarding + biométrico + mód. 17a. Calendario dual completo y nómina avanzada quedan fuera del MVP, se retoman después del piloto | | | | |
| 12 | Control de acceso físico (marcación) — lectura de dispositivos, alertas de anomalía *(depende del mód. 8)* | Add-on | Backend + IoT | 200 | 240 |
| 13 | Turnos, horarios y rotación — hereda supervisor del catálogo (mód. 6), cobertura mínima | Add-on | Backend + Frontend | 320 | 384 |
| 14 | Gestión de excepciones y aprobación de horas — justificación con evidencia, bloqueo si hay pendientes | Add-on | Backend + Frontend | 240 | 288 |
| 15 | Motor de nómina multipaís — cálculo CR (CCSS, aguinaldo), cierre por período (según calendario del mód. 7) | Add-on | Backend senior + Contador | 520 | 624 |
| 16 | Contabilización automática multimoneda — asiento por centro de costo, exportación PDF/TXT/Excel | Add-on | Backend + Contador | 400 | 480 |
| 17 | **Motor de Confianza Operativa™ — versión ML completa** — evoluciona la versión heurística (mód. 17a) con aprendizaje automático sobre el histórico ya acumulado desde el MVP | IA crítico | ML Engineer + Backend | 480 | 576 |
| 18 | **Motor de Confianza Operativa™** — Score de Riesgo Operativo (0-100), workflows de investigación automáticos | IA crítico | ML Engineer | 320 | 384 |
| 19 | Dashboard ejecutivo y KPIs multimoneda — tiempo real por sucursal/centro de costo/país | Premium | Frontend senior | 280 | 336 |
| 20 | Agentes IA bilingües (RRHH, Nómina, Auditoría) | Premium | LLM Engineer | 400 | 480 |
| 21 | QA continuo integrado por módulo (shift-left) — tests desde el módulo 1, OWASP Top 10 | Core (transversal) | QA + SecEng | 400 | 480 |
| 22 | DevOps, CI/CD y despliegue productivo — pipelines, monitoreo (ver pila sugerida en 5.2), runbooks bilingües | Core (transversal) | DevOps | 200 | 240 |
| **23** | **Motor de cálculo de renta (NUEVO, validado con el usuario)** — catálogo de tramos por país/año (vive en mód. 6), motor progresivo por excedente sobre **salario bruto**, créditos de **monto fijo por cónyuge + monto fijo por cada hijo menor de 25 años cumplidos**, aguinaldo excluido de renta (se modela como provisión contable por %, no como ingreso gravable), rollover anual automático. **Método de acumulado quincenal (confirmado):** en la **primera quincena** la tabla mensual de tramos se **divide entre 2** y se calcula el IR sobre el ingreso bruto de esa quincena. En la **segunda quincena** se suman los ingresos brutos de ambas quincenas, se calcula el IR real del mes con la tabla mensual completa, se resta lo ya retenido en la primera quincena, y si el resultado es negativo se hace **devolución de renta** al colaborador en esa misma quincena. **Cero hardcode:** tramos, tasas, montos de crédito, moneda y frecuencia de pago (mensual/quincenal/semanal) son datos de catálogo — valores exactos vigentes de Hacienda se cargan al construir este módulo, no bloquean el documento | **Add-on** (dentro del motor de nómina, mód. 15) | Backend senior + Contador | **~220** | **~264** |
| **24** | App móvil supervisores — React Native, aprobación de horas desde móvil *(al final a solicitud expresa)* | Premium | Mobile developer | 320 | 384 |
| **25** | **Catálogo/marketplace de módulos premium (NUEVO)** — activación/desactivación por cliente de módulos individuales (no solo por plan Starter/Pro/Enterprise), panel de control por tenant, historial de qué se activó/desactivó y cuándo (auditoría). Extiende el mód. 11 de feature flags para permitir combinaciones "a la carte", no solo 3 paquetes fijos | **Core** | Backend + Frontend | **~200** | **~240** |
| **26** | **Sistema de temas / white-label por tenant (NUEVO)** — catálogo de tema por tenant (logo, color primario/secundario, modo claro/oscuro por defecto), vive junto a catálogos del mód. 6. Se propaga a: manifest de la PWA (ícono, theme_color), PDFs de nómina/facturas/reportes (mods. 15/16), emails y notificaciones (mód. 20). Tema base del producto neutral (oscuro para dashboards operativos, claro para portales administrativos) + capa de personalización por cliente encima. **Cero hardcode** | **Core** | Frontend + Backend | **~200** | **~240** |
| | **Total estimado** | | | **~7,440** | **~8,928** |

*Nota: el total sube ligeramente (~120-144h) por el módulo 17a adelantado — es trabajo que de todas formas existía en el módulo 17 original, solo se reorganizó para llegar antes al checkpoint MVP.*

### 6.2 Cronograma — 8 fases, ~62 semanas

| Fase | Módulos | Semanas |
|---|---|---|
| F1 — Fundación + catálogos + calendario + relojes marcadores | Mods. 1-8 | S1–S15 |
| F2 — Personal, onboarding y Motor de Confianza Operativa™ heurístico | Mods. 9-11, **17a (adelantado)** | S13–S25 |
| ◆ **Checkpoint MVP (redefinido, más liviano)** — todo esto corre en el servidor Hetzner compartido actual | Validación con 2-3 empresas piloto reales: marcación + biometría + excepciones básicas + score de confianza heurístico | S26–S27 |
| **◆ Migración de servidor** | Servidor Hetzner nuevo, dedicado solo a WORKFORCE AI OS (ver decisión en sección 4) — se hace apenas se valida el MVP, antes de seguir con F3 | Inmediatamente después del checkpoint MVP |
| F3 — Operación y excepciones | Mods. 12-14 | S23–S35 |
| F4 — Nómina multipaís | Mods. 15-16 | S33–S45 |
| F5 — Motor de IA (evolución ML del Motor de Confianza Operativa™) | Mods. 17-18 | S41–S51 |
| F6 — Dashboards y agentes | Mods. 19-20 | S45–S55 |
| F7 — Cierre y despliegue | Mods. 21-23 (QA, DevOps, Renta) | S53–S59 |
| **F8 — App móvil + Marketplace + Temas** | **Mods. 24-26 — al final** | S59–S64 |

*Cifras de horas y semanas quedan sujetas al cierre de tu documento técnico actualizado (v5) — aquí se reflejan como referencia de planificación.*

---

## 7. Regla de trabajo desde aquí en adelante

1. No se ejecuta nada en el servidor hasta que este documento esté aprobado por ti.
2. Los pendientes de la sección 5 se resuelven **uno a la vez**, no todos juntos.
3. Este archivo se actualiza cada vez que se confirma una decisión — es la fuente de verdad del proyecto, no la conversación dispersa.
