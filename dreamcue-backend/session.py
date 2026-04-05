import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat()


@dataclass
class SleepSession:
    session_id: str
    start_time: datetime
    current_stage: str = "AWAKE"
    stage_start_time: datetime = field(default_factory=_now)
    pending_stage: str = "AWAKE"
    pending_stage_count: int = 0
    rem_periods: list = field(default_factory=list)
    cues_fired: int = 0
    last_cue_time: Optional[datetime] = None
    watch_used: bool = True

    # Internal tracking for stage durations (accumulated minutes per stage)
    _stage_minutes: dict = field(default_factory=lambda: {"AWAKE": 0.0, "REM": 0.0, "DEEP": 0.0, "LIGHT": 0.0})

    def _commit_current_stage_duration(self):
        """Accumulate time spent in current stage before a transition."""
        now = _now()
        elapsed = (now - self.stage_start_time).total_seconds() / 60.0
        stage = self.current_stage
        if stage not in self._stage_minutes:
            self._stage_minutes[stage] = 0.0
        self._stage_minutes[stage] += elapsed
        self.stage_start_time = now

    def transition_to(self, new_stage: str):
        """Commit current stage duration and switch to new stage."""
        now = _now()
        self._commit_current_stage_duration()

        # If leaving REM, close off the current REM period
        if self.current_stage == "REM" and new_stage != "REM":
            # Find the most recent open REM period (no 'end')
            for period in reversed(self.rem_periods):
                if period.get("end") is None:
                    period["end"] = _iso(now)
                    start_dt = datetime.fromisoformat(period["start"])
                    period["duration_minutes"] = round(
                        (now - start_dt).total_seconds() / 60.0, 2
                    )
                    break

        # If entering REM, open a new REM period
        if new_stage == "REM" and self.current_stage != "REM":
            self.rem_periods.append({"start": _iso(now), "end": None, "duration_minutes": 0.0})

        self.current_stage = new_stage
        self.stage_start_time = now

    def get_current_rem_duration_minutes(self) -> float:
        """Return total accumulated REM minutes including the current ongoing REM period."""
        total = self._stage_minutes.get("REM", 0.0)
        # Add time in the currently-open REM period if we are in REM
        if self.current_stage == "REM":
            now = _now()
            total += (now - self.stage_start_time).total_seconds() / 60.0
        return total


# Smoothing constant: require this many consecutive readings before stage change
STAGE_SMOOTHING_COUNT = 4


class SessionManager:
    def __init__(self):
        self._session: Optional[SleepSession] = None

    def start_session(self) -> str:
        """Create a new SleepSession and return its session_id."""
        session_id = str(uuid.uuid4())
        now = _now()
        self._session = SleepSession(
            session_id=session_id,
            start_time=now,
            stage_start_time=now,
        )
        return session_id

    def end_session(self) -> dict:
        """Close the current session and return summary stats."""
        if self._session is None:
            return {}

        session = self._session
        now = _now()

        # Commit the final stage's duration
        session._commit_current_stage_duration()

        # Close any open REM period
        if session.current_stage == "REM":
            for period in reversed(session.rem_periods):
                if period.get("end") is None:
                    period["end"] = _iso(now)
                    start_dt = datetime.fromisoformat(period["start"])
                    period["duration_minutes"] = round(
                        (now - start_dt).total_seconds() / 60.0, 2
                    )
                    break

        stats = self.get_stats()
        stats["end_time"] = _iso(now)
        self._session = None
        return stats

    def get_current_session(self) -> Optional[SleepSession]:
        return self._session

    def update_stage(self, new_stage: str, confidence: float):
        """
        Apply 4-reading smoothing before committing a stage change.
        A new stage must appear in 4 consecutive calls before it is adopted.
        """
        if self._session is None:
            return

        session = self._session

        if new_stage == session.current_stage:
            # Same as current stage — reset pending counter
            session.pending_stage = new_stage
            session.pending_stage_count = 0
            return

        if new_stage == session.pending_stage:
            session.pending_stage_count += 1
        else:
            # New candidate stage — start counting
            session.pending_stage = new_stage
            session.pending_stage_count = 1

        if session.pending_stage_count >= STAGE_SMOOTHING_COUNT:
            # Commit the stage change
            session.transition_to(new_stage)
            session.pending_stage = new_stage
            session.pending_stage_count = 0

    def should_fire_cue(self, min_rem_minutes: float, cue_interval_seconds: float) -> bool:
        """
        Return True if we should fire a lucid dreaming cue right now.
        Conditions:
        - We are currently in REM
        - Accumulated REM duration >= min_rem_minutes
        - Either no cue has been fired, or the last cue was >= cue_interval_seconds ago
        """
        if self._session is None:
            return False

        session = self._session

        if session.current_stage != "REM":
            return False

        rem_minutes = session.get_current_rem_duration_minutes()
        if rem_minutes < min_rem_minutes:
            return False

        if session.last_cue_time is None:
            return True

        now = _now()
        seconds_since_last = (now - session.last_cue_time).total_seconds()
        return seconds_since_last >= cue_interval_seconds

    def record_cue_fired(self):
        """Record that a cue was fired."""
        if self._session is None:
            return
        self._session.cues_fired += 1
        self._session.last_cue_time = _now()

    def get_stats(self) -> dict:
        """Return a summary dict for the current (or ended) session."""
        if self._session is None:
            return {}

        session = self._session
        now = _now()

        # Total session duration
        total_minutes = (now - session.start_time).total_seconds() / 60.0

        # Snapshot of accumulated stage minutes (does not mutate session state)
        stage_mins = dict(session._stage_minutes)
        # Add time spent in the current stage so far
        current_elapsed = (now - session.stage_start_time).total_seconds() / 60.0
        if session.current_stage not in stage_mins:
            stage_mins[session.current_stage] = 0.0
        stage_mins[session.current_stage] += current_elapsed

        rem_minutes = stage_mins.get("REM", 0.0)
        deep_minutes = stage_mins.get("DEEP", 0.0)
        light_minutes = stage_mins.get("LIGHT", 0.0)

        rem_pct = round(rem_minutes / total_minutes * 100, 1) if total_minutes > 0 else 0.0
        deep_pct = round(deep_minutes / total_minutes * 100, 1) if total_minutes > 0 else 0.0

        return {
            "session_id": session.session_id,
            "start_time": _iso(session.start_time),
            "current_stage": session.current_stage,
            "total_minutes": round(total_minutes, 1),
            "total_rem_minutes": round(rem_minutes, 2),
            "total_deep_minutes": round(deep_minutes, 2),
            "total_light_minutes": round(light_minutes, 2),
            "rem_pct": rem_pct,
            "deep_pct": deep_pct,
            "cues_fired": session.cues_fired,
            "rem_periods": session.rem_periods,
            "watch_used": session.watch_used,
        }


# Module-level singleton
session_manager = SessionManager()
