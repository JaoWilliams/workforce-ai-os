from fastapi import Depends, HTTPException, status
from sqlalchemy import select

from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Role, User, UserRole
from app.modules.auth.dependencies import get_current_user


def require_permission(code: str):
    async def checker(
        current_user: User = Depends(get_current_user),
        locale: str = Depends(get_locale),
    ) -> User:
        async with tenant_session(current_user.tenant_id) as session:
            result = await session.execute(
                select(Role.permissions)
                .join(UserRole, UserRole.role_id == Role.id)
                .where(UserRole.user_id == current_user.id)
            )
            all_permissions: set[str] = set()
            for (perms,) in result.all():
                all_permissions.update(perms or [])

            if code not in all_permissions:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=translate("auth.permission_denied", locale),
                )
        return current_user

    return checker
