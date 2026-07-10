from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends
from fastapi.responses import Response

from app.core.payroll import build_payroll_pdf, build_payroll_xlsx, compute_payroll_rows
from app.core.tenant import tenant_session
from app.db.base import async_session
from app.db.models import Tenant, User
from app.modules.payroll.schemas import PayrollRow
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/payroll", tags=["payroll"])


@router.get("", response_model=list[PayrollRow])
async def get_payroll(
    start_date: date,
    end_date: date,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_payroll_rows(session, start_date, end_date, branch_id)
    return rows


@router.get("/export-xlsx")
async def export_payroll_xlsx(
    start_date: date,
    end_date: date,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_payroll_rows(session, start_date, end_date, branch_id)
    content = build_payroll_xlsx(rows, start_date, end_date)
    filename = f"nomina_bruta_{start_date}_{end_date}.xlsx"
    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/export-pdf")
async def export_payroll_pdf(
    start_date: date,
    end_date: date,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with async_session() as plain_session:
        tenant = await plain_session.get(Tenant, current_user.tenant_id)
    async with tenant_session(current_user.tenant_id) as session:
        rows = await compute_payroll_rows(session, start_date, end_date, branch_id)
    content = build_payroll_pdf(rows, start_date, end_date, tenant_name=tenant.name if tenant else "")
    filename = f"nomina_bruta_{start_date}_{end_date}.pdf"
    return Response(
        content=content,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
