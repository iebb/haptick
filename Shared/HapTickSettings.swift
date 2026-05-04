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
}

struct HapTickSettings: Equatable, Codable {
    var intervalSeconds: Double
    var hapticStyle: HapticStyle
    var motionToggleEnabled: Bool
    var displayMode: DisplayMode

    static let minimumInterval = 0.8
    static let maximumInterval = 999.0
    static let minimumBPM = 0.1
    static let maximumBPM = 75.0
    static let mediumIntervalThreshold = 15.0
    static let slowIntervalThreshold = 30.0
    static let mediumIntervalPosition = 142.0
    static let slowIntervalPosition = 217.0
    static let maximumIntervalPosition = slowIntervalPosition + ((maximumInterval - slowIntervalThreshold) / 0.5).rounded()

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
        "\(Self.formattedNumber(intervalSeconds, maximumFractionDigits: 1))s"
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
        return min(max(value, minimumInterval), maximumInterval)
    }

    static func intervalPosition(for value: Double) -> Double {
        let interval = normalizedInterval(value)

        if interval <= mediumIntervalThreshold {
            return ((interval - minimumInterval) / 0.1).rounded()
        }

        if interval <= slowIntervalThreshold {
            return mediumIntervalPosition + ((interval - mediumIntervalThreshold) / 0.2).rounded()
        }

        return slowIntervalPosition + ((interval - slowIntervalThreshold) / 0.5).rounded()
    }

    static func interval(forPosition value: Double) -> Double {
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
}
