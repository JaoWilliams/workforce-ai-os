#!/bin/bash
# ============================================================
# Fix: UUID no serializable en la lista 'missing' de bank_file.py
# ============================================================
# Bug preexistente de fase 10: 4 lugares donde se arma la lista de
# empleados excluidos usan el UUID crudo en vez de str(UUID). FastAPI
# no puede serializar UUID en una respuesta de error (detail dict
# crudo, no pasa por un response_model), y crashea con 500 en vez de
# devolver el 400 esperado con el motivo de bloqueo.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/backend/app/core/bank_file.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

edits = [
    (
        'missing.append({"employee_id": row["employee_id"], "employee_name": employee_name, "reason": "net_pay_not_computable"})',
        'missing.append({"employee_id": str(row["employee_id"]), "employee_name": employee_name, "reason": "net_pay_not_computable"})',
    ),
    (
        'missing.append({"employee_id": row["employee_id"], "employee_name": None, "reason": "employee_not_found"})',
        'missing.append({"employee_id": str(row["employee_id"]), "employee_name": None, "reason": "employee_not_found"})',
    ),
    (
        'missing.append({"employee_id": employee.id, "employee_name": employee_name, "reason": "zero_or_negative_net_pay"})',
        'missing.append({"employee_id": str(employee.id), "employee_name": employee_name, "reason": "zero_or_negative_net_pay"})',
    ),
    (
        'missing.append({"employee_id": employee.id, "employee_name": employee_name, "reason": "missing_bank_account"})',
        'missing.append({"employee_id": str(employee.id), "employee_name": employee_name, "reason": "missing_bank_account"})',
    ),
]

for old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND: {old}"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE: {old}"
    src = src.replace(old, new, 1)
    print("OK edicion aplicada:", new[:70], "...")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: bank_file.py escrito")
PYEOF

echo "=== verificacion de sintaxis (host, sin pasar por Docker) ==="
python3 -m py_compile apps/backend/app/core/bank_file.py && echo "SYNTAX OK"

echo "=== rebuild api ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 20

echo "=== FIN fix bank_file UUID ==="
