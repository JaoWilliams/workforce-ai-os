"""Helper reutilizable para que cualquier módulo futuro consulte si una
funcionalidad está habilitada para un tenant (y opcionalmente una sucursal
específica), sin duplicar la lógica de resolución en cada endpoint."""
from typing import Optional
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import FeatureFlag, TenantFeatureFlag


async def is_feature_enabled(
    session: AsyncSession, tenant_id: UUID, code: str, branch_id: Optional[UUID] = None
) -> bool:
    if branch_id is not None:
        result = await session.execute(
            select(TenantFeatureFlag.enabled).where(
                TenantFeatureFlag.tenant_id == tenant_id,
                TenantFeatureFlag.feature_flag_code == code,
                TenantFeatureFlag.branch_id == branch_id,
            )
        )
        branch_override = result.scalar_one_or_none()
        if branch_override is not None:
            return branch_override

    result = await session.execute(
        select(TenantFeatureFlag.enabled).where(
            TenantFeatureFlag.tenant_id == tenant_id,
            TenantFeatureFlag.feature_flag_code == code,
            TenantFeatureFlag.branch_id.is_(None),
        )
    )
    tenant_override = result.scalar_one_or_none()
    if tenant_override is not None:
        return tenant_override

    flag_result = await session.execute(select(FeatureFlag.category).where(FeatureFlag.code == code))
    category = flag_result.scalar_one_or_none()
    if category is None:
        return False
    return category == "core"
