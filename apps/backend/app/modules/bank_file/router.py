from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy import select

from app.core.bank_file import generate_bank_transfer_rows, persist_bank_transfer_file, render_bank_transfer_txt
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import BankTransferFile, BankTransferFileLine, Employee, PayrollPeriod, User
from app.modules.bank_file.schemas import (
    BankTransferFileDetailResponse,
    BankTransferFileLineResponse,
    BankTransferFileResponse,
    BankTransferMissingEntry,
)
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/bank-file", tags=["bank-file"])


def _raise_for_error(error_result: dict):
    error = error_result.get("error")
    if error == "bank_config_missing":
        raise HTTPException(status_code=400, detail={"error": "bank_config_missing"})
    if error == "no_valid_rows":
        raise HTTPException(status_code=400, detail={"error": "no_valid_rows", "missing": error_result.get("missing", [])})
    raise HTTPException(status_code=400, detail={"error": error})


def _header_response(header: BankTransferFile, missing: list) -> BankTransferFileResponse:
    return BankTransferFileResponse(
        id=header.id, payroll_period_id=header.payroll_period_id, branch_id=header.branch_id,
        generated_at=header.generated_at, row_count=header.row_count,
        total_amount=float(header.total_amount), missing_count=header.missing_count,
        missing=[BankTransferMissingEntry(**m) for m in missing],
    )


@router.post("/generate/{payroll_period_id}", response_model=BankTransferFileResponse, status_code=201)
async def generate_bank_transfer_file(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result_period = await session.execute(select(PayrollPeriod).where(PayrollPeriod.id == payroll_period_id))
        period = result_period.scalar_one_or_none()
        if period is None:
            raise HTTPException(status_code=404, detail=translate("payroll.period_not_found", locale))

        result = await generate_bank_transfer_rows(session, current_user.tenant_id, period, branch_id)
        if "error" in result:
            _raise_for_error(result)

        persisted = await persist_bank_transfer_file(
            session, current_user.tenant_id, payroll_period_id, branch_id, result, current_user.id,
        )
        if "error" in persisted:
            _raise_for_error(persisted)

        header_result = await session.execute(
            select(BankTransferFile).where(BankTransferFile.id == persisted["bank_transfer_file_id"])
        )
        header = header_result.scalar_one()
    return _header_response(header, persisted["missing"])


@router.get("", response_model=list[BankTransferFileResponse])
async def list_bank_transfer_files(
    payroll_period_id: Optional[UUID] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(BankTransferFile)
        if payroll_period_id is not None:
            query = query.where(BankTransferFile.payroll_period_id == payroll_period_id)
        result = await session.execute(query.order_by(BankTransferFile.generated_at.desc()))
        headers = list(result.scalars().all())
        if start_date is not None:
            headers = [h for h in headers if h.generated_at.date() >= start_date]
        if end_date is not None:
            headers = [h for h in headers if h.generated_at.date() <= end_date]
    return [_header_response(h, []) for h in headers]


@router.get("/{bank_transfer_file_id}", response_model=BankTransferFileDetailResponse)
async def get_bank_transfer_file(
    bank_transfer_file_id: UUID,
    current_user: User = Depends(require_permission("payroll.view")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(BankTransferFile).where(BankTransferFile.id == bank_transfer_file_id))
        header = result.scalar_one_or_none()
        if header is None:
            raise HTTPException(status_code=404, detail=translate("payroll.bank_transfer_file_not_found", locale))
        lines_result = await session.execute(
            select(BankTransferFileLine).where(BankTransferFileLine.bank_transfer_file_id == header.id)
        )
        lines = lines_result.scalars().all()
        employee_ids = [l.employee_id for l in lines]
        employees_result = await session.execute(select(Employee).where(Employee.id.in_(employee_ids)))
        employee_by_id = {e.id: e for e in employees_result.scalars().all()}

    line_responses = [
        BankTransferFileLineResponse(
            employee_id=l.employee_id,
            employee_name=(
                f"{employee_by_id[l.employee_id].first_name} {employee_by_id[l.employee_id].last_name}"
                if l.employee_id in employee_by_id else None
            ),
            account_type=l.account_type, account_number=l.account_number,
            amount=float(l.amount), glosa=l.glosa,
        )
        for l in lines
    ]
    return BankTransferFileDetailResponse(
        id=header.id, payroll_period_id=header.payroll_period_id, branch_id=header.branch_id,
        generated_at=header.generated_at, row_count=header.row_count,
        total_amount=float(header.total_amount), missing_count=header.missing_count,
        missing=[], lines=line_responses,
    )


@router.get("/{bank_transfer_file_id}/export-txt")
async def export_bank_transfer_file_txt(
    bank_transfer_file_id: UUID,
    current_user: User = Depends(require_permission("payroll.view")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(BankTransferFile).where(BankTransferFile.id == bank_transfer_file_id))
        header = result.scalar_one_or_none()
        if header is None:
            raise HTTPException(status_code=404, detail=translate("payroll.bank_transfer_file_not_found", locale))
        lines_result = await session.execute(
            select(BankTransferFileLine).where(BankTransferFileLine.bank_transfer_file_id == header.id)
        )
        lines = lines_result.scalars().all()

    txt_content = render_bank_transfer_txt([
        {"account_type": l.account_type, "account_number": l.account_number, "amount": l.amount, "glosa": l.glosa}
        for l in lines
    ])
    filename = f"planilla_bancaria_{header.payroll_period_id}.txt"
    return Response(
        content=txt_content, media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
