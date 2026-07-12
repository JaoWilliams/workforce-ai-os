#!/bin/bash
# ============================================================
# Actualiza docs/WORKFORCE_AI_OS_PROYECTO.md con lo hecho desde el
# ultimo update: #102 (biometrico checklist), #104 (verificacion
# final pre-demo), #138 (avisos de turno). Tambien deja constancia
# del gap tecnico de RLS en shift_alert_configs en la seccion 5.2.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "docs/WORKFORCE_AI_OS_PROYECTO.md"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

# ---------- 1. nueva entrada al tope de la seccion 0 ----------
old_1 = '''## 0. Registro de cambios (esta actualización)
- ✅ **UI/UX — Onboarding incompleto, Centro de Onboarding y estándar de filtros (2026-07-11).**'''
new_1 = '''## 0. Registro de cambios (esta actualización)
- ✅ **Cierre de pendientes técnicos + Avisos de Turno (#102, #104, #138) (2026-07-11).**
  - **Biométrico como checklist de onboarding (#102):** la sección de enrolamiento en Dispositivos dejó de ser un selector libre de "cualquier empleado" — por defecto muestra solo empleados pendientes de biométrico (reutilizando `onboarding_missing`), con filtro de sucursal, barra de progreso, toggle "ver todos" para re-enrolar en un dispositivo nuevo, y desaparición automática del checklist al enrolar exitosamente. El botón "Resolver" del Centro de Onboarding ahora enruta a Dispositivos cuando el único gap pendiente es biométrico (antes siempre iba a Empleados).
  - **Verificación final pre-demo (#104):** `scripts/verificacion_final_demo.sh` (smoke test automático de los 45 endpoints reales del backend — se extrajeron directo del router de FastAPI, ninguno adivinado — clasifica cada uno OK/WARN/FAIL) + `CHECKLIST_DEMO_CLIENTE.md` (recorrido manual de 17 secciones, pantalla por pantalla, para el ensayo antes de la reunión con el cliente). Corrida real contra el tenant Burger King: 45 checks, 39 OK, 6 WARN (parámetros de query faltantes en el propio script de prueba, no bugs de la aplicación), 0 FAIL.
  - **Avisos de seguimiento al cierre/inicio de turno (#138):** módulo nuevo, calculado en vivo (sin worker en background — el stack no tiene uno — mismo patrón que `onboarding_missing`/`has_pending_exceptions`, se recalcula en cada request en vez de persistirse). Dos tipos de aviso: `no_show` (el turno ya empezó + minutos de gracia y el empleado no tiene marcación de entrada ese día) y `not_closed` (el turno ya terminó + minutos de gracia, hay entrada pero no salida). Minutos de gracia parametrizables por tenant vía catálogo nuevo `ShiftAlertConfig` (`GET/PUT /api/catalogs/shift-alert-config`, 15 min por defecto, sin valores quemados en el cálculo). Pantalla dedicada "Avisos de Turno" (`/avisos-turno`, sidebar → grupo Asistencia) con búsqueda, filtro de sucursal, tarjetas clicables por tipo de aviso y botón de refresh manual (no aplica toast/autorefresh del estándar de `CLAUDE.md` porque la pantalla es de solo lectura, sin mutaciones); tarjeta resumen nueva en el Dashboard.
    - 🟡 **Gap técnico flageado, ver también 5.2:** la tabla `shift_alert_configs` se creó por SQL directo (mismo patrón usado esta sesión para `Contract.language`) SIN política RLS todavía — no se tenía a mano el SQL exacto de las políticas existentes para replicarlo sin riesgo de error. Como red de seguridad, toda query sobre esta tabla filtra `tenant_id` explícitamente en el código Python (no depende de RLS para el aislamiento). Pendiente: agregar la política RLS formal vía Alembic, mismo tratamiento que el resto de tablas multi-tenant, antes de escalar a más tenants reales.
- ✅ **UI/UX — Onboarding incompleto, Centro de Onboarding y estándar de filtros (2026-07-11).**'''

edits.append(("insercion tope seccion 0", old_1, new_1))

# ---------- 2. pendiente tecnico en 5.2 (RLS de shift_alert_configs) ----------
old_2 = '''⏸️ **Sprint 0 (scaffold) y Sprint 1 (mód. 1 en adelante) quedan en pausa hasta resolver lo anterior.**'''
new_2 = '''- 🟡 **Antes de escalar a más tenants reales (avisos de turno, #138)** — La tabla `shift_alert_configs` no tiene política RLS formal todavía (se creó por SQL directo, ver detalle en sección 0). Mitigado con filtro explícito de `tenant_id` en cada query desde el código Python, pero falta agregar la política RLS igual que las demás tablas multi-tenant.
⏸️ **Sprint 0 (scaffold) y Sprint 1 (mód. 1 en adelante) quedan en pausa hasta resolver lo anterior.**'''

edits.append(("pendiente 5.2 RLS shift_alert_configs", old_2, new_2))

# ---------- 3. nueva linea en 5.3 "Ya construido" ----------
old_3 = '''- 🟢 **UI/UX post-MVP — Onboarding incompleto, Centro de Onboarding, estándar de filtros y retrofit (2026-07-11)** — motor de detección de gaps de onboarding (`core/onboarding.py`), badge en Empleados + KPI en Dashboard, pantalla dedicada Centro de Onboarding, botón expandir/contraer sidebar, estándar obligatorio de filtro por sucursal (Empleados/Marcación/Excepciones/Confianza Operativa) documentado en `CLAUDE.md` + `scripts/audit_ui_standards.sh`, retrofit de búsqueda (Confianza/Excepciones/Feature Flags) y toast (Marcación), deep link Marcación→Excepciones, motivo obligatorio + excepción automática en marcación manual, descripción visible en Feature Flags, y contrato PDF en idioma único. Detalle completo en sección 0.'''
new_3 = '''- 🟢 **UI/UX post-MVP — Onboarding incompleto, Centro de Onboarding, estándar de filtros y retrofit (2026-07-11)** — motor de detección de gaps de onboarding (`core/onboarding.py`), badge en Empleados + KPI en Dashboard, pantalla dedicada Centro de Onboarding, botón expandir/contraer sidebar, estándar obligatorio de filtro por sucursal (Empleados/Marcación/Excepciones/Confianza Operativa) documentado en `CLAUDE.md` + `scripts/audit_ui_standards.sh`, retrofit de búsqueda (Confianza/Excepciones/Feature Flags) y toast (Marcación), deep link Marcación→Excepciones, motivo obligatorio + excepción automática en marcación manual, descripción visible en Feature Flags, y contrato PDF en idioma único. Detalle completo en sección 0.
- 🟢 **Biométrico checklist + verificación final + Avisos de Turno (2026-07-11)** — enrolamiento biométrico rediseñado como checklist de onboarding (#102), con el deep-link del Centro de Onboarding corregido para enrutar ahí cuando corresponde; herramientas de verificación final pre-demo (#104: smoke test de backend + checklist manual de 17 secciones); módulo nuevo de Avisos de Turno (#138: `core/shift_alerts.py`, catálogo `ShiftAlertConfig`, endpoint `GET /api/shifts/alerts`, pantalla dedicada `/avisos-turno`, tarjeta en Dashboard). Detalle completo en sección 0.'''

edits.append(("nueva linea 5.3 biometrico+verificacion+avisos", old_3, new_3))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

with open(path, encoding="utf-8") as f:
    check = f.read()
problemas = []
for marker in ["Avisos de Turno", "shift_alert_configs", "Verificación final pre-demo"]:
    if marker not in check:
        problemas.append(f"falta: {marker}")
if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)
print(f"OK: {path} actualizado y verificado correctamente ({len(check)} caracteres)")
PYEOF

echo "=== commit ==="
git add docs/WORKFORCE_AI_OS_PROYECTO.md
git commit -m "docs: actualizar WORKFORCE_AI_OS_PROYECTO.md con #102, #104, #138

- Biometrico rediseñado como checklist de onboarding (#102).
- Herramientas de verificacion final pre-demo (#104).
- Modulo nuevo de Avisos de Turno (#138), con gap de RLS flageado
  en 5.2 para la tabla shift_alert_configs."
git push origin main
echo "OK: commit + push"

echo "=== FIN actualizacion master doc v2 ==="
