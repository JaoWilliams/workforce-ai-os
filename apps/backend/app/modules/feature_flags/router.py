from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.feature_flags import is_feature_enabled
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, FeatureFlag, TenantFeatureFlag, User
from app.modules.feature_flags.schemas import (
    FeatureFlagCatalogItem,
    FeatureFlagToggle,
    TenantFeatureFlagStatus,
)
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/feature-flags", tags=["feature_flags"])


@router.get("", response_model=list[FeatureFlagCatalogItem])
async def list_catalog(
    current_user: User = Depends(require_permission("feature_flags.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(FeatureFlag).order_by(FeatureFlag.code))
        flags = result.scalars().all()
    return [
        FeatureFlagCatalogItem(code=f.code, name=f.name, description=f.description, category=f.category)
        for f in flags
    ]


@router.get("/tenant", response_model=list[TenantFeatureFlagStatus])
async def list_tenant_status(
    branch_id: str | None = None,
    current_user: User = Depends(require_permission("feature_flags.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        catalog_result = await session.execute(select(FeatureFlag).order_by(FeatureFlag.code))
        catalog = catalog_result.scalars().all()

        overrides_result = await session.execute(
            select(TenantFeatureFlag).where(TenantFeatureFlag.tenant_id == current_user.tenant_id)
        )
        overrides = overrides_result.scalars().all()
        branch_overrides = {o.feature_flag_code: o.enabled for o in overrides if branch_id and str(o.branch_id) == branch_id}
        tenant_overrides = {o.feature_flag_code: o.enabled for o in overrides if o.branch_id is None}

        status_list = []
        for flag in catalog:
            if flag.code in branch_overrides:
                enabled, source = branch_overrides[flag.code], "branch_override"
            elif flag.code in tenant_overrides:
                enabled, source = tenant_overrides[flag.code], "tenant_override"
            else:
                enabled, source = (flag.category == "core"), "default"
            status_list.append(TenantFeatureFlagStatus(
                code=flag.code, name=flag.name, category=flag.category, enabled=enabled, source=source,
            ))
    return status_list


@router.patch("/tenant/{code}", response_model=TenantFeatureFlagStatus)
async def toggle_tenant_flag(
    code: str,
    payload: FeatureFlagToggle,
    current_user: User = Depends(require_permission("feature_flags.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        flag_result = await session.execute(select(FeatureFlag).where(FeatureFlag.code == code))
        flag = flag_result.scalar_one_or_none()
        if flag is None:
            raise HTTPException(status_code=404, detail=translate("feature_flags.not_found", locale))

        if payload.branch_id is not None:
            branch_result = await session.execute(select(Branch).where(Branch.id == payload.branch_id))
            if branch_result.scalar_one_or_none() is None:
                raise HTTPException(status_code=400, detail=translate("employees.branch_not_found", locale))

        existing_result = await session.execute(
            select(TenantFeatureFlag).where(
                TenantFeatureFlag.tenant_id == current_user.tenant_id,
                TenantFeatureFlag.feature_flag_code == code,
                TenantFeatureFlag.branch_id == payload.branch_id,
            )
        )
        override = existing_result.scalar_one_or_none()
        if override is None:
            override = TenantFeatureFlag(
                id=uuid4(),
                tenant_id=current_user.tenant_id,
                feature_flag_code=code,
                branch_id=payload.branch_id,
                enabled=payload.enabled,
            )
            session.add(override)
        else:
            override.enabled = payload.enabled
            override.updated_at = datetime.now(timezone.utc)

        await log_audit(
            session, tenant_id=current_user.tenant_id, actor_user_id=current_user.id,
            action="feature_flag.toggled", resource_type="tenant_feature_flag",
            resource_id=override.id if override.id else None,
            extra={"code": code, "enabled": payload.enabled,
                   "branch_id": str(payload.branch_id) if payload.branch_id else None},
        )
        await session.commit()
        await session.refresh(override)

    source = "branch_override" if payload.branch_id else "tenant_override"
    return TenantFeatureFlagStatus(
        code=flag.code, name=flag.name, category=flag.category, enabled=payload.enabled, source=source,
    )
