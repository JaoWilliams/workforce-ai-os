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


class ShiftTemplateResponse(BaseModel):
    id: UUID
    branch_id: UUID
    name: str
    start_time: time
    end_time: time
    days_of_week: List[int]
    min_coverage: int
    created_at: datetime


class ShiftAssignmentCreate(BaseModel):
    employee_id: UUID
    shift_template_id: UUID
    start_date: date
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
