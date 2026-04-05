import Foundation
import CoreLocation
import Combine

/// Keeps the app alive overnight by monitoring significant location changes.
/// This is a standard iOS technique for long-running background apps.
final class LocationManager: NSObject, ObservableObject {

    // MARK: - Published properties

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isMonitoring: Bool = false

    // MARK: - Private

    private let locationManager = CLLocationManager()

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public API

    /// Requests Always authorization (required for overnight background use) and
    /// starts significant-location-change monitoring.
    func startMonitoring() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            // This triggers the system permission dialog.
            // The usage description keys in Info.plist explain why.
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            beginSignificantLocationChanges()
        case .authorizedWhenInUse:
            // Upgrade to Always so we can run in background
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            // Cannot start; the app will still function but may be suspended overnight.
            break
        @unknown default:
            break
        }
    }

    /// Stops significant-location-change monitoring.
    func stopMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        isMonitoring = false
    }

    // MARK: - Private helpers

    private func beginSignificantLocationChanges() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        locationManager.startMonitoringSignificantLocationChanges()
        isMonitoring = true
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus

            switch manager.authorizationStatus {
            case .authorizedAlways:
                self.beginSignificantLocationChanges()
            case .authorizedWhenInUse:
                // Request upgrade — iOS will show a second prompt asking for Always
                manager.requestAlwaysAuthorization()
            default:
                self.isMonitoring = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Significant location change received — this wakes the app if it was suspended.
        // No actual location data is used; this is purely a keep-alive mechanism.
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location errors are non-fatal for our use case.
        // The keep-alive role is best-effort; the session data is primary.
    }
}
