from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class DepartmentCreate(BaseModel):
    name: str


class DepartmentUpdate(BaseModel):
    name: Optional[str] = None
    active: Optional[bool] = None


class DepartmentResponse(BaseModel):
    id: UUID
    name: str
    active: bool
    employee_count: int = 0
