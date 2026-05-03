import Foundation
import WatchConnectivity

@MainActor
final class PhoneSettingsStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var settings: HapTickSettings
    @Published private(set) var syncStatus = "Opening Watch link..."

    private var session: WCSession?

    override init() {
        settings = HapTickSettings.load()
        super.init()

        activateSession()
    }

    func update(_ transform: (inout HapTickSettings) -> Void) {
        var nextSettings = settings
        transform(&nextSettings)
        nextSettings.intervalSeconds = HapTickSettings.normalizedInterval(nextSettings.intervalSeconds)
        apply(nextSettings, shouldSend: true)
    }

    func setIntervalPosition(_ position: Double) {
        update { settings in
            settings.intervalSeconds = HapTickSettings.interval(forPosition: position)
        }
    }

    func setBPM(_ bpm: Double) {
        update { settings in
            settings.intervalSeconds = HapTickSettings.interval(forBPM: bpm)
        }
    }

    func sendCurrentSettings() {
        send(settings)
    }

    private func activateSession() {
        guard WCSession.isSupported() else {
            syncStatus = "Watch sync unavailable on this device"
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    private func apply(_ nextSettings: HapTickSettings, shouldSend: Bool) {
        guard settings != nextSettings else { return }

        settings = nextSettings
        settings.save()

        if shouldSend {
            send(nextSettings)
        }
    }

    private func send(_ settings: HapTickSettings) {
        guard let session else { return }

        do {
            try session.updateApplicationContext(settings.dictionary)
            syncStatus = "Settings queued for Apple Watch"
        } catch {
            syncStatus = "Could not queue settings"
        }

        if session.isReachable {
            session.sendMessage(settings.dictionary, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.syncStatus = "Could not reach Apple Watch"
                }
            }
            syncStatus = "Sent to Apple Watch"
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                syncStatus = "Watch sync failed: \(error.localizedDescription)"
            } else {
                syncStatus = activationState == .activated ? "Watch link active" : "Watch link inactive"
                sendCurrentSettings()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            apply(HapTickSettings(dictionary: applicationContext), shouldSend: false)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            apply(HapTickSettings(dictionary: message), shouldSend: false)
        }
    }
}
