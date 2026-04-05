import aiosqlite
import os
from typing import Optional

DB_PATH = os.getenv("DB_PATH", "dreamcue.db")

CREATE_SENSOR_READINGS = """
CREATE TABLE IF NOT EXISTS sensor_readings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    source TEXT NOT NULL,
    heart_rate REAL,
    hrv REAL,
    movement_magnitude REAL,
    accel_x REAL,
    accel_y REAL,
    accel_z REAL,
    detected_stage TEXT,
    watch_battery REAL,
    cue_fired INTEGER DEFAULT 0,
    session_id TEXT
);
"""

CREATE_SLEEP_SESSIONS = """
CREATE TABLE IF NOT EXISTS sleep_sessions (
    id TEXT PRIMARY KEY,
    start_time TEXT,
    end_time TEXT,
    total_rem_minutes REAL,
    total_deep_minutes REAL,
    total_light_minutes REAL,
    cues_fired INTEGER DEFAULT 0,
    watch_used INTEGER DEFAULT 1
);
"""


async def init_db():
    """Create both tables if they don't exist."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(CREATE_SENSOR_READINGS)
        await db.execute(CREATE_SLEEP_SESSIONS)
        await db.commit()


async def store_reading(reading_dict: dict):
    """Insert a sensor reading into the database."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            INSERT INTO sensor_readings (
                timestamp, source, heart_rate, hrv, movement_magnitude,
                accel_x, accel_y, accel_z, detected_stage, watch_battery,
                cue_fired, session_id
            ) VALUES (
                :timestamp, :source, :heart_rate, :hrv, :movement_magnitude,
                :accel_x, :accel_y, :accel_z, :detected_stage, :watch_battery,
                :cue_fired, :session_id
            )
            """,
            {
                "timestamp": reading_dict.get("timestamp"),
                "source": reading_dict.get("source"),
                "heart_rate": reading_dict.get("heart_rate"),
                "hrv": reading_dict.get("hrv"),
                "movement_magnitude": reading_dict.get("movement_magnitude"),
                "accel_x": reading_dict.get("accel_x"),
                "accel_y": reading_dict.get("accel_y"),
                "accel_z": reading_dict.get("accel_z"),
                "detected_stage": reading_dict.get("detected_stage"),
                "watch_battery": reading_dict.get("watch_battery"),
                "cue_fired": 1 if reading_dict.get("cue_fired") else 0,
                "session_id": reading_dict.get("session_id"),
            },
        )
        await db.commit()


async def get_recent_readings(limit: int = 200) -> list[dict]:
    """Return the most recent sensor readings."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            """
            SELECT * FROM sensor_readings
            ORDER BY id DESC
            LIMIT ?
            """,
            (limit,),
        ) as cursor:
            rows = await cursor.fetchall()
            # Return in chronological order (oldest first)
            return [dict(row) for row in reversed(rows)]


async def create_session(session_id: str, start_time: str):
    """Insert a new sleep session record."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            INSERT INTO sleep_sessions (id, start_time, watch_used)
            VALUES (?, ?, 1)
            """,
            (session_id, start_time),
        )
        await db.commit()


async def end_session(session_id: str, end_time: str, stats: dict):
    """Update a session record with end time and stats."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            """
            UPDATE sleep_sessions
            SET end_time = ?,
                total_rem_minutes = ?,
                total_deep_minutes = ?,
                total_light_minutes = ?,
                cues_fired = ?,
                watch_used = ?
            WHERE id = ?
            """,
            (
                end_time,
                stats.get("total_rem_minutes", 0.0),
                stats.get("total_deep_minutes", 0.0),
                stats.get("total_light_minutes", 0.0),
                stats.get("cues_fired", 0),
                1 if stats.get("watch_used", True) else 0,
                session_id,
            ),
        )
        await db.commit()


async def get_session_stats(session_id: str) -> dict:
    """Return the stats for a given session."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute(
            "SELECT * FROM sleep_sessions WHERE id = ?", (session_id,)
        ) as cursor:
            row = await cursor.fetchone()
            if row is None:
                return {}
            return dict(row)
