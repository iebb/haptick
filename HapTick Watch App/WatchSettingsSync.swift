import Foundation
import WatchConnectivity

@MainActor
final class WatchSettingsSync: NSObject, WCSessionDelegate {
    var onSettingsReceived: ((HapTickSettings) -> Void)?
    var onPlaybackCommandReceived: ((HapTickPlaybackCommand) -> Void)?

    private var session: WCSession?

    func activate() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    func send(_ settings: HapTickSettings) {
        guard let session else { return }

        try? session.updateApplicationContext(settings.dictionary)

        if session.isReachable {
            session.sendMessage(settings.dictionary, replyHandler: nil)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            onSettingsReceived?(HapTickSettings(dictionary: applicationContext, fallback: .load()))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            onSettingsReceived?(HapTickSettings(dictionary: message, fallback: .load()))

            if let rawCommand = message[HapTickMessage.playbackCommandKey] as? String,
               let command = HapTickPlaybackCommand(rawValue: rawCommand) {
                onPlaybackCommandReceived?(command)
            }
        }
    }
}
