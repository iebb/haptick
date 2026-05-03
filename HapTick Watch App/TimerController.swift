import Foundation
import CoreMotion
import os
import WatchKit

@MainActor
final class TimerController: NSObject, ObservableObject {
    @Published var intervalSeconds: Double = 1.0 {
        didSet {
            let normalized = Self.normalizedInterval(intervalSeconds)
            if intervalSeconds != normalized {
                intervalSeconds = normalized
                return
            }

            UserDefaults.standard.set(intervalSeconds, forKey: Self.intervalKey)

            guard isRunning else { return }
            anchorDate = Date()
            nextPulseDate = anchorDate.addingTimeInterval(intervalSeconds)
            scheduleNextPulse()
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var anchorDate = Date()
    @Published private(set) var nextPulseDate = Date().addingTimeInterval(1)
    @Published private(set) var pulseCount = 0
    @Published var hapticStyle: HapticStyle = .notification {
        didSet {
            UserDefaults.standard.set(hapticStyle.rawValue, forKey: Self.hapticStyleKey)
        }
    }
    @Published var motionToggleEnabled = false {
        didSet {
            UserDefaults.standard.set(motionToggleEnabled, forKey: Self.motionToggleKey)
            motionToggleEnabled ? startMotionDetection() : stopMotionDetection()
        }
    }
    @Published var displayMode: DisplayMode = .interval {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: Self.displayModeKey)
        }
    }

    private var pulseTimer: Timer?
    private var runtimeSession: WKExtendedRuntimeSession?
    private let motionManager = CMMotionManager()
    private let motionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ad.neko.haptick.watchapp", category: "Motion")
    private var lastSuccessfulFlipDate = Date.distantPast
    private var lastGravityZ: Double?
    private var lastStableFlipSign: Int?
    private var lastStableFlipDate = Date.distantPast
    private var motionToggleArmed = true
    private var lastMotionSampleLogDate = Date.distantPast

    static let minimumInterval = 0.8
    static let maximumInterval = 60.0
    private static let mediumIntervalThreshold = 15.0
    private static let slowIntervalThreshold = 30.0
    private static let mediumIntervalPosition = 142.0
    private static let slowIntervalPosition = 217.0
    private static let maximumIntervalPosition = 277.0
    static let minimumBPM = 1.0
    static let maximumBPM = 75.0
    private static let motionToggleCooldown: TimeInterval = 5.0
    private static let maximumFlipDuration: TimeInterval = 1.0
    private static let motionRearmAccelerationThreshold = 0.28
    private static let flipGravityThreshold = 0.6
    private static let intervalKey = "timer.intervalSeconds"
    private static let hapticStyleKey = "timer.hapticStyle"
    private static let motionToggleKey = "timer.motionToggleEnabled"
    private static let displayModeKey = "timer.displayMode"

    override init() {
        let defaults = UserDefaults.standard
        let savedInterval = defaults.object(forKey: Self.intervalKey) as? Double ?? 1.0
        intervalSeconds = Self.normalizedInterval(savedInterval)

        if let rawStyle = defaults.string(forKey: Self.hapticStyleKey),
           let savedStyle = HapticStyle(rawValue: rawStyle) {
            hapticStyle = savedStyle
        }

        if let rawMode = defaults.string(forKey: Self.displayModeKey),
           let savedMode = DisplayMode(rawValue: rawMode) {
            displayMode = savedMode
        }

        motionToggleEnabled = defaults.bool(forKey: Self.motionToggleKey)
        super.init()

        if motionToggleEnabled {
            startMotionDetection()
        }
    }

    var intervalLabel: String {
        String(format: "%.1fs", intervalSeconds)
    }

    var primaryValueLabel: String {
        switch displayMode {
        case .interval:
            intervalLabel
        case .bpm:
            bpmLabel
        }
    }

    var unitLabel: String {
        switch displayMode {
        case .interval: "interval"
        case .bpm: "BPM"
        }
    }

    var topLabel: String {
        isRunning ? "\(pulseCount)" : "ready"
    }

    var crownValue: Double {
        switch displayMode {
        case .interval:
            Self.intervalPosition(for: intervalSeconds)
        case .bpm:
            bpmValue
        }
    }

    var crownLowerBound: Double {
        switch displayMode {
        case .interval: 0
        case .bpm: Self.minimumBPM
        }
    }

    var crownUpperBound: Double {
        switch displayMode {
        case .interval: Self.maximumIntervalPosition
        case .bpm: Self.maximumBPM
        }
    }

    var crownStep: Double {
        switch displayMode {
        case .interval: 1
        case .bpm: bpmValue <= 10 ? 0.1 : 1.0
        }
    }

    func updateCrownValue(_ value: Double) {
        switch displayMode {
        case .interval:
            intervalSeconds = Self.interval(forPosition: value)
        case .bpm:
            let clampedBPM = min(max(value, Self.minimumBPM), Self.maximumBPM)
            let bpm = clampedBPM < 10 ? (clampedBPM * 10).rounded() / 10 : clampedBPM.rounded()
            intervalSeconds = 60 / bpm
        }
    }

    func toggleDisplayMode() {
        displayMode = displayMode == .interval ? .bpm : .interval
    }

    func toggleRunning() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        pulseCount = 0
        anchorDate = Date()
        nextPulseDate = anchorDate.addingTimeInterval(intervalSeconds)
        startRuntimeSession()
        scheduleNextPulse()
    }

    func stop() {
        isRunning = false
        pulseTimer?.invalidate()
        pulseTimer = nil
        runtimeSession?.invalidate()
        runtimeSession = nil
        pulseCount = 0
        anchorDate = Date()
        nextPulseDate = anchorDate.addingTimeInterval(intervalSeconds)
    }

    func pulseNow() {
        WKInterfaceDevice.current().play(hapticStyle.type)
    }

    func spinnerRotation(at date: Date) -> Double {
        guard isRunning else { return -90 }

        return spinnerPhase(at: date) * 360 - 90
    }

    func spinnerPhase(at date: Date) -> Double {
        guard isRunning else { return 0 }

        let elapsed = date.timeIntervalSince(anchorDate)
        return elapsed.truncatingRemainder(dividingBy: intervalSeconds) / intervalSeconds
    }

    func remainingLabel(at date: Date) -> String {
        guard isRunning else { return "ready" }

        let remaining = max(nextPulseDate.timeIntervalSince(date), 0)
        return String(format: "%.1fs", remaining)
    }

    private func scheduleNextPulse() {
        pulseTimer?.invalidate()

        let delay = max(nextPulseDate.timeIntervalSinceNow, 0.05)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.firePulse()
            }
        }
        pulseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func firePulse() {
        guard isRunning else { return }

        pulseNow()
        pulseCount += 1
        anchorDate = Date()
        nextPulseDate = anchorDate.addingTimeInterval(intervalSeconds)
        scheduleNextPulse()
    }

    private func startRuntimeSession() {
        runtimeSession?.invalidate()
        let session = WKExtendedRuntimeSession()
        session.delegate = self
        runtimeSession = session
        session.start()
    }

    private static func normalizedInterval(_ value: Double) -> Double {
        min(max(value, minimumInterval), maximumInterval)
    }

    private static func intervalPosition(for value: Double) -> Double {
        let interval = normalizedInterval(value)

        if interval <= mediumIntervalThreshold {
            return ((interval - minimumInterval) / 0.1).rounded()
        }

        if interval <= slowIntervalThreshold {
            return mediumIntervalPosition + ((interval - mediumIntervalThreshold) / 0.2).rounded()
        }

        return slowIntervalPosition + ((interval - slowIntervalThreshold) / 0.5).rounded()
    }

    private static func interval(forPosition value: Double) -> Double {
        let position = min(max(value.rounded(), 0), maximumIntervalPosition)
        let interval: Double

        if position <= mediumIntervalPosition {
            interval = minimumInterval + position * 0.1
        } else if position <= slowIntervalPosition {
            interval = mediumIntervalThreshold + (position - mediumIntervalPosition) * 0.2
        } else {
            interval = slowIntervalThreshold + (position - slowIntervalPosition) * 0.5
        }

        return normalizedInterval((interval * 10).rounded() / 10)
    }

    private var bpmValue: Double {
        min(max(60 / intervalSeconds, Self.minimumBPM), Self.maximumBPM)
    }

    private var bpmLabel: String {
        if bpmValue < 10 {
            String(format: "%.1f", bpmValue)
        } else {
            "\(Int(bpmValue.rounded()))"
        }
    }

    private func startMotionDetection() {
        guard motionManager.isDeviceMotionAvailable else {
            motionLogger.error("Motion start failed: device motion is unavailable")
            return
        }

        motionLogger.info("Motion detection starting")
        motionManager.deviceMotionUpdateInterval = 0.08
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            if let error {
                Task { @MainActor in
                    self?.motionLogger.error("Motion update error: \(error.localizedDescription, privacy: .public)")
                }
                return
            }

            guard let motion else {
                Task { @MainActor in
                    self?.motionLogger.warning("Motion update missing sample")
                }
                return
            }

            Task { @MainActor in
                self?.handleMotionUpdate(motion)
            }
        }
    }

    private func stopMotionDetection() {
        motionManager.stopDeviceMotionUpdates()
        lastGravityZ = nil
        lastStableFlipSign = nil
        lastStableFlipDate = Date.distantPast
        motionToggleArmed = true
        motionLogger.info("Motion detection stopped")
    }

    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        let now = Date()
        let acceleration = motion.userAcceleration
        let accelerationMagnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )

        let gravityZ = motion.gravity.z
        let previousGravityZ = lastGravityZ
        lastGravityZ = gravityZ

        let cooldownElapsed = now.timeIntervalSince(lastSuccessfulFlipDate) >= Self.motionToggleCooldown
        if cooldownElapsed && accelerationMagnitude < Self.motionRearmAccelerationThreshold {
            if !motionToggleArmed {
                motionLogger.info("Motion re-armed after settling")
            }
            motionToggleArmed = true
        }

        logMotionSample(
            now: now,
            gravityZ: gravityZ,
            previousGravityZ: previousGravityZ,
            accelerationMagnitude: accelerationMagnitude,
            cooldownElapsed: cooldownElapsed
        )

        guard motionToggleArmed && cooldownElapsed else { return }

        guard abs(gravityZ) >= Self.flipGravityThreshold else { return }

        let stableSign = gravityZ >= 0 ? 1 : -1
        guard let previousStableSign = lastStableFlipSign else {
            lastStableFlipSign = stableSign
            lastStableFlipDate = now
            motionLogger.info("Initial flip orientation recorded: sign=\(stableSign, privacy: .public) z=\(gravityZ, privacy: .public)")
            return
        }

        guard previousStableSign != stableSign else {
            lastStableFlipSign = stableSign
            lastStableFlipDate = now
            return
        }

        let flipDuration = now.timeIntervalSince(lastStableFlipDate)
        lastStableFlipSign = stableSign
        lastStableFlipDate = now

        guard flipDuration <= Self.maximumFlipDuration else {
            motionLogger.info("Slow flip rejected: duration=\(flipDuration, privacy: .public) previousSign=\(previousStableSign, privacy: .public) currentSign=\(stableSign, privacy: .public)")
            return
        }

        motionToggleArmed = false
        lastSuccessfulFlipDate = now
        toggleRunning()
        motionLogger.info("Flip accepted: duration=\(flipDuration, privacy: .public) previousSign=\(previousStableSign, privacy: .public) currentSign=\(stableSign, privacy: .public) z=\(gravityZ, privacy: .public) timer isRunning=\(self.isRunning, privacy: .public)")
        WKInterfaceDevice.current().play(.click)
    }

    private func logMotionSample(
        now: Date,
        gravityZ: Double,
        previousGravityZ: Double?,
        accelerationMagnitude: Double,
        cooldownElapsed: Bool
    ) {
        guard now.timeIntervalSince(lastMotionSampleLogDate) >= 0.5 else { return }
        lastMotionSampleLogDate = now

        let previousDescription = previousGravityZ.map { String(format: "%.3f", $0) } ?? "nil"
        let message = String(
            format: "Motion sample: previousZ=%@ currentZ=%.3f acc=%.3f armed=%@ cooldown=%@",
            previousDescription,
            gravityZ,
            accelerationMagnitude,
            String(motionToggleArmed),
            String(cooldownElapsed)
        )
        motionLogger.debug("\(message, privacy: .public)")
    }

}

enum DisplayMode: String {
    case interval
    case bpm
}

enum HapticStyle: String, CaseIterable, Identifiable {
    case notification
    case directionUp
    case directionDown
    case success
    case failure
    case retry
    case start
    case stop
    case click

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notification: "Notification"
        case .directionUp: "Direction Up"
        case .directionDown: "Direction Down"
        case .success: "Success"
        case .failure: "Failure"
        case .retry: "Retry"
        case .start: "Start"
        case .stop: "Stop"
        case .click: "Click"
        }
    }

    var symbolName: String {
        switch self {
        case .notification: "bell"
        case .directionUp: "arrow.up"
        case .directionDown: "arrow.down"
        case .success: "checkmark"
        case .failure: "xmark"
        case .retry: "arrow.clockwise"
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .click: "smallcircle.filled.circle"
        }
    }

    var type: WKHapticType {
        switch self {
        case .notification: .notification
        case .directionUp: .directionUp
        case .directionDown: .directionDown
        case .success: .success
        case .failure: .failure
        case .retry: .retry
        case .start: .start
        case .stop: .stop
        case .click: .click
        }
    }
}

extension TimerController: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {}
}
