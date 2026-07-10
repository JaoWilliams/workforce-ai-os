from datetime import date, timedelta
from typing import Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.payroll import build_payroll_pdf, build_payroll_xlsx, compute_payroll_rows
from app.core.tenant import tenant_session
from app.db.base import async_session
from app.db.models import PayrollPeriod, Tenant, User
from app.modules.payroll.schemas import (
    PayrollPeriodCreate,
    PayrollPeriodGenerateRequest,
    PayrollPeriodResponse,
    PayrollPeriodStatusUpdate,
    PayrollPeriodUpdate,
    PayrollRow,
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
