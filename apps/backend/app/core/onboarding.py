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
