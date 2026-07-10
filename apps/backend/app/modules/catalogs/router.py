from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import PayrollConcept, PayrollHoursConfig, User
from app.modules.catalogs.schemas import (
    PayrollConceptCreate,
    PayrollConceptResponse,
    PayrollConceptUpdate,
    PayrollHoursConfigResponse,
    PayrollHoursConfigUpsert,
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
