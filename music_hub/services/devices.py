from uuid import UUID

from music_hub.repositories.devices import DeviceRepository
from music_hub.schemas.devices import DeviceRegistration


class DeviceService:
    def __init__(self, repository: DeviceRepository) -> None:
        self.repository = repository

    async def register(self, user_id: UUID, payload: DeviceRegistration) -> dict:
        return await self.repository.register(user_id, payload)

    async def remove(self, user_id: UUID, device_id: str) -> None:
        await self.repository.remove(user_id, device_id)
