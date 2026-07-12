from datetime import datetime
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel

ExceptionType = Literal[
    "missing_checkin",
    "missing_checkout",
    "late_arrival",
    "early_departure",
    "absence",
    "manual_correction",
    "other",
]


class TimeExceptionCreate(BaseModel):
    employee_id: UUID
    exception_type: ExceptionType
    justification: str
    evidence_reference: Optional[str] = None
    attendance_record_id: Optional[UUID] = None
    trust_flag_id: Optional[UUID] = None


class TimeExceptionReview(BaseModel):
    status: Literal["approved", "rejected"]
    review_notes: Optional[str] = None


class TimeExceptionResponse(BaseModel):
    id: UUID
    employee_id: UUID
    attendance_record_id: Optional[UUID]
    trust_flag_id: Optional[UUID]
    exception_type: str
    justification: str
    evidence_reference: Optional[str]
    evidence_filename: Optional[str] = None
    status: str
    reviewed_by_user_id: Optional[UUID]
    reviewed_at: Optional[datetime]
    review_notes: Optional[str]
    created_at: datetime


class PendingExceptionsCheck(BaseModel):
    employee_id: UUID
    has_pending_exceptions: bool
