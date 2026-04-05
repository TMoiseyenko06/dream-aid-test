import SwiftUI

struct SettingsView: View {
    // MARK: - UserDefaults-backed state
    @AppStorage("backendURL") private var backendURL: String = "http://localhost:8000"
    @AppStorage("cueEnabled") private var cueEnabled: Bool = true
    @AppStorage("minREMMinutes") private var minREMMinutes: Double = 5
    @AppStorage("cueIntervalSeconds") private var cueIntervalSeconds: Double = 120

    // MARK: - Transient UI state
    @State private var connectionStatus: ConnectionTestResult = .idle
    @State private var isTestingConnection: Bool = false
    @State private var isTestingCue: Bool = false
    @State private var cueTestResult: String? = nil
    @State private var isResettingSession: Bool = false
    @State private var resetResult: String? = nil
    @State private var urlEditBuffer: String = ""
    @FocusState private var urlFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Form {
                    // MARK: Backend
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Backend URL")
                                .font(.caption)
                                .foregroundColor(.gray)

                            TextField("http://localhost:8000", text: $backendURL)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($urlFieldFocused)
                                .foregroundColor(.white)
                        }

                        // Test Connection
                        HStack {
                            Button {
                                urlFieldFocused = false
                                Task { await testConnection() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isTestingConnection {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.75)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "network")
                                    }
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTestingConnection)

                            Spacer()

                            connectionStatusView
                        }

                        // Test Cue
                        HStack {
                            Button {
                                Task { await testCue() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isTestingCue {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .scaleEffect(0.75)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "bell.badge")
                                    }
                                    Text("Test Cue")
                                }
                            }
                            .disabled(isTestingCue)

                            Spacer()

                            if let result = cueTestResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(result.hasPrefix("OK") ? .green : .red)
                            }
                        }

                    } header: {
                        Text("Backend")
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    // MARK: Cue Settings
                    Section {
                        Toggle("Cue Enabled", isOn: $cueEnabled)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Min REM Duration")
                                Spacer()
                                Text("\(Int(minREMMinutes)) min")
                                    .foregroundColor(.gray)
                                    .monospacedDigit()
                            }
                            Slider(value: $minREMMinutes, in: 3...15, step: 1)
                                .tint(.purple)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Cue Interval")
                                Spacer()
                                Text("\(Int(cueIntervalSeconds))s")
                                    .foregroundColor(.gray)
                                    .monospacedDigit()
                            }
                            Slider(value: $cueIntervalSeconds, in: 60...300, step: 10)
                                .tint(.indigo)
                        }

                    } header: {
                        Text("Cue Settings")
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    // MARK: Session
                    Section {
                        Button(role: .destructive) {
                            Task { await resetSession() }
                        } label: {
                            HStack(spacing: 6) {
                                if isResettingSession {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.75)
                                        .tint(.red)
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                Text("Reset Session")
                            }
                        }
                        .disabled(isResettingSession)

                        if let result = resetResult {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.hasPrefix("OK") ? .green : .red)
                        }
                    } header: {
                        Text("Session")
                    } footer: {
                        Text("Ends the current session on the backend and immediately starts a new one.")
                    }
                    .listRowBackground(Color.white.opacity(0.06))

                    // MARK: About
                    Section {
                        LabeledContent("App Version") {
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                                .foregroundColor(.gray)
                        }
                        LabeledContent("Build") {
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                                .foregroundColor(.gray)
                        }
                    } header: {
                        Text("About")
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Connection status badge

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .scaleEffect(0.7)
        case .success(let ms):
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("\(ms) ms")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        case .failure(let msg):
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Actions

    private func testConnection() async {
        isTestingConnection = true
        connectionStatus = .testing
        defer { isTestingConnection = false }

        guard let url = URL(string: backendURL.trimmingCharacters(in: .whitespaces) + "/api/health") else {
            connectionStatus = .failure("Bad URL")
            return
        }

        do {
            let start = Date()
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.httpMethod = "GET"
            let (_, response) = try await URLSession.shared.data(for: request)
            let latency = Int(Date().timeIntervalSince(start) * 1000)

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                connectionStatus = .success(latency)
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                connectionStatus = .failure("HTTP \(code)")
            }
        } catch {
            connectionStatus = .failure(shortErrorMessage(error))
        }
    }

    private func testCue() async {
        isTestingCue = true
        cueTestResult = nil
        defer { isTestingCue = false }

        guard let url = URL(string: backendURL.trimmingCharacters(in: .whitespaces) + "/api/test-cue") else {
            cueTestResult = "Bad URL"
            return
        }

        do {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                cueTestResult = "OK"
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                cueTestResult = "HTTP \(code)"
            }
        } catch {
            cueTestResult = shortErrorMessage(error)
        }
    }

    private func resetSession() async {
        isResettingSession = true
        resetResult = nil
        defer { isResettingSession = false }

        let base = backendURL.trimmingCharacters(in: .whitespaces)

        // End existing session
        if let endURL = URL(string: base + "/api/session/end") {
            var request = URLRequest(url: endURL, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            _ = try? await URLSession.shared.data(for: request)
        }

        // Start new session
        guard let startURL = URL(string: base + "/api/session/start") else {
            resetResult = "Bad URL"
            return
        }

        do {
            var request = URLRequest(url: startURL, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                resetResult = "OK — new session started"
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                resetResult = "HTTP \(code)"
            }
        } catch {
            resetResult = shortErrorMessage(error)
        }
    }

    private func shortErrorMessage(_ error: Error) -> String {
        let msg = error.localizedDescription
        return msg.count > 40 ? String(msg.prefix(40)) + "…" : msg
    }
}

// MARK: - Supporting types

private enum ConnectionTestResult {
    case idle
    case testing
    case success(Int)   // latency in ms
    case failure(String)
}

#Preview {
    SettingsView()
}
