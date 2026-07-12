#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 1b: DISCOVERY complementario
# ============================================================
# Solo lectura. Completa lo que faltó de la Parte 1: schemas/router
# de Employee y el resto de compute_net_payroll_rows / compute_payroll_rows.
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte1b_discovery.sh
# Pegame TODO el output de vuelta.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "############################################################"
echo "# 1. EmployeeCreate / EmployeeUpdate / EmployeeResponse (schemas.py)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/schemas.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
for target in ("class EmployeeCreate", "class EmployeeUpdate", "class EmployeeResponse"):
    start = None
    for i, l in enumerate(lines):
        if l.startswith(target):
            start = i
            break
    if start is None:
        print(f"NO ENCONTRADO: {target}\n")
        continue
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("class "):
            end = j
            break
    print("".join(lines[start:end]))
    print()
PYEOF

echo
echo "############################################################"
echo "# 2. create_employee / update_employee (router.py)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/router.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
for target in ("async def create_employee", "async def update_employee"):
    start = None
    for i, l in enumerate(lines):
        if target in l:
            start = max(0, i - 3)  # incluir el decorador @router...
            break
    if start is None:
        print(f"NO ENCONTRADO: {target}\n")
        continue
    end = len(lines)
    for j in range(start + 4, len(lines)):
        if lines[j].startswith("@") or lines[j].startswith("async def ") or lines[j].startswith("def "):
            end = j
            break
    print("".join(lines[start:end]))
    print()
PYEOF

echo
echo "############################################################"
echo "# 3. Imports de employees/schemas.py y employees/router.py"
echo "############################################################"
sed -n '1,25p' apps/backend/app/modules/employees/schemas.py
echo "---"
sed -n '1,30p' apps/backend/app/modules/employees/router.py

echo
echo "############################################################"
echo "# 4. Resto de compute_net_payroll_rows (desde 'mensual' en adelante)"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/core/renta.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if 'if period.pay_frequency == "mensual":' in l:
        start = i
        break
if start is None:
    print("NO ENCONTRADO")
else:
    end = min(start + 70, len(lines))
    print("".join(lines[start:end]))
PYEOF

echo
echo "############################################################"
echo "# 5. Como arma compute_payroll_rows cada 'row' (employee_id, etc.)"
echo "############################################################"
grep -n "employee_id" apps/backend/app/core/payroll.py | head -20

echo
echo "############################################################"
echo "# 6. Permisos existentes (para confirmar payroll.manage/.view)"
echo "############################################################"
grep -n "\"payroll\.\|'payroll\." apps/backend/app/modules/rbac/*.py 2>/dev/null | head -20

echo
echo "=== FIN discovery 1b ==="
