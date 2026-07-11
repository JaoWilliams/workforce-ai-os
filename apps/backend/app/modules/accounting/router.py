import csv
import io
from datetime import date
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select

from app.core.accounting import (
    generate_payroll_journal_entry,
    generate_aguinaldo_provision_entry,
    generate_aguinaldo_payment_entry,
    generate_vacation_provision_entry,
    generate_cesantia_entry,
    generate_ccss_patronal_entry,
    persist_journal_entry,
)
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, ChartOfAccount, JournalEntry, JournalEntryLine, Termination, User
from app.modules.accounting.schemas import JournalEntryLineResponse, JournalEntryResponse
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/accounting", tags=["accounting"])

ERROR_STATUS = {
    "period_not_found": 404,
    "no_rows": 400,
    "blocked_rows": 400,
    "missing_accounts": 400,
    "zero_amount": 400,
    "unbalanced": 400,
    "not_eligible": 400,
    "amount_not_computable": 400,
}


def _raise_for_error(error_result: dict):
    error = error_result.get("error")
    status_code = ERROR_STATUS.get(error, 400)
    detail = {"error": error}
    detail.update({k: v for k, v in error_result.items() if k != "error"})
    raise HTTPException(status_code=status_code, detail=detail)


async def _entry_response(session, entry: JournalEntry) -> JournalEntryResponse:
    result = await session.execute(select(JournalEntryLine).where(JournalEntryLine.journal_entry_id == entry.id))
    lines = result.scalars().all()
    account_ids = {l.account_id for l in lines}
    accounts = {}
    if account_ids:
        accounts_result = await session.execute(select(ChartOfAccount).where(ChartOfAccount.id.in_(account_ids)))
        accounts = {a.id: a for a in accounts_result.scalars().all()}
    branch_ids = {l.branch_id for l in lines if l.branch_id}
    branches = {}
    if branch_ids:
        branches_result = await session.execute(select(Branch).where(Branch.id.in_(branch_ids)))
        branches = {b.id: b for b in branches_result.scalars().all()}
    line_responses = []
    total_debit = 0.0
    total_credit = 0.0
    for l in lines:
        acc = accounts.get(l.account_id)
        branch = branches.get(l.branch_id) if l.branch_id else None
        line_responses.append(JournalEntryLineResponse(
            id=l.id, account_id=l.account_id,
            account_code=acc.code if acc else "?", account_name=acc.name if acc else "?",
            branch_id=l.branch_id, branch_name=branch.name if branch else None,
            debit=float(l.debit), credit=float(l.credit), description=l.description,
        ))
        total_debit += float(l.debit)
        total_credit += float(l.credit)
    return JournalEntryResponse(
        id=entry.id, entry_date=entry.entry_date, entry_type=entry.entry_type,
        payroll_period_id=entry.payroll_period_id, termination_id=entry.termination_id,
        description=entry.description, created_at=entry.created_at,
        lines=line_responses, total_debit=round(total_debit, 2), total_credit=round(total_credit, 2),
    )


@router.post("/journal-entries/payroll", response_model=JournalEntryResponse, status_code=201)
async def create_payroll_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_payroll_journal_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/aguinaldo-provision", response_model=JournalEntryResponse, status_code=201)
async def create_aguinaldo_provision_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_aguinaldo_provision_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/aguinaldo-payment", response_model=JournalEntryResponse, status_code=201)
async def create_aguinaldo_payment_entry(
    year: int,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_aguinaldo_payment_entry(session, current_user.tenant_id, year, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/vacaciones-provision", response_model=JournalEntryResponse, status_code=201)
async def create_vacation_provision_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_vacation_provision_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/cesantia/{termination_id}", response_model=JournalEntryResponse, status_code=201)
async def create_cesantia_entry(
    termination_id: UUID,
    current_user: User = Depends(require_permission("payroll.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        termination = await session.get(Termination, termination_id)
        if termination is None:
            raise HTTPException(status_code=404, detail=translate("payroll.termination_not_found", locale))
        result = await generate_cesantia_entry(session, current_user.tenant_id, termination)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.post("/journal-entries/ccss-patronal", response_model=JournalEntryResponse, status_code=201)
async def create_ccss_patronal_entry(
    payroll_period_id: UUID,
    branch_id: Optional[UUID] = None,
    current_user: User = Depends(require_permission("payroll.manage")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await generate_ccss_patronal_entry(session, current_user.tenant_id, payroll_period_id, branch_id)
        entry, error = await persist_journal_entry(session, current_user.tenant_id, result, current_user.id)
        if error:
            _raise_for_error(error)
        await session.commit()
        await session.refresh(entry)
        response = await _entry_response(session, entry)
    return response


@router.get("/journal-entries", response_model=list[JournalEntryResponse])
async def list_journal_entries(
    entry_type: Optional[str] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(JournalEntry)
        if entry_type is not None:
            query = query.where(JournalEntry.entry_type == entry_type)
        if start_date is not None:
            query = query.where(JournalEntry.entry_date >= start_date)
        if end_date is not None:
            query = query.where(JournalEntry.entry_date <= end_date)
        result = await session.execute(query.order_by(JournalEntry.entry_date.desc()))
        entries = result.scalars().all()
        responses = [await _entry_response(session, e) for e in entries]
    return responses


@router.get("/journal-entries/export-csv")
async def export_journal_entries_csv(
    entry_type: Optional[str] = None,
    start_date: Optional[date] = None,
    end_date: Optional[date] = None,
    current_user: User = Depends(require_permission("payroll.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        query = select(JournalEntry)
        if entry_type is not None:
            query = query.where(JournalEntry.entry_type == entry_type)
        if start_date is not None:
            query = query.where(JournalEntry.entry_date >= start_date)
        if end_date is not None:
            query = query.where(JournalEntry.entry_date <= end_date)
        result = await session.execute(query.order_by(JournalEntry.entry_date.asc()))
        entries = result.scalars().all()
        responses = [await _entry_response(session, e) for e in entries]

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["fecha", "tipo_asiento", "descripcion", "cuenta_codigo", "cuenta_nombre", "sucursal", "debe", "haber", "detalle_linea"])
    for entry in responses:
        for line in entry.lines:
            writer.writerow([
                entry.entry_date.isoformat(), entry.entry_type, entry.description,
                line.account_code, line.account_name, line.branch_name or "",
                f"{line.debit:.2f}", f"{line.credit:.2f}", line.description or "",
            ])
    csv_bytes = output.getvalue().encode("utf-8-sig")
    return Response(
        content=csv_bytes, media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=asientos_contables.csv"},
    )
