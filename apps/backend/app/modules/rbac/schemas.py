from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class RoleCreate(BaseModel):
    name: str
    permissions: list[str] = []


class RoleUpdate(BaseModel):
    name: Optional[str] = None
    permissions: Optional[list[str]] = None
    active: Optional[bool] = None


class RoleResponse(BaseModel):
    id: UUID
    name: str
    permissions: list[str]
    active: bool
    user_count: int = 0
