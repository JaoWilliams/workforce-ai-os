from typing import Optional
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Holiday, PayrollConcept, PayrollHoursConfig, RentaCredits, TaxBracket, User, VacationConfig
from app.modules.catalogs.schemas import (
    PayrollConceptCreate,
    PayrollConceptResponse,
    PayrollConceptUpdate,
    PayrollHoursConfigResponse,
    PayrollHoursConfigUpsert,
    HolidayCreate,
    HolidayResponse,
    HolidayUpdate,
    RentaCreditsResponse,
    RentaCreditsUpsert,
    TaxBracketCreate,
    TaxBracketResponse,
    VacationConfigResponse,
    VacationConfigUpsert,
)
from app.modules.rbac.dependencies import require_permission

PAY_FREQUENCIES = ["semanal", "quincenal", "bisemanal", "mensual"]

router = APIRouter(prefix="/api/catalogs/concepts", tags=["catalogs"])

hours_router = APIRouter(prefix="/api/catalogs", tags=["catalogs"])


def _to_response(concept: PayrollConcept) -> PayrollConceptResponse:
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
    )


@router.post("", response_model=PayrollConceptResponse, status_code=201)
async def create_concept(
    payload: PayrollConceptCreate,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        existing = await session.execute(
            select(PayrollConcept).where(PayrollConcept.code == payload.code)
        )
        if existing.scalar_one_or_none() is not None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=translate("catalogs.concept_code_exists", locale),
            )

        concept = PayrollConcept(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            code=payload.code,
            name=payload.name,
            calculation_method=payload.calculation_method,
            nature=payload.nature,
            origin=payload.origin,
            value=payload.value,
            employer_value=payload.employer_value,
            active=True,
        )
        session.add(concept)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="payroll_concept.created",
            resource_type="payroll_concept",
            resource_id=concept.id,
            extra={
                "code": payload.code,
                "name": payload.name,
                "calculation_method": payload.calculation_method,
                "nature": payload.nature,
                "origin": payload.origin,
                "value": payload.value,
                "employer_value": payload.employer_value,
            },
        )
        await session.commit()
        await session.refresh(concept)
    return _to_response(concept)


@router.get("", response_model=list[PayrollConceptResponse])
async def list_concepts(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(PayrollConcept))
        concepts = result.scalars().all()
    return [_to_response(c) for c in concepts]


@router.patch("/{concept_id}", response_model=PayrollConceptResponse)
async def update_concept(
    concept_id: UUID,
    payload: PayrollConceptUpdate,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(PayrollConcept).where(PayrollConcept.id == concept_id))
        concept = result.scalar_one_or_none()
        if concept is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=translate("catalogs.concept_not_found", locale),
            )

        changes = {}
        if payload.name is not None:
            concept.name = payload.name
            changes["name"] = payload.name
        if payload.value is not None:
            concept.value = payload.value
            changes["value"] = payload.value
        if payload.employer_value is not None:
            concept.employer_value = payload.employer_value
            changes["employer_value"] = payload.employer_value
        if payload.active is not None:
            concept.active = payload.active
            changes["active"] = payload.active

        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="payroll_concept.updated",
            resource_type="payroll_concept",
            resource_id=concept.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(concept)
    return _to_response(concept)


@hours_router.get("/payroll-hours", response_model=list[PayrollHoursConfigResponse])
async def list_payroll_hours_config(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(PayrollHoursConfig))
        configs = {c.pay_frequency: c for c in result.scalars().all()}
    return [
        PayrollHoursConfigResponse(
            pay_frequency=freq,
            standard_hours=float(configs[freq].standard_hours) if freq in configs else None,
        )
        for freq in PAY_FREQUENCIES
    ]


@hours_router.put("/payroll-hours/{pay_frequency}", response_model=PayrollHoursConfigResponse)
async def upsert_payroll_hours_config(
    pay_frequency: str,
    payload: PayrollHoursConfigUpsert,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    if pay_frequency not in PAY_FREQUENCIES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=translate("catalogs.invalid_pay_frequency", locale),
        )
    if payload.standard_hours <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=translate("catalogs.invalid_standard_hours", locale),
        )

    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(PayrollHoursConfig).where(PayrollHoursConfig.pay_frequency == pay_frequency)
        )
        config = result.scalar_one_or_none()
        if config is None:
            config = PayrollHoursConfig(
                id=uuid4(),
                tenant_id=current_user.tenant_id,
                pay_frequency=pay_frequency,
                standard_hours=payload.standard_hours,
            )
            session.add(config)
            action = "payroll_hours_config.created"
        else:
            config.standard_hours = payload.standard_hours
            action = "payroll_hours_config.updated"

        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action=action,
            resource_type="payroll_hours_config",
            resource_id=config.id,
            extra={"pay_frequency": pay_frequency, "standard_hours": payload.standard_hours},
        )
        await session.commit()
        await session.refresh(config)
    return PayrollHoursConfigResponse(pay_frequency=config.pay_frequency, standard_hours=float(config.standard_hours))


def _holiday_response(h: Holiday) -> HolidayResponse:
    return HolidayResponse(id=h.id, date=h.date, name=h.name, payment_type=h.payment_type, active=h.active)


@hours_router.post("/holidays", response_model=HolidayResponse, status_code=201)
async def create_holiday(
    payload: HolidayCreate,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        existing = await session.execute(select(Holiday).where(Holiday.date == payload.date))
        if existing.scalar_one_or_none() is not None:
            raise HTTPException(status_code=400, detail=translate("catalogs.holiday_date_exists", locale))
        holiday = Holiday(
            id=uuid4(), tenant_id=current_user.tenant_id, date=payload.date,
            name=payload.name, payment_type=payload.payment_type, active=True,
        )
        session.add(holiday)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="holiday.created", resource_type="holiday", resource_id=holiday.id,
            extra={"date": str(payload.date), "name": payload.name, "payment_type": payload.payment_type},
        )
        await session.commit()
        await session.refresh(holiday)
    return _holiday_response(holiday)


@hours_router.get("/holidays", response_model=list[HolidayResponse])
async def list_holidays(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Holiday).order_by(Holiday.date))
        holidays = result.scalars().all()
    return [_holiday_response(h) for h in holidays]


@hours_router.patch("/holidays/{holiday_id}", response_model=HolidayResponse)
async def update_holiday(
    holiday_id: UUID,
    payload: HolidayUpdate,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Holiday).where(Holiday.id == holiday_id))
        holiday = result.scalar_one_or_none()
        if holiday is None:
            raise HTTPException(status_code=404, detail=translate("catalogs.holiday_not_found", locale))
        changes = {}
        if payload.name is not None:
            holiday.name = payload.name
            changes["name"] = payload.name
        if payload.payment_type is not None:
            holiday.payment_type = payload.payment_type
            changes["payment_type"] = payload.payment_type
        if payload.active is not None:
            holiday.active = payload.active
            changes["active"] = payload.active
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="holiday.updated", resource_type="holiday", resource_id=holiday.id, extra=changes,
        )
        await session.commit()
        await session.refresh(holiday)
    return _holiday_response(holiday)


@hours_router.post("/tax-brackets", response_model=TaxBracketResponse, status_code=201)
async def create_tax_bracket(
    payload: TaxBracketCreate,
    current_user: User = Depends(require_permission("catalogs.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        existing = await session.execute(
            select(TaxBracket).where(TaxBracket.year == payload.year, TaxBracket.bracket_order == payload.bracket_order)
        )
        if existing.scalar_one_or_none() is not None:
            raise HTTPException(status_code=400, detail=translate("catalogs.tax_bracket_exists", locale))
        bracket = TaxBracket(
            id=uuid4(), tenant_id=current_user.tenant_id, year=payload.year, bracket_order=payload.bracket_order,
            lower_bound=payload.lower_bound, upper_bound=payload.upper_bound, rate=payload.rate,
        )
        session.add(bracket)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="tax_bracket.created", resource_type="tax_bracket", resource_id=bracket.id,
            extra={"year": payload.year, "bracket_order": payload.bracket_order, "lower_bound": payload.lower_bound,
                   "upper_bound": payload.upper_bound, "rate": payload.rate},
        )
        await session.commit()
        await session.refresh(bracket)
    return TaxBracketResponse(
        id=bracket.id, year=bracket.year, bracket_order=bracket.bracket_order,
        lower_bound=float(bracket.lower_bound), upper_bound=float(bracket.upper_bound) if bracket.upper_bound is not None else None,
        rate=float(bracket.rate),
    )


@hours_router.get("/tax-brackets", response_model=list[TaxBracketResponse])
async def list_tax_brackets(
    year: int = None,
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(TaxBracket).order_by(TaxBracket.year, TaxBracket.bracket_order)
        if year is not None:
            query = query.where(TaxBracket.year == year)
        result = await session.execute(query)
        brackets = result.scalars().all()
    return [
        TaxBracketResponse(
            id=b.id, year=b.year, bracket_order=b.bracket_order,
            lower_bound=float(b.lower_bound), upper_bound=float(b.upper_bound) if b.upper_bound is not None else None,
            rate=float(b.rate),
        )
        for b in brackets
    ]


@hours_router.put("/renta-credits/{year}", response_model=RentaCreditsResponse)
async def upsert_renta_credits(
    year: int,
    payload: RentaCreditsUpsert,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(RentaCredits).where(RentaCredits.year == year))
        credits = result.scalar_one_or_none()
        if credits is None:
            credits = RentaCredits(
                id=uuid4(), tenant_id=current_user.tenant_id, year=year,
                spouse_credit=payload.spouse_credit, child_credit=payload.child_credit,
            )
            session.add(credits)
            action = "renta_credits.created"
        else:
            credits.spouse_credit = payload.spouse_credit
            credits.child_credit = payload.child_credit
            action = "renta_credits.updated"
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=action, resource_type="renta_credits", resource_id=credits.id,
            extra={"year": year, "spouse_credit": payload.spouse_credit, "child_credit": payload.child_credit},
        )
        await session.commit()
        await session.refresh(credits)
    return RentaCreditsResponse(year=credits.year, spouse_credit=float(credits.spouse_credit), child_credit=float(credits.child_credit))


@hours_router.get("/renta-credits", response_model=list[RentaCreditsResponse])
async def list_renta_credits(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(RentaCredits).order_by(RentaCredits.year))
        rows = result.scalars().all()
    return [RentaCreditsResponse(year=r.year, spouse_credit=float(r.spouse_credit), child_credit=float(r.child_credit)) for r in rows]


@hours_router.put("/vacation-config", response_model=VacationConfigResponse)
async def upsert_vacation_config(
    payload: VacationConfigUpsert,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(VacationConfig))
        config = result.scalars().first()
        if config is None:
            config = VacationConfig(id=uuid4(), tenant_id=current_user.tenant_id, cycle_weeks=payload.cycle_weeks)
            session.add(config)
            action = "vacation_config.created"
        else:
            config.cycle_weeks = payload.cycle_weeks
            action = "vacation_config.updated"
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=action, resource_type="vacation_config", resource_id=None,
            extra={"cycle_weeks": payload.cycle_weeks},
        )
        await session.commit()
        await session.refresh(config)
    return VacationConfigResponse(cycle_weeks=float(config.cycle_weeks))


@hours_router.get("/vacation-config", response_model=Optional[VacationConfigResponse])
async def get_vacation_config(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(VacationConfig))
        config = result.scalars().first()
    if config is None:
        return None
    return VacationConfigResponse(cycle_weeks=float(config.cycle_weeks))
