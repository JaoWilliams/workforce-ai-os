"""
Interfaz común para adaptadores de reloj marcador (módulo 8/24).

IMPORTANTE — por qué estos métodos no están implementados:
Este proyecto sigue la regla "cero mock": no se simulan respuestas de
dispositivos que no existen. La comunicación real con un Tiandy, Hikvision
o ZKTeco requiere su SDK/protocolo propio (para ZKTeco: ZKBio Zlink /
ZKBio CVAccess, según el datasheet del SenseFace 4A) y un dispositivo
físico accesible en red para probar contra él de verdad.

Hasta que exista ese acceso, cada adaptador levanta NotImplementedError
explícito. El inventario de dispositivos (alta/baja, asignación a
sucursal) SÍ está implementado y probado — ver app/modules/devices/router.py.

Cuando haya un dispositivo real disponible, implementar el adaptador
correspondiente y probarlo end-to-end antes de darlo por completo.
"""
from abc import ABC, abstractmethod
from typing import Any


class DeviceAdapter(ABC):
    """Contrato que debe cumplir cada adaptador de marca."""

    def __init__(self, ip_address: str, **credentials: Any):
        self.ip_address = ip_address
        self.credentials = credentials

    @abstractmethod
    async def get_status(self) -> str:
        """Heartbeat real del dispositivo: 'online' | 'offline'."""
        raise NotImplementedError

    @abstractmethod
    async def sync_biometric_templates(self, templates: list) -> None:
        """Envía plantillas biométricas (server → dispositivo)."""
        raise NotImplementedError

    @abstractmethod
    async def update_firmware(self, firmware_url: str) -> None:
        """Actualización de firmware controlada desde el backend."""
        raise NotImplementedError
