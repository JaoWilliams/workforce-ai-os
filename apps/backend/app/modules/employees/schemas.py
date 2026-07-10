from datetime import date
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel


class EmployeeCreate(BaseModel):
    branch_id: UUID
    first_name: str
    last_name: str
    id_type: Literal["cedula_fisica", "cedula_juridica", "dimex", "pasaporte"]
    id_number: str
    email: Optional[str] = None
    phone: Optional[str] = None
    position: str
    hire_date: date


class EmployeeUpdate(BaseModel):
    email: Optional[str] = None
    phone: Optional[str] = None
    position: Optional[str] = None
    active: Optional[bool] = None


class EmployeeResponse(BaseModel):
    id: UUID
    branch_id: UUID
    first_name: str
    last_name: str
    id_type: str
    id_number: str
    email: Optional[str] = None
    phone: Optional[str] = None
    position: str
    hire_date: date
    active: bool


class ContractCreate(BaseModel):
    contract_type: Literal["indefinido", "plazo_fijo", "por_obra"]
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: Literal["CRC", "USD", "GTQ", "HNL", "NIO", "PAB"] = "CRC"
    pay_frequency: Literal["semanal", "quincenal", "bisemanal", "mensual"] = "mensual"


class ContractResponse(BaseModel):
    id: UUID
    employee_id: UUID
    contract_type: str
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: str
    pay_frequency: str
    pdf_path: Optional[str] = None
