import SwiftUI
import WatchKit

@main
struct DreamCueWatchApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(WatchSessionManager.shared)
        }
    }
}

class AppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionManager.shared.setup()
    }
}
