from datetime import date, datetime
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
    overtime_extra_hours: float = 0
    overtime_pending: bool = False
    overtime_concept_missing: bool = False
    overtime_surcharge: Optional[float] = None
    holiday_unworked_pay: Optional[float] = None
    holiday_worked_surcharge: Optional[float] = None
    holiday_concept_missing: bool = False
    vacation_pay: Optional[float] = None
    vacation_pending: bool = False
    vacation_no_history: bool = False
    vacation_partial_history: bool = False


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


class OvertimeGenerateRequest(BaseModel):
    start_date: date
    end_date: date
    branch_id: Optional[UUID] = None


class OvertimeGenerateResponse(BaseModel):
    created: int
    updated: int
    skipped_unassigned: list


class OvertimeApprovalResponse(BaseModel):
    id: UUID
    employee_id: UUID
    employee_name: str
    branch_id: UUID
    branch_name: str
    shift_template_id: UUID
    shift_template_name: str
    work_date: date
    ordinary_hours: float
    extra_hours: float
    status: str
    reviewed_by: Optional[UUID] = None
    reviewed_at: Optional[datetime] = None
    notes: Optional[str] = None


class OvertimeStatusUpdate(BaseModel):
    status: str
    notes: Optional[str] = None


class NetPayrollRow(PayrollRow):
    ccss_deduction: Optional[float] = None
    renta_amount: Optional[float] = None
    renta_is_refund: bool = False
    net_pay: Optional[float] = None
    renta_frequency_unsupported: bool = False
    tax_brackets_missing: bool = False
    renta_credits_missing: bool = False
    renta_period_pairing_missing: bool = False


class VacationRequestCreate(BaseModel):
    employee_id: UUID
    start_date: date
    end_date: date


class VacationRequestResponse(BaseModel):
    id: UUID
    employee_id: UUID
    employee_name: str
    start_date: date
    end_date: date
    days_count: float
    status: str
    reviewed_by: Optional[UUID] = None
    reviewed_at: Optional[datetime] = None
    notes: Optional[str] = None


class VacationStatusUpdate(BaseModel):
    status: str
    notes: Optional[str] = None


class VacationBalanceResponse(BaseModel):
    blocked: bool
    reason: Optional[str] = None
    accrued_days: Optional[float] = None
    taken_days: Optional[float] = None
    pending_days: Optional[float] = None
    available_days: Optional[float] = None
    days_per_week_worked: Optional[int] = None
    cycle_weeks: Optional[float] = None


class AguinaldoRow(BaseModel):
    employee_id: UUID
    employee_name: str
    branch_id: UUID
    branch_name: str
    aguinaldo_base: Optional[float] = None
    aguinaldo_amount: Optional[float] = None
    periods_considered: int = 0
    partial_year: bool = False
    config_missing: bool = False
