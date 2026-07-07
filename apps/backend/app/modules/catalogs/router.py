from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import PayrollConcept, User
from app.modules.catalogs.schemas import PayrollConceptCreate, PayrollConceptResponse, PayrollConceptUpdate
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/catalogs/concepts", tags=["catalogs"])


def _to_response(concept: PayrollConcept) -> PayrollConceptResponse:
    return PayrollConceptResponse(
        id=concept.id,
        code=concept.code,
        name=concept.name,
        calculation_method=concept.calculation_method,
        nature=concept.nature,
        origin=concept.origin,
        value=float(concept.value),
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
