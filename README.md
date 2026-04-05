# DreamCue

DreamCue is an iOS/watchOS sleep tracking app that detects REM sleep in real time and plays a gentle sound on your iPhone as a reality check cue for lucid dreaming. Your Apple Watch monitors heart rate and HRV throughout the night; when the classifier identifies REM sleep, the backend signals the iPhone app, which plays your chosen audio file for a configurable duration — audible enough to register subconsciously but quiet enough not to fully wake you.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Adding Your Cue Sound File](#adding-your-cue-sound-file)
3. [Backend Setup](#backend-setup)
4. [Ngrok Setup](#ngrok-setup)
5. [Xcode Setup](#xcode-setup)
6. [Permissions to Grant on First Launch](#permissions-to-grant-on-first-launch)
7. [First Use Walkthrough](#first-use-walkthrough)
8. [Understanding the Dashboard](#understanding-the-dashboard)
9. [Tuning Guide](#tuning-guide)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, make sure you have the following:

| Requirement | Notes |
|---|---|
| Mac with Xcode 15+ | Required to build and deploy the iOS/watchOS app |
| Python 3.11+ | Required to run the backend server |
| Apple Watch Series 4 or later | **Required** — primary sensor for HR and HRV data |
| ngrok account (free tier) | Exposes your local backend to the internet |
| A sound file (`cue_sound.mp3`) | The audio played when REM is detected — your choice |

---

## Adding Your Cue Sound File

When REM is detected DreamCue plays a sound file directly on your iPhone. You choose the file.

**Recommended cues** (keep volume low — you want subconscious awareness, not full waking):
- Soft Tibetan bowl tone
- A single gentle chime
- Binaural beat segment
- Your own recorded phrase ("You are dreaming…")

**Steps:**
1. Find or record an audio file in `.mp3`, `.wav`, `.m4a`, or `.aiff` format
2. Rename it to **`cue_sound.mp3`** (or keep the original extension — the app tries all four)
3. In Xcode, drag the file into the **DreamCue** group (not the Watch group) and tick **Add to targets: DreamCue**
4. Verify it appears in **Build Phases → Copy Bundle Resources** for the DreamCue target
5. Use **Settings → Test Cue** in the app to confirm it plays before bed

> If no `cue_sound` file is found in the bundle the app falls back to repeating a short system chime for the configured duration — functional but less pleasant.

---

## Backend Setup

```bash
cd dreamcue-backend
```

Copy the example environment file:

```bash
cp .env.example .env
```

The defaults work out of the box. Edit `.env` if you want to change thresholds:

```
CUE_ENABLED=true
MIN_REM_DURATION_MINUTES=5
CUE_INTERVAL_SECONDS=120
```

Install dependencies:

```bash
pip install -r requirements.txt
```

Start the server:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Once running, the web dashboard is available at:

```
http://localhost:8000/dashboard
```

---

## Ngrok Setup

ngrok creates a secure public URL that lets the DreamCue iOS app reach your local backend over the internet while you sleep.

Install ngrok:

```bash
brew install ngrok
```

Alternatively, download it directly from [ngrok.com](https://ngrok.com/download).

Authenticate with your ngrok account token:

```bash
ngrok config add-authtoken YOUR_TOKEN
```

Expose the backend port:

```bash
ngrok http 8000
```

ngrok will display a forwarding URL similar to:

```
https://abc123.ngrok.io -> http://localhost:8000
```

Copy the `https://` URL. You will paste it into the DreamCue app during first-run setup.

> **Free tier note**: The ngrok free tier tunnel expires after 8 hours. Restart ngrok before going to bed each night to ensure you have a fresh tunnel.

---

## Xcode Setup

1. Open the project in Xcode:
   ```
   dreamcue-ios/DreamCue.xcodeproj
   ```
2. Select the **DreamCue** target → **Signing & Capabilities** → set your **Development Team**
3. Select the **DreamCueWatch** target → **Signing & Capabilities** → set the same Development Team
4. Verify that the **HealthKit** capability is enabled on both targets
5. Connect your iPhone to your Mac via cable
6. Select your iPhone as the run destination in the toolbar
7. Press **⌘R** to build and run — this installs both the iOS app and the watchOS companion app simultaneously

---

## Permissions to Grant on First Launch

When you open DreamCue for the first time, you will be prompted for two permissions. Both are required for overnight operation.

- **Health access**: Tap **Allow All** in the HealthKit permission sheet. This grants DreamCue read access to heart rate and HRV data from your Apple Watch.
- **Location**: Tap **Allow Always**. Location access keeps the iOS relay alive in the background overnight. Without "Always" permission, iOS will suspend the app and watch data will stop flowing.

Audio playback requires no additional permission — the `audio` background mode in Info.plist is sufficient. Make sure your iPhone is **not on silent** (check the physical mute switch on the side of the phone) and volume is set to a comfortable level before bed.

---

## First Use Walkthrough

Follow these steps on your first night to verify everything is working end-to-end before you fall asleep.

1. Open **DreamCue** on your iPhone
2. Go to the **Settings** tab
3. Enter your ngrok URL in the **Backend URL** field (e.g. `https://abc123.ngrok.io`)
4. Tap **Test Connection** — you should see a latency value confirming the backend is reachable
5. Tap **Test Cue** — your iPhone should immediately play `cue_sound.mp3` for the configured duration, confirming audio works
6. Return to the **Tonight** tab
7. Put on your Apple Watch
8. Tap **START** — the watch app activates and begins a background workout session, which keeps the heart rate sensor running continuously
9. The green dot in the app confirms watch data is flowing to your iPhone
10. Place your iPhone on the nightstand (plugged in to charge)
11. Open the web dashboard on your phone at `[your-ngrok-url]/dashboard`
12. Within 30 seconds you should see live heart rate data appearing — you are ready to sleep

---

## Understanding the Dashboard

The dashboard updates every 10 seconds and gives you a live and historical view of your night.

| Element | What it shows |
|---|---|
| **Stage display** | Current detected sleep stage. REM appears in purple and typically first occurs 90+ minutes after sleep onset. |
| **WATCH badge** (green) | Watch data is being received and used as the primary sensor. |
| **PHONE badge** (yellow) | Fallback mode — the app is using iPhone motion data only. Watch data is not flowing. |
| **Stage timeline** | Horizontal coloured bars showing your full sleep architecture across the night. |
| **HR chart** | Heart rate over time. HR dips noticeably during deep sleep. |
| **HRV chart** | Heart rate variability over time. HRV rises during REM — this is one of the key signals the classifier uses. |
| **Movement chart** | Accelerometer movement. Should be near zero during all sleep stages; spikes indicate waking or repositioning. |
| **Cue fired indicators** | Red markers on the timeline showing exactly when reality check cues were triggered. |

---

## Tuning Guide

After your first 2–3 nights, review the dashboard history to calibrate the app to your sleep patterns.

**Cues firing too early**
Increase `MIN_REM_DURATION_MINUTES` in your `.env` or backend config. Starting with 7–10 minutes ensures the classifier has confirmed sustained REM before triggering.

**Sleeping through cues**
Increase iPhone volume before bed and decrease the cue interval so cues repeat more frequently. You can also try a more distinctive sound file. The goal is audible-but-not-waking.

**REM detection seems inaccurate**
Confirm that HRV data is available on your dashboard. HRV requires Apple Watch Series 4 or later. Without HRV, the classifier falls back to HR and movement only, which is less accurate.

**Deep sleep never appears**
The deep sleep stage is partly identified by HR dropping below 54 bpm. If your personal resting HR is higher, open `classifier.py` in the backend and adjust the threshold to match your baseline.

---

## Troubleshooting

**Watch not connecting**
Ensure Bluetooth is enabled on your iPhone, the watch is paired, and both devices have the DreamCue app installed. Kill and relaunch both the iPhone and watch apps, then tap START again.

**Background app being killed**
The most common cause is missing location permission. Go to **iPhone Settings → DreamCue → Location** and confirm it is set to **Always**. The background location session is what prevents iOS from suspending the relay process overnight.

**Cue sound not playing**
Check that `cue_sound.mp3` (or `.wav`/`.m4a`) is in the **Copy Bundle Resources** build phase for the DreamCue target. Use **Settings → Test Cue** — if you hear nothing check iPhone silent mode (flip the physical mute switch off) and volume level. If the file is missing the app will fall back to a system chime as confirmation that the trigger logic itself is working.

**Heart rate readings missing from dashboard**
The watch must be worn snugly with good skin contact. HealthKit HR samples can lag 30–60 seconds before appearing. The classifier uses a rolling 2-minute window of readings, so a brief gap will self-correct once samples resume.

**Stage stuck on AWAKE**
This is normal at sleep onset. The classifier applies a 4-reading smoothing filter, which requires approximately 20 seconds of consistent data before committing to a stage transition. This prevents spurious stage changes from isolated readings.

**Backend not reachable from iPhone**
Verify the ngrok tunnel is still running in your terminal. The free tier tunnel expires after 8 hours — always restart ngrok and update the Backend URL in DreamCue settings before going to bed.
