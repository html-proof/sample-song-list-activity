from typing import Literal

from pydantic import BaseModel, Field


class DeviceRegistration(BaseModel):
    device_id: str = Field(min_length=1, max_length=300)
    platform: Literal["android", "ios", "web", "windows", "macos", "linux"]
    device_name: str | None = Field(default=None, max_length=300)
    fcm_token: str | None = Field(default=None, max_length=4000)
    app_version: str | None = Field(default=None, max_length=50)
    notifications_enabled: bool = True
