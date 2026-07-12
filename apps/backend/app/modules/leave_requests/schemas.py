from datetime import date, datetime
from typing import Literal, Optional
from uuid import UUID

from pydantic import BaseModel

LeaveType = Literal["medico", "personal", "duelo", "otro"]


class LeaveRequestCreate(BaseModel):
    employee_id: UUID
    leave_type: LeaveType
    start_date: date
    end_date: date
    reason: Optional[str] = None


class LeaveRequestReview(BaseModel):
    status: Literal["approved", "rejected"]
    review_notes: Optional[str] = None


class LeaveRequestResponse(BaseModel):
    id: UUID
    employee_id: UUID
    employee_name: str
    leave_type: str
    start_date: date
    end_date: date
    reason: Optional[str] = None
    status: str
    reviewed_by_user_id: Optional[UUID] = None
    reviewed_at: Optional[datetime] = None
    review_notes: Optional[str] = None
    created_at: datetime
