import Foundation
import WatchConnectivity

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    // MARK: Activation

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("[DreamCue] WCSession activation error: \(error.localizedDescription)")
            return
        }

        switch activationState {
        case .activated:
            print("[DreamCue] WCSession activated.")
            // Flush any messages that were buffered before activation
            flushPendingMessages()
        case .inactive:
            print("[DreamCue] WCSession inactive.")
        case .notActivated:
            print("[DreamCue] WCSession not activated.")
        @unknown default:
            print("[DreamCue] WCSession unknown activation state: \(activationState.rawValue)")
        }
    }

    // MARK: Reachability

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[DreamCue] WCSession reachability changed: \(session.isReachable)")
        if session.isReachable {
            flushPendingMessages()
        }
    }

    // MARK: Receive Messages from iPhone

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        handleIncomingMessage(message)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleIncomingMessage(message)

        // Acknowledge the message
        let response: [String: Any] = [
            "status": "ok",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        replyHandler(response)
    }

    // MARK: Application Context

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        // Handle any context updates sent from the iPhone
        if let command = applicationContext["command"] as? String {
            processCommand(command, payload: applicationContext)
        }
    }

    // MARK: User Info

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any]
    ) {
        if let command = userInfo["command"] as? String {
            processCommand(command, payload: userInfo)
        }
    }

    // MARK: - Private Helpers

    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let command = message["command"] as? String else {
            print("[DreamCue] Received message without 'command' key: \(message)")
            return
        }
        processCommand(command, payload: message)
    }

    private func processCommand(_ command: String, payload: [String: Any]) {
        print("[DreamCue] Received command from iPhone: \(command)")

        switch command.lowercased() {
        case "start":
            Task {
                await startTracking()
            }

        case "stop":
            Task {
                await stopTracking()
            }

        case "set_stage":
            // iPhone can push detected sleep stage to watch display
            if let stage = payload["stage"] as? String {
                let validStages = ["AWAKE", "LIGHT", "DEEP", "REM"]
                let normalised = stage.uppercased()
                if validStages.contains(normalised) {
                    updateStage(normalised)
                }
            }

        case "ping":
            // Respond to a reachability check — reply is handled in the reply-handler variant
            print("[DreamCue] Ping received from iPhone.")

        default:
            print("[DreamCue] Unknown command '\(command)' — ignoring.")
        }
    }
}
