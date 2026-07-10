from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select

from app.core.audit import log_audit
from app.core.i18n import get_locale, translate
from app.core.tenant import tenant_session
from app.db.models import Branch, Device, User
from app.modules.devices.schemas import DeviceCreate, DeviceResponse, DeviceUpdate
from app.modules.rbac.dependencies import require_permission

router = APIRouter(prefix="/api/devices", tags=["devices"])


def _to_response(device: Device) -> DeviceResponse:
    return DeviceResponse(
        id=device.id,
        branch_id=device.branch_id,
        brand=device.brand,
        model=device.model,
        serial_number=device.serial_number,
        ip_address=device.ip_address,
        status=device.status,
        max_faces=device.max_faces,
        max_fingerprints=device.max_fingerprints,
        max_cards=device.max_cards,
        max_events=device.max_events,
        verification_methods=device.verification_methods,
        active=device.active,
    )


@router.post("", response_model=DeviceResponse, status_code=201)
async def create_device(
    payload: DeviceCreate,
    current_user: User = Depends(require_permission("devices.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        branch = await session.execute(select(Branch).where(Branch.id == payload.branch_id))
        if branch.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=translate("devices.branch_not_found", locale),
            )
        device = Device(
            id=uuid4(),
            tenant_id=current_user.tenant_id,
            branch_id=payload.branch_id,
            brand=payload.brand,
            model=payload.model,
            serial_number=payload.serial_number,
            ip_address=payload.ip_address,
            status="not_provisioned",
            max_faces=payload.max_faces,
            max_fingerprints=payload.max_fingerprints,
            max_cards=payload.max_cards,
            max_events=payload.max_events,
            verification_methods=payload.verification_methods,
        )
        session.add(device)
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="device.created",
            resource_type="device",
            resource_id=device.id,
            extra={
                "brand": payload.brand,
                "model": payload.model,
                "serial_number": payload.serial_number,
                "branch_id": str(payload.branch_id),
            },
        )
        await session.commit()
        await session.refresh(device)
    return _to_response(device)


@router.get("", response_model=list[DeviceResponse])
async def list_devices(
    current_user: User = Depends(require_permission("devices.view")),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Device))
        devices = result.scalars().all()
    return [_to_response(d) for d in devices]


@router.patch("/{device_id}", response_model=DeviceResponse)
async def update_device(
    device_id: UUID,
    payload: DeviceUpdate,
    current_user: User = Depends(require_permission("devices.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Device).where(Device.id == device_id))
        device = result.scalar_one_or_none()
        if device is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=translate("devices.not_found", locale),
            )

        changes = {}
        if payload.model is not None:
            device.model = payload.model
            changes["model"] = payload.model
        if payload.serial_number is not None:
            device.serial_number = payload.serial_number
            changes["serial_number"] = payload.serial_number
        if payload.ip_address is not None:
            device.ip_address = payload.ip_address
            changes["ip_address"] = payload.ip_address
        if payload.status is not None:
            device.status = payload.status
            changes["status"] = payload.status
        if payload.max_faces is not None:
            device.max_faces = payload.max_faces
            changes["max_faces"] = payload.max_faces
        if payload.max_fingerprints is not None:
            device.max_fingerprints = payload.max_fingerprints
            changes["max_fingerprints"] = payload.max_fingerprints
        if payload.max_cards is not None:
            device.max_cards = payload.max_cards
            changes["max_cards"] = payload.max_cards
        if payload.max_events is not None:
            device.max_events = payload.max_events
            changes["max_events"] = payload.max_events
        if payload.verification_methods is not None:
            device.verification_methods = payload.verification_methods
            changes["verification_methods"] = payload.verification_methods
        if payload.active is not None:
            device.active = payload.active
            changes["active"] = payload.active

        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="device.updated",
            resource_type="device",
            resource_id=device.id,
            extra=changes,
        )
        await session.commit()
        await session.refresh(device)
    return _to_response(device)


@router.delete("/{device_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deactivate_device(
    device_id: UUID,
    current_user: User = Depends(require_permission("devices.manage")),
    locale: str = Depends(get_locale),
):
    async with tenant_session(current_user.tenant_id) as session:
        result = await session.execute(select(Device).where(Device.id == device_id))
        device = result.scalar_one_or_none()
        if device is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=translate("devices.not_found", locale),
            )

        device.active = False
        await log_audit(
            session,
            tenant_id=current_user.tenant_id,
            actor_user_id=current_user.id,
            action="device.deactivated",
            resource_type="device",
            resource_id=device.id,
            extra={},
        )
        await session.commit()
    return None
