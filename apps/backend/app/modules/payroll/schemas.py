from datetime import date
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


class PayrollPeriodCreate(BaseModel):
    pay_frequency: str
    period_start: date
    period_end: date
    pay_date: Optional[date] = None
    notes: Optional[str] = None


class PayrollPeriodUpdate(BaseModel):
    period_start: Optional[date] = None
    period_end: Optional[date] = None
    pay_date: Optional[date] = None
    notes: Optional[str] = None


class PayrollPeriodStatusUpdate(BaseModel):
    status: str


class PayrollPeriodResponse(BaseModel):
    id: UUID
    pay_frequency: str
    period_start: date
    period_end: date
    pay_date: Optional[date] = None
    status: str
    notes: Optional[str] = None


class PayrollPeriodGenerateRequest(BaseModel):
    pay_frequency: str
    first_period_start: date
    days_per_period: int
    count: int
