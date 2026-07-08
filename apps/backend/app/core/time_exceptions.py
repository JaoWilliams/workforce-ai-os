from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import TimeException


async def has_pending_exceptions(session: AsyncSession, employee_id: UUID) -> bool:
    """Punto de enganche futuro para el mód. 15 (nómina, todavía no construido):
    antes de cerrar un período de pago para un empleado, ese módulo debe llamar
    esta función. Si retorna True, el cierre se bloquea hasta que las excepciones
    pendientes se resuelvan (aprobar/rechazar vía PATCH /api/exceptions/{id}/review).
    Hoy no existe un caller real desde nómina — se expone también vía
    GET /api/exceptions/pending-check para poder verificarla end-to-end ahora."""
    result = await session.execute(
        select(func.count()).select_from(TimeException).where(
            TimeException.employee_id == employee_id,
            TimeException.status == "pending",
        )
    )
    return result.scalar_one() > 0
