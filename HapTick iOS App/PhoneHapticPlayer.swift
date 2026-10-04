import CoreHaptics
import Foundation

/// Core Haptics schedules the entire composition, including the gap at its loop boundary.
@MainActor
final class PhoneHapticPlayer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status: String?
    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var playingSettings: HapTickSettings?
    private var playbackGeneration = UUID()

    func start(_ settings: HapTickSettings) {
        stop()
        guard supportsHaptics else {
            status = L10n.text("Haptics are unavailable on this device.")
            return
        }
        guard !settings.isBelowStyleMinimum else {
            status = settings.styleSpeedWarning
            return
        }

        do {
            let generation = playbackGeneration
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    guard self?.playbackGeneration == generation else { return }
                    self?.stop()
                    self?.status = L10n.text("Playback stopped. Tap Start to resume.")
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    guard self?.playbackGeneration == generation else { return }
                    self?.stop()
                    self?.status = L10n.text("Playback stopped. Tap Start to resume.")
                }
            }
            self.engine = engine
            try engine.start()

            let events = settings.playbackStyles.enumerated().flatMap { index, style in
                style.phoneEvents(at: Double(index) * settings.intervalSeconds)
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            player.loopEnabled = true
            player.loopEnd = Double(settings.playbackStyles.count) * settings.intervalSeconds
            self.player = player
            try player.start(atTime: CHHapticTimeImmediate)
            playingSettings = settings
            isRunning = true
            status = nil
        } catch {
            stop()
            status = L10n.text("Could not start haptics. Try again.")
        }
    }

    func update(_ settings: HapTickSettings) {
        guard isRunning, let previous = playingSettings else { return }
        guard previous.intervalSeconds != settings.intervalSeconds || previous.playbackStyles != settings.playbackStyles else { return }
        start(settings)
    }

    func stop() {
        // Detach callbacks before deliberately stopping the engine.
        playbackGeneration = UUID()
        engine?.stoppedHandler = { _ in }
        engine?.resetHandler = {}
        try? player?.stop(atTime: CHHapticTimeImmediate)
        engine?.stop(completionHandler: nil)
        player = nil
        engine = nil
        playingSettings = nil
        isRunning = false
        status = nil
    }
}

private extension HapticStyle {
    func phoneEvents(at time: TimeInterval) -> [CHHapticEvent] {
        let pulses: [(offset: Double, intensity: Float, sharpness: Float)]
        switch self {
        case .notification: pulses = [(0, 0.8, 0.5), (0.12, 0.8, 0.5), (0.24, 1, 0.6)]
        case .directionUp: pulses = [(0, 0.45, 0.3), (0.08, 1, 0.8)]
        case .directionDown: pulses = [(0, 1, 0.8), (0.08, 0.45, 0.3)]
        case .success: pulses = [(0, 0.5, 0.4), (0.10, 1, 0.7)]
        case .failure: pulses = [(0, 1, 0.9), (0.10, 0.6, 0.7), (0.20, 1, 0.9)]
        case .retry: pulses = [(0, 0.6, 0.7), (0.12, 0.6, 0.7), (0.22, 0.8, 0.8)]
        case .start: pulses = [(0, 1, 0.65)]
        case .stop: pulses = [(0, 0.7, 0.2), (0.10, 0.4, 0.1)]
        case .click: pulses = [(0, 0.5, 1)]
        }
        return pulses.map { pulse in
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness)
            ], relativeTime: time + pulse.offset)
        }
    }
}
