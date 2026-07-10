from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.contracts_pdf import generate_contract_pdf
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, Contract, Employee, Tenant, User
from app.modules.employees.schemas import (
    ContractCreate,
    ContractResponse,
    EmployeeCreate,
    EmployeeResponse,
    EmployeeUpdate,
)
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/employees", tags=["employees"])


def _employee_response(e: Employee) -> EmployeeResponse:
    return EmployeeResponse(
        id=e.id, branch_id=e.branch_id, first_name=e.first_name, last_name=e.last_name,
        id_type=e.id_type, id_number=e.id_number, email=e.email, phone=e.phone,
        position=e.position, hire_date=e.hire_date, active=e.active,
    )


def _contract_response(c: Contract) -> ContractResponse:
    return ContractResponse(
        id=c.id, employee_id=c.employee_id, contract_type=c.contract_type,
        start_date=c.start_date, end_date=c.end_date, base_salary=float(c.base_salary),
        currency=c.currency, pay_frequency=c.pay_frequency, pdf_path=c.pdf_path,
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
    return _employee_response(employee)


@router.get("", response_model=list[EmployeeResponse])
async def list_employees(
    current_user: User = Depends(require_permission("employees.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee))
        employees = result.scalars().all()
    return [_employee_response(e) for e in employees]


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
        for field in ("email", "phone", "position", "active"):
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
    return _employee_response(employee)


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
            pdf_path=None,
        )
        session.add(contract)
        await session.flush()

        pdf_path = generate_contract_pdf(tenant_name=tenant.name, employee=employee, contract=contract)
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
