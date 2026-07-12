#!/bin/bash
# ============================================================
# UI/UX Nomina - Parte 3b: re-verificar corridas/page.js YA ESCRITO
# (no reescribe nada - tu pegado anterior estaba correcto, mi rango
# de lineas esperado estaba mal calibrado: el archivo real tiene
# ~730 lineas, no ~450) y, si pasa, aplicar el resto (sidebar + i18n
# ya se escribieron bien tambien) y hacer el build.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/frontend/app/[locale]/dashboard/nomina/corridas/page.js"
with open(path, encoding="utf-8") as f:
    check = f.read()

problemas = []
open_braces = check.count("{")
close_braces = check.count("}")
if open_braces != close_braces:
    problemas.append(f"llaves desbalanceadas: {{ {open_braces} vs }} {close_braces}")
open_parens = check.count("(")
close_parens = check.count(")")
if open_parens != close_parens:
    problemas.append(f"parentesis desbalanceados: ( {open_parens} vs ) {close_parens}")
for marker in [
    "export default function PayrollRunsPage",
    "function renderStepper",
    "function renderAnomalyQueue",
    "function renderEmployeeTable",
    "function renderActionPanel",
    "function handleTransition",
    "function handleCreate",
    "const STATUS_ORDER",
    "const RULE_ICONS",
]:
    if marker not in check:
        problemas.append(f"falta: {marker}")

line_count = check.count("\n") + 1
if not (650 <= line_count <= 850):
    problemas.append(f"cantidad de lineas sospechosa: {line_count} (esperaba ~650-850)")

if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)

print(f"OK: corridas/page.js verificado correctamente ({line_count} lineas, estructura intacta)")
PYEOF

echo "=== verificando que el sidebar tenga el item nuevo ==="
grep -n "payroll_runs" "apps/frontend/app/[locale]/dashboard/layout.js" || { echo "FALTA el item payroll_runs en el sidebar"; exit 1; }

echo "=== verificando que las claves i18n existan ==="
python3 -c "
import json
for path in ['apps/frontend/messages/es.json', 'apps/frontend/messages/en.json']:
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    assert 'payroll_runs' in data.get('nav', {}), f'{path}: falta nav.payroll_runs'
    assert 'title' in data.get('payroll_run', {}), f'{path}: falta payroll_run.title'
    print(f'OK: {path} tiene las claves nuevas')
"

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN Parte 3b ==="
