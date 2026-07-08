from datetime import datetime
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel


class AttendanceRecordCreate(BaseModel):
    employee_id: UUID
    device_id: UUID
    type: Literal["entrada", "salida"]
    verification_method: Literal["facial", "fingerprint", "card", "manual"]
    biometric_enrollment_id: Optional[UUID] = None
    recorded_at: datetime


class AttendanceRecordResponse(BaseModel):
    id: UUID
    employee_id: UUID
    device_id: UUID
    type: str
    verification_method: str
    biometric_enrollment_id: Optional[UUID] = None
    recorded_at: datetime
    is_simulated: bool
