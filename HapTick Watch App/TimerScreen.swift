import SwiftUI
import WatchKit

struct TimerScreen: View {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = TimerController()
    @AppStorage("hasSeenCrownHint") private var hasSeenCrownHint = false
    @FocusState private var crownFocused: Bool
    @State private var showsCrownHint = false
    @State private var crownHintPulse = false
    @State private var crownValue = 1.0
    private let styleGridColumns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 3)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimateRing)) { timeline in
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geometry in
                    let contentPadding: CGFloat = 8
                    let availableWidth = geometry.size.width - contentPadding * 2
                    let availableHeight = geometry.size.height - contentPadding * 2
                    let ringSize = max(112, min(availableWidth, availableHeight))
                    let intervalFontSize = min(46, ringSize * 0.35)
                    let lapPhase = shouldAnimateRing ? controller.spinnerPhase(at: timeline.date) : 0
                    let valueColor: Color = controller.isBelowStyleMinimum ? .red : .white

                    ScrollView(.vertical) {
                        VStack(spacing: 14) {
                            VStack(spacing: 0) {
                                ZStack {
                                    PulseRing(
                                        phase: lapPhase,
                                        lapCount: controller.pulseCount,
                                        isRunning: controller.isRunning
                                    )

                                    VStack(spacing: 2) {
                                        Text(controller.topLabel)
                                            .font(.system(size: min(15, ringSize * 0.11), weight: .medium, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.62))
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)

                                        Text(controller.primaryValueLabel)
                                            .font(.system(size: intervalFontSize, weight: .semibold, design: .rounded))
                                            .foregroundStyle(valueColor)
                                            .monospacedDigit()
                                            .allowsTightening(true)
                                            .minimumScaleFactor(0.5)
                                            .lineLimit(1)
                                            .frame(height: intervalFontSize * 1.08)

                                        Text(controller.unitLabel)
                                            .font(.system(size: min(14, ringSize * 0.11), weight: .regular, design: .rounded))
                                            .foregroundStyle(controller.isBelowStyleMinimum ? .red.opacity(0.72) : .white.opacity(0.56))
                                            .minimumScaleFactor(0.75)
                                            .lineLimit(1)

                                        if let warning = controller.styleSpeedWarning {
                                            Text(warning)
                                                .font(.system(size: min(10, ringSize * 0.08), weight: .medium, design: .rounded))
                                                .foregroundStyle(.red.opacity(0.88))
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                                .minimumScaleFactor(0.7)
                                                .frame(maxWidth: ringSize * 0.74)
                                                .padding(.top, 2)
                                        }
                                    }
                                    .padding(.horizontal, 12)

                                    if showsCrownHint {
                                        CrownHint(pulse: crownHintPulse)
                                            .offset(y: ringSize * 0.35)
                                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                                    }
                                }
                                .frame(width: ringSize, height: ringSize)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: geometry.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                controller.toggleRunning()
                            }
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 28)
                                    .onEnded { value in
                                        let width = value.translation.width
                                        let height = value.translation.height
                                        guard abs(width) > abs(height), abs(width) > 32 else { return }
                                        controller.toggleDisplayMode()
                                        WKInterfaceDevice.current().play(.click)
                                    }
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(controller.isRunning ? "Stop vibration" : "Start vibration")

                            styleControl
                                .padding(.horizontal, contentPadding)
                                .padding(.bottom, 8)

                            motionControl
                                .padding(.horizontal, contentPadding)
                                .padding(.bottom, 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .contentMargins(.vertical, 0, for: .scrollContent)
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea()
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            .focusable(true)
            .focused($crownFocused)
            .digitalCrownRotation(
                crownBinding,
                from: controller.crownLowerBound,
                through: controller.crownUpperBound,
                by: controller.crownStep,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onAppear {
                crownFocused = true
                syncCrownValue()
                showCrownHintIfNeeded()
            }
            .onChange(of: controller.intervalSeconds) { _, _ in
                syncCrownValue()
            }
            .onChange(of: controller.displayMode) { _, _ in
                syncCrownValue()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }

                controller.resumeRuntimeSessionIfNeeded()
            }
        }
    }

    private var shouldAnimateRing: Bool {
        controller.isRunning && crownFocused && scenePhase == .active && !isLuminanceReduced
    }

    private var crownBinding: Binding<Double> {
        Binding(
            get: { crownValue },
            set: { newValue in
                crownValue = newValue
                controller.updateCrownValue(newValue)
            }
        )
    }

    private func syncCrownValue() {
        let nextValue = controller.crownValue
        guard abs(crownValue - nextValue) > 0.0001 else { return }
        crownValue = nextValue
    }

    private var styleControl: some View {
        VStack(spacing: 7) {
            Text("Style")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            LazyVGrid(columns: styleGridColumns, spacing: 7) {
                ForEach(HapticStyle.allCases) { style in
                    let isSelected = controller.hapticStyle == style
                    let isUnsupported = controller.isStyleUnsupported(style)
                    let styleColor: Color = isUnsupported ? .red : (isSelected ? .cyan : .white.opacity(0.72))

                    Button {
                        controller.hapticStyle = style
                        controller.pulseNow()
                    } label: {
                        Image(systemName: style.symbolName)
                            .font(.system(size: 17, weight: .regular))
                            .frame(width: 44, height: 36)
                            .foregroundStyle(styleColor)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(styleColor.opacity(0.18))
                                }
                            }
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(styleColor.opacity(0.75), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.label)
                }
            }
        }
    }

    private var motionControl: some View {
        Toggle(isOn: $controller.motionToggleEnabled) {
            Label("Flip", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .tint(.cyan)
    }

    private func showCrownHintIfNeeded() {
        guard !hasSeenCrownHint else { return }
        hasSeenCrownHint = true

        withAnimation(.easeOut(duration: 0.25)) {
            showsCrownHint = true
        }

        withAnimation(.easeInOut(duration: 0.55).repeatCount(4, autoreverses: true)) {
            crownHintPulse = true
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showsCrownHint = false
                }
            }
        }
    }
}

private struct CrownHint: View {
    let pulse: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "digitalcrown.arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))

            Text("Crown")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.88), in: Capsule())
        .scaleEffect(pulse ? 1.08 : 0.94)
        .opacity(pulse ? 1 : 0.72)
        .allowsHitTesting(false)
    }
}

private struct PulseRing: View {
    let phase: Double
    let lapCount: Int
    let isRunning: Bool

    private var currentProgress: Double {
        if isRunning {
            max(min(phase, 1), 0.003)
        } else {
            0.003
        }
    }

    private var previousLapColors: [Color] {
        lapColors(for: max(lapCount - 1, 0), brightness: 0.55, opacity: 0.58)
    }

    private var currentLapColors: [Color] {
        lapColors(for: lapCount, brightness: 1.0, opacity: isRunning ? 1 : 0.35)
    }

    private func lapColors(for lap: Int, brightness: Double, opacity: Double) -> [Color] {
        let hue = (Double(lap % 12) / 12 + phase * 0.18).truncatingRemainder(dividingBy: 1)
        let startColor = Color(hue: hue, saturation: 0.95, brightness: brightness).opacity(opacity)
        return [
            startColor,
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: brightness).opacity(opacity),
            Color(hue: (hue + 0.18).truncatingRemainder(dividingBy: 1), saturation: 0.88, brightness: brightness).opacity(opacity),
            startColor
        ]
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.13), lineWidth: 17)

            if isRunning && lapCount > 0 {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: previousLapColors,
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 17, lineCap: .round)
                    )
                    .opacity(0.72)
            }

            Circle()
                .trim(from: 0, to: currentProgress)
                .stroke(
                    AngularGradient(
                        colors: currentLapColors,
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 17, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(.white.opacity(isRunning ? 0.18 : 0.08), lineWidth: 1)
                .padding(10)
        }
        .padding(7)
    }
}

#Preview {
    TimerScreen()
}
