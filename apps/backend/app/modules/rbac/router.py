from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Role, User, UserRole
from app.modules.rbac.constants import ALL_PERMISSIONS
from app.modules.rbac.dependencies import require_permission
from app.modules.rbac.schemas import RoleCreate, RoleResponse, RoleUpdate

router = APIRouter(prefix="/api/rbac", tags=["rbac"])


def _to_response(role: Role, user_count: int = 0) -> RoleResponse:
    return RoleResponse(
        id=role.id,
        name=role.name,
        permissions=role.permissions or [],
        active=role.active,
        user_count=user_count,
    )


@router.get("/permissions", response_model=list[str])
async def list_permissions(
    current_user: User = Depends(require_permission("roles.view")),
):
    return ALL_PERMISSIONS


@router.post("/roles", response_model=RoleResponse, status_code=201)
async def create_role(
    payload: RoleCreate,
    current_user: User = Depends(require_permission("roles.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        role = Role(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            name=payload.name,
            permissions=payload.permissions,
        )
        session.add(role)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="role.created",
            resource_type="role",
            resource_id=role.id,
            extra={"name": payload.name, "permissions": payload.permissions},
        )
        await session.commit()
        await session.refresh(role)
    return _to_response(role, user_count=0)


@router.get("/roles", response_model=list[RoleResponse])
async def list_roles(
    current_user: User = Depends(require_permission("roles.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Role))
        roles = result.scalars().all()

        counts_result = await session.execute(
            select(UserRole.role_id, func.count(UserRole.id)).group_by(UserRole.role_id)
        )
        counts = {row[0]: row[1] for row in counts_result.all()}

    return [_to_response(r, user_count=counts.get(r.id, 0)) for r in roles]


@router.patch("/roles/{role_id}", response_model=RoleResponse)
async def update_role(
    role_id: UUID,
    payload: RoleUpdate,
    current_user: User = Depends(require_permission("roles.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Role).where(Role.id == role_id))
        role = result.scalar_one_or_none()
        if role is None:
            raise HTTPException(status_code=404, detail=translate("rbac.role_not_found", locale))

        changes = {}
        if payload.name is not None:
            role.name = payload.name
            changes["name"] = payload.name
        if payload.permissions is not None:
            role.permissions = payload.permissions
            changes["permissions"] = payload.permissions
        if payload.active is not None:
            role.active = payload.active
            changes["active"] = payload.active

        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="role.updated",
            resource_type="role",
            resource_id=role.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(role)

        count_result = await session.execute(
            select(func.count(UserRole.id)).where(UserRole.role_id == role.id)
        )
        user_count = count_result.scalar_one()

    return _to_response(role, user_count=user_count)


@router.delete("/roles/{role_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deactivate_role(
    role_id: UUID,
    current_user: User = Depends(require_permission("roles.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Role).where(Role.id == role_id))
        role = result.scalar_one_or_none()
        if role is None:
            raise HTTPException(status_code=404, detail=translate("rbac.role_not_found", locale))

        count_result = await session.execute(
            select(func.count(UserRole.id))
            .join(User, User.id == UserRole.user_id)
            .where(UserRole.role_id == role.id, User.active == True)  # noqa: E712
        )
        active_user_count = count_result.scalar_one()
        if active_user_count > 0:
            raise HTTPException(status_code=400, detail=translate("rbac.has_active_users", locale))

        role.active = False
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="role.deactivated",
            resource_type="role",
            resource_id=role.id,
            extra={},
        )
        await session.commit()
    return None
