#!/bin/bash
# ============================================================
# Fase 10 (Archivo bancario) - Parte 4a: extender Employee (banco)
# ============================================================
# Agrega bank_account_type/bank_account_number a EmployeeUpdate y
# EmployeeResponse, y los conecta al PATCH existente de empleados
# (reusa el loop generico, no crea un endpoint nuevo).
# Ejecutar: cd /opt/workforce-ai-os && bash fase10_parte4a_employees.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/schemas.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if "bank_account_type" in src:
    print("SKIP: employees/schemas.py ya tiene bank_account_type (idempotente)")
else:
    anchor_update = '''class EmployeeUpdate(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    position: Optional[str] = None
    active: Optional[bool] = None'''
    assert anchor_update in src, "ANCHOR NOT FOUND: EmployeeUpdate"
    assert src.count(anchor_update) == 1, "ANCHOR NOT UNIQUE: EmployeeUpdate"
    new_update = '''class EmployeeUpdate(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    position: Optional[str] = None
    active: Optional[bool] = None
    bank_account_type: Optional[Literal["Cuenta de Ahorro", "Cuenta Corriente"]] = None
    bank_account_number: Optional[str] = None'''
    src = src.replace(anchor_update, new_update)

    anchor_response = '''class EmployeeResponse(BaseModel):
    id: UUID
    branch_id: UUID
    first_name: str
    last_name: str
    id_type: str
    id_number: str
    email: Optional[str] = None
    phone: Optional[str] = None
    position: str
    hire_date: date
    active: bool'''
    assert anchor_response in src, "ANCHOR NOT FOUND: EmployeeResponse"
    assert src.count(anchor_response) == 1, "ANCHOR NOT UNIQUE: EmployeeResponse"
    new_response = '''class EmployeeResponse(BaseModel):
    id: UUID
    branch_id: UUID
    first_name: str
    last_name: str
    id_type: str
    id_number: str
    email: Optional[str] = None
    phone: Optional[str] = None
    position: str
    hire_date: date
    active: bool
    bank_account_type: Optional[str] = None
    bank_account_number: Optional[str] = None'''
    src = src.replace(anchor_response, new_response)

    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK: employees/schemas.py actualizado")
PYEOF

python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/router.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if "bank_account_type" in src:
    print("SKIP: employees/router.py ya tiene bank_account_type (idempotente)")
else:
    anchor_resp_fn = '''def _employee_response(e: Employee) -> EmployeeResponse:
    return EmployeeResponse(
        id=e.id, branch_id=e.branch_id, first_name=e.first_name, last_name=e.last_name,
        id_type=e.id_type, id_number=e.id_number, email=e.email, phone=e.phone,
        position=e.position, hire_date=e.hire_date, active=e.active,
    )'''
    assert anchor_resp_fn in src, "ANCHOR NOT FOUND: _employee_response"
    assert src.count(anchor_resp_fn) == 1, "ANCHOR NOT UNIQUE: _employee_response"
    new_resp_fn = '''def _employee_response(e: Employee) -> EmployeeResponse:
    return EmployeeResponse(
        id=e.id, branch_id=e.branch_id, first_name=e.first_name, last_name=e.last_name,
        id_type=e.id_type, id_number=e.id_number, email=e.email, phone=e.phone,
        position=e.position, hire_date=e.hire_date, active=e.active,
        bank_account_type=e.bank_account_type, bank_account_number=e.bank_account_number,
    )'''
    src = src.replace(anchor_resp_fn, new_resp_fn)

    anchor_loop = 'for field in ("email", "phone", "position", "active"):'
    assert anchor_loop in src, "ANCHOR NOT FOUND: update_employee loop"
    assert src.count(anchor_loop) == 1, "ANCHOR NOT UNIQUE: update_employee loop"
    new_loop = 'for field in ("email", "phone", "position", "active", "bank_account_type", "bank_account_number"):'
    src = src.replace(anchor_loop, new_loop)

    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK: employees/router.py actualizado")
PYEOF

python3 -m py_compile apps/backend/app/modules/employees/schemas.py apps/backend/app/modules/employees/router.py && echo "SYNTAX OK: employees schemas.py + router.py"

echo "=== FIN Parte 4a (empleados) ==="
