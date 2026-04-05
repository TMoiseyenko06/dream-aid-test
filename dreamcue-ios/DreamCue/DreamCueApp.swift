import SwiftUI

@main
struct DreamCueApp: App {
    @StateObject private var sessionManager = SessionManager()
    @StateObject private var watchConnectivity = WatchConnectivityManager()
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(watchConnectivity)
                .environmentObject(locationManager)
                .onAppear {
                    // Wire watch connectivity callback into session manager
                    watchConnectivity.onMessageReceived = { [weak sessionManager] message in
                        sessionManager?.processWatchData(message)
                    }
                }
        }
    }
}
