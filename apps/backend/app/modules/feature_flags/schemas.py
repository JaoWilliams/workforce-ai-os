from typing import Optional
from uuid import UUID

from pydantic import BaseModel


class FeatureFlagCatalogItem(BaseModel):
    code: str
    name: str
    description: str
    category: str


class TenantFeatureFlagStatus(BaseModel):
    code: str
    name: str
    description: str
    category: str
    enabled: bool
    source: str  # "branch_override" | "tenant_override" | "default"


class FeatureFlagToggle(BaseModel):
    enabled: bool
    branch_id: Optional[UUID] = None
