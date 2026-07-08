from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.core.audit import log_audit
from app.core.confianza_operativa import evaluate_new_attendance_record
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import AttendanceRecord, Device, Employee, User
from app.modules.attendance.schemas import AttendanceRecordCreate, AttendanceRecordResponse
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/attendance", tags=["attendance"])


def _to_response(r: AttendanceRecord) -> AttendanceRecordResponse:
    return AttendanceRecordResponse(
        id=r.id, employee_id=r.employee_id, device_id=r.device_id, type=r.type,
        verification_method=r.verification_method, biometric_enrollment_id=r.biometric_enrollment_id,
        recorded_at=r.recorded_at, is_simulated=r.is_simulated,
    )


@router.post("", response_model=AttendanceRecordResponse, status_code=201)
async def create_attendance_record(
    payload: AttendanceRecordCreate,
    current_user: User = Depends(require_permission("attendance.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        employee_result = await session.execute(select(Employee).where(Employee.id == payload.employee_id))
        employee = employee_result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=400, detail=translate("attendance.employee_not_found", locale))

        device_result = await session.execute(select(Device).where(Device.id == payload.device_id))
        device = device_result.scalar_one_or_none()
        if device is None:
            raise HTTPException(status_code=400, detail=translate("attendance.device_not_found", locale))
        # NOTA: a propósito NO se rechaza marcar en un dispositivo de otra sucursal —
        # eso es justo lo que el Motor de Confianza Operativa™ (mód. 17a) necesita poder
        # observar para marcarlo como señal de "patrón imposible" cuando el tiempo entre
        # marcaciones es demasiado corto. Bloquearlo acá impediría que la regla exista.

        record = AttendanceRecord(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            employee_id=payload.employee_id,
            device_id=payload.device_id,
            type=payload.type,
            verification_method=payload.verification_method,
            biometric_enrollment_id=payload.biometric_enrollment_id,
            recorded_at=payload.recorded_at,
            is_simulated=True,
        )
        session.add(record)
        try:
            await session.flush()
        except IntegrityError:
            await session.rollback()
            raise HTTPException(status_code=400, detail=translate("attendance.duplicate", locale))

        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="attendance.recorded", resource_type="attendance_record", resource_id=record.id,
            extra={"employee_id": str(payload.employee_id), "device_id": str(payload.device_id),
                   "type": payload.type, "verification_method": payload.verification_method,
                   "recorded_at": payload.recorded_at.isoformat(), "is_simulated": True},
        )

        # Motor de Confianza Operativa™ heurístico (mód. 17a) — evalúa la marcación
        # nueva en tiempo real contra la inmediatamente anterior del mismo empleado.
        new_flags = await evaluate_new_attendance_record(
            session, current_user.tenant_id, payload.employee_id, record, device.branch_id,
        )
        for flag in new_flags:
            await log_audit(
                session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
                action="trust_flag.detected", resource_type="trust_flag", resource_id=flag.id,
                extra={"rule_code": flag.rule_code, "severity": flag.severity, "details": flag.details},
            )

        await session.commit()
        await session.refresh(record)
    return _to_response(record)


@router.get("", response_model=list[AttendanceRecordResponse])
async def list_attendance_records(
    current_user: User = Depends(require_permission("attendance.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(AttendanceRecord).order_by(AttendanceRecord.recorded_at.desc()))
        records = result.scalars().all()
    return [_to_response(r) for r in records]
