#!/bin/bash
# ============================================================
# Onboarding incompleto - Parte A: backend (motor + hooks + endpoint)
# Nuevo modulo core/onboarding.py + wiring en employees/router.py y
# biometrics/router.py + campo onboarding_missing en EmployeeResponse +
# i18n para las 3 nuevas reglas en namespaces confianza/dashboard.
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

# ---------- 1. nuevo archivo core/onboarding.py ----------
cat > apps/backend/app/core/onboarding.py << 'PYEOF'
"""
Deteccion proactiva de onboarding incompleto (cuenta bancaria, contrato,
enrolamiento biometrico). Reutiliza el motor de Confianza Operativa (mod
17a) via TrustFlag para dejar un registro auditable y visible en la cola
de excepciones existente, ademas de exponerse como campo calculado en
EmployeeResponse para el badge de la pantalla de Empleados y el contador
del Dashboard.

Se dispara (sync_onboarding_flags) en cada punto donde el estado de un
empleado puede cambiar: alta, edicion, alta de contrato, alta de
enrolamiento biometrico. Tambien hay un endpoint de backfill
(POST /api/employees/onboarding-check) para escanear empleados activos
que ya existian antes de este chequeo.
"""
from uuid import UUID, uuid4

from sqlalchemy import select

from app.db.models import BiometricEnrollment, Contract, Employee, TrustFlag

ONBOARDING_RULE_MAP = {
    "bank_account": "onboarding_missing_bank_account",
    "contract": "onboarding_missing_contract",
    "biometric": "onboarding_missing_biometric",
}
ONBOARDING_RULE_CODES = list(ONBOARDING_RULE_MAP.values())
ONBOARDING_REASON_MAP = {
    "bank_account": "El empleado no tiene cuenta bancaria registrada para el pago de planilla",
    "contract": "El empleado no tiene ningun contrato registrado",
    "biometric": "El empleado no tiene enrolamiento biometrico activo",
}


async def get_missing_items_bulk(session, employees: list[Employee]) -> dict:
    """Version de solo lectura (no crea/resuelve TrustFlag), pensada para
    listados: 2 consultas bulk en vez de N+1 por empleado."""
    active_ids = [e.id for e in employees if e.active]
    if not active_ids:
        return {}
    contract_result = await session.execute(
        select(Contract.employee_id).where(Contract.employee_id.in_(active_ids)).distinct()
    )
    has_contract_ids = {row[0] for row in contract_result.all()}
    bio_result = await session.execute(
        select(BiometricEnrollment.employee_id).where(
            BiometricEnrollment.employee_id.in_(active_ids),
            BiometricEnrollment.active.is_(True),
        ).distinct()
    )
    has_bio_ids = {row[0] for row in bio_result.all()}
    result = {}
    for e in employees:
        if not e.active:
            continue
        missing = []
        if not e.bank_account_number:
            missing.append("bank_account")
        if e.id not in has_contract_ids:
            missing.append("contract")
        if e.id not in has_bio_ids:
            missing.append("biometric")
        if missing:
            result[e.id] = missing
    return result


async def sync_onboarding_flags(session, tenant_id: UUID, employee: Employee) -> dict:
    """Calcula que le falta a un empleado y sincroniza TrustFlag: crea los
    que faltan (si no existe ya uno sin resolver del mismo tipo) y resuelve
    automaticamente los que ya no aplican. Devuelve {"missing": [...]}."""
    if not employee.active:
        existing_result = await session.execute(
            select(TrustFlag).where(
                TrustFlag.employee_id == employee.id,
                TrustFlag.rule_code.in_(ONBOARDING_RULE_CODES),
                TrustFlag.resolved.is_(False),
            )
        )
        for f in existing_result.scalars().all():
            f.resolved = True
        await session.flush()
        return {"missing": []}

    missing = []
    if not employee.bank_account_number:
        missing.append("bank_account")
    contract_result = await session.execute(select(Contract).where(Contract.employee_id == employee.id))
    if contract_result.scalars().first() is None:
        missing.append("contract")
    bio_result = await session.execute(
        select(BiometricEnrollment).where(
            BiometricEnrollment.employee_id == employee.id,
            BiometricEnrollment.active.is_(True),
        )
    )
    if bio_result.scalars().first() is None:
        missing.append("biometric")

    existing_result = await session.execute(
        select(TrustFlag).where(
            TrustFlag.employee_id == employee.id,
            TrustFlag.rule_code.in_(ONBOARDING_RULE_CODES),
            TrustFlag.resolved.is_(False),
        )
    )
    existing_by_rule = {f.rule_code: f for f in existing_result.scalars().all()}

    for key, rule_code in ONBOARDING_RULE_MAP.items():
        if key in missing:
            if rule_code not in existing_by_rule:
                session.add(TrustFlag(
                    id=uuid4(), tenant_id=tenant_id, employee_id=employee.id,
                    payroll_period_id=None, branch_id=employee.branch_id,
                    rule_code=rule_code, severity="medium",
                    details={"reason": ONBOARDING_REASON_MAP[key]}, resolved=False,
                ))
        else:
            existing = existing_by_rule.get(rule_code)
            if existing is not None:
                existing.resolved = True

    await session.flush()
    return {"missing": missing}
PYEOF
echo "OK: core/onboarding.py creado"

# ---------- 2. EmployeeResponse: agregar onboarding_missing ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/schemas.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

old = '''class EmployeeResponse(BaseModel):
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
new = '''class EmployeeResponse(BaseModel):
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
    bank_account_number: Optional[str] = None
    onboarding_missing: list[str] = []'''

assert old in src, "ANCHOR NOT FOUND: EmployeeResponse"
assert src.count(old) == 1, "ANCHOR NOT UNIQUE: EmployeeResponse"
src = src.replace(old, new, 1)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: schemas.py - onboarding_missing agregado a EmployeeResponse")
PYEOF

# ---------- 3. employees/router.py: import + 4 hooks + endpoint nuevo ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/employees/router.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []

# import
edits.append(("import onboarding", '''from app.core.contracts_pdf import generate_contract_pdf''',
'''from app.core.contracts_pdf import generate_contract_pdf
from app.core.onboarding import get_missing_items_bulk, sync_onboarding_flags'''))

# create_employee
edits.append(("create_employee hook", '''        session.add(employee)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="employee.created", resource_type="employee", resource_id=employee.id,
            extra={"first_name": payload.first_name, "last_name": payload.last_name,
                   "id_type": payload.id_type, "id_number": payload.id_number, "position": payload.position},
        )
        await session.commit()
        await session.refresh(employee)
    return _employee_response(employee)''',
'''        session.add(employee)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="employee.created", resource_type="employee", resource_id=employee.id,
            extra={"first_name": payload.first_name, "last_name": payload.last_name,
                   "id_type": payload.id_type, "id_number": payload.id_number, "position": payload.position},
        )
        await session.commit()
        await session.refresh(employee)
        sync_result = await sync_onboarding_flags(session, current_user.tenant_id, employee)
        await session.commit()
    response = _employee_response(employee)
    response.onboarding_missing = sync_result["missing"]
    return response'''))

# list_employees + nuevo endpoint onboarding-check (insertado antes de update_employee)
edits.append(("list_employees + nuevo endpoint", '''@router.get("", response_model=list[EmployeeResponse])
async def list_employees(
    current_user: User = Depends(require_permission("employees.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee))
        employees = result.scalars().all()
    return [_employee_response(e) for e in employees]''',
'''@router.get("", response_model=list[EmployeeResponse])
async def list_employees(
    current_user: User = Depends(require_permission("employees.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee))
        employees = result.scalars().all()
        missing_map = await get_missing_items_bulk(session, employees)
    responses = []
    for e in employees:
        r = _employee_response(e)
        r.onboarding_missing = missing_map.get(e.id, [])
        responses.append(r)
    return responses


@router.post("/onboarding-check")
async def run_onboarding_check(
    current_user: User = Depends(require_permission("employees.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee).where(Employee.active.is_(True)))
        employees = result.scalars().all()
        checked = 0
        with_gaps = 0
        for e in employees:
            sync_result = await sync_onboarding_flags(session, current_user.tenant_id, e)
            checked += 1
            if sync_result["missing"]:
                with_gaps += 1
        await session.commit()
    return {"checked": checked, "with_gaps": with_gaps}'''))

# update_employee
edits.append(("update_employee hook", '''        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="employee.updated", resource_type="employee", resource_id=employee.id, extra=changes,
        )
        await session.commit()
        await session.refresh(employee)
    return _employee_response(employee)''',
'''        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="employee.updated", resource_type="employee", resource_id=employee.id, extra=changes,
        )
        await session.commit()
        await session.refresh(employee)
        sync_result = await sync_onboarding_flags(session, current_user.tenant_id, employee)
        await session.commit()
    response = _employee_response(employee)
    response.onboarding_missing = sync_result["missing"]
    return response'''))

# create_contract
edits.append(("create_contract hook", '''        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="contract.created", resource_type="contract", resource_id=contract.id,
            extra={"contract_type": payload.contract_type, "base_salary": payload.base_salary,
                   "currency": payload.currency, "pay_frequency": payload.pay_frequency,
                   "employee_id": str(employee_id), "pdf_generated": True},
        )
        await session.commit()
        await session.refresh(contract)
    return _contract_response(contract)''',
'''        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="contract.created", resource_type="contract", resource_id=contract.id,
            extra={"contract_type": payload.contract_type, "base_salary": payload.base_salary,
                   "currency": payload.currency, "pay_frequency": payload.pay_frequency,
                   "employee_id": str(employee_id), "pdf_generated": True},
        )
        await session.commit()
        await session.refresh(contract)
        await sync_onboarding_flags(session, current_user.tenant_id, employee)
        await session.commit()
    return _contract_response(contract)'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: employees/router.py escrito")
PYEOF

# ---------- 4. biometrics/router.py: import + hook ----------
python3 << 'PYEOF'
path = "apps/backend/app/modules/biometrics/router.py"
with open(path, encoding="utf-8") as f:
    src = f.read()

edits = []
edits.append(("import onboarding", '''from app.core.audit import log_audit''',
'''from app.core.audit import log_audit
from app.core.onboarding import sync_onboarding_flags'''))

edits.append(("create_biometric_enrollment hook", '''        session.add(enrollment)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="biometric_enrollment.created", resource_type="biometric_enrollment",
            resource_id=enrollment.id,
            extra={"employee_id": str(employee_id), "device_id": str(payload.device_id),
                   "biometric_type": payload.biometric_type, "is_simulated": True,
                   "consent_record_id": str(consent.id)},
        )
        await session.commit()
        await session.refresh(enrollment)
    return _to_response(enrollment)''',
'''        session.add(enrollment)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="biometric_enrollment.created", resource_type="biometric_enrollment",
            resource_id=enrollment.id,
            extra={"employee_id": str(employee_id), "device_id": str(payload.device_id),
                   "biometric_type": payload.biometric_type, "is_simulated": True,
                   "consent_record_id": str(consent.id)},
        )
        await session.commit()
        await session.refresh(enrollment)
        await sync_onboarding_flags(session, current_user.tenant_id, employee)
        await session.commit()
    return _to_response(enrollment)'''))

for label, old, new in edits:
    assert old in src, f"ANCHOR NOT FOUND ({label})"
    assert src.count(old) == 1, f"ANCHOR NOT UNIQUE ({label})"
    src = src.replace(old, new, 1)
    print(f"OK edicion aplicada: {label}")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK: biometrics/router.py escrito")
PYEOF

# ---------- 5. i18n: rule_onboarding_* en namespaces confianza y dashboard ----------
python3 << 'PYEOF'
import json

nuevas_es = {
    "rule_onboarding_missing_bank_account": "Cuenta bancaria pendiente",
    "rule_onboarding_missing_contract": "Contrato pendiente",
    "rule_onboarding_missing_biometric": "Enrolamiento biométrico pendiente",
}
nuevas_en = {
    "rule_onboarding_missing_bank_account": "Bank account pending",
    "rule_onboarding_missing_contract": "Contract pending",
    "rule_onboarding_missing_biometric": "Biometric enrollment pending",
}

for path, nuevas in [
    ("apps/frontend/messages/es.json", nuevas_es),
    ("apps/frontend/messages/en.json", nuevas_en),
]:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for ns in ("confianza", "dashboard"):
        data.setdefault(ns, {})
        added = 0
        for k, v in nuevas.items():
            if k not in data[ns]:
                data[ns][k] = v
                added += 1
        print(f"OK: {path} - {ns} +{added}")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PYEOF

# ---------- 6. verificacion de sintaxis (host) ----------
echo "=== verificacion de sintaxis ==="
python3 -m py_compile apps/backend/app/core/onboarding.py && echo "onboarding.py SYNTAX OK"
python3 -m py_compile apps/backend/app/modules/employees/router.py && echo "employees/router.py SYNTAX OK"
python3 -m py_compile apps/backend/app/modules/employees/schemas.py && echo "employees/schemas.py SYNTAX OK"
python3 -m py_compile apps/backend/app/modules/biometrics/router.py && echo "biometrics/router.py SYNTAX OK"

# ---------- 7. rebuild api ----------
echo "=== rebuild api ==="
docker compose build --no-cache api
docker compose up -d api
sleep 5
docker compose logs api --tail 30

echo "=== FIN Parte A (backend) ==="
