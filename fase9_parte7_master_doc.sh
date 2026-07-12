#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 7: actualizar doc maestro
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "docs/WORKFORCE_AI_OS_PROYECTO.md"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# ---------- 1. Seccion 0: nueva entrada (va arriba) ----------
anchor_section0 = """## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 8: Cesantía (#145), commit `30cde23`.**"""
assert anchor_section0 in src, "ANCHOR NOT FOUND: seccion 0"
assert src.count(anchor_section0) == 1, "ANCHOR NOT UNIQUE: seccion 0"

new_entry = """## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 9: Asientos contables (#146), commit `aeb2354`.** Alcance confirmado con vos: planilla ordinaria + provisión de aguinaldo (con reconciliación al pago real que cancela el pasivo acumulado) + provisión de vacaciones (delta de días acumulados × tarifa Art.157) + cesantía SOLO al aprobar una terminación con responsabilidad patronal (sin provisión mensual especulativa — provisionar mensualmente requeriría asumir una tasa de rotación que no existe como dato real) + aporte patronal CCSS (tasa de prueba flageada). No existía un plan de cuentas cargado — se creó desde cero (`ChartOfAccount`, 13 cuentas reales sembradas). Cada asiento (`JournalEntry` + `JournalEntryLine`, líneas debe/haber) se genera y valida (debe==haber) antes de guardarse; si falta una cuenta contable, no se genera nada (mismo patrón de "no asumir" de siempre). Exportación a CSV genérico (no confirmaste sistema contable específico, pediste "un csv").
  - 🔧 **Bug encontrado y corregido durante el testing:** el aguinaldo y el nuevo concepto CCSS patronal guardan su tasa en `PayrollConcept.value` (son conceptos 100% patronales, sin lado empleado), no en `employer_value` — ese campo es para conceptos que tienen AMBOS lados en la misma fila, patrón que no se usó acá. El código inicial leía el campo equivocado; se corrigió y se verificó contra el dato real de aguinaldo (8.33% confirmado en `value`).
  - 🔧 **Ajuste de diseño durante el testing:** no existe un concepto `RENTA` en el catálogo — el cálculo de renta (fase 5) usa las tablas `TaxBracket`/`RentaCredits` directamente, no pasa por `PayrollConcept`. Su cuenta de pasivo se resuelve por código fijo (`PASIVO-RENTA-POR-PAGAR`) en vez de por concepto vinculado.
  - 🟡 **CCSS patronal — tasa de prueba flageada:** se creó el concepto `CCSS-PATRONAL` con una tasa técnica de 26.67% para poder construir y probar el flujo completo — pendiente de validación de tu contador, mismo tratamiento que `CCSS-EMPLEADO` (10.67%), `HORAS_EXTRA` y `FERIADO_OBLIGATORIO_TRABAJADO`.
  - Probado end-to-end (31/31 PASS): siembra de plan de cuentas real, vinculación de conceptos existentes, y cada uno de los 6 generadores de asientos probado con los cálculos downstream (nómina neta, aguinaldo, vacaciones, cesantía) verificados con valores conocidos — esos cálculos ya se probaron en sus fases respectivas, acá se probó la lógica nueva de generación y persistencia de asientos, incluida la reconciliación de aguinaldo y la detección de asientos desbalanceados.
- ✅ **Nómina fase 8: Cesantía (#145), commit `30cde23`.**"""

src = src.replace(anchor_section0, new_entry)

# ---------- 2. Roadmap: item 10 Asientos contables -> hecho ----------
anchor_roadmap = "10. ⬜ Asientos contables (planilla + provisiones)"
assert anchor_roadmap in src, "ANCHOR NOT FOUND: roadmap item 10"
assert src.count(anchor_roadmap) == 1, "ANCHOR NOT UNIQUE: roadmap item 10"
src = src.replace(
    anchor_roadmap,
    "10. ✅ Asientos contables — plan de cuentas nuevo, 6 tipos de asiento (planilla, provisión/pago de aguinaldo, provisión de vacaciones, cesantía al aprobar terminación, CCSS patronal), export CSV",
)

# ---------- 3. Seccion 5.2: nuevo pendiente (CCSS patronal) ----------
anchor_52 = """- 🟡 **Cesantía — interpretación de fracción de año (fase 8)** — El documento legal se contradice sobre si una fracción de año ">6 meses" o "≥6 meses" redondea al año siguiente para efectos de la tabla acumulativa del Art. 29. Se adoptó ">6 meses" (la versión de la sección detallada del documento). Necesita confirmación de tu abogado laboral antes de operar cesantía real — es un valor de catálogo (`CesantiaConfig.fraction_round_months`), no requiere cambio de código si hay que ajustarlo.
⏸️"""
assert anchor_52 in src, "ANCHOR NOT FOUND: seccion 5.2"
assert src.count(anchor_52) == 1, "ANCHOR NOT UNIQUE: seccion 5.2"
new_52 = """- 🟡 **Cesantía — interpretación de fracción de año (fase 8)** — El documento legal se contradice sobre si una fracción de año ">6 meses" o "≥6 meses" redondea al año siguiente para efectos de la tabla acumulativa del Art. 29. Se adoptó ">6 meses" (la versión de la sección detallada del documento). Necesita confirmación de tu abogado laboral antes de operar cesantía real — es un valor de catálogo (`CesantiaConfig.fraction_round_months`), no requiere cambio de código si hay que ajustarlo.
- 🟡 **CCSS patronal y plan de cuentas (fase 9)** — El concepto `CCSS-PATRONAL` (26.67%) es una tasa técnica de prueba, no confirmada por tu contador. Además, el plan de cuentas (`ChartOfAccount`) se sembró con 13 cuentas genéricas razonables para poder probar el flujo — revisar con tu contador si los códigos/nombres coinciden con los que realmente usa, o si hay que renombrarlos/agregar más antes de operar asientos reales.
⏸️"""
src = src.replace(anchor_52, new_52)

# ---------- 4. Seccion 5.3: bump fases 1-8 -> 1-9 ----------
anchor_53 = "- 🟢 **Mód. 15 (fases 1-8 de 11, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto, Vacaciones y Aguinaldo (fases 1-7) más Cesantía (`core/cesantia.py`: tabla oficial Art. 29 acumulativa con tope de 8 años, promedio salarial de 6 meses, modelo de terminación con aprobación). Detalle completo del porqué y las correcciones de proceso en sección 0."
assert anchor_53 in src, "ANCHOR NOT FOUND: seccion 5.3"
assert src.count(anchor_53) == 1, "ANCHOR NOT UNIQUE: seccion 5.3"
new_53 = "- 🟢 **Mód. 15 (fases 1-9 de 11, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto, Vacaciones, Aguinaldo y Cesantía (fases 1-8) más Asientos contables (`core/accounting.py`: plan de cuentas nuevo, 6 tipos de asiento con validación de balance, export CSV). Detalle completo del porqué y las correcciones de proceso en sección 0."
src = src.replace(anchor_53, new_53)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("OK: master doc actualizado (seccion 0, roadmap item 10, seccion 5.2, seccion 5.3)")
PYEOF

echo "=== diff resumido ==="
git diff --stat docs/WORKFORCE_AI_OS_PROYECTO.md

git add docs/WORKFORCE_AI_OS_PROYECTO.md
git commit -m "docs: actualizar master doc con fase 9 (Asientos contables) completa

- Seccion 0: nueva entrada fechada con el resumen de la fase, el bug
  de value/employer_value corregido, y el ajuste de diseño de RENTA.
- Roadmap de nomina: item 10 Asientos contables pasa de pendiente a hecho.
- Seccion 5.2: nuevo pendiente de validacion (tasa CCSS patronal +
  revision del plan de cuentas sembrado).
- Seccion 5.3: bump de 'fases 1-8 de 11' a 'fases 1-9 de 11'."

git push

echo "=== FIN Parte 7 ==="
