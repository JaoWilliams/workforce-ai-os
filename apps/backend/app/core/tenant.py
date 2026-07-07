from contextlib import asynccontextmanager
from typing import AsyncIterator
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.base import async_session


@asynccontextmanager
async def tenant_session(tenant_id: UUID) -> AsyncIterator[AsyncSession]:
    """
    Sesion de base de datos con el tenant_id ya seteado como variable de
    sesion de Postgres (app.current_tenant), para que las politicas de
    Row-Level Security se apliquen automaticamente en cada query.

    Uso:
        async with tenant_session(tenant_id) as session:
            result = await session.execute(select(User))
    """
    async with async_session() as session:
        await session.execute(
            text("SELECT set_config('app.current_tenant', :tenant_id, false)"),
            {"tenant_id": str(tenant_id)},
        )
        yield session
