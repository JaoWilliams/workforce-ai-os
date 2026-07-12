"""
Catalogo de Departamentos (tenant-wide) + asignacion opcional por
empleado (Employee.department_id, nullable). Mismo patron que
Sucursales, pero mas simple (sin codigo/cuenta contable/supervisor).

Gap reconocido: 'departments' no tiene politica RLS formal todavia
(mismo caso que shift_alert_configs, ver WORKFORCE_AI_OS_PROYECTO.md
seccion 5.2) - se filtra tenant_id explicito en cada consulta de este
router como defensa en profundidad mientras se agrega la politica
formal via Alembic.
"""
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select

from app.core.audit import log_audit
from app.core.tenant import tenant_session
from app.db.models import Department, Employee, User
from app.modules.departments.schemas import DepartmentCreate, DepartmentResponse, DepartmentUpdate
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/departments", tags=["departments"])


def _to_response(department: Department, employee_count: int = 0) -> DepartmentResponse:
    return DepartmentResponse(
        id=department.id,
        name=department.name,
        active=department.active,
        employee_count=employee_count,
    )


@router.post("", response_model=DepartmentResponse, status_code=201)
async def create_department(
    payload: DepartmentCreate,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        department = Department(id=uuid4(), tenant_id=current_user.tenant_id, name=payload.name)
        session.add(department)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="department.created",
            resource_type="department",
            resource_id=department.id,
            extra={"name": payload.name},
        )
        await session.commit()
        await session.refresh(department)
    return _to_response(department, employee_count=0)


@router.get("", response_model=list[DepartmentResponse])
async def list_departments(
    current_user: User = Depends(require_permission("catalogs.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Department).where(Department.tenant_id == current_user.tenant_id)
        )
        departments = result.scalars().all()
        counts_result = await session.execute(
            select(Employee.department_id, func.count(Employee.id))
            .where(Employee.tenant_id == current_user.tenant_id)
            .group_by(Employee.department_id)
        )
        counts = {row[0]: row[1] for row in counts_result.all()}
    return [_to_response(d, employee_count=counts.get(d.id, 0)) for d in departments]


@router.patch("/{department_id}", response_model=DepartmentResponse)
async def update_department(
    department_id: UUID,
    payload: DepartmentUpdate,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Department).where(
                Department.id == department_id,
                Department.tenant_id == current_user.tenant_id,
            )
        )
        department = result.scalar_one_or_none()
        if department is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Departamento no encontrado")
        changes = {}
        if payload.name is not None:
            department.name = payload.name
            changes["name"] = payload.name
        if payload.active is not None:
            department.active = payload.active
            changes["active"] = payload.active
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="department.updated",
            resource_type="department",
            resource_id=department.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(department)
        count_result = await session.execute(
            select(func.count(Employee.id)).where(
                Employee.department_id == department.id,
                Employee.tenant_id == current_user.tenant_id,
            )
        )
        employee_count = count_result.scalar_one()
    return _to_response(department, employee_count=employee_count)


@router.delete("/{department_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deactivate_department(
    department_id: UUID,
    current_user: User = Depends(require_permission("catalogs.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Department).where(
                Department.id == department_id,
                Department.tenant_id == current_user.tenant_id,
            )
        )
        department = result.scalar_one_or_none()
        if department is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Departamento no encontrado")
        count_result = await session.execute(
            select(func.count(Employee.id)).where(
                Employee.department_id == department.id,
                Employee.active == True,  # noqa: E712
                Employee.tenant_id == current_user.tenant_id,
            )
        )
        active_employee_count = count_result.scalar_one()
        if active_employee_count > 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No se puede desactivar: hay empleados activos asignados a este departamento",
            )
        department.active = False
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="department.deactivated",
            resource_type="department",
            resource_id=department.id,
            extra={},
        )
        await session.commit()
    return None
