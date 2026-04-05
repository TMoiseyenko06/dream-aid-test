import SwiftUI

struct TonightView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var watchConnectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Watch disconnected banner
                        if !watchConnectivity.isWatchReachable {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.yellow)
                                Text("Watch not connected — using phone sensors")
                                    .font(.subheadline)
                                    .foregroundColor(.yellow)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.yellow.opacity(0.15))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        }

                        // Sleep stage card
                        SleepStageCard(stage: sessionManager.currentStage,
                                       timeInStage: sessionManager.timeInCurrentStage)

                        // HR / HRV card
                        BiometricsCard(hr: sessionManager.currentHR,
                                       hrv: sessionManager.currentHRV,
                                       source: sessionManager.dataSource)

                        // Movement card
                        MovementCard(level: sessionManager.movementLevel)

                        // Tonight stats card
                        StatsCard(sessionStartTime: sessionManager.sessionStartTime,
                                  totalREMMinutes: sessionManager.totalREMMinutes,
                                  cuesFired: sessionManager.cuesFired)

                        // Connection status row
                        ConnectionStatusRow(isWatchReachable: watchConnectivity.isWatchReachable,
                                            isWatchPaired: watchConnectivity.isWatchPaired,
                                            watchBattery: sessionManager.watchBattery,
                                            dataSource: sessionManager.dataSource)

                        // START / STOP button
                        SessionButton(isActive: sessionManager.isSessionActive) {
                            Task {
                                if sessionManager.isSessionActive {
                                    await sessionManager.stopSession()
                                    watchConnectivity.sendStopCommand()
                                } else {
                                    await sessionManager.startSession()
                                    watchConnectivity.sendStartCommand()
                                }
                            }
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 12)
                }
            }
            .navigationTitle("DreamCue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Sub-views

private struct SleepStageCard: View {
    let stage: SleepStage
    let timeInStage: TimeInterval

    var body: some View {
        VStack(spacing: 8) {
            Text("SLEEP STAGE")
                .font(.caption)
                .foregroundColor(.gray)
                .tracking(1.5)

            Text(stage.displayName)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundColor(stage.color)

            Text(formatDuration(timeInStage))
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(stage.color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(stage.color.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s in stage"
        } else {
            return "\(seconds)s in stage"
        }
    }
}

private struct BiometricsCard: View {
    let hr: Double?
    let hrv: Double?
    let source: DataSource

    var body: some View {
        HStack(spacing: 0) {
            BiometricCell(
                label: "HEART RATE",
                value: hr.map { String(format: "%.0f", $0) } ?? "--",
                unit: "BPM",
                icon: "heart.fill",
                iconColor: .red
            )

            Divider()
                .background(Color.gray.opacity(0.4))
                .frame(height: 60)

            BiometricCell(
                label: "HRV",
                value: hrv.map { String(format: "%.1f", $0) } ?? "--",
                unit: "ms",
                icon: "waveform.path.ecg",
                iconColor: .green
            )
        }
        .overlay(alignment: .bottomTrailing) {
            SourceBadge(source: source)
                .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

private struct BiometricCell: View {
    let label: String
    let value: String
    let unit: String
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.caption)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .tracking(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

private struct SourceBadge: View {
    let source: DataSource

    var body: some View {
        Text(source == .watch ? "Watch" : "Phone")
            .font(.caption2)
            .foregroundColor(source == .watch ? .cyan : .orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill((source == .watch ? Color.cyan : Color.orange).opacity(0.15))
            )
    }
}

private struct MovementCard: View {
    let level: MovementLevel

    var levelColor: Color {
        switch level {
        case .calm: return .green
        case .someMovement: return .yellow
        case .active: return .orange
        }
    }

    var levelLabel: String {
        switch level {
        case .calm: return "Calm"
        case .someMovement: return "Some Movement"
        case .active: return "Active"
        }
    }

    var filledBars: Int {
        switch level {
        case .calm: return 1
        case .someMovement: return 2
        case .active: return 3
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MOVEMENT")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .tracking(1.5)
                Text(levelLabel)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(levelColor)
            }

            Spacer()

            HStack(spacing: 5) {
                ForEach(1...3, id: \.self) { bar in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bar <= filledBars ? levelColor : Color.white.opacity(0.15))
                        .frame(width: 10, height: CGFloat(bar) * 10 + 10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

private struct StatsCard: View {
    let sessionStartTime: Date?
    let totalREMMinutes: Double
    let cuesFired: Int

    var timeAsleep: String {
        guard let start = sessionStartTime else { return "--" }
        let elapsed = Date().timeIntervalSince(start)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TONIGHT")
                .font(.caption)
                .foregroundColor(.gray)
                .tracking(1.5)

            HStack(spacing: 0) {
                StatCell(label: "Time Asleep", value: timeAsleep)
                Divider().background(Color.gray.opacity(0.3)).frame(height: 40)
                StatCell(label: "REM Time", value: String(format: "%.0fm", totalREMMinutes))
                Divider().background(Color.gray.opacity(0.3)).frame(height: 40)
                StatCell(label: "Cues Fired", value: "\(cuesFired)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
}

private struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ConnectionStatusRow: View {
    let isWatchReachable: Bool
    let isWatchPaired: Bool
    let watchBattery: Double?
    let dataSource: DataSource

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(isWatchReachable ? Color.green : Color.yellow)
                .frame(width: 10, height: 10)

            Text(isWatchReachable ? "Apple Watch connected" : "Phone sensors only")
                .font(.subheadline)
                .foregroundColor(isWatchReachable ? .green : .yellow)

            Spacer()

            if let battery = watchBattery, isWatchReachable {
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon(battery))
                        .foregroundColor(batteryColor(battery))
                        .font(.caption)
                    Text(String(format: "%.0f%%", battery * 100))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.04))
        )
        .padding(.horizontal)
    }

    private func batteryIcon(_ level: Double) -> String {
        switch level {
        case 0.75...: return "battery.100"
        case 0.50...: return "battery.75"
        case 0.25...: return "battery.50"
        case 0.10...: return "battery.25"
        default: return "battery.0"
        }
    }

    private func batteryColor(_ level: Double) -> Color {
        level < 0.20 ? .red : .gray
    }
}

private struct SessionButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isActive ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                Text(isActive ? "Stop Session" : "Start Session")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isActive ? Color.red.opacity(0.8) : Color.indigo.opacity(0.9))
            )
        }
        .padding(.horizontal)
        .buttonStyle(.plain)
    }
}

#Preview {
    TonightView()
        .environmentObject(SessionManager())
        .environmentObject(WatchConnectivityManager())
}
