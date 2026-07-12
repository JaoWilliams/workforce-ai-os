#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 1c: DISCOVERY final
# ============================================================
# Solo lectura. Ultimo dato que falta: la funcion _employee_response
# completa (para agregarle bank_account_type/bank_account_number al
# return), y confirmar el resto del archivo employees/router.py.
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte1c_discovery.sh
# Pegame TODO el output de vuelta.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

echo "############################################################"
echo "# 1. Funcion _employee_response completa"
echo "############################################################"
python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/router.py"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
start = None
for i, l in enumerate(lines):
    if l.startswith("def _employee_response"):
        start = i
        break
if start is None:
    print("NO ENCONTRADO")
else:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("@") or lines[j].startswith("def ") or lines[j].startswith("async def "):
            end = j
            break
    print("".join(lines[start:end]))
PYEOF

echo
echo "############################################################"
echo "# 2. Cuantas veces aparece el patron del loop de update_employee"
echo "############################################################"
grep -n 'for field in ("email", "phone", "position", "active"):' apps/backend/app/modules/employees/router.py

echo
echo "############################################################"
echo "# 3. i18n: claves 'payroll.' existentes (para reusar o agregar solo lo nuevo)"
echo "############################################################"
grep -n '"period_not_found"\|"payroll\.' apps/backend/app/i18n/es/messages.json | head -10

echo
echo "=== FIN discovery 1c ==="
