from datetime import date
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel


class PayrollConceptCreate(BaseModel):
    code: str
    name: str
    calculation_method: Literal["monto_fijo", "porcentaje", "cantidad"]
    nature: Literal["ingreso", "deduccion"]
    origin: Literal["patronal", "empleado"]
    value: float
    employer_value: Optional[float] = None
    accounting_account_id: Optional[UUID] = None


class PayrollConceptUpdate(BaseModel):
    name: Optional[str] = None
    value: Optional[float] = None
    employer_value: Optional[float] = None
    active: Optional[bool] = None
    accounting_account_id: Optional[UUID] = None


class PayrollConceptResponse(BaseModel):
    id: UUID
    code: str
    name: str
    calculation_method: str
    nature: str
    origin: str
    value: float
    employer_value: Optional[float] = None
    active: bool
    accounting_account_id: Optional[UUID] = None


class PayrollHoursConfigUpsert(BaseModel):
    standard_hours: float


class PayrollHoursConfigResponse(BaseModel):
    pay_frequency: str
    standard_hours: Optional[float] = None


class HolidayCreate(BaseModel):
    date: date
    name: str
    payment_type: Literal["obligatorio", "no_obligatorio"]


class HolidayUpdate(BaseModel):
    name: Optional[str] = None
    payment_type: Optional[Literal["obligatorio", "no_obligatorio"]] = None
    active: Optional[bool] = None


class HolidayResponse(BaseModel):
    id: UUID
    date: date
    name: str
    payment_type: str
    active: bool


class TaxBracketCreate(BaseModel):
    year: int
    bracket_order: int
    lower_bound: float
    upper_bound: Optional[float] = None
    rate: float


class TaxBracketResponse(BaseModel):
    id: UUID
    year: int
    bracket_order: int
    lower_bound: float
    upper_bound: Optional[float] = None
    rate: float


class RentaCreditsUpsert(BaseModel):
    spouse_credit: float
    child_credit: float


class RentaCreditsResponse(BaseModel):
    year: int
    spouse_credit: float
    child_credit: float


class VacationConfigUpsert(BaseModel):
    cycle_weeks: float


class VacationConfigResponse(BaseModel):
    cycle_weeks: float


class ShiftAlertConfigUpsert(BaseModel):
    no_show_grace_minutes: int = 15
    not_closed_grace_minutes: int = 15


class ShiftAlertConfigResponse(BaseModel):
    no_show_grace_minutes: int
    not_closed_grace_minutes: int


class AguinaldoConfigUpsert(BaseModel):
    period_start_month: int = 12
    period_start_day: int = 1
    period_end_month: int = 11
    period_end_day: int = 30
    divisor: float = 12


class AguinaldoConfigResponse(BaseModel):
    period_start_month: int
    period_start_day: int
    period_end_month: int
    period_end_day: int
    divisor: float

class CesantiaConfigUpsert(BaseModel):
    max_years_cap: int = 8
    fraction_round_months: int = 6
    days_3to6_months: float = 7
    days_6to12_months: float = 14
    daily_divisor: float = 30
    months_for_average: int = 6
class CesantiaConfigResponse(BaseModel):
    max_years_cap: int
    fraction_round_months: int
    days_3to6_months: float
    days_6to12_months: float
    daily_divisor: float
    months_for_average: int
class CesantiaScaleRowUpsert(BaseModel):
    year_number: int
    days: float
class CesantiaScaleRowResponse(BaseModel):
    year_number: int
    days: float
class CesantiaScaleBulkUpsert(BaseModel):
    rows: list[CesantiaScaleRowUpsert]


class ChartOfAccountCreate(BaseModel):
    code: str
    name: str
    account_type: Literal["activo", "pasivo", "patrimonio", "ingreso", "gasto"]


class ChartOfAccountUpdate(BaseModel):
    name: Optional[str] = None
    account_type: Optional[Literal["activo", "pasivo", "patrimonio", "ingreso", "gasto"]] = None
    active: Optional[bool] = None


class ChartOfAccountResponse(BaseModel):
    id: UUID
    code: str
    name: str
    account_type: str
    active: bool
class BankFileConfigUpsert(BaseModel):
    glosa: str
class BankFileConfigResponse(BaseModel):
    glosa: str
    active: bool
class PayrollAnomalyConfigUpsert(BaseModel):
    net_deviation_pct_threshold: float
    overtime_hours_multiplier_threshold: float
    bank_account_change_window_days: int
    branch_net_deviation_pct_threshold: float
class PayrollAnomalyConfigResponse(BaseModel):
    net_deviation_pct_threshold: float
    overtime_hours_multiplier_threshold: float
    bank_account_change_window_days: int
    branch_net_deviation_pct_threshold: float
    active: bool
