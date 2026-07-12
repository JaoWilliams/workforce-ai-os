from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select

from app.core.audit import log_audit
from app.core.onboarding import sync_onboarding_flags
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import BiometricEnrollment, ConsentRecord, Device, Employee, User
from app.modules.biometrics.schemas import BiometricEnrollmentCreate, BiometricEnrollmentResponse
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/employees", tags=["biometrics"])

CAPACITY_FIELD = {
    "facial": "max_faces",
    "fingerprint": "max_fingerprints",
    "card": "max_cards",
}


def _to_response(e: BiometricEnrollment) -> BiometricEnrollmentResponse:
    return BiometricEnrollmentResponse(
        id=e.id, employee_id=e.employee_id, device_id=e.device_id,
        consent_record_id=e.consent_record_id, biometric_type=e.biometric_type,
        template_reference=e.template_reference, is_simulated=e.is_simulated,
        active=e.active, enrolled_at=e.enrolled_at,
    )


@router.post("/{employee_id}/biometric-enrollments", response_model=BiometricEnrollmentResponse, status_code=201)
async def create_biometric_enrollment(
    employee_id: UUID,
    payload: BiometricEnrollmentCreate,
    current_user: User = Depends(require_permission("biometrics.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        employee_result = await session.execute(select(Employee).where(Employee.id == employee_id))
        employee = employee_result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=404, detail=translate("employees.not_found", locale))

        device_result = await session.execute(select(Device).where(Device.id == payload.device_id))
        device = device_result.scalar_one_or_none()
        if device is None:
            raise HTTPException(status_code=400, detail=translate("biometrics.device_not_found", locale))
        if device.branch_id != employee.branch_id:
            raise HTTPException(status_code=400, detail=translate("biometrics.device_branch_mismatch", locale))

        consent_result = await session.execute(
            select(ConsentRecord)
            .where(
                ConsentRecord.employee_id == employee_id,
                ConsentRecord.consent_type == "biometric",
                ConsentRecord.granted == True,  # noqa: E712
            )
            .order_by(ConsentRecord.granted_at.desc())
        )
        consent = consent_result.scalars().first()
        if consent is None:
            raise HTTPException(status_code=400, detail=translate("biometrics.consent_required", locale))

        capacity_field = CAPACITY_FIELD[payload.biometric_type]
        max_capacity = getattr(device, capacity_field)
        if max_capacity is not None:
            count_result = await session.execute(
                select(func.count()).select_from(BiometricEnrollment).where(
                    BiometricEnrollment.device_id == device.id,
                    BiometricEnrollment.biometric_type == payload.biometric_type,
                    BiometricEnrollment.active == True,  # noqa: E712
                )
            )
            current_count = count_result.scalar_one()
            if current_count >= max_capacity:
                raise HTTPException(status_code=400, detail=translate("biometrics.device_at_capacity", locale))

        # MOCK explícitamente autorizado por el usuario (2026-07-08) ante ausencia de
        # hardware real — nunca datos biométricos reales, solo un placeholder identificable.
        template_reference = f"SIMULATED-{uuid4()}"

        enrollment = BiometricEnrollment(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            employee_id=employee_id,
            device_id=payload.device_id,
            consent_record_id=consent.id,
            biometric_type=payload.biometric_type,
            template_reference=template_reference,
            is_simulated=True,
            active=True,
        )
        session.add(enrollment)
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="biometric_enrollment.created", resource_type="biometric_enrollment",
            resource_id=enrollment.id,
            extra={"employee_id": str(employee_id), "device_id": str(payload.device_id),
                   "biometric_type": payload.biometric_type, "is_simulated": True,
                   "consent_record_id": str(consent.id)},
        )
        await session.commit()
        await session.refresh(enrollment)
        await sync_onboarding_flags(session, current_user.tenant_id, employee)
        await session.commit()
    return _to_response(enrollment)


@router.get("/{employee_id}/biometric-enrollments", response_model=list[BiometricEnrollmentResponse])
async def list_biometric_enrollments(
    employee_id: UUID,
    current_user: User = Depends(require_permission("biometrics.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(BiometricEnrollment).where(BiometricEnrollment.employee_id == employee_id)
        )
        enrollments = result.scalars().all()
    return [_to_response(e) for e in enrollments]
