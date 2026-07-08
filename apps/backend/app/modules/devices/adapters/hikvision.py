"""
Adaptador Hikvision — PENDIENTE de implementación real (sin hardware/SDK
accesible todavía). No implementar con datos simulados — ver base.py.
"""
from app.modules.devices.adapters.base import DeviceAdapter


class HikvisionAdapter(DeviceAdapter):
    async def get_status(self) -> str:
        raise NotImplementedError("Adaptador Hikvision pendiente: requiere dispositivo/SDK real. No se mockea.")

    async def sync_biometric_templates(self, templates: list) -> None:
        raise NotImplementedError("Adaptador Hikvision pendiente: requiere dispositivo/SDK real. No se mockea.")

    async def update_firmware(self, firmware_url: str) -> None:
        raise NotImplementedError("Adaptador Hikvision pendiente: requiere dispositivo/SDK real. No se mockea.")
