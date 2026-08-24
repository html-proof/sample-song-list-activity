from uuid import UUID

from music_hub.auth.firebase import FirebaseIdentity
from music_hub.repositories.users import UserRepository


class UserService:
    def __init__(self, repository: UserRepository) -> None:
        self.repository = repository

    async def profile(self, user_id: UUID) -> dict:
        return await self.repository.get(user_id)

    async def register_login(self, user_id: UUID, identity: FirebaseIdentity) -> dict:
        return await self.repository.sync_login(user_id, identity)
