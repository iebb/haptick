import CoreMotion
import Foundation
import os
import WatchKit

#if DEBUG
@MainActor
final class HapticMeasurement {
    static let shared = HapticMeasurement()

    private struct Sample {
        let offset: TimeInterval
        let magnitude: Double
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ad.neko.haptick.watchapp", category: "HapticMeasurement")
    private let motionManager = CMMotionManager()
    private var samples: [Sample] = []
    private var sampleStartDate = Date()
    private var isMeasuring = false

    private let sampleWindow: TimeInterval = 1.25
    private let interStyleDelay: TimeInterval = 1.6
    private let baselineWindow: TimeInterval = 0.18
    private let settleWindow: TimeInterval = 0.12
    private let cadenceIntervals: [TimeInterval] = [0.20, 0.30, 0.45, 0.60, 0.80]
    private let cadencePulseCount = 5
    private let preciseNotificationIntervals: [TimeInterval] = [0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 1.00]
    private let preciseTrialCount = 2
    private let precisePulseCount = 6
    private var outputURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("haptic-measurements.txt")
    }

    func measureAllStyles() {
        guard !isMeasuring else { return }
        isMeasuring = true

        guard motionManager.isAccelerometerAvailable else {
            log("Haptic measurement unavailable: accelerometer is unavailable", level: .error)
            isMeasuring = false
            return
        }

        resetOutputFile()
        log("Haptic measurement starting")
        Task {
            for style in HapticStyle.allCases {
                await measure(style)
                try? await Task.sleep(for: .seconds(interStyleDelay))
            }
            log("Haptic measurement finished")
            isMeasuring = false
        }
    }

    func measurePreciseNotificationCadence() {
        guard !isMeasuring else { return }
        isMeasuring = true

        guard motionManager.isAccelerometerAvailable else {
            log("Haptic precise cadence unavailable: accelerometer is unavailable", level: .error)
            isMeasuring = false
            return
        }

        resetOutputFile()
        log("Haptic precise cadence starting style=notification intervals=\(preciseNotificationIntervals.map { String(format: "%.2f", $0) }.joined(separator: ",")) trials=\(preciseTrialCount) pulses=\(precisePulseCount)")

        Task {
            for interval in preciseNotificationIntervals {
                var acceptedTrials = 0
                var distinctTrials = 0
                var totalDetectedWindows = 0
                var totalBursts = 0
                var rejectedTrials = 0

                for trial in 1...preciseTrialCount {
                    let control = await measurePreciseCadenceTrial(style: nil, interval: interval)
                    try? await Task.sleep(for: .seconds(0.45))
                    let haptic = await measurePreciseCadenceTrial(style: .notification, interval: interval)

                    let rejectReason = rejectionReason(control: control, haptic: haptic)
                    if let rejectReason {
                        rejectedTrials += 1
                        log("Haptic precise trial style=notification gap=\(String(format: "%.2f", interval))s trial=\(trial) rejected=\(rejectReason) controlBursts=\(control.burstCount) controlPeak=\(control.peakDelta) hapticWindows=\(haptic.detectedWindows) hapticBursts=\(haptic.burstCount) hapticPeak=\(haptic.peakDelta)")
                    } else {
                        acceptedTrials += 1
                        totalDetectedWindows += haptic.detectedWindows
                        totalBursts += haptic.burstCount
                        if haptic.isDistinct {
                            distinctTrials += 1
                        }
                        log("Haptic precise trial style=notification gap=\(String(format: "%.2f", interval))s trial=\(trial) accepted=true detectedWindows=\(haptic.detectedWindows)/\(haptic.requestedCount) bursts=\(haptic.burstCount) distinct=\(haptic.isDistinct) baselineMAD=\(haptic.baselineMAD) threshold=\(haptic.threshold) peakDelta=\(haptic.peakDelta)")
                    }

                    try? await Task.sleep(for: .seconds(0.8))
                }

                let requiredDistinctTrials = max(1, Int(ceil(Double(acceptedTrials) * 0.8)))
                let pass = acceptedTrials > 0 && distinctTrials >= requiredDistinctTrials
                let avgWindows = acceptedTrials > 0 ? Double(totalDetectedWindows) / Double(acceptedTrials * precisePulseCount) : 0
                let avgBursts = acceptedTrials > 0 ? Double(totalBursts) / Double(acceptedTrials) : 0
                log("Haptic precise summary style=notification gap=\(String(format: "%.2f", interval))s acceptedTrials=\(acceptedTrials) rejectedTrials=\(rejectedTrials) distinctTrials=\(distinctTrials) avgWindowRate=\(String(format: "%.2f", avgWindows)) avgBursts=\(String(format: "%.1f", avgBursts)) pass=\(pass)")
            }

            log("Haptic precise cadence finished")
            isMeasuring = false
        }
    }

    func measureContinuousTriggers() {
        guard !isMeasuring else { return }
        isMeasuring = true

        guard motionManager.isAccelerometerAvailable else {
            log("Haptic cadence unavailable: accelerometer is unavailable", level: .error)
            isMeasuring = false
            return
        }

        resetOutputFile()
        log("Haptic cadence starting intervals=\(cadenceIntervals.map { String(format: "%.2f", $0) }.joined(separator: ",")) pulses=\(cadencePulseCount)")
        Task {
            for style in HapticStyle.allCases {
                for interval in cadenceIntervals {
                    await measureCadence(style: style, interval: interval)
                    try? await Task.sleep(for: .seconds(0.8))
                }
                log("Haptic cadence style=\(style.rawValue) complete")
                try? await Task.sleep(for: .seconds(1.2))
            }
            log("Haptic cadence finished")
            isMeasuring = false
        }
    }

    private func measure(_ style: HapticStyle) async {
        samples = []
        sampleStartDate = Date()

        motionManager.accelerometerUpdateInterval = 0.01
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            let acceleration = data.acceleration
            let magnitude = sqrt(
                acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
            )
            let sample = Sample(offset: Date().timeIntervalSince(self.sampleStartDate), magnitude: magnitude)

            Task { @MainActor in
                self.samples.append(sample)
            }
        }

        try? await Task.sleep(for: .seconds(baselineWindow))
        let playOffset = Date().timeIntervalSince(sampleStartDate)
        WKInterfaceDevice.current().play(style.type)
        try? await Task.sleep(for: .seconds(sampleWindow))
        motionManager.stopAccelerometerUpdates()

        logMeasurement(for: style, playOffset: playOffset)
    }

    private func measureCadence(style: HapticStyle, interval: TimeInterval) async {
        samples = []
        sampleStartDate = Date()

        motionManager.accelerometerUpdateInterval = 0.01
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            let acceleration = data.acceleration
            let magnitude = sqrt(
                acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
            )
            let sample = Sample(offset: Date().timeIntervalSince(self.sampleStartDate), magnitude: magnitude)

            Task { @MainActor in
                self.samples.append(sample)
            }
        }

        try? await Task.sleep(for: .seconds(baselineWindow))
        var triggerOffsets: [TimeInterval] = []

        for index in 0..<cadencePulseCount {
            triggerOffsets.append(Date().timeIntervalSince(sampleStartDate))
            WKInterfaceDevice.current().play(style.type)

            if index < cadencePulseCount - 1 {
                try? await Task.sleep(for: .seconds(interval))
            }
        }

        try? await Task.sleep(for: .seconds(max(0.45, interval)))
        motionManager.stopAccelerometerUpdates()

        logCadenceMeasurement(for: style, interval: interval, triggerOffsets: triggerOffsets)
    }

    private struct PreciseCadenceResult {
        let requestedCount: Int
        let detectedWindows: Int
        let burstCount: Int
        let baselineMAD: Double
        let threshold: Double
        let peakDelta: Double

        var isDistinct: Bool {
            detectedWindows == requestedCount && burstCount >= requestedCount
        }
    }

    private func measurePreciseCadenceTrial(style: HapticStyle?, interval: TimeInterval) async -> PreciseCadenceResult {
        samples = []
        sampleStartDate = Date()

        motionManager.accelerometerUpdateInterval = 0.005
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            let acceleration = data.acceleration
            let magnitude = sqrt(
                acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
            )
            let sample = Sample(offset: Date().timeIntervalSince(self.sampleStartDate), magnitude: magnitude)

            Task { @MainActor in
                self.samples.append(sample)
            }
        }

        let preciseBaselineWindow = 0.35
        try? await Task.sleep(for: .seconds(preciseBaselineWindow))
        var triggerOffsets: [TimeInterval] = []

        for index in 0..<precisePulseCount {
            triggerOffsets.append(Date().timeIntervalSince(sampleStartDate))
            if let style {
                WKInterfaceDevice.current().play(style.type)
            }

            if index < precisePulseCount - 1 {
                try? await Task.sleep(for: .seconds(interval))
            }
        }

        try? await Task.sleep(for: .seconds(max(0.65, interval)))
        motionManager.stopAccelerometerUpdates()

        return analyzePreciseCadence(triggerOffsets: triggerOffsets)
    }

    private func logMeasurement(for style: HapticStyle, playOffset: TimeInterval) {
        let baselineSamples = samples.filter { $0.offset < playOffset }
        let baseline = baselineSamples.map(\.magnitude).average ?? 1.0
        let baselineNoise = baselineSamples.map { abs($0.magnitude - baseline) }.average ?? 0.004
        let threshold = max(0.012, baselineNoise * 4)

        let postPlaySamples = samples.filter { $0.offset >= playOffset }
        let activeSamples = postPlaySamples.filter { abs($0.magnitude - baseline) >= threshold }
        let peakDelta = postPlaySamples.map { abs($0.magnitude - baseline) }.max() ?? 0

        guard let firstActive = activeSamples.first, let lastActive = activeSamples.last else {
            log("Haptic measurement style=\(style.rawValue) detected=false baseline=\(baseline) threshold=\(threshold) peakDelta=\(peakDelta)")
            return
        }

        let activeDuration = max(lastActive.offset - firstActive.offset, 0)
        let settleDuration = settleDurationAfter(lastActive.offset, baseline: baseline, threshold: threshold) ?? activeDuration
        let recommendedGap = ceil((settleDuration + 0.15) * 100) / 100

        log("Haptic measurement style=\(style.rawValue) detected=true active=\(activeDuration)s settle=\(settleDuration)s recommendedGap=\(recommendedGap)s baseline=\(baseline) threshold=\(threshold) peakDelta=\(peakDelta)")
    }

    private func logCadenceMeasurement(for style: HapticStyle, interval: TimeInterval, triggerOffsets: [TimeInterval]) {
        guard let firstTrigger = triggerOffsets.first else { return }

        let baselineSamples = samples.filter { $0.offset < firstTrigger }
        let baseline = baselineSamples.map(\.magnitude).average ?? 1.0
        let baselineNoise = baselineSamples.map { abs($0.magnitude - baseline) }.average ?? 0.004
        let threshold = max(0.012, baselineNoise * 4)
        let postTriggerSamples = samples.filter { $0.offset >= firstTrigger }
        let peakDelta = postTriggerSamples.map { abs($0.magnitude - baseline) }.max() ?? 0
        let burstCount = countBursts(in: postTriggerSamples, baseline: baseline, threshold: threshold)

        let detectedWindows = triggerOffsets.enumerated().filter { index, triggerOffset in
            let nextTrigger = index + 1 < triggerOffsets.count ? triggerOffsets[index + 1] : nil
            let end = min(nextTrigger.map { $0 - 0.01 } ?? triggerOffset + max(interval, 0.45), triggerOffset + max(interval * 0.92, 0.10))
            let window = samples.filter { $0.offset >= triggerOffset && $0.offset <= end }
            return window.contains { abs($0.magnitude - baseline) >= threshold }
        }.count

        let distinct = detectedWindows == triggerOffsets.count && burstCount >= triggerOffsets.count
        let partial = detectedWindows > 0 || burstCount > 0
        let status = distinct ? "distinct" : (partial ? "merged-or-dropped" : "dropped")
        log("Haptic cadence style=\(style.rawValue) gap=\(String(format: "%.2f", interval))s requested=\(triggerOffsets.count) detectedWindows=\(detectedWindows) bursts=\(burstCount) status=\(status) baseline=\(baseline) threshold=\(threshold) peakDelta=\(peakDelta)")
    }

    private func countBursts(in samples: [Sample], baseline: Double, threshold: Double) -> Int {
        var bursts = 0
        var isActive = false
        var quietSamples = 0
        let quietSamplesNeeded = 3

        for sample in samples {
            let active = abs(sample.magnitude - baseline) >= threshold
            if active {
                if !isActive {
                    bursts += 1
                }
                isActive = true
                quietSamples = 0
            } else if isActive {
                quietSamples += 1
                if quietSamples >= quietSamplesNeeded {
                    isActive = false
                    quietSamples = 0
                }
            }
        }

        return bursts
    }

    private func analyzePreciseCadence(triggerOffsets: [TimeInterval]) -> PreciseCadenceResult {
        guard let firstTrigger = triggerOffsets.first else {
            return PreciseCadenceResult(requestedCount: 0, detectedWindows: 0, burstCount: 0, baselineMAD: 0, threshold: 1, peakDelta: 0)
        }

        let baselineSamples = samples.filter { $0.offset < firstTrigger }.map(\.magnitude)
        let baseline = baselineSamples.median ?? 1.0
        let baselineMAD = baselineSamples.map { abs($0 - baseline) }.median ?? 0.004
        let threshold = max(0.012, baselineMAD * 6)
        let postTriggerSamples = samples.filter { $0.offset >= firstTrigger }
        let peakDelta = postTriggerSamples.map { abs($0.magnitude - baseline) }.max() ?? 0
        let burstCount = countBursts(in: postTriggerSamples, baseline: baseline, threshold: threshold)

        let detectedWindows = triggerOffsets.enumerated().filter { index, triggerOffset in
            let nextTrigger = index + 1 < triggerOffsets.count ? triggerOffsets[index + 1] : nil
            let end = min(nextTrigger.map { $0 - 0.015 } ?? triggerOffset + 0.50, triggerOffset + 0.42)
            let window = samples.filter { $0.offset >= triggerOffset && $0.offset <= end }
            return window.contains { abs($0.magnitude - baseline) >= threshold }
        }.count

        return PreciseCadenceResult(
            requestedCount: triggerOffsets.count,
            detectedWindows: detectedWindows,
            burstCount: burstCount,
            baselineMAD: baselineMAD,
            threshold: threshold,
            peakDelta: peakDelta
        )
    }

    private func rejectionReason(control: PreciseCadenceResult, haptic: PreciseCadenceResult) -> String? {
        if control.detectedWindows > 1 || control.burstCount > 1 {
            return "noisy-control"
        }

        if haptic.baselineMAD > 0.02 {
            return "unstable-baseline"
        }

        if haptic.peakDelta <= control.peakDelta * 1.15 && haptic.detectedWindows < haptic.requestedCount {
            return "weak-signal"
        }

        return nil
    }

    private func settleDurationAfter(_ offset: TimeInterval, baseline: Double, threshold: Double) -> TimeInterval? {
        let postActiveSamples = samples.filter { $0.offset >= offset }

        for (index, sample) in postActiveSamples.enumerated() {
            let end = sample.offset + settleWindow
            let window = postActiveSamples[index...].prefix { $0.offset <= end }
            guard window.last?.offset ?? 0 >= end else { continue }

            if window.allSatisfy({ abs($0.magnitude - baseline) < threshold }) {
                return sample.offset - baselineWindow
            }
        }

        return nil
    }

    private enum LogLevel {
        case info
        case error
    }

    private func log(_ message: String, level: LogLevel = .info) {
        switch level {
        case .info:
            logger.info("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
        print(message)
        appendToOutputFile(message)
    }

    private func resetOutputFile() {
        guard let outputURL else { return }
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "".write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func appendToOutputFile(_ message: String) {
        guard let outputURL else { return }

        let line = "\(message)\n"
        if let data = line.data(using: .utf8), FileManager.default.fileExists(atPath: outputURL.path) {
            if let handle = try? FileHandle(forWritingTo: outputURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }
        }

        try? line.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }

    var median: Double? {
        guard !isEmpty else { return nil }

        let sortedValues = sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }

        return sortedValues[middle]
    }
}
#endif
