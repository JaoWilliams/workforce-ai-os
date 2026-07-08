from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import AuditLog, ConsentRecord, Employee, User
from app.modules.auth.dependencies import get_current_user
from app.modules.legal.schemas import AuditLogResponse, ConsentGrant, ConsentResponse
from app.modules.rbac.dependencies import require_permission, user_has_permission

router = APIRouter(prefix="/api/legal", tags=["legal"])


def _to_consent_response(c: ConsentRecord) -> ConsentResponse:
    return ConsentResponse(
        id=c.id, user_id=c.user_id, employee_id=c.employee_id, consent_type=c.consent_type,
        granted=c.granted, granted_at=c.granted_at, revoked_at=c.revoked_at,
    )


@router.post("/consent", response_model=ConsentResponse, status_code=201)
async def grant_consent(
    payload: ConsentGrant,
    current_user: User = Depends(get_current_user),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        employee_id = None
        if payload.employee_id is not None:
            # Consentimiento en nombre de un empleado: requiere permiso de gestión,
            # no cualquier usuario logueado puede registrar consentimiento ajeno.
            if not await user_has_permission(session, current_user.id, current_user.tenant_id, "employees.manage"):
                raise HTTPException(status_code=403, detail=translate("auth.permission_denied", locale))
            emp = await session.execute(select(Employee).where(Employee.id == payload.employee_id))
            if emp.scalar_one_or_none() is None:
                raise HTTPException(status_code=400, detail=translate("legal.employee_not_found", locale))
            employee_id = payload.employee_id

        consent = ConsentRecord(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            user_id=None if employee_id else current_user.id,
            employee_id=employee_id,
            consent_type=payload.consent_type,
            granted=True,
        )
        session.add(consent)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="consent.granted",
            resource_type="consent_record",
            resource_id=consent.id,
            extra={"consent_type": payload.consent_type, "employee_id": str(employee_id) if employee_id else None},
        )
        await session.commit()
        await session.refresh(consent)
    return _to_consent_response(consent)


@router.post("/consent/{consent_id}/revoke", response_model=ConsentResponse)
async def revoke_consent(consent_id: UUID, current_user: User = Depends(get_current_user), locale: str = Depends(get_locale)):
    async with tenant_session(current_user.tenant_id) as session:
        consent = await session.get(ConsentRecord, consent_id)
        if consent is None:
            raise HTTPException(status_code=404, detail=translate("legal.consent_not_found", locale))

        if consent.employee_id is not None:
            if not await user_has_permission(session, current_user.id, current_user.tenant_id, "employees.manage"):
                raise HTTPException(status_code=403, detail=translate("auth.permission_denied", locale))
        elif consent.user_id != current_user.id:
            raise HTTPException(status_code=404, detail=translate("legal.consent_not_found", locale))

        consent.granted = False
        consent.revoked_at = datetime.now(timezone.utc)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="consent.revoked",
            resource_type="consent_record",
            resource_id=consent.id,
        )
        await session.commit()
        await session.refresh(consent)
    return _to_consent_response(consent)


@router.get("/audit-log", response_model=list[AuditLogResponse])
async def list_audit_log(current_user: User = Depends(require_permission("audit.view"))):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(AuditLog).order_by(AuditLog.created_at.desc()))
        logs = result.scalars().all()
    return [
        AuditLogResponse(
            id=l.id, actor_user_id=l.actor_user_id, action=l.action,
            resource_type=l.resource_type, resource_id=l.resource_id,
            extra=l.extra, created_at=l.created_at,
        )
        for l in logs
    ]
