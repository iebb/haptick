import Foundation

enum DisplayMode: String, CaseIterable, Identifiable, Codable {
    case interval
    case bpm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .interval: "Interval"
        case .bpm: "BPM"
        }
    }
}

enum HapticStyle: String, CaseIterable, Identifiable, Codable {
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

    var recommendedMinimumInterval: Double {
        switch self {
        case .notification: 0.75
        case .directionUp: 0.2
        case .directionDown: 0.2
        case .success: 0.3
        case .failure: 0.35
        case .retry: 0.35
        case .start: 0.2
        case .stop: 0.25
        case .click: 0.2
        }
    }
}

struct HapTickSettings: Equatable, Codable {
    var intervalSeconds: Double
    var hapticStyle: HapticStyle
    var motionToggleEnabled: Bool
    var displayMode: DisplayMode

    static let minimumInterval = 0.2
    static let maximumInterval = 999.0
    static let minimumBPM = 0.1
    static let maximumBPM = 60 / minimumInterval
    static let fineIntervalThreshold = 1.5
    static let mediumIntervalThreshold = 15.0
    static let slowIntervalThreshold = 30.0
    static let fineIntervalStep = 0.05
    static let mediumIntervalStep = 0.1
    static let slowIntervalStep = 0.2
    static let longIntervalStep = 0.5
    static let fineIntervalPosition = ((fineIntervalThreshold - minimumInterval) / fineIntervalStep).rounded()
    static let mediumIntervalPosition = fineIntervalPosition + ((mediumIntervalThreshold - fineIntervalThreshold) / mediumIntervalStep).rounded()
    static let slowIntervalPosition = mediumIntervalPosition + ((slowIntervalThreshold - mediumIntervalThreshold) / slowIntervalStep).rounded()
    static let maximumIntervalPosition = slowIntervalPosition + ((maximumInterval - slowIntervalThreshold) / longIntervalStep).rounded()

    static let intervalKey = "timer.intervalSeconds"
    static let hapticStyleKey = "timer.hapticStyle"
    static let motionToggleKey = "timer.motionToggleEnabled"
    static let displayModeKey = "timer.displayMode"

    init(
        intervalSeconds: Double = 1.0,
        hapticStyle: HapticStyle = .notification,
        motionToggleEnabled: Bool = false,
        displayMode: DisplayMode = .interval
    ) {
        self.intervalSeconds = Self.normalizedInterval(intervalSeconds)
        self.hapticStyle = hapticStyle
        self.motionToggleEnabled = motionToggleEnabled
        self.displayMode = displayMode
    }

    init(dictionary: [String: Any]) {
        let interval = dictionary[Self.intervalKey] as? Double ?? 1.0
        let styleRaw = dictionary[Self.hapticStyleKey] as? String ?? HapticStyle.notification.rawValue
        let modeRaw = dictionary[Self.displayModeKey] as? String ?? DisplayMode.interval.rawValue

        self.init(
            intervalSeconds: interval,
            hapticStyle: HapticStyle(rawValue: styleRaw) ?? .notification,
            motionToggleEnabled: dictionary[Self.motionToggleKey] as? Bool ?? false,
            displayMode: DisplayMode(rawValue: modeRaw) ?? .interval
        )
    }

    var dictionary: [String: Any] {
        [
            Self.intervalKey: intervalSeconds,
            Self.hapticStyleKey: hapticStyle.rawValue,
            Self.motionToggleKey: motionToggleEnabled,
            Self.displayModeKey: displayMode.rawValue
        ]
    }

    var intervalLabel: String {
        intervalLabel(maximumFractionDigits: intervalSeconds < Self.fineIntervalThreshold ? 2 : 1)
    }

    func intervalLabel(maximumFractionDigits: Int) -> String {
        "\(Self.formattedNumber(intervalSeconds, maximumFractionDigits: maximumFractionDigits))s"
    }

    var bpmValue: Double {
        60 / intervalSeconds
    }

    var bpmLabel: String {
        if bpmValue < 10 {
            String(format: "%.1f", bpmValue)
        } else {
            "\(Int(bpmValue.rounded()))"
        }
    }

    var primaryValueLabel: String {
        switch displayMode {
        case .interval: intervalLabel
        case .bpm: bpmLabel
        }
    }

    var unitLabel: String {
        switch displayMode {
        case .interval: "interval"
        case .bpm: "BPM"
        }
    }

    var isBelowSupportedMinimum: Bool {
        intervalSeconds + 0.0001 < Self.minimumInterval
    }

    var isBelowStyleMinimum: Bool {
        isStyleUnsupported(hapticStyle)
    }

    func isStyleUnsupported(_ style: HapticStyle) -> Bool {
        intervalSeconds + 0.0001 < max(Self.minimumInterval, style.recommendedMinimumInterval)
    }

    func styleMinimumIntervalLabel(for style: HapticStyle) -> String {
        let minimum = max(Self.minimumInterval, style.recommendedMinimumInterval)
        let digits = minimum < Self.fineIntervalThreshold ? 2 : 1
        return "\(Self.formattedNumber(minimum, maximumFractionDigits: digits))s"
    }

    var styleMinimumIntervalLabel: String {
        styleMinimumIntervalLabel(for: hapticStyle)
    }

    func styleLimitLabel(for style: HapticStyle) -> String {
        let minimum = max(Self.minimumInterval, style.recommendedMinimumInterval)

        switch displayMode {
        case .interval:
            return styleMinimumIntervalLabel(for: style)
        case .bpm:
            let bpm = 60 / minimum
            let digits = bpm < 10 ? 1 : 0
            return "\(Self.formattedNumber(bpm, maximumFractionDigits: digits)) BPM"
        }
    }

    var styleSpeedWarning: String? {
        if isBelowSupportedMinimum {
            switch displayMode {
            case .interval:
                return "Slow down to at least \(Self.formattedNumber(Self.minimumInterval, maximumFractionDigits: 2))s."
            case .bpm:
                return "Slow down to \(Self.formattedNumber(Self.maximumBPM, maximumFractionDigits: 0)) BPM or lower."
            }
        }

        guard isBelowStyleMinimum else { return nil }

        switch displayMode {
        case .interval:
            return "Slow down to \(styleMinimumIntervalLabel), or choose another supported style."
        case .bpm:
            return "Slow down to \(styleLimitLabel(for: hapticStyle)) or lower, or choose another supported style."
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        let interval = defaults.object(forKey: intervalKey) as? Double ?? 1.0
        let style = defaults.string(forKey: hapticStyleKey).flatMap(HapticStyle.init(rawValue:)) ?? .notification
        let mode = defaults.string(forKey: displayModeKey).flatMap(DisplayMode.init(rawValue:)) ?? .interval

        return Self(
            intervalSeconds: interval,
            hapticStyle: style,
            motionToggleEnabled: defaults.bool(forKey: motionToggleKey),
            displayMode: mode
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(intervalSeconds, forKey: Self.intervalKey)
        defaults.set(hapticStyle.rawValue, forKey: Self.hapticStyleKey)
        defaults.set(motionToggleEnabled, forKey: Self.motionToggleKey)
        defaults.set(displayMode.rawValue, forKey: Self.displayModeKey)
    }

    static func normalizedInterval(_ value: Double) -> Double {
        guard value.isFinite else { return minimumInterval }
        return min(max(value, 0.001), maximumInterval)
    }

    static func intervalPosition(for value: Double) -> Double {
        let interval = max(normalizedInterval(value), minimumInterval)

        if interval <= fineIntervalThreshold {
            return ((interval - minimumInterval) / fineIntervalStep).rounded()
        }

        if interval <= mediumIntervalThreshold {
            return fineIntervalPosition + ((interval - fineIntervalThreshold) / mediumIntervalStep).rounded()
        }

        if interval <= slowIntervalThreshold {
            return mediumIntervalPosition + ((interval - mediumIntervalThreshold) / slowIntervalStep).rounded()
        }

        return slowIntervalPosition + ((interval - slowIntervalThreshold) / longIntervalStep).rounded()
    }

    static func interval(forPosition value: Double) -> Double {
        let position = min(max(value.rounded(), 0), maximumIntervalPosition)
        let interval: Double

        let step: Double

        if position <= fineIntervalPosition {
            interval = minimumInterval + position * fineIntervalStep
            step = fineIntervalStep
        } else if position <= mediumIntervalPosition {
            interval = fineIntervalThreshold + (position - fineIntervalPosition) * mediumIntervalStep
            step = mediumIntervalStep
        } else if position <= slowIntervalPosition {
            interval = mediumIntervalThreshold + (position - mediumIntervalPosition) * slowIntervalStep
            step = slowIntervalStep
        } else {
            interval = slowIntervalThreshold + (position - slowIntervalPosition) * longIntervalStep
            step = longIntervalStep
        }

        return normalizedInterval(round(interval, toNearest: step))
    }

    static func interval(forBPM value: Double) -> Double {
        guard value.isFinite, value > 0 else { return maximumInterval }

        let bpm = value < 10 ? (value * 10).rounded() / 10 : value.rounded()
        return 60 / bpm
    }

    static func formattedNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func round(_ value: Double, toNearest step: Double) -> Double {
        guard value.isFinite, step > 0 else { return value }
        return (value / step).rounded() * step
    }
}
