from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, text

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.base import async_session
from app.db.models import Role, Tenant, User, UserRole
from app.modules.auth.dependencies import get_current_user
from app.modules.auth.schemas import (
    LoginRequest,
    MeResponse,
    RegisterRequest,
    TokenResponse,
    UserCreate,
    UserResponse,
    UserUpdate,
)
from app.modules.auth.security import create_access_token, hash_password, verify_password
from app.modules.rbac.constants import ALL_PERMISSIONS
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/auth", tags=["auth"])

DEFAULT_ADMIN_PERMISSIONS = ALL_PERMISSIONS


async def _role_info(session, user_id):
    result = await session.execute(
        select(Role.id, Role.name)
        .join(UserRole, UserRole.role_id == Role.id)
        .where(UserRole.user_id == user_id)
    )
    row = result.first()
    if row:
        return row[0], row[1]
    return None, None


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, locale: str = Depends(get_locale)):
    async with async_session() as session:
        existing = await session.scalar(select(Tenant).where(Tenant.slug == payload.tenant_slug))
        if existing:
            raise HTTPException(status_code=400, detail=translate("auth.tenant_slug_exists", locale))

        tenant = Tenant(id=uuid4(), slug=payload.tenant_slug, name=payload.tenant_name)
        session.add(tenant)
        await session.flush()

        await session.execute(
            text("SELECT set_config('app.current_tenant', :tid, false)"),
            {"tid": str(tenant.id)},
        )
        user = User(
            id=uuid4(),
            tenant_id=tenant.id,
            email=payload.email,
            hashed_password=hash_password(payload.password),
        )
        session.add(user)
        await session.flush()

        admin_role = Role(
            id=uuid4(),
            tenant_id=tenant.id,
            name="admin",
            permissions=DEFAULT_ADMIN_PERMISSIONS,
        )
        session.add(admin_role)
        await session.flush()

        session.add(UserRole(id=uuid4(), tenant_id=tenant.id, user_id=user.id, role_id=admin_role.id))

        await session.commit()
        await session.refresh(user)

    return UserResponse(
        id=user.id,
        tenant_id=user.tenant_id,
        email=user.email,
        active=True,
        role_id=admin_role.id,
        role_name=admin_role.name,
    )


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, locale: str = Depends(get_locale)):
    async with async_session() as session:
        tenant = await session.scalar(select(Tenant).where(Tenant.slug == payload.tenant_slug))
        if not tenant:
            raise HTTPException(status_code=401, detail=translate("auth.invalid_credentials", locale))

    async with tenant_session(tenant.id) as session:
        user = await session.scalar(select(User).where(User.email == payload.email))
        if not user or not verify_password(payload.password, user.hashed_password):
            raise HTTPException(status_code=401, detail=translate("auth.invalid_credentials", locale))
        if not user.active:
            raise HTTPException(status_code=401, detail=translate("auth.invalid_credentials", locale))

    token = create_access_token(tenant_id=str(tenant.id), user_id=str(user.id))
    return TokenResponse(access_token=token)


@router.get("/users", response_model=list[UserResponse])
async def list_users(
    current_user: User = Depends(require_permission("users.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(User))
        users = result.scalars().all()

        roles_result = await session.execute(
            select(UserRole.user_id, Role.id, Role.name).join(Role, Role.id == UserRole.role_id)
        )
        role_map = {row[0]: (row[1], row[2]) for row in roles_result.all()}

    return [
        UserResponse(
            id=u.id,
            tenant_id=u.tenant_id,
            email=u.email,
            active=u.active,
            role_id=role_map.get(u.id, (None, None))[0],
            role_name=role_map.get(u.id, (None, None))[1],
        )
        for u in users
    ]


@router.post("/users", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def create_user(
    payload: UserCreate,
    current_user: User = Depends(require_permission("users.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        existing = await session.scalar(select(User).where(User.email == payload.email))
        if existing:
            raise HTTPException(status_code=400, detail=translate("auth.email_exists", locale))

        role = await session.scalar(select(Role).where(Role.id == payload.role_id))
        if role is None:
            raise HTTPException(status_code=400, detail=translate("auth.invalid_role", locale))

        user = User(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            email=payload.email,
            hashed_password=hash_password(payload.password),
        )
        session.add(user)
        await session.flush()
        session.add(UserRole(id=uuid4(), tenant_id=current_user.tenant_id, user_id=user.id, role_id=role.id))

        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="user.created",
            resource_type="user",
            resource_id=user.id,
            extra={"email": payload.email, "role_id": str(role.id)},
        )
        await session.commit()
        await session.refresh(user)

    return UserResponse(
        id=user.id,
        tenant_id=user.tenant_id,
        email=user.email,
        active=True,
        role_id=role.id,
        role_name=role.name,
    )


@router.patch("/users/{user_id}", response_model=UserResponse)
async def update_user(
    user_id: UUID,
    payload: UserUpdate,
    current_user: User = Depends(require_permission("users.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if user is None:
            raise HTTPException(status_code=404, detail=translate("auth.user_not_found", locale))

        if payload.active is not None and payload.active is False and user.id == current_user.id:
            raise HTTPException(status_code=400, detail=translate("auth.cannot_deactivate_self", locale))

        changes = {}
        if payload.email is not None:
            user.email = payload.email
            changes["email"] = payload.email
        if payload.password:
            user.hashed_password = hash_password(payload.password)
            changes["password"] = "changed"
        if payload.active is not None:
            user.active = payload.active
            changes["active"] = payload.active

        if payload.role_id is not None:
            new_role = await session.scalar(select(Role).where(Role.id == payload.role_id))
            if new_role is None:
                raise HTTPException(status_code=400, detail=translate("auth.invalid_role", locale))
            existing_ur_result = await session.execute(select(UserRole).where(UserRole.user_id == user.id))
            for ur in existing_ur_result.scalars().all():
                await session.delete(ur)
            await session.flush()
            session.add(UserRole(id=uuid4(), tenant_id=current_user.tenant_id, user_id=user.id, role_id=new_role.id))
            changes["role_id"] = str(new_role.id)

        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="user.updated",
            resource_type="user",
            resource_id=user.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(user)

        role_id, role_name = await _role_info(session, user.id)

    return UserResponse(
        id=user.id,
        tenant_id=user.tenant_id,
        email=user.email,
        active=user.active,
        role_id=role_id,
        role_name=role_name,
    )


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deactivate_user(
    user_id: UUID,
    current_user: User = Depends(require_permission("users.manage")),
    locale: str = Depends(get_locale),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail=translate("auth.cannot_deactivate_self", locale))

    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(User).where(User.id == user_id))
        user = result.scalar_one_or_none()
        if user is None:
            raise HTTPException(status_code=404, detail=translate("auth.user_not_found", locale))

        user.active = False
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="user.deactivated",
            resource_type="user",
            resource_id=user.id,
            extra={},
        )
        await session.commit()
    return None


@router.get("/me", response_model=MeResponse)
async def me(current_user: User = Depends(get_current_user)):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(
            select(Role.id, Role.name, Role.permissions)
            .join(UserRole, UserRole.role_id == Role.id)
            .where(UserRole.user_id == current_user.id)
        )
        rows = result.all()
        all_permissions: set[str] = set()
        role_id, role_name = None, None
        for rid, rname, perms in rows:
            all_permissions.update(perms or [])
            role_id, role_name = rid, rname

    return MeResponse(
        id=current_user.id,
        tenant_id=current_user.tenant_id,
        email=current_user.email,
        active=current_user.active,
        role_id=role_id,
        role_name=role_name,
        permissions=sorted(all_permissions),
    )
