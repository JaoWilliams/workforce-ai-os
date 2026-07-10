from typing import List, Literal, Optional
from uuid import UUID

from pydantic import BaseModel


class DeviceCreate(BaseModel):
    branch_id: UUID
    brand: Literal["tiandy", "hikvision", "zkteco"]
    model: str
    serial_number: str
    ip_address: Optional[str] = None
    max_faces: Optional[int] = None
    max_fingerprints: Optional[int] = None
    max_cards: Optional[int] = None
    max_events: Optional[int] = None
    verification_methods: Optional[List[str]] = None


class DeviceUpdate(BaseModel):
    model: Optional[str] = None
    serial_number: Optional[str] = None
    ip_address: Optional[str] = None
    status: Optional[Literal["not_provisioned", "online", "offline"]] = None
    max_faces: Optional[int] = None
    max_fingerprints: Optional[int] = None
    max_cards: Optional[int] = None
    max_events: Optional[int] = None
    verification_methods: Optional[List[str]] = None
    active: Optional[bool] = None


class DeviceResponse(BaseModel):
    id: UUID
    branch_id: UUID
    brand: str
    model: str
    serial_number: str
    ip_address: Optional[str] = None
    status: str
    max_faces: Optional[int] = None
    max_fingerprints: Optional[int] = None
    max_cards: Optional[int] = None
    max_events: Optional[int] = None
    verification_methods: Optional[List[str]] = None
    active: bool
