import os
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.core.time_exceptions import has_pending_exceptions
from app.db.models import AttendanceRecord, Employee, TimeException, TrustFlag, User
from app.modules.exceptions.schemas import (
    PendingExceptionsCheck,
    TimeExceptionCreate,
    TimeExceptionResponse,
    TimeExceptionReview,
)
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/exceptions", tags=["exceptions"])

EVIDENCE_STORAGE_DIR = "/app/storage/evidence"
EVIDENCE_ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png", ".pdf"}
EVIDENCE_MAX_SIZE = 10 * 1024 * 1024  # 10 MB


def _to_response(e: TimeException) -> TimeExceptionResponse:
    return TimeExceptionResponse(
        id=e.id, employee_id=e.employee_id,
        attendance_record_id=e.attendance_record_id, trust_flag_id=e.trust_flag_id,
        exception_type=e.exception_type, justification=e.justification,
        evidence_reference=e.evidence_reference, evidence_filename=e.evidence_filename, status=e.status,
        reviewed_by_user_id=e.reviewed_by_user_id, reviewed_at=e.reviewed_at,
        review_notes=e.review_notes, created_at=e.created_at,
    )


@router.post("", response_model=TimeExceptionResponse, status_code=201)
async def create_exception(
    payload: TimeExceptionCreate,
    current_user: User = Depends(require_permission("exceptions.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Employee).where(Employee.id == payload.employee_id))
        employee = result.scalar_one_or_none()
        if employee is None:
            raise HTTPException(status_code=404, detail=translate("exceptions.employee_not_found", locale))

        if payload.attendance_record_id is not None:
            result = await session.execute(
                select(AttendanceRecord).where(AttendanceRecord.id == payload.attendance_record_id)
            )
            record = result.scalar_one_or_none()
            if record is None or record.employee_id != payload.employee_id:
                raise HTTPException(
                    status_code=404, detail=translate("exceptions.attendance_record_not_found", locale)
                )

        if payload.trust_flag_id is not None:
            result = await session.execute(select(TrustFlag).where(TrustFlag.id == payload.trust_flag_id))
            flag = result.scalar_one_or_none()
            if flag is None or flag.employee_id != payload.employee_id:
                raise HTTPException(status_code=404, detail=translate("exceptions.trust_flag_not_found", locale))

        exception = TimeException(
            tenant_id=current_user.tenant_id,
            employee_id=payload.employee_id,
            attendance_record_id=payload.attendance_record_id,
            trust_flag_id=payload.trust_flag_id,
            exception_type=payload.exception_type,
            justification=payload.justification,
            evidence_reference=payload.evidence_reference,
            status="pending",
        )
        session.add(exception)
        await session.flush()

        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="time_exception.created", resource_type="time_exception", resource_id=exception.id,
            extra={"employee_id": str(payload.employee_id), "exception_type": payload.exception_type},
        )

        await session.commit()
        await session.refresh(exception)
    return _to_response(exception)


@router.get("", response_model=list[TimeExceptionResponse])
async def list_exceptions(
    employee_id: UUID | None = None,
    status: str | None = None,
    current_user: User = Depends(require_permission("exceptions.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(TimeException).order_by(TimeException.created_at.desc())
        if employee_id is not None:
            query = query.where(TimeException.employee_id == employee_id)
        if status is not None:
            query = query.where(TimeException.status == status)
        result = await session.execute(query)
        exceptions = result.scalars().all()
    return [_to_response(e) for e in exceptions]


@router.post("/{exception_id}/evidence", response_model=TimeExceptionResponse)
async def upload_evidence(
    exception_id: UUID,
    file: UploadFile = File(...),
    current_user: User = Depends(require_permission("exceptions.manage")),
    locale: str = Depends(get_locale),
):
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in EVIDENCE_ALLOWED_EXTENSIONS:
        raise HTTPException(status_code=400, detail="Formato no permitido - usa JPG, PNG o PDF")
    content = await file.read()
    if len(content) > EVIDENCE_MAX_SIZE:
        raise HTTPException(status_code=400, detail="El archivo supera el limite de 10MB")
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(TimeException).where(TimeException.id == exception_id))
        exception = result.scalar_one_or_none()
        if exception is None:
            raise HTTPException(status_code=404, detail=translate("exceptions.not_found", locale))
        os.makedirs(EVIDENCE_STORAGE_DIR, exist_ok=True)
        filepath = os.path.join(EVIDENCE_STORAGE_DIR, f"{exception_id}{ext}")
        with open(filepath, "wb") as out:
            out.write(content)
        exception.evidence_reference = filepath
        exception.evidence_filename = file.filename
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="time_exception.evidence_uploaded", resource_type="time_exception", resource_id=exception.id,
            extra={"filename": file.filename},
        )
        await session.commit()
        await session.refresh(exception)
    return _to_response(exception)


@router.get("/{exception_id}/evidence")
async def download_evidence(
    exception_id: UUID,
    current_user: User = Depends(require_permission("exceptions.view")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(TimeException).where(TimeException.id == exception_id))
        exception = result.scalar_one_or_none()
        if (
            exception is None
            or not exception.evidence_reference
            or not os.path.exists(exception.evidence_reference)
        ):
            raise HTTPException(status_code=404, detail=translate("exceptions.not_found", locale))
        filename = exception.evidence_filename or os.path.basename(exception.evidence_reference)
    return FileResponse(exception.evidence_reference, filename=filename)


@router.get("/pending-check", response_model=PendingExceptionsCheck)
async def pending_check(
    employee_id: UUID,
    current_user: User = Depends(require_permission("exceptions.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        pending = await has_pending_exceptions(session, employee_id)
    return PendingExceptionsCheck(employee_id=employee_id, has_pending_exceptions=pending)


@router.patch("/{exception_id}/review", response_model=TimeExceptionResponse)
async def review_exception(
    exception_id: UUID,
    payload: TimeExceptionReview,
    current_user: User = Depends(require_permission("exceptions.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(TimeException).where(TimeException.id == exception_id))
        exception = result.scalar_one_or_none()
        if exception is None:
            raise HTTPException(status_code=404, detail=translate("exceptions.not_found", locale))
        if exception.status != "pending":
            raise HTTPException(status_code=400, detail=translate("exceptions.invalid_status_transition", locale))

        exception.status = payload.status
        exception.review_notes = payload.review_notes
        exception.reviewed_by_user_id = current_user.id
        exception.reviewed_at = datetime.now(timezone.utc)

        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action=f"time_exception.{payload.status}", resource_type="time_exception", resource_id=exception.id,
            extra={"review_notes": payload.review_notes},
        )

        await session.commit()
        await session.refresh(exception)
    return _to_response(exception)
