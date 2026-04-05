import asyncio
import httpx
import os

SINRICPRO_API_KEY = os.getenv("SINRICPRO_API_KEY", "")
SINRICPRO_DEVICE_ID = os.getenv("SINRICPRO_DEVICE_ID", "")
SINRICPRO_URL = "https://api.sinric.pro/api/v1/devices/action"


async def fire_reality_check_cue():
    """Fire the SinricPro trigger: turn device on for 2 seconds then off."""
    if not SINRICPRO_API_KEY or not SINRICPRO_DEVICE_ID:
        raise ValueError("SinricPro API key and device ID must be configured")

    headers = {"x-sinric-api-key": SINRICPRO_API_KEY}

    async with httpx.AsyncClient(timeout=10.0) as client:
        await client.post(
            SINRICPRO_URL,
            headers=headers,
            json={"deviceId": SINRICPRO_DEVICE_ID, "action": "setPowerState", "value": "On"},
        )
        await asyncio.sleep(2)
        await client.post(
            SINRICPRO_URL,
            headers=headers,
            json={"deviceId": SINRICPRO_DEVICE_ID, "action": "setPowerState", "value": "Off"},
        )
