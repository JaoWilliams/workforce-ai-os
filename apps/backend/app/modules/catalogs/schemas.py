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


class PayrollConceptUpdate(BaseModel):
    name: Optional[str] = None
    value: Optional[float] = None
    employer_value: Optional[float] = None
    active: Optional[bool] = None


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
