#!/bin/bash
# ============================================================
# Fase 9 (Asientos contables) - Parte 3: schemas + endpoints
# ============================================================
# CAMBIOS:
#   catalogs/schemas.py: + ChartOfAccountCreate/Update/Response,
#     + accounting_account_id en PayrollConceptCreate/Update/Response
#   catalogs/router.py: + import ChartOfAccount, CRUD de
#     /api/catalogs/chart-of-accounts, wiring de accounting_account_id
#     en los endpoints existentes de PayrollConcept
#   NUEVO modulo apps/backend/app/modules/accounting/ (schemas.py +
#     router.py): endpoints para generar+persistir cada tipo de
#     asiento, listarlos, y exportar CSV generico (no se confirmo
#     sistema contable especifico - el cliente pidio "un csv")
#   main.py: registra el nuevo accounting_router
#   i18n es/en: + catalogs.account_code_exists / account_not_found
#     (los errores de generacion de asientos van como detail
#     estructurado {error, ...}, no como texto traducido, para que el
#     frontend pueda mostrar exactamente que cuenta falta)
# Ejecutar: cd /opt/workforce-ai-os && bash fase9_parte3_schemas_router.sh
# ============================================================
set -e
REPO_DIR="${REPO_DIR:-/opt/workforce-ai-os}"
cd "$REPO_DIR"
BACKEND_DIR="apps/backend/app"

mkdir -p "$BACKEND_DIR/modules/accounting"
touch "$BACKEND_DIR/modules/accounting/__init__.py"

python3 << 'PYEOF'
import json

BACKEND = "apps/backend/app"

# ---------- 1. catalogs/schemas.py ----------
path = f"{BACKEND}/modules/catalogs/schemas.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

if "accounting_account_id" in src:
    print("SKIP catalogs/schemas.py: PayrollConcept* ya tenia accounting_account_id (corrida anterior)")
else:
    anchor_create = """class PayrollConceptCreate(BaseModel):
    code: str
    name: str
    calculation_method: Literal["monto_fijo", "porcentaje", "cantidad"]
    nature: Literal["ingreso", "deduccion"]
    origin: Literal["patronal", "empleado"]
    value: float
    employer_value: Optional[float] = None"""
    assert anchor_create in src, "ANCHOR NOT FOUND: PayrollConceptCreate"
    src = src.replace(anchor_create, anchor_create + "\n    accounting_account_id: Optional[UUID] = None")

    anchor_update = """class PayrollConceptUpdate(BaseModel):
    name: Optional[str] = None
    value: Optional[float] = None
    employer_value: Optional[float] = None
    active: Optional[bool] = None"""
    assert anchor_update in src, "ANCHOR NOT FOUND: PayrollConceptUpdate"
    src = src.replace(anchor_update, anchor_update + "\n    accounting_account_id: Optional[UUID] = None")

    anchor_response = """class PayrollConceptResponse(BaseModel):
    id: UUID
    code: str
    name: str
    calculation_method: str
    nature: str
    origin: str
    value: float
    employer_value: Optional[float] = None
    active: bool"""
    assert anchor_response in src, "ANCHOR NOT FOUND: PayrollConceptResponse"
    src = src.replace(anchor_response, anchor_response + "\n    accounting_account_id: Optional[UUID] = None")

if "class ChartOfAccountCreate" not in src:
    src = src.rstrip("\n") + '''


class ChartOfAccountCreate(BaseModel):
    code: str
    name: str
    account_type: Literal["activo", "pasivo", "patrimonio", "ingreso", "gasto"]


class ChartOfAccountUpdate(BaseModel):
    name: Optional[str] = None
    account_type: Optional[Literal["activo", "pasivo", "patrimonio", "ingreso", "gasto"]] = None
    active: Optional[bool] = None


class ChartOfAccountResponse(BaseModel):
    id: UUID
    code: str
    name: str
    account_type: str
    active: bool
'''

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK catalogs/schemas.py: ChartOfAccount* + accounting_account_id agregados")

# ---------- 2. catalogs/router.py ----------
path = f"{BACKEND}/modules/catalogs/router.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

anchor_model_import = "from app.db.models import AguinaldoConfig, CesantiaConfig, CesantiaScaleRow, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig"
assert anchor_model_import in src, "ANCHOR NOT FOUND: model import"
src = src.replace(
    anchor_model_import,
    "from app.db.models import AguinaldoConfig, CesantiaConfig, CesantiaScaleRow, ChartOfAccount, Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig",
)

anchor_schemas_import = """    CesantiaScaleRowResponse,
    CesantiaScaleRowUpsert,
    CesantiaScaleBulkUpsert,
)"""
assert anchor_schemas_import in src, "ANCHOR NOT FOUND: schemas import"
src = src.replace(
    anchor_schemas_import,
    """    CesantiaScaleRowResponse,
    CesantiaScaleRowUpsert,
    CesantiaScaleBulkUpsert,
    ChartOfAccountCreate,
    ChartOfAccountUpdate,
    ChartOfAccountResponse,
)""",
)

anchor_to_response = """def _to_response(concept: PayrollConcept) -> PayrollConceptResponse:
    return PayrollConceptResponse(
        id=concept.id,
        code=concept.code,
        name=concept.name,
        calculation_method=concept.calculation_method,
        nature=concept.nature,
        origin=concept.origin,
        value=float(concept.value),
        employer_value=float(concept.employer_value) if concept.employer_value is not None else None,
        active=concept.active,
    )"""
assert anchor_to_response in src, "ANCHOR NOT FOUND: _to_response"
src = src.replace(anchor_to_response, """def _to_response(concept: PayrollConcept) -> PayrollConceptResponse:
    return PayrollConceptResponse(
        id=concept.id,
        code=concept.code,
        name=concept.name,
        calculation_method=concept.calculation_method,
        nature=concept.nature,
        origin=concept.origin,
        value=float(concept.value),
        employer_value=float(concept.employer_value) if concept.employer_value is not None else None,
        active=concept.active,
        accounting_account_id=concept.accounting_account_id,
    )""")

anchor_create_concept = """            value=payload.value,
            employer_value=payload.employer_value,
            active=True,
        )"""
assert anchor_create_concept in src, "ANCHOR NOT FOUND: create_concept PayrollConcept(...)"
src = src.replace(anchor_create_concept, """            value=payload.value,
            employer_value=payload.employer_value,
            accounting_account_id=payload.accounting_account_id,
            active=True,
        )""")

anchor_update_concept = """        if payload.active is not None:
            concept.active = payload.active
            changes["active"] = payload.active

        await log_audit("""
assert anchor_update_concept in src, "ANCHOR NOT FOUND: update_concept active block"
src = src.replace(anchor_update_concept, """        if payload.active is not None:
            concept.active = payload.active
            changes["active"] = payload.active
        if payload.accounting_account_id is not None:
            concept.accounting_account_id = payload.accounting_account_id
            changes["accounting_account_id"] = str(payload.accounting_account_id)

        await log_audit(""")

anchor_last_endpoint = '''@hours_router.get("/cesantia-scale", response_model=list[CesantiaScaleRowResponse])
async def get_cesantia_scale(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(CesantiaScaleRow).order_by(CesantiaScaleRow.year_number))
        rows = result.scalars().all()
    return [CesantiaScaleRowResponse(year_number=r.year_number, days=float(r.days)) for r in rows]'''
assert anchor_last_endpoint in src, "ANCHOR NOT FOUND: last endpoint (cesantia-scale GET)"
assert src.count(anchor_last_endpoint) == 1, "ANCHOR NOT UNIQUE: last endpoint"

new_endpoints = anchor_last_endpoint + '''
def _to_account_response(account: ChartOfAccount) -> ChartOfAccountResponse:
    return ChartOfAccountResponse(
        id=account.id, code=account.code, name=account.name,
        account_type=account.account_type, active=account.active,
    )
@hours_router.post("/chart-of-accounts", response_model=ChartOfAccountResponse, status_code=201)
async def create_chart_of_account(
    payload: ChartOfAccountCreate,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        existing = await session.execute(
            select(ChartOfAccount).where(ChartOfAccount.code == payload.code)
        )
        if existing.scalar_one_or_none() is not None:
            raise HTTPException(status_code=400, detail=translate("catalogs.account_code_exists", locale))
        account = ChartOfAccount(
            id=uuid4(), tenant_id=current_user.tenant_id, code=payload.code,
            name=payload.name, account_type=payload.account_type, active=True,
        )
        session.add(account)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="chart_of_account.created", resource_type="chart_of_account", resource_id=account.id,
            extra={"code": payload.code, "name": payload.name, "account_type": payload.account_type},
        )
        await session.commit()
        await session.refresh(account)
    return _to_account_response(account)
@hours_router.get("/chart-of-accounts", response_model=list[ChartOfAccountResponse])
async def list_chart_of_accounts(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(ChartOfAccount).order_by(ChartOfAccount.code))
        accounts = result.scalars().all()
    return [_to_account_response(a) for a in accounts]
@hours_router.patch("/chart-of-accounts/{account_id}", response_model=ChartOfAccountResponse)
async def update_chart_of_account(
    account_id: UUID,
    payload: ChartOfAccountUpdate,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(ChartOfAccount).where(ChartOfAccount.id == account_id))
        account = result.scalar_one_or_none()
        if account is None:
            raise HTTPException(status_code=404, detail=translate("catalogs.account_not_found", locale))
        changes = {}
        if payload.name is not None:
            account.name = payload.name
            changes["name"] = payload.name
        if payload.account_type is not None:
            account.account_type = payload.account_type
            changes["account_type"] = payload.account_type
        if payload.active is not None:
            account.active = payload.active
            changes["active"] = payload.active
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="chart_of_account.updated", resource_type="chart_of_account", resource_id=account.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(account)
    return _to_account_response(account)
'''

src = src.replace(anchor_last_endpoint, new_endpoints)
with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK catalogs/router.py: ChartOfAccount CRUD + accounting_account_id wiring agregados")

# ---------- 3. nuevo modulo accounting: schemas.py ----------
schemas_content = '''from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class JournalEntryLineResponse(BaseModel):
    id: UUID
    account_id: UUID
    account_code: str
    account_name: str
    branch_id: Optional[UUID] = None
    branch_name: Optional[str] = None
    debit: float
    credit: float
    description: Optional[str] = None


class JournalEntryResponse(BaseModel):
    id: UUID
    entry_date: date
    entry_type: str
    payroll_period_id: Optional[UUID] = None
    termination_id: Optional[UUID] = None
    description: str
    created_at: datetime
    lines: list[JournalEntryLineResponse]
    total_debit: float
    total_credit: float
'''
with open(f"{BACKEND}/modules/accounting/schemas.py", "w", encoding="utf-8") as f:
    f.write(schemas_content)
print("OK modules/accounting/schemas.py escrito")

# ---------- 4. nuevo modulo accounting: router.py ----------
router_content = '''import csv
import io
from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select

from app.core.accounting import (
    generate_payroll_journal_entry,
    generate_aguinaldo_provision_entry,
    generate_aguinaldo_payment_entry,
    generate_vacation_provision_entry,
    generate_cesantia_entry,
    generate_ccss_patronal_entry,
    persist_journal_entry,
)
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, ChartOfAccount, JournalEntry, JournalEntryLine, Termination, User
from app.modules.accounting.schemas import JournalEntryLineResponse, JournalEntryResponse
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/accounting", tags=["accounting"])

ERROR_STATUS = {
    "period_not_found": 404,
    "no_rows": 400,
    "blocked_rows": 400,
    "missing_accounts": 400,
    "zero_amount": 400,
    "unbalanced": 400,
    "not_eligible": 400,
    "amount_not_computable": 400,
}


def _raise_for_error(error_result: dict):
    error = error_result.get("error")
    status_code = ERROR_STATUS.get(error, 400)
    detail = {"error": error}
    detail.update({k: v for k, v in error_result.items() if k != "error"})
    raise HTTPException(status_code=status_code, detail=detail)


async def _entry_response(session, entry: JournalEntry) -> JournalEntryResponse:
    result = await session.execute(select(JournalEntryLine).where(JournalEntryLine.journal_entry_id == entry.id))
    lines = result.scalars().all()
    account_ids = {l.account_id for l in lines}
    accounts = {}
    if account_ids:
        accounts_result = await session.execute(select(ChartOfAccount).where(ChartOfAccount.id.in_(account_ids)))
        accounts = {a.id: a for a in accounts_result.scalars().all()}
    branch_ids = {l.branch_id for l in lines if l.branch_id}
    branches = {}
    if branch_ids:
        branches_result = await session.execute(select(Branch).where(Branch.id.in_(branch_ids)))
        branches = {b.id: b for b in branches_result.scalars().all()}
    line_responses = []
    total_debit = 0.0
    total_credit = 0.0
    for l in lines:
        acc = accounts.get(l.account_id)
        branch = branches.get(l.branch_id) if l.branch_id else None
        line_responses.append(JournalEntryLineResponse(
            id=l.id, account_id=l.account_id,
            account_code=acc.code if acc else "?", account_name=acc.name if acc else "?",
            branch_id=l.branch_id, branch_name=branch.name if branch else None,
            debit=float(l.debit), credit=float(l.credit), description=l.description,
        ))
        total_debit += float(l.debit)
        total_credit += float(l.credit)
    return JournalEntryResponse(
        id=entry.id, entry_date=entry.entry_date, entry_type=entry.entry_type,
        payroll_period_id=entry.payroll_period_id, termination_id=entry.termination_id,
        description=entry.description, created_at=entry.created_at,
        lines=line_responses, total_debit=round(total_debit, 2), total_credit=round(total_credit, 2),
    )


@router.post("/journal-entries/payroll", response_model=JournalEntryResponse, status_code=201)
async def create_payroll_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_payroll_journal_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/aguinaldo-provision", response_model=JournalEntryResponse, status_code=201)
async def create_aguinaldo_provision_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_aguinaldo_provision_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/aguinaldo-payment", response_model=JournalEntryResponse, status_code=201)
async def create_aguinaldo_payment_entry(
    year: int,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_aguinaldo_payment_entry(session, current_user.tenant_id, year, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/vacaciones-provision", response_model=JournalEntryResponse, status_code=201)
async def create_vacation_provision_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_vacation_provision_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/cesantia/{termination_id}", response_model=JournalEntryResponse, status_code=201)
async def create_cesantia_entry(
    termination_id: UUID,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        termination = await session.get(Termination, termination_id)
        if termination is None:
            raise HTTPException(status_code=404, detail=translate("payroll.termination_not_found", locale))
        result = await generate_cesantia_entry(session, current_user.tenant_id, termination)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/ccss-patronal", response_model=JournalEntryResponse, status_code=201)
async def create_ccss_patronal_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_ccss_patronal_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.get("/journal-entries", response_model=list[JournalEntryResponse])
async def list_journal_entries(
    entry_type: Optional[str] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(JournalEntry)
        if entry_type is not None:
            query = query.where(JournalEntry.entry_type == entry_type)
        if start_date is not None:
            query = query.where(JournalEntry.entry_date >= start_date)
        if end_date is not None:
            query = query.where(JournalEntry.entry_date <= end_date)
        result = await session.execute(query.order_by(JournalEntry.entry_date.desc()))
        entries = result.scalars().all()
        responses = [await _entry_response(session, e) for e in entries]
    return responses


@router.get("/journal-entries/export-csv")
async def export_journal_entries_csv(
    entry_type: Optional[str] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(JournalEntry)
        if entry_type is not None:
            query = query.where(JournalEntry.entry_type == entry_type)
        if start_date is not None:
            query = query.where(JournalEntry.entry_date >= start_date)
        if end_date is not None:
            query = query.where(JournalEntry.entry_date <= end_date)
        result = await session.execute(query.order_by(JournalEntry.entry_date.asc()))
        entries = result.scalars().all()
        responses = [await _entry_response(session, e) for e in entries]

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["fecha", "tipo_asiento", "descripcion", "cuenta_codigo", "cuenta_nombre", "sucursal", "debe", "haber", "detalle_linea"])
    for entry in responses:
        for line in entry.lines:
            writer.writerow([
                entry.entry_date.isoformat(), entry.entry_type, entry.description,
                line.account_code, line.account_name, line.branch_name or "",
                f"{line.debit:.2f}", f"{line.credit:.2f}", line.description or "",
            ])
    csv_bytes = output.getvalue().encode("utf-8-sig")
    return Response(
        content=csv_bytes, media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=asientos_contables.csv"},
    )
'''
with open(f"{BACKEND}/modules/accounting/router.py", "w", encoding="utf-8") as f:
    f.write(router_content)
print("OK modules/accounting/router.py escrito")

# ---------- 5. main.py: registrar el nuevo router ----------
path = f"{BACKEND}/main.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

anchor_import = "from app.modules.payroll.router import router as payroll_router"
assert anchor_import in src, "ANCHOR NOT FOUND: main.py import payroll_router"
src = src.replace(anchor_import, anchor_import + "\nfrom app.modules.accounting.router import router as accounting_router")

anchor_include = "app.include_router(payroll_router)"
assert anchor_include in src, "ANCHOR NOT FOUND: main.py include payroll_router"
src = src.replace(anchor_include, anchor_include + "\napp.include_router(accounting_router)")

with open(path, "w", encoding="utf-8") as f:
    f.write(src)
print("OK main.py: accounting_router registrado")

# ---------- 6. i18n es/en: claves de ChartOfAccount ----------
new_keys_es = {
    "catalogs.account_code_exists": "Ya existe una cuenta contable con ese codigo",
    "catalogs.account_not_found": "Cuenta contable no encontrada",
}
new_keys_en = {
    "catalogs.account_code_exists": "An account with this code already exists",
    "catalogs.account_not_found": "Account not found",
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
        print(f"OK i18n/{lang}/messages.json: claves de cuentas agregadas")
    else:
        print(f"SKIP i18n/{lang}/messages.json: ya tenia esas claves")

print("DONE")
PYEOF

echo "--- verificando sintaxis (host python3, sin docker) ---"
python3 -m py_compile apps/backend/app/modules/catalogs/schemas.py && echo "SYNTAX OK: catalogs/schemas.py"
python3 -m py_compile apps/backend/app/modules/catalogs/router.py && echo "SYNTAX OK: catalogs/router.py"
python3 -m py_compile apps/backend/app/modules/accounting/schemas.py && echo "SYNTAX OK: accounting/schemas.py"
python3 -m py_compile apps/backend/app/modules/accounting/router.py && echo "SYNTAX OK: accounting/router.py"
python3 -m py_compile apps/backend/app/main.py && echo "SYNTAX OK: main.py"
python3 -c "import json; json.load(open('apps/backend/app/i18n/es/messages.json', encoding='utf-8')); json.load(open('apps/backend/app/i18n/en/messages.json', encoding='utf-8')); print('JSON OK: es + en messages.json')"
