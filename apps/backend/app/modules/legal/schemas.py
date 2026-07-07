from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class ConsentGrant(BaseModel):
    consent_type: str = "biometric"


class ConsentResponse(BaseModel):
    id: UUID
    user_id: UUID
    consent_type: str
    granted: bool
    granted_at: datetime
    revoked_at: Optional[datetime] = None


class AuditLogResponse(BaseModel):
    id: UUID
    actor_user_id: Optional[UUID]
    action: str
    resource_type: str
    resource_id: Optional[UUID]
    extra: dict
    created_at: datetime
