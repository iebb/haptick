import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

var settings = HapTickSettings(intervalSeconds: 0.5, compositionEnabled: true)
check((0..<12).map { settings.style(atBeat: $0) } == Array(repeating: HapTickSettings.exampleComposition, count: 3).flatMap { $0 }, "The composition must loop in order across cycle boundaries")
check(settings.compositionLabel == "UP · CLK · SUC · CLK", "Use style abbreviations, including repeated styles")
check(settings.compositionLabel == HapTickSettings(dictionary: settings.dictionary).compositionLabel, "WatchConnectivity must preserve the composition")
settings.compositionEnabled = false
check((0..<12).allSatisfy { settings.style(atBeat: $0) == settings.hapticStyle }, "Disabling composition restores single-style playback")

let legacy = try JSONDecoder().decode(HapTickSettings.self, from: Data("{\"intervalSeconds\":2,\"hapticStyle\":\"click\",\"motionToggleEnabled\":true,\"displayMode\":\"bpm\"}".utf8))
check(legacy.intervalSeconds == 2 && !legacy.compositionEnabled, "Existing saved settings must migrate")
let roundTripped = try JSONDecoder().decode(HapTickSettings.self, from: JSONEncoder().encode(settings))
check(roundTripped == settings, "Codable must round-trip settings")
let merged = HapTickSettings(dictionary: [HapTickSettings.intervalKey: 3.0], fallback: settings)
check(merged.composition == settings.composition && merged.hapticStyle == settings.hapticStyle, "An older peer must not erase a composition")
check(HapTickSettings(composition: []).composition == HapTickSettings.exampleComposition, "Empty compositions must safely recover")
check(HapTickSettings(composition: Array(repeating: .click, count: 100)).composition.count == 64, "Bound the composition size")

settings.compositionEnabled = true
settings.composition = [.click, .notification, .click]
settings.intervalSeconds = 0.5
check(settings.isBelowStyleMinimum && settings.styleSpeedWarning != nil, "Validate every style in the composition, including middle steps")
settings.intervalSeconds = 0.75
check(!settings.isBelowStyleMinimum && settings.styleSpeedWarning == nil, "The limiting style must allow its minimum interval")
settings.compositionEnabled = false
settings.hapticStyle = .click
settings.intervalSeconds = 0.2
check(!settings.isBelowStyleMinimum, "Inactive sequence styles must not constrain single-style playback")

let suite = "HapTickTests-\(UUID())"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
settings.compositionEnabled = true
settings.save(to: defaults)
check(HapTickSettings.load(from: defaults) == settings, "Settings must survive an app restart")
check(HapTickSettings.numericValue(from: "0,75", locale: Locale(identifier: "fr_FR")) == 0.75, "French decimal input")
check(HapTickSettings.numericValue(from: "0,75", locale: Locale(identifier: "es_ES")) == 0.75, "Spanish decimal input")
check(HapTickSettings.numericValue(from: "0.75", locale: Locale(identifier: "fr_FR")) == 0.75, "Also accept a typed decimal point")
check(HapTickSettings.numericValue(from: "1abc") == nil && HapTickSettings.numericValue(from: "nan") == nil, "Reject malformed and nonfinite input")
print("All composition, migration, persistence, validation, and locale tests passed.")
