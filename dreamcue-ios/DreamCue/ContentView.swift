import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        TabView {
            TonightView()
                .tabItem {
                    Label("Tonight", systemImage: "moon.stars.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(SessionManager())
        .environmentObject(WatchConnectivityManager())
        .environmentObject(LocationManager())
}
