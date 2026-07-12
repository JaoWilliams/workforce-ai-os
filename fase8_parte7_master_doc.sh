#!/bin/bash
# ============================================================
# Fase 8 (Cesantía) - Parte 7: actualizar doc maestro
# ============================================================
# CAMBIOS en docs/WORKFORCE_AI_OS_PROYECTO.md:
#   - Seccion 0: nueva entrada fechada (la mas reciente, va arriba)
#   - Roadmap de nomina: item 9 "Cesantia" pasa de ⬜ a ✅
#   - Seccion 5.2: nuevo pendiente (interpretacion >6 meses flageada)
#   - Seccion 5.3: bullet Mod.15 bump de "fases 1-7 de 11" a "fases 1-8"
# Ejecutar: cd /opt/workforce-ai-os && bash fase8_parte7_master_doc.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "docs/WORKFORCE_AI_OS_PROYECTO.md"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# ---------- 1. Seccion 0: nueva entrada (va arriba, es la mas reciente) ----------
anchor_section0 = """## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 7: Aguinaldo (#144), commit `ba8a714`.**"""
assert anchor_section0 in src, "ANCHOR NOT FOUND: seccion 0"
assert src.count(anchor_section0) == 1, "ANCHOR NOT UNIQUE: seccion 0"

new_entry = """## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 8: Cesantía (#145), commit `30cde23`.** Basado en documento legal que cargaste ("Cesantía Art 29.docx", Código de Trabajo Art. 28/29/30). Solo aplica con responsabilidad patronal (despido injustificado) — sin ella, 0 días sin importar antigüedad, pero el empleado se considera igual desvinculado. Antigüedad: <3 meses=0 días, 3-6 meses=7 días fijos, 6-12 meses=14 días fijos (`CesantiaConfig.days_3to6_months`/`days_6to12_months`, valores legales reales), ≥1 año usa la tabla oficial completa del Art. 29 (`CesantiaScaleRow`, 13 filas sembradas con los valores reales del documento: 19.5/20/20.5/21/21.24/21.5/22/22/22/21.5/21/20.5/20 días por año, acumulativa) con tope de 8 años (`max_years_cap`). Salario diario: promedio de `gross_pay` de los últimos 6 meses de planilla (mensual/quincenal, semanal bloqueado explícitamente — el documento distingue un divisor de 26 para no-comercial que no está definido para este tenant) dividido entre 30. Modelo de terminación (`Termination`) con causa + flujo de aprobación (pending/approved/rejected) — al aprobar, `Employee.active` pasa a `False` automáticamente, incluso cuando no hay responsabilidad patronal (el empleado se fue de todas formas, la cesantía es una cuestión legal aparte). Probado end-to-end (62/62 PASS): 7 casos de cálculo de días verificados a mano, promedio salarial probado con datos de nómina conocidos (agrupación quincenal por mes, historial parcial/nulo, bloqueo semanal), integración real vía los endpoints de terminación (mismo código que producción), validaciones de negocio (terminación duplicada, empleado ya inactivo, estados inválidos) y el efecto lateral de desactivación de empleado.
  - ⚠️ **Interpretación flageada (pendiente de validación con tu abogado):** el documento se contradice a sí mismo sobre el redondeo de fracción de año — el resumen ejecutivo dice "fracciones IGUALES O MAYORES a 6 meses redondean" pero la sección detallada con la tabla dice "SUPERIOR a 6 meses". Se adoptó la versión detallada (estrictamente más de 6 meses, umbral parametrizado en `CesantiaConfig.fraction_round_months`, no hardcodeado) por ser la fuente más específica del documento. Si tu abogado confirma que debe ser "≥6", es un cambio de un solo valor de catálogo, no de código.
  - 🟡 **Anotado para fase 9 (asientos contables):** igual que con aguinaldo, hay que definir cómo se registra contablemente el pago de cesantía cuando ocurre (no es una provisión mensual como aguinaldo — es un pasivo contingente que se paga completo al momento del despido).
- ✅ **Nómina fase 7: Aguinaldo (#144), commit `ba8a714`.**"""

src = src.replace(anchor_section0, new_entry)

# ---------- 2. Roadmap: item 9 Cesantia -> hecho ----------
anchor_roadmap = "9. ⬜ Cesantía"
assert anchor_roadmap in src, "ANCHOR NOT FOUND: roadmap item 9"
assert src.count(anchor_roadmap) == 1, "ANCHOR NOT UNIQUE: roadmap item 9"
src = src.replace(
    anchor_roadmap,
    "9. ✅ Cesantía — tabla oficial Art. 29 acumulativa con tope de 8 años, promedio salarial de 6 meses, modelo de terminación con aprobación",
)

# ---------- 3. Seccion 5.2: nuevo pendiente ----------
anchor_52 = """- 🟡 **Aguinaldo y comisiones (fase 7)** — El cálculo de aguinaldo solo suma lo que el sistema efectivamente calcula como `gross_pay` (horas trabajadas, horas extra, feriados, vacaciones). Si Burger King paga comisiones u otros ingresos salariales fuera de este sistema, esos montos no entran en la base del aguinaldo — hay que cargarlos como concepto de nómina o definir un mecanismo de captura antes de operar el aguinaldo real.
⏸️"""
assert anchor_52 in src, "ANCHOR NOT FOUND: seccion 5.2"
assert src.count(anchor_52) == 1, "ANCHOR NOT UNIQUE: seccion 5.2"
new_52 = """- 🟡 **Aguinaldo y comisiones (fase 7)** — El cálculo de aguinaldo solo suma lo que el sistema efectivamente calcula como `gross_pay` (horas trabajadas, horas extra, feriados, vacaciones). Si Burger King paga comisiones u otros ingresos salariales fuera de este sistema, esos montos no entran en la base del aguinaldo — hay que cargarlos como concepto de nómina o definir un mecanismo de captura antes de operar el aguinaldo real.
- 🟡 **Cesantía — interpretación de fracción de año (fase 8)** — El documento legal se contradice sobre si una fracción de año ">6 meses" o "≥6 meses" redondea al año siguiente para efectos de la tabla acumulativa del Art. 29. Se adoptó ">6 meses" (la versión de la sección detallada del documento). Necesita confirmación de tu abogado laboral antes de operar cesantía real — es un valor de catálogo (`CesantiaConfig.fraction_round_months`), no requiere cambio de código si hay que ajustarlo.
⏸️"""
src = src.replace(anchor_52, new_52)

# ---------- 4. Seccion 5.3: bump fases 1-7 -> 1-8 ----------
anchor_53 = "- 🟢 **Mód. 15 (fases 1-7 de 11, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto y Vacaciones (fases 1-6) más Aguinaldo (`core/aguinaldo.py`: suma de gross_pay dic-nov / 12, planilla dedicada sin deducciones, sin aprobación por ser cálculo objetivo). Detalle completo del porqué y las correcciones de proceso en sección 0."
assert anchor_53 in src, "ANCHOR NOT FOUND: seccion 5.3"
assert src.count(anchor_53) == 1, "ANCHOR NOT UNIQUE: seccion 5.3"
new_53 = "- 🟢 **Mód. 15 (fases 1-8 de 11, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto, Vacaciones y Aguinaldo (fases 1-7) más Cesantía (`core/cesantia.py`: tabla oficial Art. 29 acumulativa con tope de 8 años, promedio salarial de 6 meses, modelo de terminación con aprobación). Detalle completo del porqué y las correcciones de proceso en sección 0."
src = src.replace(anchor_53, new_53)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("OK: master doc actualizado (seccion 0, roadmap item 9, seccion 5.2, seccion 5.3)")
PYEOF

echo "=== diff resumido ==="
git diff --stat docs/WORKFORCE_AI_OS_PROYECTO.md

git add docs/WORKFORCE_AI_OS_PROYECTO.md
git commit -m "docs: actualizar master doc con fase 8 (Cesantia) completa

- Seccion 0: nueva entrada fechada con el resumen de la fase y la
  interpretacion flageada (>6 vs >=6 meses de fraccion).
- Roadmap de nomina: item 9 Cesantia pasa de pendiente a hecho.
- Seccion 5.2: nuevo pendiente de validacion legal (umbral de
  redondeo de fraccion de anio).
- Seccion 5.3: bump de 'fases 1-7 de 11' a 'fases 1-8 de 11'."

git push

echo "=== FIN Parte 7 ==="
