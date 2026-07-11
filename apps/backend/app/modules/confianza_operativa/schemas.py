from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class TrustFlagResponse(BaseModel):
    id: UUID
    employee_id: Optional[UUID] = None
    payroll_period_id: Optional[UUID] = None
    branch_id: Optional[UUID] = None
    rule_code: str
    severity: str
    details: dict
    resolved: bool
    detected_at: datetime


class TrustFlagResolve(BaseModel):
    resolved: bool = True
