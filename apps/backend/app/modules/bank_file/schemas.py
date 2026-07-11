from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class BankTransferMissingEntry(BaseModel):
    employee_id: UUID
    employee_name: Optional[str] = None
    reason: str


class BankTransferFileLineResponse(BaseModel):
    employee_id: UUID
    employee_name: Optional[str] = None
    account_type: str
    account_number: str
    amount: float
    glosa: str


class BankTransferFileResponse(BaseModel):
    id: UUID
    payroll_period_id: UUID
    branch_id: Optional[UUID] = None
    generated_at: datetime
    row_count: int
    total_amount: float
    missing_count: int
    missing: list[BankTransferMissingEntry] = []


class BankTransferFileDetailResponse(BankTransferFileResponse):
    lines: list[BankTransferFileLineResponse] = []
