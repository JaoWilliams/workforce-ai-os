#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 8: actualizar doc maestro
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "docs/WORKFORCE_AI_OS_PROYECTO.md"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# ---------- 1. Seccion 0: nueva entrada (va arriba de fase 9) ----------
anchor_section0 = """## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 9: Asientos contables (#146), commit `aeb2354`.**"""
assert anchor_section0 in src, "ANCHOR NOT FOUND: seccion 0"
assert src.count(anchor_section0) == 1, "ANCHOR NOT UNIQUE: seccion 0"

new_entry = """## 0. Registro de cambios (esta actualización)
- ✅ **Nómina fase 10: Archivo bancario (#147), commit `ff6016a`.** Formato de salida NO inventado — lo diste vos con un ejemplo real de un archivo de tu banco: texto plano delimitado por TAB, sin encabezado, 4 columnas: tipo de cuenta / número de cuenta / monto (2 decimales) / glosa. La glosa real que confirmaste es `PLANILLA EMPRESARIAL BURGER KING COSTA RICA` (tu ejemplo tenía un typo — sin la R de BURGER — confirmaste que había que corregirlo), guardada como catálogo por tenant (`BankFileConfig`), no hardcodeada. Cada empleado ahora puede tener tipo y número de cuenta bancaria (`Employee.bank_account_type/bank_account_number`, nullable — se completan después del alta vía el mismo PATCH de empleados que ya existía, no es obligatorio al crear). Cada generación real del archivo queda persistida (`BankTransferFile` + líneas) para auditoría — qué se generó, cuándo, por cuánto, y cuántos empleados quedaron fuera por falta de cuenta bancaria cargada.
  - Patrón blocking-cascade de siempre: si falta la glosa configurada, no se genera nada. Si a un empleado individual le falta la cuenta bancaria, o su neto no es computable, o es cero/negativo, ESE empleado se excluye del archivo y queda listado con el motivo exacto — no bloquea a los demás.
  - 🟡 **Pendiente de validar contra el banco real:** la codificación de caracteres (UTF-8) y el salto de línea del archivo exportado son un valor por defecto razonable, no confirmado todavía contra una subida real al portal del banco — es un ajuste de una línea si el banco lo rechaza.
  - Probado end-to-end (27/27 PASS): 4 empleados de prueba cubriendo cada rama del patrón blocking-cascade (neto no computable, empleado no encontrado, neto cero/negativo, cuenta bancaria faltante, caso válido), formato del TXT verificado carácter por carácter contra tu ejemplo real, los 4 endpoints probados de punta a punta, y el caso de bloqueo total (todos los empleados excluidos).
- ✅ **Nómina fase 9: Asientos contables (#146), commit `aeb2354`.**"""

src = src.replace(anchor_section0, new_entry)

# ---------- 2. Roadmap: item 11 Archivo bancario -> hecho ----------
anchor_roadmap = "11. ⬜ Archivo bancario (formato pendiente de confirmar banco de Burger King — no se inventa)"
assert anchor_roadmap in src, "ANCHOR NOT FOUND: roadmap item 11"
assert src.count(anchor_roadmap) == 1, "ANCHOR NOT UNIQUE: roadmap item 11"
src = src.replace(
    anchor_roadmap,
    "11. ✅ Archivo bancario — formato real confirmado por el cliente (TXT delimitado por TAB, sin encabezado), glosa real cargada como catálogo, cuenta bancaria por empleado, generación con auditoría",
)

# ---------- 3. Seccion 5.2: nuevo pendiente (encoding archivo bancario) ----------
anchor_52 = """- 🟡 **CCSS patronal y plan de cuentas (fase 9)** — El concepto `CCSS-PATRONAL` (26.67%) es una tasa técnica de prueba, no confirmada por tu contador. Además, el plan de cuentas (`ChartOfAccount`) se sembró con 13 cuentas genéricas razonables para poder probar el flujo — revisar con tu contador si los códigos/nombres coinciden con los que realmente usa, o si hay que renombrarlos/agregar más antes de operar asientos reales.
⏸️ **Sprint 0 (scaffold) y Sprint 1 (mód. 1 en adelante) quedan en pausa hasta resolver lo anterior.**"""
assert anchor_52 in src, "ANCHOR NOT FOUND: seccion 5.2"
assert src.count(anchor_52) == 1, "ANCHOR NOT UNIQUE: seccion 5.2"
new_52 = """- 🟡 **CCSS patronal y plan de cuentas (fase 9)** — El concepto `CCSS-PATRONAL` (26.67%) es una tasa técnica de prueba, no confirmada por tu contador. Además, el plan de cuentas (`ChartOfAccount`) se sembró con 13 cuentas genéricas razonables para poder probar el flujo — revisar con tu contador si los códigos/nombres coinciden con los que realmente usa, o si hay que renombrarlos/agregar más antes de operar asientos reales.
- 🟡 **Archivo bancario — codificación no confirmada contra el banco real (fase 10)** — El formato (columnas, TAB, glosa) sí es real, confirmado con tu ejemplo. Lo único sin confirmar es la codificación de caracteres y el salto de línea del archivo exportado, porque todavía no se probó una subida real al portal del banco — ajuste de una línea si hace falta.
⏸️ **Sprint 0 (scaffold) y Sprint 1 (mód. 1 en adelante) quedan en pausa hasta resolver lo anterior.**"""
src = src.replace(anchor_52, new_52)

# ---------- 4. Seccion 5.3: bump fases 1-9 -> 1-10 ----------
anchor_53 = "- 🟢 **Mód. 15 (fases 1-9 de 11, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto, Vacaciones, Aguinaldo y Cesantía (fases 1-8) más Asientos contables (`core/accounting.py`: plan de cuentas nuevo, 6 tipos de asiento con validación de balance, export CSV). Detalle completo del porqué y las correcciones de proceso en sección 0."
assert anchor_53 in src, "ANCHOR NOT FOUND: seccion 5.3"
assert src.count(anchor_53) == 1, "ANCHOR NOT UNIQUE: seccion 5.3"
new_53 = "- 🟢 **Mód. 15 (fases 1-10 de 11, post-MVP)** — Reporte de horas trabajadas, Nómina bruta, `pay_frequency` en `Contract`, Calendario de planillas, Horas extra, Catálogo de feriados, Deducciones CCSS + Renta → Neto, Vacaciones, Aguinaldo, Cesantía y Asientos contables (fases 1-9) más Archivo bancario (`core/bank_file.py`: formato TXT real del banco, cuenta bancaria por empleado, generación con auditoría). Detalle completo del porqué y las correcciones de proceso en sección 0."
src = src.replace(anchor_53, new_53)

with open(path, "w", encoding="utf-8") as f:
    f.write(src)

print("OK: master doc actualizado (seccion 0, roadmap item 11, seccion 5.2, seccion 5.3)")
PYEOF

echo "=== diff resumido ==="
git diff --stat docs/WORKFORCE_AI_OS_PROYECTO.md

git add docs/WORKFORCE_AI_OS_PROYECTO.md
git commit -m "docs: actualizar master doc con fase 10 (Archivo bancario) completa

- Seccion 0: nueva entrada fechada con el resumen de la fase y la
  nota de codificacion pendiente de confirmar contra el banco real.
- Roadmap de nomina: item 11 Archivo bancario pasa de pendiente a hecho.
- Seccion 5.2: nuevo pendiente de validacion (codificacion/salto de
  linea del archivo exportado).
- Seccion 5.3: bump de 'fases 1-9 de 11' a 'fases 1-10 de 11'."

git push

echo "=== FIN Parte 8 ==="
