import Foundation
import SwiftUI
import Combine

// MARK: - Enums

enum SleepStage: String, Codable {
    case awake
    case light
    case deep
    case rem

    var displayName: String {
        switch self {
        case .awake: return "AWAKE"
        case .light: return "LIGHT"
        case .deep: return "DEEP"
        case .rem: return "REM"
        }
    }

    var color: Color {
        switch self {
        case .awake: return .white
        case .light: return Color(red: 0.4, green: 0.6, blue: 1.0)   // light blue
        case .deep: return Color(red: 0.1, green: 0.2, blue: 0.7)    // dark blue
        case .rem: return Color(red: 0.7, green: 0.3, blue: 1.0)     // purple
        }
    }
}

enum MovementLevel: String, Codable {
    case calm
    case someMovement = "some_movement"
    case active
}

enum DataSource: String, Codable {
    case watch
    case phone
}

// MARK: - SensorReading

struct SensorReading: Codable {
    let sessionID: String
    let timestamp: Double
    let heartRate: Double?
    let hrv: Double?
    let accelX: Double?
    let accelY: Double?
    let accelZ: Double?
    let movementMagnitude: Double?
    let source: String
    let watchBattery: Double?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case timestamp
        case heartRate = "heart_rate"
        case hrv
        case accelX = "accel_x"
        case accelY = "accel_y"
        case accelZ = "accel_z"
        case movementMagnitude = "movement_magnitude"
        case source
        case watchBattery = "watch_battery"
    }
}

// MARK: - SessionStartResponse

private struct SessionStartResponse: Codable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

// MARK: - SessionManager

@MainActor
final class SessionManager: ObservableObject {

    // MARK: Published state
    @Published var currentStage: SleepStage = .awake
    @Published var currentHR: Double? = nil
    @Published var currentHRV: Double? = nil
    @Published var movementLevel: MovementLevel = .calm
    @Published var dataSource: DataSource = .watch
    @Published var isSessionActive: Bool = false
    @Published var sessionStartTime: Date? = nil
    @Published var sessionID: String? = nil
    @Published var timeInCurrentStage: TimeInterval = 0
    @Published var totalREMMinutes: Double = 0
    @Published var cuesFired: Int = 0
    @Published var watchBattery: Double? = nil

    // MARK: Private state
    private var stageTimer: Timer?
    private var stageStartTime: Date = Date()
    private var lastStage: SleepStage = .awake
    private var fallbackTimer: Timer?

    let fallbackSensorManager = FallbackSensorManager()

    private var backendURL: String {
        UserDefaults.standard.string(forKey: "backendURL") ?? "http://localhost:8000"
    }

    // MARK: - Session lifecycle

    func startSession() async {
        guard !isSessionActive else { return }

        // Ask backend to create a new session
        guard let url = URL(string: backendURL + "/api/session/start") else { return }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                let decoded = try JSONDecoder().decode(SessionStartResponse.self, from: data)
                sessionID = decoded.sessionId
            } else {
                // Fallback: generate a local session ID if backend is unavailable
                sessionID = UUID().uuidString
            }
        } catch {
            // Still start locally even if network fails
            sessionID = UUID().uuidString
        }

        isSessionActive = true
        sessionStartTime = Date()
        stageStartTime = Date()
        lastStage = .awake
        currentStage = .awake
        timeInCurrentStage = 0
        totalREMMinutes = 0
        cuesFired = 0

        startStageTimer()
        startFallbackPolling()
        await fallbackSensorManager.startMonitoring()
    }

    func stopSession() async {
        guard isSessionActive else { return }

        stopStageTimer()
        stopFallbackPolling()
        await fallbackSensorManager.stopMonitoring()

        isSessionActive = false

        // Notify backend
        if let sid = sessionID,
           let url = URL(string: backendURL + "/api/session/end") {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["session_id": sid]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: request)
        }

        sessionID = nil
        sessionStartTime = nil
    }

    // MARK: - Stage timer

    private func startStageTimer() {
        stageTimer?.invalidate()
        stageTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSessionActive else { return }
                self.timeInCurrentStage = Date().timeIntervalSince(self.stageStartTime)
                if self.currentStage == .rem {
                    self.totalREMMinutes += 1.0 / 60.0
                }
            }
        }
    }

    private func stopStageTimer() {
        stageTimer?.invalidate()
        stageTimer = nil
    }

    // MARK: - Fallback polling (phone sensors)

    private func startFallbackPolling() {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isSessionActive, self.dataSource == .phone else { return }
                await self.processFallbackData()
            }
        }
    }

    private func stopFallbackPolling() {
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    // MARK: - Watch data handler

    func processWatchData(_ data: [String: Any]) {
        dataSource = .watch

        if let hr = data["heartRate"] as? Double { currentHR = hr }
        if let hrv = data["hrv"] as? Double { currentHRV = hrv }
        if let battery = data["batteryLevel"] as? Double { watchBattery = battery }

        // Movement
        let movementMag = data["movementMagnitude"] as? Double ?? 0.0
        movementLevel = movementLevelFromMagnitude(movementMag)

        guard isSessionActive, let sid = sessionID else { return }

        let accelX = data["accelX"] as? Double
        let accelY = data["accelY"] as? Double
        let accelZ = data["accelZ"] as? Double

        let reading = SensorReading(
            sessionID: sid,
            timestamp: Date().timeIntervalSince1970,
            heartRate: currentHR,
            hrv: currentHRV,
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ,
            movementMagnitude: movementMag,
            source: "watch",
            watchBattery: watchBattery
        )

        Task {
            await sendToBackend(reading)
        }
    }

    // MARK: - Fallback data handler

    func processFallbackData() async {
        dataSource = .phone

        let raw = fallbackSensorManager.getCurrentReading()
        movementLevel = movementLevelFromMagnitude(raw.movement)

        let hr = await fallbackSensorManager.getLatestHR()
        let hrv = await fallbackSensorManager.getLatestHRV()
        if let hr { currentHR = hr }
        if let hrv { currentHRV = hrv }

        guard isSessionActive, let sid = sessionID else { return }

        let reading = SensorReading(
            sessionID: sid,
            timestamp: Date().timeIntervalSince1970,
            heartRate: currentHR,
            hrv: currentHRV,
            accelX: raw.accelX,
            accelY: raw.accelY,
            accelZ: raw.accelZ,
            movementMagnitude: raw.movement,
            source: "phone",
            watchBattery: nil
        )

        await sendToBackend(reading)
    }

    // MARK: - Backend submission

    func sendToBackend(_ reading: SensorReading) async {
        guard let url = URL(string: backendURL + "/api/sensor-data") else { return }

        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(reading)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                updateStageFromResponse(json)
            }
        } catch {
            // Network errors are non-fatal; we keep displaying last known values
        }
    }

    // MARK: - Response parsing

    func updateStageFromResponse(_ response: [String: Any]) {
        // Update sleep stage — backend uses "stage" key.
        let stageRaw = response["stage"] as? String ?? response["sleep_stage"] as? String
        if let stageRaw,
           let newStage = SleepStage(rawValue: stageRaw.lowercased()) {
            if newStage != currentStage {
                currentStage = newStage
                stageStartTime = Date()
                timeInCurrentStage = 0
            }
        }

        // Fire local audio cue when the backend says to.
        if let cueTriggered = response["cue_triggered"] as? Bool, cueTriggered {
            cuesFired += 1
            let duration = UserDefaults.standard.double(forKey: "cueDurationSeconds")
            AudioCueManager.shared.playCue(duration: duration > 0 ? duration : 30)
        }

        if let cueCount = response["cues_fired"] as? Int {
            cuesFired = cueCount
        }
    }

    // MARK: - Helpers

    private func movementLevelFromMagnitude(_ magnitude: Double) -> MovementLevel {
        switch magnitude {
        case 0..<0.02: return .calm
        case 0.02..<0.1: return .someMovement
        default: return .active
        }
    }
}
