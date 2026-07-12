#!/bin/bash
# ============================================================
# Actualiza docs/WORKFORCE_AI_OS_PROYECTO.md:
# - Backfill de la sesion anterior (no registrada en su momento):
#   sidebar reorg (#158), pantalla Payroll Run (#160), fix em-dash/
#   status legacy (#161), fix UUID bank_file (#162).
# - Backfill de esta sesion: Onboarding incompleto (#163-165),
#   sidebar expandir/contraer (#159), retrofit busqueda+toast,
#   estandar de filtro de sucursal (#166) + CLAUDE.md + audit script,
#   Marcacion->Excepciones (#109), motivo en marcacion manual (#103),
#   Feature Flags descripcion (#110), Contrato PDF idioma unico (#98).
# - Ajusta las 2 menciones de "PDF bilingue" a idioma unico (#98).
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "docs/WORKFORCE_AI_OS_PROYECTO.md"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

# ---------- 1. nueva entrada al TOPE de la seccion 0 ----------
old_1 = '''## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 11: Orquestación'''
new_1 = '''## 0. Registro de cambios (esta actualización)
- ✅ **UI/UX — Onboarding incompleto, Centro de Onboarding y estándar de filtros (2026-07-11).** Bloque de trabajo iniciado a partir de un bug real (UUID no serializable en `bank_file`) que expuso un problema de fondo: el sistema era reactivo, no preventivo, con gaps de onboarding (cuenta bancaria, contrato, biométrico) que solo se descubrían a mitad de un cierre de nómina.
  - **Motor de onboarding incompleto (#163-165):** `core/onboarding.py` calcula en vivo (`get_missing_items_bulk`, sin backfill) qué le falta a cada empleado activo — cuenta bancaria, contrato, enrolamiento biométrico — expuesto como `onboarding_missing` en `GET /api/employees`. Badge visible en Empleados + contador en el Dashboard (#164). A pedido explícito tuyo de "pensar en grande" dado el volumen (1,345 empleados, alta rotación), en vez de un simple toast se construyó una pantalla dedicada, **Centro de Onboarding** (#165, nueva ruta `/onboarding`): banner de riesgo de nómina (empleados con período abierto y cuenta bancaria faltante), tarjetas resumen por tipo de gap, gráfico de gaps por sucursal, tabla filtrable/ordenable por antigüedad del gap, con deep-link directo a Empleados (`?highlight=<id>`). El botón "Verificar onboarding" en Empleados ahora redirige a esta pantalla en vez de mostrar un mensaje genérico.
  - **Sidebar (#159):** botón para expandir/contraer todas las categorías de una vez, persistido en `localStorage` igual que el estado individual de cada grupo. Orden Empleados→Onboarding confirmado como correcto (Empleados = alta, Onboarding = seguimiento).
  - **Estándar de filtro por sucursal (#166):** a partir de tu observación de escala ("¿cómo haría una persona si solo requiere ver las marcas de X sucursal?"), se definió un estándar obligatorio — dropdown de sucursal, poblado desde `/api/branches`, en toda pantalla que liste datos asociables a empleado/sucursal. Aplicado en Empleados, Marcación, Excepciones y Confianza Operativa (Dispositivos, Turnos, Reportes y Centro de Onboarding ya lo tenían). Documentado como checklist obligatorio en `CLAUDE.md` ("Estandar de pantallas con listado") junto con `scripts/audit_ui_standards.sh`, un script reutilizable que audita cada pantalla del dashboard contra 4 señales (búsqueda, filtro de sucursal, toast, fetch de `/api/branches`) — correr antes de cerrar cualquier pantalla nueva.
  - **Retrofit de búsqueda y toast (#127/#118, gaps cerrados):** búsqueda de texto agregada a Confianza Operativa, Excepciones y Feature Flags. Toast de éxito/error agregado a Marcación (única pantalla que aún no lo tenía).
  - **Marcación → Excepciones (#109):** cada marcación en la lista tiene un botón "Corregir marca" (visible solo con permiso `exceptions.manage`) que lleva a Excepciones con el empleado y la marcación pre-cargados.
  - **Marcación: motivo solo en casos atípicos (#103):** una marcación con `verification_method=manual` ahora exige un motivo (textarea) y crea automáticamente una `TimeException` tipo `manual_correction` en estado pendiente, vinculada a la marcación — reutiliza 100% el flujo de aprobación de Excepciones ya existente, sin modelo ni endpoint nuevo. Marcaciones con verificación real (biométrica, tarjeta) no piden motivo ni generan excepción.
  - **Feature Flags: descripción (#110):** el campo `description` ya existía en el modelo pero no se exponía en `/tenant` ni se mostraba en el frontend — agregado a `TenantFeatureFlagStatus` y renderizado bajo el nombre de cada flag.
  - **Contrato PDF: idioma único (#98):** se eliminó el PDF bilingüe (ES+EN en cada línea) — ahora cada contrato se genera en un único idioma, elegido al crearlo (`Contract.language`, columna nueva vía `ALTER TABLE`, default `'es'`). `core/contracts_pdf.py` reescrito de cero para generar un documento en un solo idioma, preservando el aviso legal y la nota sobre el logo de Burger King ya documentados en fases anteriores.
- ✅ **Backfill — pendiente de la sesión anterior, nunca registrado en su momento.** Detectado al revisar el seguimiento de este documento junto con vos; se deja constancia acá con retraso de una sesión:
  - 🟢 **Sidebar agrupado y colapsable (#158)** — navegación reorganizada en grupos plegables, con persistencia de estado en `localStorage`.
  - 🟢 **Pantalla Payroll Run (#160)** — interfaz para la máquina de estados de 7 pasos de la fase 11 de nómina (draft→validado→calculado→aprobado→pagado→contabilizado→archivo bancario), consumiendo los endpoints ya construidos en esa fase.
  - 🔧 **Fix: em-dash literal y status legacy sin traducir en Corridas (#161)** — corrección de visualización en la pantalla de corridas de nómina.
  - 🔧 **Fix: UUID no serializable en error `no_valid_rows` de `bank_file` (#162)** — el bug que disparó toda la revisión de onboarding incompleto descrita arriba: un error de serialización JSON exponía la causa raíz real (empleados sin cuenta bancaria cargada, descubierto solo al intentar generar el archivo bancario).
- ✅ **Nómina fase 11: Orquestación'''

edits.append(("insercion tope seccion 0", old_1, new_1))

# ---------- 2. Mod 9 en 5.3: quitar mencion "bilingue ES/EN" ----------
old_2 = '''Genera **PDF real bilingüe ES/EN** del contrato (`reportlab`) con datos reales del empleado. **Verificado end-to-end** (empleado real, validaciones de cédula duplicada y fecha de fin por tipo de contrato, PDF descargado y confirmado con `pdftotext`). ⚠️ **Pendiente**: las cláusulas del contrato son un modelo de referencia general (Código de Trabajo CR) — requieren revisión legal antes de uso oficial, mismo tratamiento que el motor de renta (ver 5.2)'''
new_2 = '''Genera **PDF real del contrato** (`reportlab`) con datos reales del empleado — originalmente bilingüe ES/EN, reemplazado por generación en **idioma único seleccionable** (`Contract.language`, ver #98 en sección 0). **Verificado end-to-end** (empleado real, validaciones de cédula duplicada y fecha de fin por tipo de contrato, PDF descargado y confirmado con `pdftotext`). ⚠️ **Pendiente**: las cláusulas del contrato son un modelo de referencia general (Código de Trabajo CR) — requieren revisión legal antes de uso oficial, mismo tratamiento que el motor de renta (ver 5.2)'''

edits.append(("mod9 5.3 idioma unico", old_2, new_2))

# ---------- 3. pendiente 5.2: quitar mencion "bilingue" ----------
old_3 = '''- 🟡 **Antes de uso oficial de contratos (mód. 9)** — El PDF de contrato de trabajo (bilingüe, generado con datos reales) usa cláusulas de referencia general del Código de Trabajo de Costa Rica. Igual que el motor de renta (fila anterior), necesita revisión de un abogado laboral antes de usarse como contrato real con un cliente piloto — el aviso ya queda impreso en el propio PDF'''
new_3 = '''- 🟡 **Antes de uso oficial de contratos (mód. 9)** — El PDF de contrato de trabajo (generado en idioma único seleccionable desde #98, con datos reales) usa cláusulas de referencia general del Código de Trabajo de Costa Rica. Igual que el motor de renta (fila anterior), necesita revisión de un abogado laboral antes de usarse como contrato real con un cliente piloto — el aviso ya queda impreso en el propio PDF'''

edits.append(("pendiente 5.2 idioma unico", old_3, new_3))

# ---------- 4. nueva linea en 5.3 "Ya construido" tras el bullet de Mod 15 ----------
old_4 = '''Con esto el motor de nómina queda completo de punta a punta: de la marcación de asistencia al archivo bancario listo para subir. Detalle completo del porqué y las correcciones de proceso en sección 0.'''
new_4 = '''Con esto el motor de nómina queda completo de punta a punta: de la marcación de asistencia al archivo bancario listo para subir. Detalle completo del porqué y las correcciones de proceso en sección 0.
- 🟢 **UI/UX post-MVP — Onboarding incompleto, Centro de Onboarding, estándar de filtros y retrofit (2026-07-11)** — motor de detección de gaps de onboarding (`core/onboarding.py`), badge en Empleados + KPI en Dashboard, pantalla dedicada Centro de Onboarding, botón expandir/contraer sidebar, estándar obligatorio de filtro por sucursal (Empleados/Marcación/Excepciones/Confianza Operativa) documentado en `CLAUDE.md` + `scripts/audit_ui_standards.sh`, retrofit de búsqueda (Confianza/Excepciones/Feature Flags) y toast (Marcación), deep link Marcación→Excepciones, motivo obligatorio + excepción automática en marcación manual, descripción visible en Feature Flags, y contrato PDF en idioma único. Detalle completo en sección 0.'''

edits.append(("nueva linea 5.3 UI/UX", old_4, new_4))

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
for marker in ["Centro de Onboarding", "Sidebar agrupado", "idioma único seleccionable", "Backfill — pendiente de la sesión anterior"]:
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
git commit -m "docs: actualizar WORKFORCE_AI_OS_PROYECTO.md con sesion anterior + hoy

- Backfill sesion anterior: sidebar reorg, pantalla Payroll Run,
  fix em-dash/status legacy, fix UUID bank_file.
- Sesion de hoy: Onboarding incompleto + Centro de Onboarding,
  sidebar expandir/contraer, estandar de filtro de sucursal +
  CLAUDE.md + audit script, retrofit busqueda/toast, Marcacion->
  Excepciones, motivo en marcacion manual, Feature Flags descripcion,
  Contrato PDF idioma unico.
- Actualizadas 2 menciones de PDF de contrato bilingue -> idioma unico."
git push origin main
echo "OK: commit + push"

echo "=== FIN actualizacion master doc ==="
