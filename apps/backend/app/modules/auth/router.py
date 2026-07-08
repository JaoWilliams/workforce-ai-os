from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, text

from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.base import async_session
from app.db.models import Role, Tenant, User, UserRole
from app.modules.auth.dependencies import get_current_user
from app.modules.auth.schemas import LoginRequest, RegisterRequest, TokenResponse, UserResponse
from app.modules.auth.security import create_access_token, hash_password, verify_password

router = APIRouter(prefix="/api/auth", tags=["auth"])

DEFAULT_ADMIN_PERMISSIONS = [
    "branches.manage",
    "branches.view",
    "users.manage",
    "users.view",
    "roles.manage",
    "audit.view",
    "catalogs.manage",
    "catalogs.view",
    "devices.manage",
    "devices.view",
    "employees.manage",
    "employees.view",
    "biometrics.manage",
    "biometrics.view",
    "feature_flags.manage",
    "feature_flags.view",
    "attendance.manage",
    "attendance.view",
    "confianza.manage",
    "confianza.view",
    "exceptions.manage",
    "exceptions.view",
]


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

    return UserResponse(id=user.id, tenant_id=user.tenant_id, email=user.email)


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

    token = create_access_token(tenant_id=str(tenant.id), user_id=str(user.id))
    return TokenResponse(access_token=token)


@router.get("/me", response_model=UserResponse)
async def me(current_user: User = Depends(get_current_user)):
    return UserResponse(id=current_user.id, tenant_id=current_user.tenant_id, email=current_user.email)
