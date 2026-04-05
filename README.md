# DreamCue

DreamCue is an iOS/watchOS sleep tracking app that detects REM sleep in real time and triggers an Alexa-enabled device as a gentle reality check cue for lucid dreaming. Your Apple Watch monitors heart rate and HRV throughout the night; when the on-device classifier identifies REM sleep, it signals your backend, which flips a SinricPro virtual switch — causing Alexa to play a soft sound without waking you fully.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [SinricPro Setup](#sinricpro-setup)
3. [Alexa Setup](#alexa-setup)
4. [Backend Setup](#backend-setup)
5. [Ngrok Setup](#ngrok-setup)
6. [Xcode Setup](#xcode-setup)
7. [Permissions to Grant on First Launch](#permissions-to-grant-on-first-launch)
8. [First Use Walkthrough](#first-use-walkthrough)
9. [Understanding the Dashboard](#understanding-the-dashboard)
10. [Tuning Guide](#tuning-guide)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before you begin, make sure you have the following:

| Requirement | Notes |
|---|---|
| Mac with Xcode 15+ | Required to build and deploy the iOS/watchOS app |
| Python 3.11+ | Required to run the backend server |
| Apple Watch Series 4 or later | **Required** — primary sensor for HR and HRV data |
| Alexa-enabled device | Echo, Echo Dot, or any Alexa device |
| SinricPro account (free) | Virtual switch bridge between backend and Alexa |
| ngrok account (free tier) | Exposes your local backend to the internet |

---

## SinricPro Setup

SinricPro acts as the bridge between the DreamCue backend and your Alexa device via a virtual switch.

1. Create a free account at [sinric.pro](https://sinric.pro)
2. In the dashboard, create a new device and select **Virtual Switch** as the device type
3. Give it a recognisable name (e.g. `DreamCue Switch`)
4. Navigate to **Settings → API Key** and copy your API key
5. Open the device page and copy the **Device ID** (the long hexadecimal string — not the display name)
6. Keep both values handy; you will add them to the `.env` file during backend setup

---

## Alexa Setup

1. Open the **Alexa** app on your phone
2. Go to **More → Skills & Games** and search for **SinricPro**
3. Enable the SinricPro skill and link your SinricPro account when prompted
4. Tap **Discover Devices** — your virtual switch should appear as `DreamCue Switch`
5. Create a new Routine:
   - **Trigger**: When `DreamCue Switch` turns on
   - **Action**: Play ambient music or a gentle sound at low volume (or any subtle audio cue of your choice)
6. Save the routine

> **Why the on/off cycle?** The backend briefly turns the switch on then off (2-second pulse). This is intentional — Alexa routines only fire on a state *change*, not on repeated "on" commands. The off pulse resets the switch so the next REM detection triggers the routine again.

---

## Backend Setup

```bash
cd dreamcue-backend
```

Copy the example environment file and fill in your credentials:

```bash
cp .env.example .env
```

Open `.env` and set the following values:

```
SINRICPRO_API_KEY=your_api_key_here
SINRICPRO_DEVICE_ID=your_device_id_here
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
- **Location**: Tap **Allow Always**. Location access is what keeps the iOS relay process alive in the background overnight. Without "Always" permission, iOS will suspend the app and watch data will stop flowing.

---

## First Use Walkthrough

Follow these steps on your first night to verify everything is working end-to-end before you fall asleep.

1. Open **DreamCue** on your iPhone
2. Go to the **Settings** tab
3. Enter your ngrok URL in the **Backend URL** field (e.g. `https://abc123.ngrok.io`)
4. Tap **Test Connection** — you should see a latency value confirming the backend is reachable
5. Tap **Test Cue** — Alexa should play your chosen sound within a few seconds, confirming the full pipeline works
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
Decrease the cue interval so sounds repeat more frequently, or increase the Alexa routine volume slightly. The goal is audible-but-not-waking.

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

**SinricPro not triggering Alexa**
Check that `SINRICPRO_API_KEY` and `SINRICPRO_DEVICE_ID` in your `.env` file are correct. The Device ID is the long hexadecimal identifier from the SinricPro device page — not the display name. You can test the integration directly by calling the `/api/test-cue` endpoint on your backend.

**Heart rate readings missing from dashboard**
The watch must be worn snugly with good skin contact. HealthKit HR samples can lag 30–60 seconds before appearing. The classifier uses a rolling 2-minute window of readings, so a brief gap will self-correct once samples resume.

**Stage stuck on AWAKE**
This is normal at sleep onset. The classifier applies a 4-reading smoothing filter, which requires approximately 20 seconds of consistent data before committing to a stage transition. This prevents spurious stage changes from isolated readings.

**Backend not reachable from iPhone**
Verify the ngrok tunnel is still running in your terminal. The free tier tunnel expires after 8 hours — always restart ngrok and update the Backend URL in DreamCue settings before going to bed.
