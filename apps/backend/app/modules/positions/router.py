"""
Catalogo de Puestos (tenant-wide). A diferencia de Departamentos, NO
hay foreign key en Employee - Employee.position sigue siendo texto
libre (sin migracion, sin riesgo sobre datos ya cargados). Este
catalogo alimenta un <datalist> en el frontend (autocompletar): sugiere
nombres pero el campo sigue aceptando cualquier texto. employee_count
se calcula por coincidencia exacta de texto (Employee.position ==
Position.name), no por FK.

Gap reconocido: 'positions' no tiene politica RLS formal todavia
(mismo caso que shift_alert_configs / departments, ver
WORKFORCE_AI_OS_PROYECTO.md seccion 5.2) - se filtra tenant_id
explicito en cada consulta de este router como defensa en profundidad.
"""
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select

from app.core.audit import log_audit
from app.core.tenant import tenant_session
from app.db.models import Employee, Position, User
from app.modules.positions.schemas import PositionCreate, PositionResponse, PositionUpdate
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/positions", tags=["positions"])


def _to_response(position: Position, employee_count: int = 0) -> PositionResponse:
    return PositionResponse(
        id=position.id,
        name=position.name,
        active=position.active,
        employee_count=employee_count,
    )


@router.post("", response_model=PositionResponse, status_code=201)
async def create_position(
    payload: PositionCreate,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        position = Position(id=uuid4(), tenant_id=current_user.tenant_id, name=payload.name)
        session.add(position)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="position.created",
            resource_type="position",
            resource_id=position.id,
            extra={"name": payload.name},
        )
        await session.commit()
        await session.refresh(position)
    return _to_response(position, employee_count=0)


@router.get("", response_model=list[PositionResponse])
async def list_positions(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Position).where(Position.tenant_id == current_user.tenant_id)
        )
        positions = result.scalars().all()
        counts_result = await session.execute(
            select(Employee.position, func.count(Employee.id))
            .where(Employee.tenant_id == current_user.tenant_id)
            .group_by(Employee.position)
        )
        counts = {row[0]: row[1] for row in counts_result.all()}
    return [_to_response(p, employee_count=counts.get(p.name, 0)) for p in positions]


@router.patch("/{position_id}", response_model=PositionResponse)
async def update_position(
    position_id: UUID,
    payload: PositionUpdate,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Position).where(
                Position.id == position_id,
                Position.tenant_id == current_user.tenant_id,
            )
        )
        position = result.scalar_one_or_none()
        if position is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Puesto no encontrado")
        changes = {}
        if payload.name is not None:
            position.name = payload.name
            changes["name"] = payload.name
        if payload.active is not None:
            position.active = payload.active
            changes["active"] = payload.active
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="position.updated",
            resource_type="position",
            resource_id=position.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(position)
        count_result = await session.execute(
            select(func.count(Employee.id)).where(
                Employee.position == position.name,
                Employee.tenant_id == current_user.tenant_id,
            )
        )
        employee_count = count_result.scalar_one()
    return _to_response(position, employee_count=employee_count)


@router.delete("/{position_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deactivate_position(
    position_id: UUID,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Position).where(
                Position.id == position_id,
                Position.tenant_id == current_user.tenant_id,
            )
        )
        position = result.scalar_one_or_none()
        if position is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Puesto no encontrado")
        count_result = await session.execute(
            select(func.count(Employee.id)).where(
                Employee.position == position.name,
                Employee.active == True,  # noqa: E712
                Employee.tenant_id == current_user.tenant_id,
            )
        )
        active_employee_count = count_result.scalar_one()
        if active_employee_count > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se puede desactivar: hay empleados activos con este puesto",
            )
        position.active = False
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="position.deactivated",
            resource_type="position",
            resource_id=position.id,
            extra={},
        )
        await session.commit()
    return None
