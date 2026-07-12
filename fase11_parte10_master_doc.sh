#!/bin/bash
# ============================================================
# Fase 11 - Parte 10: actualizar documento maestro (fase FINAL de Mod.15)
# ============================================================
# 4 ediciones sobre docs/WORKFORCE_AI_OS_PROYECTO.md:
#  1. Nueva entrada en seccion 0 (registro de cambios) para fase 11.
#  2. Roadmap item 12: flip de bullet vacio a completo.
#  3. Seccion 5.3: Mod.15 pasa de "fases 1-10 de 11" a "fases 1-11 de 11"
#     (COMPLETO - era la ultima fase planeada del modulo).
#  4. Seccion 5.2: nuevo pendiente (umbrales de PayrollAnomalyConfig).
# Escritura solo ocurre si TODOS los asserts pasan (si algo falla,
# el archivo queda intacto, sin riesgo).
# Ejecutar: cd /opt/workforce-ai-os && bash fase11_parte10_master_doc.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
DOC="docs/WORKFORCE_AI_OS_PROYECTO.md"

python3 << 'PYEOF'
path = "docs/WORKFORCE_AI_OS_PROYECTO.md"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# ---------- Edicion 1: nueva entrada en seccion 0 ----------
anchor1 = "## 0. Registro de cambios (esta actualizacion)\n- [OK] **Nomina fase 10: Archivo bancario (#147), commit `ff6016a`.**"
# el doc real usa caracteres acentuados / emoji reales; construimos el anchor
# con los literales exactos en vez de placeholders ASCII:
anchor1 = "## 0. Registro de cambios (esta actualización)\n- ✅ **Nómina fase 10: Archivo bancario (#147), commit `ff6016a`.**"
assert anchor1 in src, "ANCHOR 1 NOT FOUND (seccion 0 / fase 10 bullet)"
assert src.count(anchor1) == 1, "ANCHOR 1 NOT UNIQUE"

fase11_entry = """## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 11: Orquestación y auto-validación (Payroll Run) (#150), commit `d3d06ff` — ÚLTIMA FASE del Mód. 15, motor de nómina completo.** Las 4 piezas acordadas con vos, todas construidas: (1) máquina de estados de 7 pasos (`draft → validado → calculado → aprobado → pagado → contabilizado → archivo_bancario`), estrictamente secuencial, sin saltar pasos; (2) snapshot inmutable (`PayrollSnapshotLine`) que congela el resultado por empleado al pasar a "calculado" — desde ahí, asientos contables (fase 9) y archivo bancario (fase 10) leen siempre del snapshot, no del cálculo en vivo, así un cambio posterior en CCSS/renta no altera un período ya pagado; (3) validación proactiva en cada transición (catálogos faltantes bloquean antes de calcular, no se descubre a mitad de camino); (4) motor de anomalías con 6 reglas reutilizando el Motor de Confianza Operativa™ (mód. 17a) — incluidas las 3 que vos mismo elegiste como "wow factor": cuenta bancaria cambiada justo antes del pago, empleado pagado después de una terminación aprobada, y sucursal con neto muy fuera del promedio de las demás.
  - **Prueba de inmutabilidad, hecha explícita en el test:** se cambió el cálculo en vivo DESPUÉS de congelar el snapshot de un período, y se confirmó que tanto una lectura directa como el asiento contable (fase 9) y el archivo bancario (fase 10) siguieron devolviendo los montos originales congelados, no los nuevos.
  - 🟡 **Pendiente de validar (ver 5.2):** los 4 umbrales de `PayrollAnomalyConfig` son valores de prueba técnica, no legales — necesitan ajuste de sensibilidad con el equipo de nómina antes de operar en real.
  - Probado end-to-end (37/37 PASS): las 7 transiciones de punta a punta, los 3 bloqueos negativos (transición inválida, filas bloqueadas al calcular, catálogos faltantes), las 6 reglas de anomalía disparadas con datos conocidos, y la prueba de inmutabilidad descrita arriba.
- ✅ **Nómina fase 10: Archivo bancario (#147), commit `ff6016a`.**"""

src = src.replace(anchor1, fase11_entry, 1)
print("OK edicion 1: entrada de fase 11 insertada en seccion 0")

# ---------- Edicion 2: roadmap item 12 ----------
anchor2 = "12. ⬜ Orquestación y auto-validación — máquina de estados de corrida (`draft→validado→calculado→aprobado→pagado→contabilizado→banco`), snapshot inmutable al cerrar período, validación proactiva de catálogos antes del cierre, cola de excepciones y detección de anomalías (reutilizando el motor heurístico del mód. 17a)"
assert anchor2 in src, "ANCHOR 2 NOT FOUND (roadmap item 12)"
assert src.count(anchor2) == 1, "ANCHOR 2 NOT UNIQUE"
replacement2 = anchor2.replace("⬜", "✅") + " — commit `d3d06ff`, probado end-to-end 37/37 PASS."
src = src.replace(anchor2, replacement2, 1)
print("OK edicion 2: roadmap item 12 marcado completo")

# ---------- Edicion 3: seccion 5.3, linea de Mod.15 ----------
anchor3 = "- \U0001f7e2 **Mód. 15 (fases 1-10 de 11, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto, Vacaciones, Aguinaldo, Cesantía y Asientos contables (fases 1-9) más Archivo bancario (`core/bank_file.py`: formato TXT real del banco, cuenta bancaria por empleado, generación con auditoría). Detalle completo del porqué y las correcciones de proceso en sección 0."
assert anchor3 in src, "ANCHOR 3 NOT FOUND (seccion 5.3 / Mod.15)"
assert src.count(anchor3) == 1, "ANCHOR 3 NOT UNIQUE"
replacement3 = "- \U0001f7e2 **Mód. 15 (fases 1-11 de 11, COMPLETO, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto, Vacaciones, Aguinaldo, Cesantía y Asientos contables (fases 1-9), Archivo bancario (fase 10, `core/bank_file.py`) y Orquestación y auto-validación (fase 11, `core/payroll_run.py`: máquina de estados de 7 pasos, snapshot inmutable, validación proactiva de catálogos, motor de anomalías con 6 reglas reutilizando Confianza Operativa™). Con esto el motor de nómina queda completo de punta a punta: de la marcación de asistencia al archivo bancario listo para subir. Detalle completo del porqué y las correcciones de proceso en sección 0."
src = src.replace(anchor3, replacement3, 1)
print("OK edicion 3: Mod.15 marcado 'fases 1-11 de 11, COMPLETO'")

# ---------- Edicion 4: seccion 5.2, nuevo pendiente ----------
anchor4 = "ajuste de una línea si hace falta.\n⏸️ **Sprint 0 (scaffold)"
assert anchor4 in src, "ANCHOR 4 NOT FOUND (seccion 5.2 / cierre antes de Sprint 0 pausa)"
assert src.count(anchor4) == 1, "ANCHOR 4 NOT UNIQUE"
nuevo_pendiente = (
    "ajuste de una línea si hace falta.\n"
    "- \U0001f7e1 **Antes de operar nómina real (orquestación, fase 11)** — Los 4 umbrales de "
    "`PayrollAnomalyConfig` (desviación de neto 30%, multiplicador de horas extra 2x, ventana de "
    "cambio de cuenta bancaria 5 días, desviación de neto por sucursal 30%) se cargaron como valores "
    "de PRUEBA para poder probar el motor de anomalías end-to-end — no son valores legales sino de "
    "sensibilidad heurística, pero conviene revisarlos con el equipo de nómina/RRHH antes de operar "
    "en real: muy bajos generan ruido (alertas falsas), muy altos dejan pasar anomalías reales.\n"
    "⏸️ **Sprint 0 (scaffold)"
)
src = src.replace(anchor4, nuevo_pendiente, 1)
print("OK edicion 4: nuevo pendiente agregado a seccion 5.2")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("ARCHIVO ESCRITO OK:", path)
PYEOF

echo ""
echo "=== verificacion rapida (grep de las 4 ediciones) ==="
grep -n "fase 11: Orquestación y auto-validación" "$DOC" | head -3
grep -n "commit \`d3d06ff\`" "$DOC"
grep -n "fases 1-11 de 11, COMPLETO" "$DOC"
grep -n "Antes de operar nómina real (orquestación" "$DOC"

echo ""
echo "=== git diff --stat ==="
git diff --stat -- "$DOC"

echo "=== FIN Parte 10 (master doc, sin commit todavia) ==="
