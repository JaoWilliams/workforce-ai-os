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


class PayrollConceptUpdate(BaseModel):
    name: Optional[str] = None
    value: Optional[float] = None
    active: Optional[bool] = None


class PayrollConceptResponse(BaseModel):
    id: UUID
    code: str
    name: str
    calculation_method: str
    nature: str
    origin: str
    value: float
    active: bool
