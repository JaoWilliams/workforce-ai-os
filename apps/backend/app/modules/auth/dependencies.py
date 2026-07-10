from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError

from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import User
from app.modules.auth.security import decode_access_token

bearer_scheme = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    locale: str = Depends(get_locale),
) -> User:
    try:
        payload = decode_access_token(credentials.credentials)
    except JWTError:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=translate("auth.invalid_token", locale))

    tenant_id = payload.get("tenant_id")
    user_id = payload.get("sub")
    if not tenant_id or not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=translate("auth.invalid_token", locale))

    async with tenant_session(tenant_id) as session:
        user = await session.get(User, user_id)
        if not user:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=translate("auth.user_not_found", locale))
        if not user.active:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=translate("auth.invalid_token", locale))
        return user
