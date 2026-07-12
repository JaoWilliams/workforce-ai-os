from datetime import date as date_type
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends

from app.core.labor_analytics import compute_labor_analytics
from app.core.tenant import tenant_session
from app.db.models import User
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/analytics", tags=["analytics"])


@router.get("/labor-dashboard")
async def get_labor_dashboard(
    start_date: date_type,
    end_date: date_type,
    branch_id: Optional[UUID] = None,
    department_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await compute_labor_analytics(
            session, current_user.tenant_id, start_date, end_date, branch_id, department_id
        )
    return result
