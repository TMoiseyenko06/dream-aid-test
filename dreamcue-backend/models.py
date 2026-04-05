from pydantic import BaseModel
from typing import Optional


class SensorReading(BaseModel):
    timestamp: str
    source: str  # "watch" or "phone"
    heart_rate: Optional[float] = None
    hrv: Optional[float] = None
    movement_magnitude: Optional[float] = None
    accel_x: Optional[float] = None
    accel_y: Optional[float] = None
    accel_z: Optional[float] = None
    watch_battery: Optional[float] = None
    session_id: Optional[str] = None


class SessionStartResponse(BaseModel):
    session_id: str
    start_time: str


class StageResponse(BaseModel):
    stage: str
    confidence: float
    rem_duration_minutes: float
    source: str


class HealthResponse(BaseModel):
    status: str
    uptime_seconds: float


class SensorDataResponse(BaseModel):
    stage: str
    cue_triggered: bool
    session_id: str
    confidence: float
