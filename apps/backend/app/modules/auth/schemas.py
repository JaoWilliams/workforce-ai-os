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
