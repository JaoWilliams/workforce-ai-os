from datetime import date
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel


class EmployeeCreate(BaseModel):
    branch_id: UUID
    department_id: Optional[UUID] = None
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
    bank_account_type: Optional[Literal["Cuenta de Ahorro", "Cuenta Corriente"]] = None
    bank_account_number: Optional[str] = None


class EmployeeResponse(BaseModel):
    id: UUID
    branch_id: UUID
    department_id: Optional[UUID] = None
    first_name: str
    last_name: str
    id_type: str
    id_number: str
    email: Optional[str] = None
    phone: Optional[str] = None
    position: str
    hire_date: date
    active: bool
    bank_account_type: Optional[str] = None
    bank_account_number: Optional[str] = None
    onboarding_missing: list[str] = []


class ContractCreate(BaseModel):
    contract_type: Literal["indefinido", "plazo_fijo", "por_obra"]
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: Literal["CRC", "USD", "GTQ", "HNL", "NIO", "PAB"] = "CRC"
    pay_frequency: Literal["semanal", "quincenal", "bisemanal", "mensual"] = "mensual"
    language: Literal["es", "en"] = "es"


class ContractResponse(BaseModel):
    id: UUID
    employee_id: UUID
    contract_type: str
    start_date: date
    end_date: Optional[date] = None
    base_salary: float
    currency: str
    pay_frequency: str
    language: str = "es"
    pdf_path: Optional[str] = None


class DependentCreate(BaseModel):
    relationship_type: Literal["conyuge", "hijo"]
    name: str
    birth_date: Optional[date] = None


class DependentUpdate(BaseModel):
    name: Optional[str] = None
    birth_date: Optional[date] = None
    active: Optional[bool] = None


class DependentResponse(BaseModel):
    id: UUID
    employee_id: UUID
    relationship_type: str
    name: str
    birth_date: Optional[date] = None
    active: bool
