"""
Adaptador Tiandy — PENDIENTE de implementación real (sin hardware/SDK
accesible todavía). No implementar con datos simulados — ver base.py.

Nota de seguridad (del documento maestro, sección 6): los dispositivos
Tiandy tienen vulnerabilidades documentadas de recuperación remota de
contraseña de administrador vía su mecanismo P2P/nube de fábrica. Cuando
se implemente este adaptador, el dispositivo debe seguir sin exponerse
nunca directo a internet — toda gestión pasa por este backend.
"""
from app.modules.devices.adapters.base import DeviceAdapter


class TiandyAdapter(DeviceAdapter):
    async def get_status(self) -> str:
        raise NotImplementedError("Adaptador Tiandy pendiente: requiere dispositivo/SDK real. No se mockea.")

    async def sync_biometric_templates(self, templates: list) -> None:
        raise NotImplementedError("Adaptador Tiandy pendiente: requiere dispositivo/SDK real. No se mockea.")

    async def update_firmware(self, firmware_url: str) -> None:
        raise NotImplementedError("Adaptador Tiandy pendiente: requiere dispositivo/SDK real. No se mockea.")
