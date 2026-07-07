from uuid import UUID

from pydantic import BaseModel


class BranchCreate(BaseModel):
    code: str
    name: str


class BranchResponse(BaseModel):
    id: UUID
    code: str
    name: str
