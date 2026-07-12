from datetime import date, datetime, time
from typing import List, Optional
from uuid import UUID

from pydantic import BaseModel


class ShiftTemplateCreate(BaseModel):
    branch_id: UUID
    name: str
    start_time: time
    end_time: time
    days_of_week: List[int]
    min_coverage: int = 1


class ShiftTemplateUpdate(BaseModel):
    name: Optional[str] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    days_of_week: Optional[List[int]] = None
    min_coverage: Optional[int] = None
    active: Optional[bool] = None


class ShiftTemplateResponse(BaseModel):
    id: UUID
    branch_id: UUID
    name: str
    start_time: time
    end_time: time
    days_of_week: List[int]
    min_coverage: int
    active: bool
    created_at: datetime


class ShiftAssignmentCreate(BaseModel):
    employee_id: UUID
    shift_template_id: UUID
    start_date: date
    end_date: Optional[date] = None


class ShiftAssignmentUpdate(BaseModel):
    employee_id: Optional[UUID] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None


class ShiftAssignmentResponse(BaseModel):
    id: UUID
    employee_id: UUID
    shift_template_id: UUID
    start_date: date
    end_date: Optional[date]
    created_at: datetime


class ShiftCoverageResponse(BaseModel):
    shift_template_id: UUID
    date: date
    min_coverage: int
    assigned_count: int
    covered: bool


class ShiftAlertResponse(BaseModel):
    type: str
    employee_id: UUID
    employee_name: str
    branch_id: UUID
    shift_template_id: UUID
    shift_name: str
    scheduled_at: datetime
    minutes_late: int
