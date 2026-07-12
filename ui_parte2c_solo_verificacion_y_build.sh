#!/bin/bash
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
import re

path = "apps/frontend/app/[locale]/dashboard/layout.js"
with open(path, encoding="utf-8") as f:
    check = f.read()

problemas = []

open_a = len(re.findall(r"<a(?=[\s/>])", check))
if open_a != 2:
    problemas.append(f"esperaba 2 tags <a reales, encontre {open_a}")

close_a = check.count("</a>")
if close_a != 2:
    problemas.append(f"esperaba 2 cierres </a>, encontre {close_a}")

if check.count("<div") < 5:
    problemas.append(f"muy pocos <div ({check.count('<div')}), algo se perdio")
if "function renderLink" not in check:
    problemas.append("falta function renderLink")
if "function renderDisabled" not in check:
    problemas.append("falta function renderDisabled")
if "export default function DashboardLayout" not in check:
    problemas.append("falta export default function DashboardLayout")
if "<aside" not in check:
    problemas.append("falta <aside (la barra lateral en si)")

line_count = check.count("\n") + 1
if not (300 <= line_count <= 340):
    problemas.append(f"cantidad de lineas sospechosa: {line_count} (esperaba ~324)")

if problemas:
    print("XXX VERIFICACION FALLO XXX")
    for p in problemas:
        print(" -", p)
    raise SystemExit(1)

print(f"OK: layout.js verificado correctamente ({line_count} lineas, estructura intacta)")
PYEOF

echo "=== rebuild frontend ==="
docker compose build --no-cache frontend
docker compose up -d frontend
sleep 5
docker compose logs frontend --tail 30

echo "=== FIN Parte 2c ==="
