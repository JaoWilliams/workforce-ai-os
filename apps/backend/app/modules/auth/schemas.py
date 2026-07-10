from typing import Optional
from uuid import UUID

from pydantic import BaseModel, EmailStr


class LoginRequest(BaseModel):
    tenant_slug: str
    email: EmailStr
    password: str


class RegisterRequest(BaseModel):
    tenant_slug: str
    tenant_name: str
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserResponse(BaseModel):
    id: UUID
    tenant_id: UUID
    email: EmailStr
    active: bool = True
    role_id: Optional[UUID] = None
    role_name: Optional[str] = None


class MeResponse(UserResponse):
    permissions: list[str] = []


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    role_id: UUID


class UserUpdate(BaseModel):
    email: Optional[EmailStr] = None
    password: Optional[str] = None
    role_id: Optional[UUID] = None
    active: Optional[bool] = None
