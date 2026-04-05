import Foundation
import SwiftUI
import HealthKit
import CoreMotion
import WatchConnectivity
import WatchKit

// MARK: - WatchSessionManager

class WatchSessionManager: NSObject, ObservableObject {

    // MARK: Singleton
    static let shared = WatchSessionManager()

    // MARK: Published State
    @Published var currentStage: String = "AWAKE"
    @Published var currentHR: Double = 0
    @Published var isTracking: Bool = false
    @Published var stageStartTime: Date? = nil
    @Published var timeInStage: TimeInterval = 0
    @Published var batteryLevel: Float = 1.0

    // MARK: Private Properties
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private let healthStore = HKHealthStore()
    private let motionManager = CMMotionManager()
    private var dataTimer: Timer?
    private var wcSession: WCSession?
    private var pendingMessages: [[String: Any]] = []
    private let maxPendingMessages = 20

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: Init
    override private init() {
        super.init()
    }

    // MARK: - Setup

    func setup() {
        setupWCSession()
        requestHealthKitAuthorization()
        setupBatteryMonitoring()
    }

    // MARK: - WatchConnectivity Setup

    private func setupWCSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        wcSession = session
    }

    // MARK: - HealthKit Authorization

    private func requestHealthKitAuthorization() {
        var typesToRead = Set<HKObjectType>()
        var typesToShare = Set<HKSampleType>()

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .activeEnergyBurned,
            .distanceWalkingRunning
        ]

        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                typesToRead.insert(type)
                typesToShare.insert(type)
            }
        }

        // Also request workout type share
        typesToShare.insert(HKObjectType.workoutType())

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { granted, error in
            if let error = error {
                print("[DreamCue] HealthKit authorization error: \(error.localizedDescription)")
            } else {
                print("[DreamCue] HealthKit authorization granted: \(granted)")
            }
        }
    }

    // MARK: - Battery Monitoring

    private func setupBatteryMonitoring() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        updateBatteryLevel()

        // Observe battery level change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelDidChange),
            name: WKApplicationDelegate.batteryLevelDidChangeNotification,
            object: nil
        )
    }

    @objc private func batteryLevelDidChange() {
        updateBatteryLevel()
    }

    private func updateBatteryLevel() {
        let level = WKInterfaceDevice.current().batteryLevel
        DispatchQueue.main.async {
            self.batteryLevel = level
        }
    }

    // MARK: - Start Tracking

    func startTracking() async {
        guard !isTracking else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            session.delegate = self
            builder.delegate = self

            self.workoutSession = session
            self.workoutBuilder = builder

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            // Start accelerometer
            if motionManager.isAccelerometerAvailable {
                motionManager.accelerometerUpdateInterval = 1.0
                motionManager.startAccelerometerUpdates()
            }

            await MainActor.run {
                self.isTracking = true
                self.stageStartTime = startDate
                self.timeInStage = 0
            }

            startDataTimer()
            print("[DreamCue] Tracking started.")
        } catch {
            print("[DreamCue] Failed to start workout session: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop Tracking

    func stopTracking() async {
        guard isTracking else { return }

        stopDataTimer()

        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }

        let endDate = Date()

        if let session = workoutSession {
            session.end()
            workoutSession = nil
        }

        if let builder = workoutBuilder {
            do {
                try await builder.endCollection(at: endDate)
                _ = try await builder.finishWorkout()
            } catch {
                print("[DreamCue] Error ending workout builder: \(error.localizedDescription)")
            }
            workoutBuilder = nil
        }

        await MainActor.run {
            self.isTracking = false
            self.currentStage = "AWAKE"
            self.stageStartTime = nil
            self.timeInStage = 0
            self.currentHR = 0
        }

        print("[DreamCue] Tracking stopped.")
    }

    // MARK: - Data Timer

    func startDataTimer() {
        stopDataTimer()
        // Schedule on the main run loop so it fires reliably on watch
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.collectAndSendData() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.dataTimer = timer
    }

    private func stopDataTimer() {
        dataTimer?.invalidate()
        dataTimer = nil
    }

    // MARK: - Collect and Send Data

    func collectAndSendData() async {
        // 1. Accelerometer
        var accelX: Double = 0
        var accelY: Double = 0
        var accelZ: Double = 1   // default to gravity vector
        var movementMagnitude: Double = 0

        if let accelData = motionManager.accelerometerData {
            accelX = accelData.acceleration.x
            accelY = accelData.acceleration.y
            accelZ = accelData.acceleration.z
            // Subtract approximate gravity (assuming watch mostly at rest, z≈1g)
            let dx = accelX
            let dy = accelY
            let dz = accelZ - 1.0
            movementMagnitude = sqrt(dx * dx + dy * dy + dz * dz)
        }

        // 2. Heart rate
        let hr = await getLatestHR() ?? 0

        // 3. HRV
        let hrv = await getLatestHRV() ?? 0

        // 4. Battery
        let battery = WKInterfaceDevice.current().batteryLevel

        // 5. Update published HR on main thread
        let hrValue = hr
        await MainActor.run {
            if hrValue > 0 {
                self.currentHR = hrValue
            }
            self.batteryLevel = battery
        }

        // 6. Package message
        let message: [String: Any] = [
            "timestamp": isoFormatter.string(from: Date()),
            "source": "watch",
            "heart_rate": hr,
            "hrv": hrv,
            "movement_magnitude": movementMagnitude,
            "accel_x": accelX,
            "accel_y": accelY,
            "accel_z": accelZ,
            "watch_battery": Double(battery)
        ]

        sendMessageToPhone(message)
    }

    // MARK: - HealthKit Queries

    func getLatestHR() async -> Double? {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }

        return await withCheckedContinuation { continuation in
            let now = Date()
            let start = now.addingTimeInterval(-30)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictEndDate)

            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("[DreamCue] HR query error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: bpm)
            }
            healthStore.execute(query)
        }
    }

    func getLatestHRV() async -> Double? {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return nil }

        return await withCheckedContinuation { continuation in
            let now = Date()
            let start = now.addingTimeInterval(-120) // last 2 minutes
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictEndDate)

            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("[DreamCue] HRV query error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let ms = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: ms)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - WatchConnectivity Messaging

    func sendMessageToPhone(_ message: [String: Any]) {
        guard let session = wcSession else { return }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("[DreamCue] sendMessage error: \(error.localizedDescription)")
                // Queue it on failure
                self.enqueuePendingMessage(message)
            }
        } else {
            enqueuePendingMessage(message)
        }
    }

    private func enqueuePendingMessage(_ message: [String: Any]) {
        if pendingMessages.count >= maxPendingMessages {
            pendingMessages.removeFirst()
        }
        pendingMessages.append(message)
    }

    func flushPendingMessages() {
        guard let session = wcSession, session.isReachable else { return }

        let toSend = pendingMessages
        pendingMessages.removeAll()

        for message in toSend {
            session.sendMessage(message, replyHandler: nil) { error in
                print("[DreamCue] flush sendMessage error: \(error.localizedDescription)")
                // Re-enqueue if still failing
                self.enqueuePendingMessage(message)
            }
        }
    }

    // MARK: - Stage Update (called from iPhone commands)

    func updateStage(_ stage: String) {
        DispatchQueue.main.async {
            if stage != self.currentStage {
                self.currentStage = stage
                self.stageStartTime = Date()
                self.timeInStage = 0
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchSessionManager: HKWorkoutSessionDelegate {

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async {
            switch toState {
            case .running:
                self.isTracking = true
                print("[DreamCue] Workout session running.")
            case .ended, .stopped:
                self.isTracking = false
                print("[DreamCue] Workout session ended/stopped.")
            case .paused:
                print("[DreamCue] Workout session paused.")
            case .notStarted, .prepared:
                break
            @unknown default:
                print("[DreamCue] Unknown workout state: \(toState.rawValue)")
            }
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("[DreamCue] Workout session failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isTracking = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchSessionManager: HKLiveWorkoutBuilderDelegate {

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }

            if quantityType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue {
                let statistics = workoutBuilder.statistics(for: quantityType)
                if let mostRecent = statistics?.mostRecentQuantity() {
                    let bpm = mostRecent.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    DispatchQueue.main.async {
                        self.currentHR = bpm
                    }
                }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // No-op: handle workout events if needed
    }
}
