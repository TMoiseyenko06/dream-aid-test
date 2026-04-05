from datetime import datetime, timezone
from typing import Optional


def update_session_time(session_start_iso: str) -> float:
    """Compute the number of minutes elapsed since the session started."""
    try:
        start = datetime.fromisoformat(session_start_iso)
        # Ensure both datetimes are comparable (make naive if needed)
        now = datetime.now(tz=start.tzinfo) if start.tzinfo else datetime.now()
        elapsed = (now - start).total_seconds() / 60.0
        return max(0.0, elapsed)
    except Exception:
        return 0.0


def _safe_avg(values: list) -> Optional[float]:
    """Return mean of a list, or None if the list is empty or all None."""
    clean = [v for v in values if v is not None]
    if not clean:
        return None
    return sum(clean) / len(clean)


def classify_stage(
    recent_readings: list[dict],
    session_start_iso: Optional[str] = None,
) -> tuple[str, float]:
    """
    Classify the current sleep stage from the last 12 sensor readings.

    Returns a (stage, confidence) tuple where stage is one of:
    "AWAKE", "REM", "DEEP", "LIGHT"
    """
    if not recent_readings:
        return ("AWAKE", 0.5)

    # Use last 12 readings (approx 60 seconds at 5-second intervals)
    window = recent_readings[-12:]

    # Determine dominant source — prefer watch data
    sources = [r.get("source", "phone") for r in window]
    watch_count = sum(1 for s in sources if s == "watch")
    is_watch = watch_count >= len(window) / 2

    # Collect metrics from the window
    hr_values = [r.get("heart_rate") for r in window]
    hrv_values = [r.get("hrv") for r in window]
    movement_values = [r.get("movement_magnitude") for r in window]

    avg_hr = _safe_avg(hr_values)
    avg_hrv = _safe_avg(hrv_values)
    avg_movement = _safe_avg(movement_values)

    # Tighter thresholds for watch data
    awake_mov_thresh = 0.15 if is_watch else 0.25
    deep_mov_thresh = 0.015 if is_watch else 0.03
    rem_mov_thresh = 0.04 if is_watch else 0.08

    # Minutes since session start
    elapsed_minutes = 0.0
    if session_start_iso:
        elapsed_minutes = update_session_time(session_start_iso)

    # -------------------------------------------------------------------
    # AWAKE detection
    # -------------------------------------------------------------------
    movement_very_high = avg_movement is not None and avg_movement > awake_mov_thresh * 2
    movement_high = avg_movement is not None and avg_movement > awake_mov_thresh
    hr_very_high = avg_hr is not None and avg_hr > 95

    if movement_very_high or hr_very_high:
        confidence = 0.9 if movement_very_high else 0.7
        return ("AWAKE", confidence)

    if movement_high:
        return ("AWAKE", 0.7)

    # -------------------------------------------------------------------
    # DEEP sleep detection
    # -------------------------------------------------------------------
    deep_movement_ok = avg_movement is not None and avg_movement < deep_mov_thresh
    deep_hr_ok = avg_hr is not None and avg_hr < 54
    deep_hrv_ok = avg_hrv is not None and avg_hrv < 28
    deep_time_ok = elapsed_minutes < 210  # 3.5 hours

    deep_score = 0
    deep_confidence_parts = []

    if deep_movement_ok:
        deep_score += 1
        # Scale confidence by how far below threshold
        ratio = avg_movement / deep_mov_thresh
        deep_confidence_parts.append(max(0.0, 1.0 - ratio))

    if deep_hr_ok:
        deep_score += 1
        ratio = avg_hr / 54.0
        deep_confidence_parts.append(max(0.0, 1.0 - ratio))

    if deep_hrv_ok:
        deep_score += 1
        ratio = avg_hrv / 28.0
        deep_confidence_parts.append(max(0.0, 1.0 - ratio))

    if deep_score >= 2 and deep_time_ok:
        base_confidence = sum(deep_confidence_parts) / len(deep_confidence_parts) if deep_confidence_parts else 0.6
        # Require at least movement + one of HR/HRV for high confidence
        if deep_movement_ok and (deep_hr_ok or deep_hrv_ok):
            confidence = min(0.95, 0.5 + base_confidence * 0.45)
            return ("DEEP", round(confidence, 3))

    # -------------------------------------------------------------------
    # REM detection
    # -------------------------------------------------------------------
    rem_movement_ok = avg_movement is not None and avg_movement < rem_mov_thresh
    rem_hr_ok = avg_hr is not None and 54 <= avg_hr <= 82
    rem_hrv_ok = avg_hrv is not None and avg_hrv > 38
    rem_time_ok = elapsed_minutes > 90

    if rem_movement_ok and rem_time_ok:
        hrv_weight = 0.5
        hr_weight = 0.3
        movement_weight = 0.2

        hrv_score = 0.0
        hr_score = 0.0
        movement_score = 0.0

        if rem_hrv_ok and avg_hrv is not None:
            # Higher HRV above 38 gives more confidence
            hrv_score = min(1.0, (avg_hrv - 38) / 30.0 + 0.6)
        elif avg_hrv is not None:
            # Below threshold but not disqualifying — partial credit
            hrv_score = max(0.0, avg_hrv / 38.0 * 0.4)

        if rem_hr_ok and avg_hr is not None:
            # HR in the center of 54–82 range gets full credit
            center = 68.0
            hr_score = max(0.0, 1.0 - abs(avg_hr - center) / 14.0)
        elif avg_hr is not None:
            hr_score = 0.2  # partial credit for unknown HR

        if avg_movement is not None:
            # Lower movement = higher score
            movement_score = max(0.0, 1.0 - avg_movement / rem_mov_thresh)

        weighted_confidence = (
            hrv_weight * hrv_score
            + hr_weight * hr_score
            + movement_weight * movement_score
        )

        # Need at least HRV hint or clear HR+movement combination
        if rem_hrv_ok or (rem_hr_ok and avg_movement is not None and avg_movement < rem_mov_thresh * 0.6):
            confidence = min(0.92, max(0.45, weighted_confidence))
            return ("REM", round(confidence, 3))

    # -------------------------------------------------------------------
    # LIGHT sleep — default
    # -------------------------------------------------------------------
    return ("LIGHT", 0.6)
