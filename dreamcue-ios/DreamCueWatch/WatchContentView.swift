import SwiftUI
import WatchKit

struct WatchContentView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    // Refresh time-in-stage every second
    @State private var displayTimer: Timer? = nil
    @State private var displayedTimeInStage: TimeInterval = 0

    var body: some View {
        ZStack {
            // Dim the entire display background during sleep mode
            Color(sessionManager.isTracking ? stageDimBackground : Color.black)
                .ignoresSafeArea()

            VStack(spacing: 6) {

                // --- Battery warning ---
                if sessionManager.batteryLevel < 0.20 && sessionManager.batteryLevel >= 0 {
                    Text(String(format: "Battery: %d%%", Int(sessionManager.batteryLevel * 100)))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                }

                // --- Sleep stage label ---
                Text(sessionManager.currentStage)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(stageColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                // --- Heart rate ---
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 13))
                    if sessionManager.currentHR > 0 {
                        Text("\(Int(sessionManager.currentHR)) BPM")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(sessionManager.isTracking ? .white.opacity(0.85) : .white)
                    } else {
                        Text("-- BPM")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }

                // --- Time in stage ---
                if sessionManager.stageStartTime != nil {
                    Text(formattedTimeInStage)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(sessionManager.isTracking ? .white.opacity(0.65) : .secondary)
                }

                Spacer(minLength: 4)

                // --- Sleep / Wake toggle button ---
                Button(action: toggleTracking) {
                    Text(sessionManager.isTracking ? "Wake" : "Sleep")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(sessionManager.isTracking ? Color.indigo.opacity(0.80) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // Dim content opacity during sleep mode
            .opacity(sessionManager.isTracking ? 0.75 : 1.0)
        }
        .onAppear {
            startDisplayTimer()
        }
        .onDisappear {
            stopDisplayTimer()
        }
    }

    // MARK: - Helpers

    private var stageColor: Color {
        switch sessionManager.currentStage {
        case "AWAKE": return .yellow
        case "LIGHT": return .cyan
        case "DEEP":  return .indigo
        case "REM":   return .purple
        default:      return .white
        }
    }

    private var stageDimBackground: Color {
        switch sessionManager.currentStage {
        case "DEEP": return Color(white: 0.04)
        case "REM":  return Color(white: 0.06)
        default:     return Color(white: 0.08)
        }
    }

    private var formattedTimeInStage: String {
        let totalSeconds = Int(displayedTimeInStage)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            let secs = totalSeconds % 60
            return "\(minutes)m \(secs)s"
        }
    }

    // MARK: - Timer

    private func startDisplayTimer() {
        displayedTimeInStage = sessionManager.timeInStage
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if let start = sessionManager.stageStartTime {
                displayedTimeInStage = Date().timeIntervalSince(start)
            } else {
                displayedTimeInStage = 0
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Actions

    private func toggleTracking() {
        if sessionManager.isTracking {
            Task { await sessionManager.stopTracking() }
        } else {
            Task { await sessionManager.startTracking() }
        }
    }
}

#if DEBUG
struct WatchContentView_Previews: PreviewProvider {
    static var previews: some View {
        WatchContentView()
            .environmentObject(WatchSessionManager.shared)
    }
}
#endif
