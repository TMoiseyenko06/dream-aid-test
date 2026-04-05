import Foundation
import WatchConnectivity
import Combine

final class WatchConnectivityManager: NSObject, ObservableObject {

    // MARK: - Published properties
    @Published var isWatchReachable: Bool = false
    @Published var isWatchPaired: Bool = false
    @Published var lastWatchMessage: [String: Any]? = nil

    // MARK: - Callback
    /// Set by the owner (e.g., SessionManager) to receive watch messages.
    var onMessageReceived: (([String: Any]) -> Void)?

    // MARK: - Private
    private var session: WCSession?
    private var pendingMessages: [[String: Any]] = []
    private let pendingMessagesQueue = DispatchQueue(label: "com.dreamcue.pendingMessages")

    // MARK: - Init

    override init() {
        super.init()
        activateIfSupported()
    }

    private func activateIfSupported() {
        guard WCSession.isSupported() else { return }
        let wcSession = WCSession.default
        wcSession.delegate = self
        wcSession.activate()
        session = wcSession
    }

    // MARK: - Public commands

    /// Sends a start command to the paired Apple Watch.
    func sendStartCommand() {
        sendMessage(["command": "start"])
    }

    /// Sends a stop command to the paired Apple Watch.
    func sendStopCommand() {
        sendMessage(["command": "stop"])
    }

    // MARK: - Private message dispatch

    private func sendMessage(_ message: [String: Any]) {
        guard let session = session, session.isPaired else { return }

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                // If it fails despite reachability, buffer it
                self?.bufferMessage(message)
            }
        } else {
            // Buffer for when watch becomes reachable
            bufferMessage(message)

            // Also try via applicationContext as a best-effort fallback
            try? session.updateApplicationContext(message)
        }
    }

    private func bufferMessage(_ message: [String: Any]) {
        pendingMessagesQueue.async { [weak self] in
            self?.pendingMessages.append(message)
        }
    }

    private func flushPendingMessages() {
        guard let session = session, session.isReachable else { return }

        pendingMessagesQueue.async { [weak self] in
            guard let self else { return }
            let messages = self.pendingMessages
            self.pendingMessages.removeAll()

            for message in messages {
                session.sendMessage(message, replyHandler: nil) { [weak self] error in
                    self?.bufferMessage(message)
                }
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isWatchPaired = session.isPaired
            self.isWatchReachable = session.isReachable

            if activationState == .activated {
                self.flushPendingMessages()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isWatchReachable = session.isReachable
            self.isWatchPaired = session.isPaired

            if session.isReachable {
                self.flushPendingMessages()
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastWatchMessage = message
            self.isWatchReachable = session.isReachable
            self.onMessageReceived?(message)
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastWatchMessage = message
            self.isWatchReachable = session.isReachable
            self.onMessageReceived?(message)
        }
        // Acknowledge receipt
        replyHandler(["status": "received"])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastWatchMessage = applicationContext
            self.onMessageReceived?(applicationContext)
        }
    }

    // Required on iOS
    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isWatchReachable = false
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isWatchReachable = false
        }
        // Re-activate after deactivation (e.g., watch switch)
        session.activate()
    }
}
