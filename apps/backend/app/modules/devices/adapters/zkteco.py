"""
Adaptador ZKTeco — PENDIENTE de implementación real.

Modelo de referencia disponible: SenseFace 4A (specs cargadas en el
inventario, ver Device.max_faces/max_fingerprints/max_cards/max_events).
Software del fabricante: ZKBio Zlink / BioTalk Pro / ZKBio CVAccess.

No implementar con datos simulados. Implementar cuando haya un
dispositivo físico accesible en red (IP + credenciales de admin) para
probar de verdad — ver decisión registrada en WORKFORCE_AI_OS_PROYECTO.md
sección 5.3 (Mód. 8).
"""
from app.modules.devices.adapters.base import DeviceAdapter


class ZKTecoAdapter(DeviceAdapter):
    async def get_status(self) -> str:
        raise NotImplementedError(
            "Adaptador ZKTeco pendiente: requiere dispositivo real accesible en red "
            "(SDK ZKBio) para implementar y probar. No se mockea."
        )

    async def sync_biometric_templates(self, templates: list) -> None:
        raise NotImplementedError(
            "Adaptador ZKTeco pendiente: requiere dispositivo real accesible en red "
            "(SDK ZKBio) para implementar y probar. No se mockea."
        )

    async def update_firmware(self, firmware_url: str) -> None:
        raise NotImplementedError(
            "Adaptador ZKTeco pendiente: requiere dispositivo real accesible en red "
            "(SDK ZKBio) para implementar y probar. No se mockea."
        )
