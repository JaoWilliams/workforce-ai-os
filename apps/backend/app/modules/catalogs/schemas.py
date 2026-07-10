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
