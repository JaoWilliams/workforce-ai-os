from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class PositionCreate(BaseModel):
    name: str


class PositionUpdate(BaseModel):
    name: Optional[str] = None
    active: Optional[bool] = None


class PositionResponse(BaseModel):
    id: UUID
    name: str
    active: bool
    employee_count: int = 0
