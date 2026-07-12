#!/bin/bash
# ============================================================
# Fase 8 (Cesantía) - Parte 3: schemas + endpoints + i18n
# ============================================================
# CAMBIOS:
#   catalogs/schemas.py: + CesantiaConfigUpsert/Response,
#     CesantiaScaleRowUpsert/Response, CesantiaScaleBulkUpsert
#   catalogs/router.py: + import CesantiaConfig/CesantiaScaleRow,
#     PUT/GET /api/catalogs/cesantia-config,
#     PUT/GET /api/catalogs/cesantia-scale (bulk replace de la tabla)
#   payroll/schemas.py: + TerminationCreate/Response/StatusUpdate
#     (Response trae embebidos los campos de cálculo de cesantía:
#     cesantia_days, cesantia_amount, banderas de datos faltantes)
#   payroll/router.py: + import Termination, compute_cesantia_amount,
#     POST /api/payroll/terminations (crea, status=pending, valida
#       empleado activo y que no exista terminación previa),
#     GET /api/payroll/terminations (lista, cesantía calculada inline),
#     PATCH /api/payroll/terminations/{id}/status (approved/rejected;
#       al aprobar, efecto lateral Employee.active=False)
#   i18n es/en: + 5 claves payroll.termination_* (mismo patrón flat
#     que vacation_*/overtime_*), insertadas via json para mantener
#     el orden alfabético existente del archivo.
# Ejecutar: cd /opt/workforce-ai-os && bash fase8_parte3_schemas_router.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"

python3 << 'PYEOF'
import json

BACKEND = "apps/backend/app"

# ---------- 1. catalogs/schemas.py: append Cesantia schemas ----------
catalogs_schemas_path = f"{BACKEND}/modules/catalogs/schemas.py"
with open(catalogs_schemas_path, "r", encoding="utf-8") as f:
    src = f.read()

addition = '''
class CesantiaConfigUpsert(BaseModel):
    max_years_cap: int = 8
    fraction_round_months: int = 6
    days_3to6_months: float = 7
    days_6to12_months: float = 14
    daily_divisor: float = 30
    months_for_average: int = 6
class CesantiaConfigResponse(BaseModel):
    max_years_cap: int
    fraction_round_months: int
    days_3to6_months: float
    days_6to12_months: float
    daily_divisor: float
    months_for_average: int
class CesantiaScaleRowUpsert(BaseModel):
    year_number: int
    days: float
class CesantiaScaleRowResponse(BaseModel):
    year_number: int
    days: float
class CesantiaScaleBulkUpsert(BaseModel):
    rows: list[CesantiaScaleRowUpsert]
'''

if "CesantiaConfigUpsert" not in src:
    with open(catalogs_schemas_path, "a", encoding="utf-8") as f:
        f.write(addition)
    print("OK catalogs/schemas.py: Cesantia schemas agregados")
else:
    print("SKIP catalogs/schemas.py: ya tenia Cesantia schemas")

# ---------- 2. catalogs/router.py: import + schemas import + endpoints ----------
catalogs_router_path = f"{BACKEND}/modules/catalogs/router.py"
with open(catalogs_router_path, "r", encoding="utf-8") as f:
    src = f.read()

anchor_model_import = "from app.db.models import AguinaldoConfig, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig"
assert anchor_model_import in src, "ANCHOR NOT FOUND: catalogs/router.py model import"
src = src.replace(
    anchor_model_import,
    "from app.db.models import AguinaldoConfig, CesantiaConfig, CesantiaScaleRow, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig",
)

anchor_schemas_import = """    AguinaldoConfigResponse,
    AguinaldoConfigUpsert,
)"""
assert anchor_schemas_import in src, "ANCHOR NOT FOUND: catalogs/router.py schemas import"
src = src.replace(
    anchor_schemas_import,
    """    AguinaldoConfigResponse,
    AguinaldoConfigUpsert,
    CesantiaConfigResponse,
    CesantiaConfigUpsert,
    CesantiaScaleRowResponse,
    CesantiaScaleRowUpsert,
    CesantiaScaleBulkUpsert,
)""",
)

anchor_last_endpoint = '''    if config is None:
        return None
    return AguinaldoConfigResponse(
        period_start_month=config.period_start_month, period_start_day=config.period_start_day,
        period_end_month=config.period_end_month, period_end_day=config.period_end_day,
        divisor=float(config.divisor),
    )'''
occurrences = src.count(anchor_last_endpoint)
assert occurrences == 1, f"ANCHOR NOT UNIQUE (found {occurrences}): catalogs/router.py last endpoint"

new_endpoints = anchor_last_endpoint + '''
@hours_router.put("/cesantia-config", response_model=CesantiaConfigResponse)
async def upsert_cesantia_config(
    payload: CesantiaConfigUpsert,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(CesantiaConfig))
        config = result.scalars().first()
        if config is None:
            config = CesantiaConfig(
                id=uuid4(), tenant_id=current_user.tenant_id,
                max_years_cap=payload.max_years_cap, fraction_round_months=payload.fraction_round_months,
                days_3to6_months=payload.days_3to6_months, days_6to12_months=payload.days_6to12_months,
                daily_divisor=payload.daily_divisor, months_for_average=payload.months_for_average,
            )
            session.add(config)
            action = "cesantia_config.created"
        else:
            config.max_years_cap = payload.max_years_cap
            config.fraction_round_months = payload.fraction_round_months
            config.days_3to6_months = payload.days_3to6_months
            config.days_6to12_months = payload.days_6to12_months
            config.daily_divisor = payload.daily_divisor
            config.months_for_average = payload.months_for_average
            action = "cesantia_config.updated"
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=action, resource_type="cesantia_config", resource_id=None,
            extra={"max_years_cap": payload.max_years_cap},
        )
        await session.commit()
        await session.refresh(config)
    return CesantiaConfigResponse(
        max_years_cap=config.max_years_cap, fraction_round_months=config.fraction_round_months,
        days_3to6_months=float(config.days_3to6_months), days_6to12_months=float(config.days_6to12_months),
        daily_divisor=float(config.daily_divisor), months_for_average=config.months_for_average,
    )
@hours_router.get("/cesantia-config", response_model=Optional[CesantiaConfigResponse])
async def get_cesantia_config(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(CesantiaConfig))
        config = result.scalars().first()
    if config is None:
        return None
    return CesantiaConfigResponse(
        max_years_cap=config.max_years_cap, fraction_round_months=config.fraction_round_months,
        days_3to6_months=float(config.days_3to6_months), days_6to12_months=float(config.days_6to12_months),
        daily_divisor=float(config.daily_divisor), months_for_average=config.months_for_average,
    )
@hours_router.put("/cesantia-scale", response_model=list[CesantiaScaleRowResponse])
async def upsert_cesantia_scale(
    payload: CesantiaScaleBulkUpsert,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        await session.execute(CesantiaScaleRow.__table__.delete())
        rows = []
        for item in payload.rows:
            row = CesantiaScaleRow(
                id=uuid4(), tenant_id=current_user.tenant_id,
                year_number=item.year_number, days=item.days,
            )
            session.add(row)
            rows.append(row)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="cesantia_scale.replaced", resource_type="cesantia_scale_row", resource_id=None,
            extra={"rows_count": len(payload.rows)},
        )
        await session.commit()
        for row in rows:
            await session.refresh(row)
    return [
        CesantiaScaleRowResponse(year_number=r.year_number, days=float(r.days))
        for r in sorted(rows, key=lambda r: r.year_number)
    ]
@hours_router.get("/cesantia-scale", response_model=list[CesantiaScaleRowResponse])
async def get_cesantia_scale(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(CesantiaScaleRow).order_by(CesantiaScaleRow.year_number))
        rows = result.scalars().all()
    return [CesantiaScaleRowResponse(year_number=r.year_number, days=float(r.days)) for r in rows]
'''

if "cesantia-config" not in src:
    src = src.replace(anchor_last_endpoint, new_endpoints)
    with open(catalogs_router_path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK catalogs/router.py: imports + endpoints de cesantia agregados")
else:
    print("SKIP catalogs/router.py: ya tenia endpoints de cesantia")

# ---------- 3. payroll/schemas.py: append Termination schemas ----------
payroll_schemas_path = f"{BACKEND}/modules/payroll/schemas.py"
with open(payroll_schemas_path, "r", encoding="utf-8") as f:
    src = f.read()

addition = '''
class TerminationCreate(BaseModel):
    employee_id: UUID
    termination_date: date
    cause: str
    con_responsabilidad_patronal: bool
    notes: Optional[str] = None
class TerminationStatusUpdate(BaseModel):
    status: str
    notes: Optional[str] = None
class TerminationResponse(BaseModel):
    id: UUID
    employee_id: UUID
    employee_name: str
    termination_date: date
    cause: str
    con_responsabilidad_patronal: bool
    status: str
    reviewed_by: Optional[UUID] = None
    reviewed_at: Optional[datetime] = None
    notes: Optional[str] = None
    cesantia_eligible: bool = False
    cesantia_days: Optional[float] = None
    cesantia_years_recognized: Optional[int] = None
    cesantia_daily_rate: Optional[float] = None
    cesantia_amount: Optional[float] = None
    cesantia_config_missing: bool = False
    cesantia_scale_missing: bool = False
    cesantia_frequency_unsupported: bool = False
    cesantia_no_history: bool = False
    cesantia_partial_history: bool = False
'''

if "TerminationCreate" not in src:
    with open(payroll_schemas_path, "a", encoding="utf-8") as f:
        f.write(addition)
    print("OK payroll/schemas.py: Termination schemas agregados")
else:
    print("SKIP payroll/schemas.py: ya tenia Termination schemas")

# ---------- 4. payroll/router.py: imports + endpoints ----------
payroll_router_path = f"{BACKEND}/modules/payroll/router.py"
with open(payroll_router_path, "r", encoding="utf-8") as f:
    src = f.read()

anchor_model_import = "from app.db.models import Branch, Employee, OvertimeApproval, PayrollPeriod, ShiftTemplate, Tenant, User, VacationRequest"
assert anchor_model_import in src, "ANCHOR NOT FOUND: payroll/router.py model import"
src = src.replace(
    anchor_model_import,
    "from app.db.models import Branch, Employee, OvertimeApproval, PayrollPeriod, ShiftTemplate, Tenant, Termination, User, VacationRequest",
)

anchor_core_import = "from app.core.aguinaldo import compute_aguinaldo_rows"
assert anchor_core_import in src, "ANCHOR NOT FOUND: payroll/router.py core import"
src = src.replace(
    anchor_core_import,
    anchor_core_import + "\nfrom app.core.cesantia import compute_cesantia_amount",
)

anchor_schemas_import = """    VacationStatusUpdate,
    AguinaldoRow,
)"""
assert anchor_schemas_import in src, "ANCHOR NOT FOUND: payroll/router.py schemas import"
src = src.replace(
    anchor_schemas_import,
    """    VacationStatusUpdate,
    AguinaldoRow,
    TerminationCreate,
    TerminationResponse,
    TerminationStatusUpdate,
)""",
)

anchor_last_endpoint = '''    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_aguinaldo_rows(session, year, branch_id)
    return rows'''
occurrences = src.count(anchor_last_endpoint)
assert occurrences == 1, f"ANCHOR NOT UNIQUE (found {occurrences}): payroll/router.py last endpoint"

new_endpoints = anchor_last_endpoint + '''
async def _termination_response(t: Termination, employee: Employee, session) -> TerminationResponse:
    cesantia = await compute_cesantia_amount(session, t)
    return TerminationResponse(
        id=t.id, employee_id=t.employee_id, employee_name=f"{employee.first_name} {employee.last_name}",
        termination_date=t.termination_date, cause=t.cause,
        con_responsabilidad_patronal=t.con_responsabilidad_patronal, status=t.status,
        reviewed_by=t.reviewed_by, reviewed_at=t.reviewed_at, notes=t.notes,
        cesantia_eligible=cesantia["eligible"], cesantia_days=cesantia["days"],
        cesantia_years_recognized=cesantia["years_recognized"], cesantia_daily_rate=cesantia["daily_rate"],
        cesantia_amount=cesantia["amount"], cesantia_config_missing=cesantia["config_missing"],
        cesantia_scale_missing=cesantia["scale_missing"], cesantia_frequency_unsupported=cesantia["frequency_unsupported"],
        cesantia_no_history=cesantia["no_history"], cesantia_partial_history=cesantia["partial_history"],
    )
@router.post("/terminations", response_model=TerminationResponse, status_code=201)
async def create_termination(
    payload: TerminationCreate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        emp_result = await session.execute(select(Employee).where(Employee.id == payload.employee_id))
        employee = emp_result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))
        if not employee.active:
            raise HTTPException(status_code=400, detail=translate("payroll.termination_employee_inactive", locale))
        existing_result = await session.execute(
            select(Termination).where(Termination.employee_id == payload.employee_id)
        )
        if existing_result.scalars().first() is not None:
            raise HTTPException(status_code=400, detail=translate("payroll.termination_already_exists", locale))
        term = Termination(
            id=uuid4(), tenant_id=current_user.tenant_id, employee_id=payload.employee_id,
            termination_date=payload.termination_date, cause=payload.cause,
            con_responsabilidad_patronal=payload.con_responsabilidad_patronal,
            status="pending", notes=payload.notes,
        )
        session.add(term)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="termination.requested", resource_type="termination", resource_id=term.id,
            extra={"employee_id": str(payload.employee_id), "con_responsabilidad_patronal": payload.con_responsabilidad_patronal},
        )
        await session.commit()
        await session.refresh(term)
        response = await _termination_response(term, employee, session)
    return response
@router.get("/terminations", response_model=list[TerminationResponse])
async def list_terminations(
    employee_id: Optional[UUID] = None,
    status: Optional[str] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(Termination, Employee).join(Employee, Employee.id == Termination.employee_id)
        if employee_id is not None:
            query = query.where(Termination.employee_id == employee_id)
        if status is not None:
            query = query.where(Termination.status == status)
        result = await session.execute(query.order_by(Termination.created_at.desc()))
        rows = result.all()
        responses = [await _termination_response(t, e, session) for t, e in rows]
    return responses
@router.patch("/terminations/{termination_id}/status", response_model=TerminationResponse)
async def update_termination_status(
    termination_id: UUID,
    payload: TerminationStatusUpdate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.status not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail=translate("payroll.termination_invalid_status", locale))
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Termination, Employee)
            .join(Employee, Employee.id == Termination.employee_id)
            .where(Termination.id == termination_id)
        )
        row = result.first()
        if row is None:
            raise HTTPException(status_code=404, detail=translate("payroll.termination_not_found", locale))
        term, employee = row
        if term.status != "pending":
            raise HTTPException(status_code=400, detail=translate("payroll.termination_not_pending", locale))
        term.status = payload.status
        term.reviewed_by = current_user.id
        term.reviewed_at = datetime.now(timezone.utc)
        term.notes = payload.notes
        if payload.status == "approved":
            employee.active = False
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=f"termination.{payload.status}", resource_type="termination", resource_id=term.id,
            extra={"employee_id": str(term.employee_id), "notes": payload.notes},
        )
        await session.commit()
        await session.refresh(term)
        await session.refresh(employee)
        response = await _termination_response(term, employee, session)
    return response
'''

if "/terminations" not in src:
    src = src.replace(anchor_last_endpoint, new_endpoints)
    with open(payroll_router_path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK payroll/router.py: imports + endpoints de terminations agregados")
else:
    print("SKIP payroll/router.py: ya tenia endpoints de terminations")

# ---------- 5. i18n es/en: termination keys ----------
new_keys_es = {
    "payroll.termination_already_exists": "Ya existe un registro de terminacion para este empleado",
    "payroll.termination_employee_inactive": "El empleado ya esta inactivo (posiblemente ya fue terminado)",
    "payroll.termination_invalid_status": "Estado invalido (debe ser approved o rejected)",
    "payroll.termination_not_found": "Registro de terminacion no encontrado",
    "payroll.termination_not_pending": "Este registro de terminacion ya fue revisado",
}
new_keys_en = {
    "payroll.termination_already_exists": "A termination record already exists for this employee",
    "payroll.termination_employee_inactive": "This employee is already inactive (possibly already terminated)",
    "payroll.termination_invalid_status": "Invalid status (must be approved or rejected)",
    "payroll.termination_not_found": "Termination record not found",
    "payroll.termination_not_pending": "This termination record has already been reviewed",
}

for lang, new_keys in (("es", new_keys_es), ("en", new_keys_en)):
    path = f"{BACKEND}/i18n/{lang}/messages.json"
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    added = False
    for k, v in new_keys.items():
        if k not in data:
            data[k] = v
            added = True
    if added:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.write("\n")
        print(f"OK i18n/{lang}/messages.json: claves termination_* agregadas")
    else:
        print(f"SKIP i18n/{lang}/messages.json: ya tenia claves termination_*")

print("DONE")
PYEOF

echo "--- verificando sintaxis (host python3, sin docker) ---"
python3 -m py_compile apps/backend/app/modules/catalogs/schemas.py && echo "SYNTAX OK: catalogs/schemas.py"
python3 -m py_compile apps/backend/app/modules/catalogs/router.py && echo "SYNTAX OK: catalogs/router.py"
python3 -m py_compile apps/backend/app/modules/payroll/schemas.py && echo "SYNTAX OK: payroll/schemas.py"
python3 -m py_compile apps/backend/app/modules/payroll/router.py && echo "SYNTAX OK: payroll/router.py"
python3 -c "import json; json.load(open('apps/backend/app/i18n/es/messages.json', encoding='utf-8')); json.load(open('apps/backend/app/i18n/en/messages.json', encoding='utf-8')); print('JSON OK: es + en messages.json')"
