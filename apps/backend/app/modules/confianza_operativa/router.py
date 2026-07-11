from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import TrustFlag, User
from app.modules.confianza_operativa.schemas import TrustFlagResolve, TrustFlagResponse
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/confianza-operativa", tags=["confianza_operativa"])


def _to_response(f: TrustFlag) -> TrustFlagResponse:
    return TrustFlagResponse(
        id=f.id, employee_id=f.employee_id, payroll_period_id=f.payroll_period_id, branch_id=f.branch_id,
        rule_code=f.rule_code, severity=f.severity,
        details=f.details, resolved=f.resolved, detected_at=f.detected_at,
    )


@router.get("/flags", response_model=list[TrustFlagResponse])
async def list_flags(
    employee_id: UUID | None = None,
    payroll_period_id: UUID | None = None,
    resolved: bool | None = None,
    current_user: User = Depends(require_permission("confianza.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(TrustFlag).order_by(TrustFlag.detected_at.desc())
        if employee_id is not None:
            query = query.where(TrustFlag.employee_id == employee_id)
        if payroll_period_id is not None:
            query = query.where(TrustFlag.payroll_period_id == payroll_period_id)
        if resolved is not None:
            query = query.where(TrustFlag.resolved == resolved)
        result = await session.execute(query)
        flags = result.scalars().all()
    return [_to_response(f) for f in flags]


@router.patch("/flags/{flag_id}", response_model=TrustFlagResponse)
async def resolve_flag(
    flag_id: UUID,
    payload: TrustFlagResolve,
    current_user: User = Depends(require_permission("confianza.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(TrustFlag).where(TrustFlag.id == flag_id))
        flag = result.scalar_one_or_none()
        if flag is None:
            raise HTTPException(status_code=404, detail=translate("confianza.flag_not_found", locale))
        flag.resolved = payload.resolved
        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="trust_flag.resolved" if payload.resolved else "trust_flag.reopened",
            resource_type="trust_flag", resource_id=flag.id, extra={"resolved": payload.resolved},
        )
        await session.commit()
        await session.refresh(flag)
    return _to_response(flag)
