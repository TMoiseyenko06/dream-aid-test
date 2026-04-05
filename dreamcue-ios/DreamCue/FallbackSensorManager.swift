import Foundation
import CoreMotion
import HealthKit

/// Provides iPhone-based sensor readings when the Apple Watch is unavailable.
final class FallbackSensorManager: ObservableObject {

    // MARK: - Private properties

    private let motionManager = CMMotionManager()
    private let healthStore = HKHealthStore()
    private let sensorQueue = OperationQueue()

    /// Most-recent accelerometer snapshot, protected by the motion update callback thread.
    private var latestAccel: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)

    /// Rolling buffer of the last ~10 accelerometer samples for movement magnitude.
    private var magnitudeBuffer: [Double] = []
    private let magnitudeBufferCapacity = 10

    private var isMonitoring = false

    // MARK: - Init

    init() {
        sensorQueue.name = "com.dreamcue.sensorQueue"
        sensorQueue.qualityOfService = .utility
    }

    // MARK: - Public API

    /// Starts accelerometer monitoring at 10 Hz and sets up HealthKit observer queries.
    func startMonitoring() async {
        guard !isMonitoring else { return }
        isMonitoring = true

        await requestHealthKitAuthorization()
        startAccelerometer()
    }

    /// Stops all active monitoring.
    func stopMonitoring() async {
        guard isMonitoring else { return }
        isMonitoring = false
        motionManager.stopAccelerometerUpdates()
    }

    /// Returns the current movement state derived from accelerometer data.
    func getCurrentReading() -> (movement: Double, accelX: Double, accelY: Double, accelZ: Double) {
        let accel = latestAccel
        let movement = averageMagnitude()
        return (movement: movement,
                accelX: accel.x,
                accelY: accel.y,
                accelZ: accel.z)
    }

    /// Queries HealthKit for the most recent heart rate sample within the last 30 seconds.
    func getLatestHR() async -> Double? {
        return await queryLatestHealthKitSample(
            typeIdentifier: .heartRate,
            unit: HKUnit(from: "count/min"),
            withinSeconds: 30
        )
    }

    /// Queries HealthKit for the most recent HRV (SDNN) sample within the last 2 minutes.
    func getLatestHRV() async -> Double? {
        return await queryLatestHealthKitSample(
            typeIdentifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            withinSeconds: 120
        )
    }

    // MARK: - Accelerometer

    private func startAccelerometer() {
        guard motionManager.isAccelerometerAvailable else { return }

        motionManager.accelerometerUpdateInterval = 0.1 // 10 Hz

        motionManager.startAccelerometerUpdates(to: sensorQueue) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            self.latestAccel = data.acceleration

            let magnitude = sqrt(
                data.acceleration.x * data.acceleration.x +
                data.acceleration.y * data.acceleration.y +
                data.acceleration.z * data.acceleration.z
            )
            // Subtract 1g of gravity contribution (approximate)
            let dynamic = abs(magnitude - 1.0)

            self.magnitudeBuffer.append(dynamic)
            if self.magnitudeBuffer.count > self.magnitudeBufferCapacity {
                self.magnitudeBuffer.removeFirst()
            }
        }
    }

    private func averageMagnitude() -> Double {
        guard !magnitudeBuffer.isEmpty else { return 0.0 }
        return magnitudeBuffer.reduce(0, +) / Double(magnitudeBuffer.count)
    }

    // MARK: - HealthKit authorization

    private func requestHealthKitAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        let writeTypes: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            // Authorization errors are non-fatal; we just won't have HealthKit data
        }
    }

    // MARK: - HealthKit queries

    private func queryLatestHealthKitSample(
        typeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        withinSeconds: TimeInterval
    ) async -> Double? {
        guard HKHealthStore.isHealthDataAvailable(),
              let quantityType = HKQuantityType.quantityType(forIdentifier: typeIdentifier)
        else { return nil }

        let now = Date()
        let startDate = now.addingTimeInterval(-withinSeconds)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now, options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard error == nil,
                      let sample = samples?.first as? HKQuantitySample
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }
}
