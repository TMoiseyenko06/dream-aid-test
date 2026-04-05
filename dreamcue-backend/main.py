import asyncio
import os
import time
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse

import database
from classifier import classify_stage, update_session_time
from models import (
    HealthResponse,
    SensorDataResponse,
    SensorReading,
    SessionStartResponse,
)
from session import session_manager
from sinricpro import fire_reality_check_cue

load_dotenv()

_START_TIME = time.monotonic()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: initialise DB. Shutdown: nothing needed."""
    await database.init_db()
    yield


app = FastAPI(title="DreamCue API", version="1.0.0", lifespan=lifespan)

# --------------------------------------------------------------------------- #
# Helper: resolve runtime config                                               #
# --------------------------------------------------------------------------- #

def _cue_enabled() -> bool:
    return os.getenv("CUE_ENABLED", "true").lower() in ("true", "1", "yes")


def _min_rem_minutes() -> float:
    return float(os.getenv("MIN_REM_DURATION_MINUTES", "5"))


def _cue_interval_seconds() -> float:
    return float(os.getenv("CUE_INTERVAL_SECONDS", "120"))


# --------------------------------------------------------------------------- #
# Endpoints                                                                    #
# --------------------------------------------------------------------------- #

@app.get("/api/health", response_model=HealthResponse)
async def health():
    return HealthResponse(
        status="ok",
        uptime_seconds=round(time.monotonic() - _START_TIME, 2),
    )


@app.post("/api/sensor-data", response_model=SensorDataResponse)
async def receive_sensor_data(reading: SensorReading):
    """Accept a sensor reading, classify sleep stage, optionally fire cue."""

    # 1. Fetch recent readings to provide context for the classifier
    recent = await database.get_recent_readings(limit=200)

    # Determine session context
    current_session = session_manager.get_current_session()
    session_id = reading.session_id or (current_session.session_id if current_session else "no-session")
    session_start_iso = current_session.start_time.isoformat() if current_session else None

    # 2. Classify
    stage, confidence = classify_stage(recent, session_start_iso=session_start_iso)

    # 3. Update session manager with the new stage (applies smoothing)
    session_manager.update_stage(stage, confidence)

    # 4. Persist the reading with detected stage
    reading_dict = reading.model_dump()
    reading_dict["detected_stage"] = stage
    reading_dict["session_id"] = session_id
    reading_dict["cue_fired"] = False

    # 5. Check whether to fire a cue
    cue_triggered = False
    if _cue_enabled() and session_manager.should_fire_cue(
        _min_rem_minutes(), _cue_interval_seconds()
    ):
        cue_triggered = True
        reading_dict["cue_fired"] = True
        session_manager.record_cue_fired()

        # Fire asynchronously — do not block the response
        asyncio.create_task(fire_reality_check_cue())

    await database.store_reading(reading_dict)

    return SensorDataResponse(
        stage=stage,
        cue_triggered=cue_triggered,
        session_id=session_id,
        confidence=round(confidence, 3),
    )


@app.get("/api/current-stage")
async def current_stage():
    """Return the latest classified sleep stage."""
    current_session = session_manager.get_current_session()

    # Also peek at the last DB reading for comparison
    recent = await database.get_recent_readings(limit=1)
    last_reading = recent[0] if recent else {}

    stage = current_session.current_stage if current_session else last_reading.get("detected_stage", "UNKNOWN")
    session_id = current_session.session_id if current_session else last_reading.get("session_id", "")
    session_start_iso = current_session.start_time.isoformat() if current_session else None

    rem_minutes = 0.0
    if current_session:
        rem_minutes = current_session.get_current_rem_duration_minutes()

    elapsed = update_session_time(session_start_iso) if session_start_iso else 0.0

    return {
        "stage": stage,
        "session_id": session_id,
        "rem_duration_minutes": round(rem_minutes, 2),
        "elapsed_minutes": round(elapsed, 1),
        "source": last_reading.get("source", "unknown"),
        "heart_rate": last_reading.get("heart_rate"),
        "hrv": last_reading.get("hrv"),
        "watch_battery": last_reading.get("watch_battery"),
    }


@app.get("/api/history")
async def history(limit: int = Query(default=200, ge=1, le=1000)):
    """Return recent sensor readings from the database."""
    readings = await database.get_recent_readings(limit=limit)
    return {"readings": readings, "count": len(readings)}


@app.get("/api/stats")
async def stats():
    """Return tonight's session summary."""
    current_session = session_manager.get_current_session()
    if current_session is None:
        return {"message": "No active session", "session": None}

    summary = session_manager.get_stats()
    # Enrich with DB record if available
    db_record = await database.get_session_stats(current_session.session_id)
    return {"session": summary, "db_record": db_record}


@app.post("/api/test-cue")
async def test_cue():
    """Fire a test cue immediately, regardless of sleep stage."""
    try:
        await fire_reality_check_cue()
        return {"success": True, "message": "Cue fired successfully"}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Cue failed: {exc}")


@app.post("/api/session/start", response_model=SessionStartResponse)
async def start_session():
    """Create a new sleep-tracking session."""
    session_id = session_manager.start_session()
    current = session_manager.get_current_session()
    start_time_iso = current.start_time.isoformat()

    await database.create_session(session_id, start_time_iso)

    return SessionStartResponse(session_id=session_id, start_time=start_time_iso)


@app.post("/api/session/end")
async def end_session():
    """End the current sleep-tracking session."""
    current = session_manager.get_current_session()
    if current is None:
        raise HTTPException(status_code=400, detail="No active session to end")

    session_id = current.session_id
    final_stats = session_manager.end_session()

    from datetime import datetime, timezone
    end_time_iso = final_stats.get("end_time") or datetime.now(tz=timezone.utc).isoformat()

    await database.end_session(session_id, end_time_iso, final_stats)

    return {"message": "Session ended", "stats": final_stats}


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    """Serve the DreamCue web dashboard."""
    dashboard_path = os.path.join(os.path.dirname(__file__), "dashboard.html")
    try:
        with open(dashboard_path, "r", encoding="utf-8") as f:
            return HTMLResponse(content=f.read())
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Dashboard not found")


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("PORT", "8000"))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
