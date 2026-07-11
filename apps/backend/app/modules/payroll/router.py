from datetime import date, datetime, timedelta, timezone
from typing import Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.payroll import build_payroll_pdf, build_payroll_xlsx, compute_payroll_rows
from app.core.overtime import generate_overtime_candidates
from app.core.renta import compute_net_payroll_rows
from app.core.vacations import compute_request_days_count, compute_vacation_balance
from app.core.aguinaldo import compute_aguinaldo_rows
from app.core.cesantia import compute_cesantia_amount
from app.core.tenant import tenant_session
from app.db.base import async_session
from app.db.models import Branch, Employee, OvertimeApproval, PayrollPeriod, ShiftTemplate, Tenant, Termination, User, VacationRequest
from app.modules.payroll.schemas import (
    PayrollPeriodCreate,
    PayrollPeriodGenerateRequest,
    PayrollPeriodResponse,
    PayrollPeriodStatusUpdate,
    PayrollPeriodUpdate,
    PayrollRow,
    OvertimeApprovalResponse,
    OvertimeGenerateRequest,
    OvertimeGenerateResponse,
    OvertimeStatusUpdate,
    NetPayrollRow,
    VacationBalanceResponse,
    VacationRequestCreate,
    VacationRequestResponse,
    VacationStatusUpdate,
    AguinaldoRow,
    TerminationCreate,
    TerminationResponse,
    TerminationStatusUpdate,
)
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/payroll", tags=["payroll"])

PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"]
VALID_STATUSES = ["draft", "closed", "paid"]


def _period_response(p: PayrollPeriod) -> PayrollPeriodResponse:
    return PayrollPeriodResponse(
        id=p.id, pay_frequency=p.pay_frequency, period_start=p.period_start,
        period_end=p.period_end, pay_date=p.pay_date, status=p.status, notes=p.notes,
    )


@router.post("/periods", response_model=PayrollPeriodResponse, status_code=201)
async def create_period(
    payload: PayrollPeriodCreate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.pay_frequency not in PAY_FREQUENCIES:
        raise HTTPException(status_code=400, detail=translate("catalogs.invalid_pay_frequency", locale))
    if payload.period_end < payload.period_start:
        raise HTTPException(status_code=400, detail=translate("payroll.invalid_period_range", locale))

    async with tenant_session(current_user.tenant_id) as session:
        existing = await session.execute(
            select(PayrollPeriod).where(
                PayrollPeriod.pay_frequency == payload.pay_frequency,
                PayrollPeriod.period_start == payload.period_start,
            )
        )
        if existing.scalar_one_or_none() is not None:
            raise HTTPException(status_code=400, detail=translate("payroll.period_exists", locale))

        period = PayrollPeriod(
            id=uuid4(), tenant_id=current_user.tenant_id, pay_frequency=payload.pay_frequency,
            period_start=payload.period_start, period_end=payload.period_end,
            pay_date=payload.pay_date, notes=payload.notes, status="draft",
        )
        session.add(period)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="payroll_period.created", resource_type="payroll_period", resource_id=period.id,
            extra={"pay_frequency": payload.pay_frequency, "period_start": str(payload.period_start),
                   "period_end": str(payload.period_end)},
        )
        await session.commit()
        await session.refresh(period)
    return _period_response(period)


@router.post("/periods/generate", response_model=list[PayrollPeriodResponse], status_code=201)
async def generate_periods(
    payload: PayrollPeriodGenerateRequest,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.pay_frequency not in PAY_FREQUENCIES:
        raise HTTPException(status_code=400, detail=translate("catalogs.invalid_pay_frequency", locale))
    if payload.days_per_period <= 0 or payload.count <= 0:
        raise HTTPException(status_code=400, detail=translate("payroll.invalid_generate_params", locale))

    created = []
    async with tenant_session(current_user.tenant_id) as session:
        cursor = payload.first_period_start
        for _ in range(payload.count):
            period_end = cursor + timedelta(days=payload.days_per_period - 1)
            existing = await session.execute(
                select(PayrollPeriod).where(
                    PayrollPeriod.pay_frequency == payload.pay_frequency,
                    PayrollPeriod.period_start == cursor,
                )
            )
            if existing.scalar_one_or_none() is None:
                period = PayrollPeriod(
                    id=uuid4(), tenant_id=current_user.tenant_id, pay_frequency=payload.pay_frequency,
                    period_start=cursor, period_end=period_end, pay_date=None, status="draft",
                )
                session.add(period)
                created.append(period)
            cursor = period_end + timedelta(days=1)

        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="payroll_period.generated", resource_type="payroll_period", resource_id=None,
            extra={"pay_frequency": payload.pay_frequency, "count": len(created)},
        )
        await session.commit()
        for p in created:
            await session.refresh(p)
    return [_period_response(p) for p in created]


@router.get("/periods", response_model=list[PayrollPeriodResponse])
async def list_periods(
    pay_frequency: Optional[str] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(PayrollPeriod).order_by(PayrollPeriod.period_start.desc())
        if pay_frequency:
            query = query.where(PayrollPeriod.pay_frequency == pay_frequency)
        result = await session.execute(query)
        periods = result.scalars().all()
    return [_period_response(p) for p in periods]


@router.patch("/periods/{period_id}", response_model=PayrollPeriodResponse)
async def update_period(
    period_id: UUID,
    payload: PayrollPeriodUpdate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(PayrollPeriod).where(PayrollPeriod.id == period_id))
        period = result.scalar_one_or_none()
        if period is None:
            raise HTTPException(status_code=404, detail=translate("payroll.period_not_found", locale))
        if period.status != "draft":
            raise HTTPException(status_code=400, detail=translate("payroll.period_not_editable", locale))

        changes = {}
        for field in ("period_start", "period_end", "pay_date", "notes"):
            value = getattr(payload, field)
            if value is not None:
                setattr(period, field, value)
                changes[field] = str(value)

        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="payroll_period.updated", resource_type="payroll_period", resource_id=period.id, extra=changes,
        )
        await session.commit()
        await session.refresh(period)
    return _period_response(period)


@router.patch("/periods/{period_id}/status", response_model=PayrollPeriodResponse)
async def update_period_status(
    period_id: UUID,
    payload: PayrollPeriodStatusUpdate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.status not in VALID_STATUSES:
        raise HTTPException(status_code=400, detail=translate("payroll.invalid_status", locale))
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(PayrollPeriod).where(PayrollPeriod.id == period_id))
        period = result.scalar_one_or_none()
        if period is None:
            raise HTTPException(status_code=404, detail=translate("payroll.period_not_found", locale))

        old_status = period.status
        period.status = payload.status
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="payroll_period.status_changed", resource_type="payroll_period", resource_id=period.id,
            extra={"from": old_status, "to": payload.status},
        )
        await session.commit()
        await session.refresh(period)
    return _period_response(period)


@router.get("", response_model=list[PayrollRow])
async def get_payroll(
    start_date: date,
    end_date: date,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_payroll_rows(session, start_date, end_date, branch_id)
    return rows


@router.get("/export-xlsx")
async def export_payroll_xlsx(
    start_date: date,
    end_date: date,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_payroll_rows(session, start_date, end_date, branch_id)
    content = build_payroll_xlsx(rows, start_date, end_date)
    filename = f"nomina_bruta_{start_date}_{end_date}.xlsx"
    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/export-pdf")
async def export_payroll_pdf(
    start_date: date,
    end_date: date,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with async_session() as plain_session:
        tenant = await plain_session.get(Tenant, current_user.tenant_id)
    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_payroll_rows(session, start_date, end_date, branch_id)
    content = build_payroll_pdf(rows, start_date, end_date, tenant_name=tenant.name if tenant else "")
    filename = f"nomina_bruta_{start_date}_{end_date}.pdf"
    return Response(
        content=content,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/overtime/generate", response_model=OvertimeGenerateResponse)
async def generate_overtime(
    payload: OvertimeGenerateRequest,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.end_date < payload.start_date:
        raise HTTPException(status_code=400, detail=translate("payroll.invalid_period_range", locale))
    async with tenant_session(current_user.tenant_id) as session:
        summary = await generate_overtime_candidates(
            session, current_user.tenant_id, payload.start_date, payload.end_date, payload.branch_id
        )
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="overtime.generated", resource_type="overtime_approval", resource_id=None,
            extra={"start_date": str(payload.start_date), "end_date": str(payload.end_date),
                   "created": summary["created"], "updated": summary["updated"]},
        )
    return OvertimeGenerateResponse(**summary)


def _overtime_response(o: OvertimeApproval, employee: Employee, branch: Branch, template: ShiftTemplate) -> OvertimeApprovalResponse:
    return OvertimeApprovalResponse(
        id=o.id, employee_id=o.employee_id, employee_name=f"{employee.first_name} {employee.last_name}",
        branch_id=branch.id, branch_name=branch.name,
        shift_template_id=o.shift_template_id, shift_template_name=template.name if template else "?",
        work_date=o.work_date, ordinary_hours=float(o.ordinary_hours), extra_hours=float(o.extra_hours),
        status=o.status, reviewed_by=o.reviewed_by, reviewed_at=o.reviewed_at, notes=o.notes,
    )


@router.get("/overtime", response_model=list[OvertimeApprovalResponse])
async def list_overtime(
    status_filter: Optional[str] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = (
            select(OvertimeApproval, Employee, Branch, ShiftTemplate)
            .join(Employee, Employee.id == OvertimeApproval.employee_id)
            .join(Branch, Branch.id == Employee.branch_id)
            .join(ShiftTemplate, ShiftTemplate.id == OvertimeApproval.shift_template_id)
            .order_by(OvertimeApproval.work_date.desc())
        )
        if status_filter:
            query = query.where(OvertimeApproval.status == status_filter)
        if start_date:
            query = query.where(OvertimeApproval.work_date >= start_date)
        if end_date:
            query = query.where(OvertimeApproval.work_date <= end_date)
        if branch_id:
            query = query.where(Employee.branch_id == branch_id)
        result = await session.execute(query)
        rows = result.all()
    return [_overtime_response(o, e, b, t) for o, e, b, t in rows]


@router.patch("/overtime/{overtime_id}/status", response_model=OvertimeApprovalResponse)
async def update_overtime_status(
    overtime_id: UUID,
    payload: OvertimeStatusUpdate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.status not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail=translate("payroll.overtime_invalid_status", locale))
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(OvertimeApproval, Employee, Branch, ShiftTemplate)
            .join(Employee, Employee.id == OvertimeApproval.employee_id)
            .join(Branch, Branch.id == Employee.branch_id)
            .join(ShiftTemplate, ShiftTemplate.id == OvertimeApproval.shift_template_id)
            .where(OvertimeApproval.id == overtime_id)
        )
        row = result.first()
        if row is None:
            raise HTTPException(status_code=404, detail=translate("payroll.overtime_not_found", locale))
        overtime, employee, branch, template = row
        if overtime.status != "pending":
            raise HTTPException(status_code=400, detail=translate("payroll.overtime_not_pending", locale))
        overtime.status = payload.status
        overtime.reviewed_by = current_user.id
        overtime.reviewed_at = datetime.now(timezone.utc)
        overtime.notes = payload.notes
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=f"overtime.{payload.status}", resource_type="overtime_approval", resource_id=overtime.id,
            extra={"employee_id": str(overtime.employee_id), "work_date": str(overtime.work_date),
                   "extra_hours": float(overtime.extra_hours), "notes": payload.notes},
        )
        await session.commit()
        await session.refresh(overtime)
    return _overtime_response(overtime, employee, branch, template)


@router.get("/net", response_model=list[NetPayrollRow])
async def get_net_payroll(
    period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(PayrollPeriod).where(PayrollPeriod.id == period_id))
        period = result.scalar_one_or_none()
        if period is None:
            raise HTTPException(status_code=404, detail=translate("payroll.period_not_found", locale))
        rows = await compute_net_payroll_rows(session, current_user.tenant_id, period, branch_id)
    return rows


def _vacation_response(v: VacationRequest, employee: Employee) -> VacationRequestResponse:
    return VacationRequestResponse(
        id=v.id, employee_id=v.employee_id, employee_name=f"{employee.first_name} {employee.last_name}",
        start_date=v.start_date, end_date=v.end_date, days_count=float(v.days_count),
        status=v.status, reviewed_by=v.reviewed_by, reviewed_at=v.reviewed_at, notes=v.notes,
    )


@router.post("/vacations/request", response_model=VacationRequestResponse, status_code=201)
async def request_vacation(
    payload: VacationRequestCreate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.end_date < payload.start_date:
        raise HTTPException(status_code=400, detail=translate("payroll.vacation_invalid_range", locale))
    async with tenant_session(current_user.tenant_id) as session:
        emp_result = await session.execute(select(Employee).where(Employee.id == payload.employee_id))
        employee = emp_result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))
        days_count = await compute_request_days_count(session, payload.employee_id, payload.start_date, payload.end_date)
        if days_count is None:
            raise HTTPException(status_code=400, detail=translate("payroll.vacation_no_shift", locale))
        vac = VacationRequest(
            id=uuid4(), tenant_id=current_user.tenant_id, employee_id=payload.employee_id,
            start_date=payload.start_date, end_date=payload.end_date, days_count=days_count, status="pending",
        )
        session.add(vac)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="vacation.requested", resource_type="vacation_request", resource_id=vac.id,
            extra={"employee_id": str(payload.employee_id), "days_count": days_count},
        )
        await session.commit()
        await session.refresh(vac)
    return _vacation_response(vac, employee)


@router.get("/vacations", response_model=list[VacationRequestResponse])
async def list_vacations(
    employee_id: Optional[UUID] = None,
    status: Optional[str] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(VacationRequest, Employee).join(Employee, Employee.id == VacationRequest.employee_id)
        if employee_id is not None:
            query = query.where(VacationRequest.employee_id == employee_id)
        if status is not None:
            query = query.where(VacationRequest.status == status)
        result = await session.execute(query.order_by(VacationRequest.start_date.desc()))
        rows = result.all()
    return [_vacation_response(v, e) for v, e in rows]


@router.patch("/vacations/{vacation_id}/status", response_model=VacationRequestResponse)
async def update_vacation_status(
    vacation_id: UUID,
    payload: VacationStatusUpdate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.status not in ("approved", "rejected"):
        raise HTTPException(status_code=400, detail=translate("payroll.vacation_invalid_status", locale))
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(VacationRequest, Employee)
            .join(Employee, Employee.id == VacationRequest.employee_id)
            .where(VacationRequest.id == vacation_id)
        )
        row = result.first()
        if row is None:
            raise HTTPException(status_code=404, detail=translate("payroll.vacation_not_found", locale))
        vac, employee = row
        if vac.status != "pending":
            raise HTTPException(status_code=400, detail=translate("payroll.vacation_not_pending", locale))
        vac.status = payload.status
        vac.reviewed_by = current_user.id
        vac.reviewed_at = datetime.now(timezone.utc)
        vac.notes = payload.notes
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=f"vacation.{payload.status}", resource_type="vacation_request", resource_id=vac.id,
            extra={"employee_id": str(vac.employee_id), "days_count": float(vac.days_count), "notes": payload.notes},
        )
        await session.commit()
        await session.refresh(vac)
    return _vacation_response(vac, employee)


@router.get("/vacations/balance", response_model=VacationBalanceResponse)
async def get_vacation_balance(
    employee_id: UUID,
    as_of: Optional[date] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await compute_vacation_balance(session, employee_id, as_of or date.today())
    return VacationBalanceResponse(**result)


@router.get("/aguinaldo", response_model=list[AguinaldoRow])
async def get_aguinaldo(
    year: int,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_aguinaldo_rows(session, year, branch_id)
    return rows
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

