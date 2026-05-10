import Foundation
import CoreMotion
import os
import WatchKit

@MainActor
final class TimerController: NSObject, ObservableObject {
    @Published var intervalSeconds: Double = 1.0 {
        didSet {
            let normalized = HapTickSettings.normalizedInterval(intervalSeconds)
            if intervalSeconds != normalized {
                intervalSeconds = normalized
                return
            }

            persistAndBroadcastSettings()

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
            persistAndBroadcastSettings()
        }
    }
    @Published var motionToggleEnabled = false {
        didSet {
            persistAndBroadcastSettings()
            motionToggleEnabled ? startMotionDetection() : stopMotionDetection()
        }
    }
    @Published var displayMode: DisplayMode = .interval {
        didSet {
            persistAndBroadcastSettings()
        }
    }
    @Published private var usesSyncedIntervalPrecision = false

    private var pulseTimer: Timer?
    private var runtimeSession: WKExtendedRuntimeSession?
    private var runtimeRestartTask: Task<Void, Never>?
    private let motionManager = CMMotionManager()
    private let motionLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ad.neko.haptick.watchapp", category: "Motion")
    private let runtimeLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ad.neko.haptick.watchapp", category: "Runtime")
    private let settingsSync = WatchSettingsSync()
    private var isApplyingRemoteSettings = false
    private var lastSuccessfulFlipDate = Date.distantPast
    private var lastGravityZ: Double?
    private var lastStableFlipSign: Int?
    private var lastStableFlipDate = Date.distantPast
    private var motionToggleArmed = true
    private var lastMotionSampleLogDate = Date.distantPast

    static let minimumInterval = HapTickSettings.minimumInterval
    static let maximumInterval = HapTickSettings.maximumInterval
    static let minimumBPM = HapTickSettings.minimumBPM
    static let maximumBPM = HapTickSettings.maximumBPM
    private static let motionToggleCooldown: TimeInterval = 5.0
    private static let maximumFlipDuration: TimeInterval = 1.0
    private static let motionRearmAccelerationThreshold = 0.28
    private static let flipGravityThreshold = 0.6
    private static let runtimeRestartDelay: TimeInterval = 1.0

    override init() {
        let settings = HapTickSettings.load()
        intervalSeconds = settings.intervalSeconds
        hapticStyle = settings.hapticStyle
        displayMode = settings.displayMode
        motionToggleEnabled = settings.motionToggleEnabled
        super.init()

        settingsSync.onSettingsReceived = { [weak self] settings in
            self?.apply(settings)
        }
        settingsSync.activate()
        persistAndBroadcastSettings()

        if motionToggleEnabled {
            startMotionDetection()
        }

    }

    var intervalLabel: String {
        currentSettings.intervalLabel(maximumFractionDigits: intervalFractionDigits)
    }

    var primaryValueLabel: String {
        switch displayMode {
        case .interval: intervalLabel
        case .bpm: currentSettings.bpmLabel
        }
    }

    var unitLabel: String {
        currentSettings.unitLabel
    }

    var styleSpeedWarning: String? {
        currentSettings.styleSpeedWarning
    }

    var isBelowStyleMinimum: Bool {
        currentSettings.isBelowStyleMinimum
    }

    func isStyleUnsupported(_ style: HapticStyle) -> Bool {
        currentSettings.isStyleUnsupported(style)
    }

    var topLabel: String {
        isRunning ? "\(pulseCount)" : "ready"
    }

    var crownValue: Double {
        switch displayMode {
        case .interval:
            HapTickSettings.intervalPosition(for: intervalSeconds)
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
        case .interval: HapTickSettings.maximumIntervalPosition
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
        usesSyncedIntervalPrecision = false

        switch displayMode {
        case .interval:
            intervalSeconds = HapTickSettings.interval(forPosition: value)
        case .bpm:
            intervalSeconds = HapTickSettings.interval(forBPM: value)
        }
    }

    func toggleDisplayMode() {
        usesSyncedIntervalPrecision = false
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
        startRuntimeSessionIfNeeded()
        scheduleNextPulse()
    }

    func stop() {
        isRunning = false
        runtimeRestartTask?.cancel()
        runtimeRestartTask = nil
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

    func resumeRuntimeSessionIfNeeded() {
        guard isRunning else { return }

        startRuntimeSessionIfNeeded()
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

    private func startRuntimeSessionIfNeeded() {
        if let runtimeSession {
            switch runtimeSession.state {
            case .running, .scheduled:
                return
            case .notStarted:
                runtimeLogger.info("Starting existing extended runtime session")
                runtimeSession.start()
                return
            case .invalid:
                self.runtimeSession = nil
            @unknown default:
                self.runtimeSession = nil
            }
        }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        runtimeSession = session
        runtimeLogger.info("Starting extended runtime session")
        session.start()
    }

    private func scheduleRuntimeSessionRestart() {
        runtimeRestartTask?.cancel()
        runtimeRestartTask = Task { [weak self] in
            let delay = UInt64(Self.runtimeRestartDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)

            await MainActor.run {
                guard let self, self.isRunning else { return }

                self.runtimeLogger.info("Retrying extended runtime session")
                self.startRuntimeSessionIfNeeded()
            }
        }
    }

    private func handleRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        guard session === runtimeSession else { return }

        runtimeLogger.info("Extended runtime session started")
    }

    private func handleRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        guard session === runtimeSession else { return }

        runtimeLogger.warning("Extended runtime session will expire")
    }

    private func handleRuntimeSessionInvalidation(
        _ session: WKExtendedRuntimeSession,
        reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        guard session === runtimeSession else { return }

        let errorDescription = error?.localizedDescription ?? "none"
        runtimeLogger.warning("Extended runtime session invalidated reason=\(reason.rawValue, privacy: .public) error=\(errorDescription, privacy: .public)")
        runtimeSession = nil

        guard isRunning else { return }

        switch reason {
        case .expired, .suppressedBySystem, .error, .sessionInProgress:
            scheduleRuntimeSessionRestart()
        case .resignedFrontmost:
            stop()
        case .none:
            break
        @unknown default:
            scheduleRuntimeSessionRestart()
        }
    }

    private var bpmValue: Double {
        currentSettings.bpmValue
    }

    private var bpmLabel: String {
        currentSettings.bpmLabel
    }

    private var currentSettings: HapTickSettings {
        HapTickSettings(
            intervalSeconds: intervalSeconds,
            hapticStyle: hapticStyle,
            motionToggleEnabled: motionToggleEnabled,
            displayMode: displayMode
        )
    }

    private var intervalFractionDigits: Int {
        if usesSyncedIntervalPrecision {
            3
        } else {
            intervalSeconds < HapTickSettings.fineIntervalThreshold ? 2 : 1
        }
    }

    private func persistAndBroadcastSettings() {
        guard !isApplyingRemoteSettings else { return }

        let settings = currentSettings
        settings.save()
        settingsSync.send(settings)
    }

    private func apply(_ settings: HapTickSettings) {
        isApplyingRemoteSettings = true
        intervalSeconds = settings.intervalSeconds
        hapticStyle = settings.hapticStyle
        displayMode = settings.displayMode
        motionToggleEnabled = settings.motionToggleEnabled
        usesSyncedIntervalPrecision = true
        isApplyingRemoteSettings = false
        settings.save()
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

extension HapticStyle {
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
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.handleRuntimeSessionDidStart(extendedRuntimeSession)
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.handleRuntimeSessionWillExpire(extendedRuntimeSession)
        }
    }

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            self.handleRuntimeSessionInvalidation(extendedRuntimeSession, reason: reason, error: error)
        }
    }
}
