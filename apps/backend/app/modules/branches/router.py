from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, User
from app.modules.branches.schemas import BranchCreate, BranchResponse, BranchUpdate
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/branches", tags=["branches"])


def _to_response(branch: Branch) -> BranchResponse:
    return BranchResponse(
        id=branch.id,
        code=branch.code,
        name=branch.name,
        accounting_account=branch.accounting_account,
        supervisor_user_id=branch.supervisor_user_id,
    )


@router.post("", response_model=BranchResponse, status_code=201)
async def create_branch(
    payload: BranchCreate,
    current_user: User = Depends(require_permission("branches.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        branch = Branch(id=uuid4(), tenant_id=current_user.tenant_id, code=payload.code, name=payload.name)
        session.add(branch)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="branch.created",
            resource_type="branch",
            resource_id=branch.id,
            extra={"code": payload.code, "name": payload.name},
        )
        await session.commit()
        await session.refresh(branch)
    return _to_response(branch)


@router.get("", response_model=list[BranchResponse])
async def list_branches(
    current_user: User = Depends(require_permission("branches.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Branch))
        branches = result.scalars().all()
    return [_to_response(b) for b in branches]


@router.patch("/{branch_id}", response_model=BranchResponse)
async def update_branch(
    branch_id: UUID,
    payload: BranchUpdate,
    current_user: User = Depends(require_permission("branches.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Branch).where(Branch.id == branch_id))
        branch = result.scalar_one_or_none()
        if branch is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=translate("branches.not_found", locale),
            )

        changes = {}
        if payload.accounting_account is not None:
            branch.accounting_account = payload.accounting_account
            changes["accounting_account"] = payload.accounting_account
        if payload.supervisor_user_id is not None:
            branch.supervisor_user_id = payload.supervisor_user_id
            changes["supervisor_user_id"] = str(payload.supervisor_user_id)

        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="branch.updated",
            resource_type="branch",
            resource_id=branch.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(branch)
    return _to_response(branch)
