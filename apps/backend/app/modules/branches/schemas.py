from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class BranchCreate(BaseModel):
    code: str
    name: str


class BranchUpdate(BaseModel):
    code: Optional[str] = None
    name: Optional[str] = None
    accounting_account: Optional[str] = None
    supervisor_user_id: Optional[UUID] = None
    active: Optional[bool] = None


class BranchResponse(BaseModel):
    id: UUID
    code: str
    name: str
    accounting_account: Optional[str] = None
    supervisor_user_id: Optional[UUID] = None
    active: bool
    employee_count: int = 0
