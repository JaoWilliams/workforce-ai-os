from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.contracts_pdf import generate_contract_pdf
from app.core.onboarding import get_missing_items_bulk, sync_onboarding_flags
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, Contract, Dependent, Employee, Tenant, User
from app.modules.employees.schemas import (
    ContractCreate,
    ContractResponse,
    DependentCreate,
    DependentResponse,
    DependentUpdate,
    EmployeeCreate,
    EmployeeResponse,
    EmployeeUpdate,
)
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/employees", tags=["employees"])


def _employee_response(e: Employee) -> EmployeeResponse:
    return EmployeeResponse(
        id=e.id, branch_id=e.branch_id, department_id=e.department_id, first_name=e.first_name, last_name=e.last_name,
        id_type=e.id_type, id_number=e.id_number, email=e.email, phone=e.phone,
        position=e.position, hire_date=e.hire_date, active=e.active,
        bank_account_type=e.bank_account_type, bank_account_number=e.bank_account_number,
    )


def _contract_response(c: Contract) -> ContractResponse:
    return ContractResponse(
        id=c.id, employee_id=c.employee_id, contract_type=c.contract_type,
        start_date=c.start_date, end_date=c.end_date, base_salary=float(c.base_salary),
        currency=c.currency, pay_frequency=c.pay_frequency, language=c.language, pdf_path=c.pdf_path,
    )


@router.post("", response_model=EmployeeResponse, status_code=201)
async def create_employee(
    payload: EmployeeCreate,
    current_user: User = Depends(require_permission("employees.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        branch = await session.execute(select(Branch).where(Branch.id == payload.branch_id))
        if branch.scalar_one_or_none() is None:
            raise HTTPException(status_code=400, detail=translate("employees.branch_not_found", locale))

        existing = await session.execute(select(Employee).where(Employee.id_number == payload.id_number))
        if existing.scalar_one_or_none() is not None:
            raise HTTPException(status_code=400, detail=translate("employees.id_number_exists", locale))

        employee = Employee(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            branch_id=payload.branch_id,
            department_id=payload.department_id,
            first_name=payload.first_name,
            last_name=payload.last_name,
            id_type=payload.id_type,
            id_number=payload.id_number,
            email=payload.email,
            phone=payload.phone,
            position=payload.position,
            hire_date=payload.hire_date,
            active=True,
        )
        session.add(employee)
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
    return response


@router.get("", response_model=list[EmployeeResponse])
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
    return {"checked": checked, "with_gaps": with_gaps}


@router.patch("/{employee_id}", response_model=EmployeeResponse)
async def update_employee(
    employee_id: UUID,
    payload: EmployeeUpdate,
    current_user: User = Depends(require_permission("employees.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee).where(Employee.id == employee_id))
        employee = result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))

        changes = {}
        for field in ("email", "phone", "position", "active", "bank_account_type", "bank_account_number"):
            value = getattr(payload, field)
            if value is not None:
                setattr(employee, field, value)
                changes[field] = value

        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="employee.updated", resource_type="employee", resource_id=employee.id, extra=changes,
        )
        await session.commit()
        await session.refresh(employee)
        sync_result = await sync_onboarding_flags(session, current_user.tenant_id, employee)
        await session.commit()
    response = _employee_response(employee)
    response.onboarding_missing = sync_result["missing"]
    return response


@router.post("/{employee_id}/contracts", response_model=ContractResponse, status_code=201)
async def create_contract(
    employee_id: UUID,
    payload: ContractCreate,
    current_user: User = Depends(require_permission("employees.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee).where(Employee.id == employee_id))
        employee = result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))

        if payload.contract_type == "indefinido" and payload.end_date is not None:
            raise HTTPException(status_code=400, detail=translate("contracts.end_date_not_allowed", locale))
        if payload.contract_type != "indefinido" and payload.end_date is None:
            raise HTTPException(status_code=400, detail=translate("contracts.end_date_required", locale))

        tenant_result = await session.execute(select(Tenant).where(Tenant.id == current_user.tenant_id))
        tenant = tenant_result.scalar_one()

        contract = Contract(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            employee_id=employee_id,
            contract_type=payload.contract_type,
            start_date=payload.start_date,
            end_date=payload.end_date,
            base_salary=payload.base_salary,
            currency=payload.currency,
            pay_frequency=payload.pay_frequency,
            language=payload.language,
            pdf_path=None,
        )
        session.add(contract)
        await session.flush()

        pdf_path = generate_contract_pdf(
            tenant_name=tenant.name, employee=employee, contract=contract, language=payload.language
        )
        contract.pdf_path = pdf_path

        await log_audit(
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
    return _contract_response(contract)


@router.get("/{employee_id}/contracts", response_model=list[ContractResponse])
async def list_contracts(
    employee_id: UUID,
    current_user: User = Depends(require_permission("employees.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Contract).where(Contract.employee_id == employee_id))
        contracts = result.scalars().all()
    return [_contract_response(c) for c in contracts]


@router.get("/{employee_id}/contracts/{contract_id}/pdf")
async def download_contract_pdf(
    employee_id: UUID,
    contract_id: UUID,
    current_user: User = Depends(require_permission("employees.view")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Contract).where(Contract.id == contract_id, Contract.employee_id == employee_id)
        )
        contract = result.scalar_one_or_none()
        if contract is None or contract.pdf_path is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))
        pdf_path = contract.pdf_path
    return FileResponse(pdf_path, media_type="application/pdf", filename=f"contrato_{contract_id}.pdf")


def _dependent_response(d: Dependent) -> DependentResponse:
    return DependentResponse(
        id=d.id, employee_id=d.employee_id, relationship_type=d.relationship_type,
        name=d.name, birth_date=d.birth_date, active=d.active,
    )


@router.post("/{employee_id}/dependents", response_model=DependentResponse, status_code=201)
async def create_dependent(
    employee_id: UUID,
    payload: DependentCreate,
    current_user: User = Depends(require_permission("employees.manage")),
    locale: str = Depends(get_locale),
):
    if payload.relationship_type == "hijo" and payload.birth_date is None:
        raise HTTPException(status_code=400, detail=translate("employees.dependent_birthdate_required", locale))
    async with tenant_session(current_user.tenant_id) as session:
        emp_result = await session.execute(select(Employee).where(Employee.id == employee_id))
        if emp_result.scalar_one_or_none() is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))
        dependent = Dependent(
            id=uuid4(), tenant_id=current_user.tenant_id, employee_id=employee_id,
            relationship_type=payload.relationship_type, name=payload.name,
            birth_date=payload.birth_date, active=True,
        )
        session.add(dependent)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="dependent.created", resource_type="dependent", resource_id=dependent.id,
            extra={"employee_id": str(employee_id), "relationship_type": payload.relationship_type, "name": payload.name},
        )
        await session.commit()
        await session.refresh(dependent)
    return _dependent_response(dependent)


@router.get("/{employee_id}/dependents", response_model=list[DependentResponse])
async def list_dependents(
    employee_id: UUID,
    current_user: User = Depends(require_permission("employees.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Dependent).where(Dependent.employee_id == employee_id))
        dependents = result.scalars().all()
    return [_dependent_response(d) for d in dependents]


@router.patch("/{employee_id}/dependents/{dependent_id}", response_model=DependentResponse)
async def update_dependent(
    employee_id: UUID,
    dependent_id: UUID,
    payload: DependentUpdate,
    current_user: User = Depends(require_permission("employees.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Dependent).where(Dependent.id == dependent_id, Dependent.employee_id == employee_id)
        )
        dependent = result.scalar_one_or_none()
        if dependent is None:
            raise HTTPException(status_code=404, detail=translate("employees.dependent_not_found", locale))
        changes = {}
        if payload.name is not None:
            dependent.name = payload.name
            changes["name"] = payload.name
        if payload.birth_date is not None:
            dependent.birth_date = payload.birth_date
            changes["birth_date"] = str(payload.birth_date)
        if payload.active is not None:
            dependent.active = payload.active
            changes["active"] = payload.active
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="dependent.updated", resource_type="dependent", resource_id=dependent.id, extra=changes,
        )
        await session.commit()
        await session.refresh(dependent)
    return _dependent_response(dependent)
