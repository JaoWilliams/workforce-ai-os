from datetime import date, datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class JournalEntryLineResponse(BaseModel):
    id: UUID
    account_id: UUID
    account_code: str
    account_name: str
    branch_id: Optional[UUID] = None
    branch_name: Optional[str] = None
    debit: float
    credit: float
    description: Optional[str] = None


class JournalEntryResponse(BaseModel):
    id: UUID
    entry_date: date
    entry_type: str
    payroll_period_id: Optional[UUID] = None
    termination_id: Optional[UUID] = None
    description: str
    created_at: datetime
    lines: list[JournalEntryLineResponse]
    total_debit: float
    total_credit: float
