from uuid import uuid4

from fastapi import APIRouter, Depends
from sqlalchemy import select

from app.core.tenant import tenant_session
from app.db.models import Branch, User
from app.modules.branches.schemas import BranchCreate, BranchResponse
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/branches", tags=["branches"])


@router.post("", response_model=BranchResponse, status_code=201)
async def create_branch(
    payload: BranchCreate,
    current_user: User = Depends(require_permission("branches.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        branch = Branch(id=uuid4(), tenant_id=current_user.tenant_id, code=payload.code, name=payload.name)
        session.add(branch)
        await session.commit()
        await session.refresh(branch)
    return BranchResponse(id=branch.id, code=branch.code, name=branch.name)


@router.get("", response_model=list[BranchResponse])
async def list_branches(
    current_user: User = Depends(require_permission("branches.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Branch))
        branches = result.scalars().all()
    return [BranchResponse(id=b.id, code=b.code, name=b.name) for b in branches]
