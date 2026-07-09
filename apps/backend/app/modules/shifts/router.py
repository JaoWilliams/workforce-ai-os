from datetime import date as date_type
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, Employee, ShiftAssignment, ShiftTemplate, User
from app.modules.rbac.dependencies import require_permission
from app.modules.shifts.schemas import (
    ShiftAssignmentCreate,
    ShiftAssignmentResponse,
    ShiftCoverageResponse,
    ShiftTemplateCreate,
    ShiftTemplateResponse,
)

router = APIRouter(prefix="/api/shifts", tags=["shifts"])


def _template_to_response(s: ShiftTemplate) -> ShiftTemplateResponse:
    return ShiftTemplateResponse(
        id=s.id, branch_id=s.branch_id, name=s.name, start_time=s.start_time,
        end_time=s.end_time, days_of_week=s.days_of_week, min_coverage=s.min_coverage,
        created_at=s.created_at,
    )


def _assignment_to_response(a: ShiftAssignment) -> ShiftAssignmentResponse:
    return ShiftAssignmentResponse(
        id=a.id, employee_id=a.employee_id, shift_template_id=a.shift_template_id,
        start_date=a.start_date, end_date=a.end_date, created_at=a.created_at,
    )


@router.post("", response_model=ShiftTemplateResponse, status_code=201)
async def create_shift_template(
    payload: ShiftTemplateCreate,
    current_user: User = Depends(require_permission("shifts.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        branch = await session.execute(select(Branch).where(Branch.id == payload.branch_id))
        if branch.scalar_one_or_none() is None:
            raise HTTPException(status_code=400, detail=translate("shifts.branch_not_found", locale))

        template = ShiftTemplate(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            branch_id=payload.branch_id,
            name=payload.name,
            start_time=payload.start_time,
            end_time=payload.end_time,
            days_of_week=payload.days_of_week,
            min_coverage=payload.min_coverage,
        )
        session.add(template)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="shift_template.created", resource_type="shift_template", resource_id=template.id,
            extra={"branch_id": str(payload.branch_id), "name": payload.name},
        )
        await session.commit()
        await session.refresh(template)
    return _template_to_response(template)


@router.get("", response_model=list[ShiftTemplateResponse])
async def list_shift_templates(
    branch_id: UUID | None = None,
    current_user: User = Depends(require_permission("shifts.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(ShiftTemplate)
        if branch_id is not None:
            query = query.where(ShiftTemplate.branch_id == branch_id)
        result = await session.execute(query)
        templates = result.scalars().all()
    return [_template_to_response(t) for t in templates]


@router.post("/assignments", response_model=ShiftAssignmentResponse, status_code=201)
async def create_shift_assignment(
    payload: ShiftAssignmentCreate,
    current_user: User = Depends(require_permission("shifts.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        employee = await session.execute(select(Employee).where(Employee.id == payload.employee_id))
        if employee.scalar_one_or_none() is None:
            raise HTTPException(status_code=404, detail=translate("shifts.employee_not_found", locale))

        template = await session.execute(
            select(ShiftTemplate).where(ShiftTemplate.id == payload.shift_template_id)
        )
        if template.scalar_one_or_none() is None:
            raise HTTPException(status_code=404, detail=translate("shifts.template_not_found", locale))

        if payload.end_date is not None and payload.end_date < payload.start_date:
            raise HTTPException(status_code=400, detail=translate("shifts.invalid_date_range", locale))

        assignment = ShiftAssignment(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            employee_id=payload.employee_id,
            shift_template_id=payload.shift_template_id,
            start_date=payload.start_date,
            end_date=payload.end_date,
        )
        session.add(assignment)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="shift_assignment.created", resource_type="shift_assignment", resource_id=assignment.id,
            extra={"employee_id": str(payload.employee_id), "shift_template_id": str(payload.shift_template_id)},
        )
        await session.commit()
        await session.refresh(assignment)
    return _assignment_to_response(assignment)


@router.get("/assignments", response_model=list[ShiftAssignmentResponse])
async def list_shift_assignments(
    employee_id: UUID | None = None,
    shift_template_id: UUID | None = None,
    current_user: User = Depends(require_permission("shifts.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(ShiftAssignment)
        if employee_id is not None:
            query = query.where(ShiftAssignment.employee_id == employee_id)
        if shift_template_id is not None:
            query = query.where(ShiftAssignment.shift_template_id == shift_template_id)
        result = await session.execute(query)
        assignments = result.scalars().all()
    return [_assignment_to_response(a) for a in assignments]


@router.get("/{shift_template_id}/coverage", response_model=ShiftCoverageResponse)
async def get_shift_coverage(
    shift_template_id: UUID,
    on_date: date_type,
    current_user: User = Depends(require_permission("shifts.view")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        template_result = await session.execute(
            select(ShiftTemplate).where(ShiftTemplate.id == shift_template_id)
        )
        template = template_result.scalar_one_or_none()
        if template is None:
            raise HTTPException(status_code=404, detail=translate("shifts.template_not_found", locale))

        result = await session.execute(
            select(ShiftAssignment).where(
                ShiftAssignment.shift_template_id == shift_template_id,
                ShiftAssignment.start_date <= on_date,
            )
        )
        assignments = result.scalars().all()
        assigned_count = sum(
            1 for a in assignments if a.end_date is None or a.end_date >= on_date
        )
    return ShiftCoverageResponse(
        shift_template_id=shift_template_id,
        date=on_date,
        min_coverage=template.min_coverage,
        assigned_count=assigned_count,
        covered=assigned_count >= template.min_coverage,
    )
