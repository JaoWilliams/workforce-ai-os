"""
Solicitudes de permiso generico (medico, personal, duelo, otro).
Separado a proposito de VacationRequest: ese modelo alimenta
core/vacations.py (compute_vacation_adjustments -> vacation_pay en
cada corrida de planilla) - un permiso generico NO debe tener ese
efecto automatico, ya que las reglas de pago varian por tipo y no
estan definidas legalmente como las vacaciones. Mismo permiso que
Vacaciones (payroll.manage/payroll.view) para que convivan en una
sola pantalla de Solicitudes.
"""
from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Employee, LeaveRequest, User
from app.modules.leave_requests.schemas import LeaveRequestCreate, LeaveRequestResponse, LeaveRequestReview
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/leave-requests", tags=["leave-requests"])


def _to_response(lr: LeaveRequest, employee_name: str) -> LeaveRequestResponse:
    return LeaveRequestResponse(
        id=lr.id, employee_id=lr.employee_id, employee_name=employee_name,
        leave_type=lr.leave_type, start_date=lr.start_date, end_date=lr.end_date,
        reason=lr.reason, status=lr.status,
        reviewed_by_user_id=lr.reviewed_by_user_id, reviewed_at=lr.reviewed_at,
        review_notes=lr.review_notes, created_at=lr.created_at,
    )


@router.post("", response_model=LeaveRequestResponse, status_code=201)
async def create_leave_request(
    payload: LeaveRequestCreate,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    if payload.end_date < payload.start_date:
        raise HTTPException(status_code=400, detail="El rango de fechas es invalido")
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee).where(Employee.id == payload.employee_id))
        employee = result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))
        leave = LeaveRequest(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            employee_id=payload.employee_id,
            leave_type=payload.leave_type,
            start_date=payload.start_date,
            end_date=payload.end_date,
            reason=payload.reason,
            status="pending",
        )
        session.add(leave)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="leave_request.created", resource_type="leave_request", resource_id=leave.id,
            extra={"employee_id": str(payload.employee_id), "leave_type": payload.leave_type},
        )
        await session.commit()
        await session.refresh(leave)
        employee_name = f"{employee.first_name} {employee.last_name}"
    return _to_response(leave, employee_name)


@router.get("", response_model=list[LeaveRequestResponse])
async def list_leave_requests(
    employee_id: UUID | None = None,
    status: str | None = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(LeaveRequest, Employee).join(Employee, Employee.id == LeaveRequest.employee_id)
        if employee_id is not None:
            query = query.where(LeaveRequest.employee_id == employee_id)
        if status is not None:
            query = query.where(LeaveRequest.status == status)
        result = await session.execute(query.order_by(LeaveRequest.created_at.desc()))
        rows = result.all()
    return [_to_response(lr, f"{e.first_name} {e.last_name}") for lr, e in rows]


@router.patch("/{leave_id}/status", response_model=LeaveRequestResponse)
async def review_leave_request(
    leave_id: UUID,
    payload: LeaveRequestReview,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(LeaveRequest, Employee)
            .join(Employee, Employee.id == LeaveRequest.employee_id)
            .where(LeaveRequest.id == leave_id)
        )
        row = result.first()
        if row is None:
            raise HTTPException(status_code=404, detail="Solicitud no encontrada")
        leave, employee = row
        if leave.status != "pending":
            raise HTTPException(status_code=400, detail="La solicitud ya fue revisada")
        leave.status = payload.status
        leave.review_notes = payload.review_notes
        leave.reviewed_by_user_id = current_user.id
        leave.reviewed_at = datetime.now(timezone.utc)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=f"leave_request.{payload.status}", resource_type="leave_request", resource_id=leave.id,
            extra={"review_notes": payload.review_notes},
        )
        await session.commit()
        await session.refresh(leave)
        employee_name = f"{employee.first_name} {employee.last_name}"
    return _to_response(leave, employee_name)
