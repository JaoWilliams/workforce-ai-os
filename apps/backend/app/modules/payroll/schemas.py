from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class PayrollRow(BaseModel):
    employee_id: UUID
    employee_name: str
    branch_id: UUID
    branch_name: str
    branch_accounting_account: Optional[str] = None
    days_worked: int
    total_hours: float
    total_sessions: int
    has_contract: bool
    currency: Optional[str] = None
    base_salary: Optional[float] = None
    pay_frequency: Optional[str] = None
    hourly_rate: Optional[float] = None
    gross_pay: Optional[float] = None
    hours_config_missing: bool = False
