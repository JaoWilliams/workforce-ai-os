from typing import Literal, Optional
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class BiometricEnrollmentCreate(BaseModel):
    device_id: UUID
    biometric_type: Literal["facial", "fingerprint", "card"]


class BiometricEnrollmentResponse(BaseModel):
    id: UUID
    employee_id: UUID
    device_id: UUID
    consent_record_id: UUID
    biometric_type: str
    template_reference: str
    is_simulated: bool
    active: bool
    enrolled_at: datetime
