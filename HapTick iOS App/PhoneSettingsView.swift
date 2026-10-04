import SwiftUI

struct PhoneSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = PhoneSettingsStore()
    @StateObject private var player = PhoneHapticPlayer()
    @State private var intervalText = ""
    @State private var bpmText = ""
    @FocusState private var focusedField: EditedField?

    private let styleColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private enum EditedField {
        case interval
        case bpm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    phonePanel
                    valuePanel
                    compositionPanel
                    stylePanel
                    syncPanel
                    behaviorPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .onAppear(perform: syncInputText)
            .onChange(of: store.settings) { _, _ in
                player.update(store.settings)
                guard focusedField == nil else { return }
                syncInputText()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { player.stop() }
            }
            .onChange(of: focusedField) { oldValue, newValue in
                if oldValue != nil, newValue == nil {
                    commitFocusedInput(oldValue)
                    if oldValue == .interval, intervalLimitWarning != nil {
                        return
                    }
                    if oldValue == .bpm, bpmLimitWarning != nil {
                        return
                    }
                    syncInputText()
                } else if newValue == nil {
                    syncInputText()
                }
            }
            .onChange(of: intervalText) { _, newValue in
                guard focusedField == .interval else { return }
                applyIntervalText(newValue)
            }
            .onChange(of: bpmText) { _, newValue in
                guard focusedField == .bpm else { return }
                applyBPMText(newValue)
            }
        }
    }

    private var valuePanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            unitPicker

            let isInterval = store.settings.displayMode == .interval
            let field: EditedField = isInterval ? .interval : .bpm
            let text = isInterval ? $intervalText : $bpmText
            let intervalWarning = intervalLimitWarning
            let bpmWarning = bpmLimitWarning
            let styleWarning = styleSpeedWarning
            let hasWarning = intervalWarning != nil || bpmWarning != nil || styleWarning != nil

            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.text(isInterval ? "Interval" : "BPM"), systemImage: isInterval ? "timer" : "metronome")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(hasWarning ? Color.red : Color.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField(isInterval ? "0.2" : "75", text: text)
                        .focused($focusedField, equals: field)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 56, weight: .semibold, design: .rounded))
                        .foregroundStyle(hasWarning ? Color.red : Color.primary)
                        .monospacedDigit()
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                        .textFieldStyle(.plain)

                    Text(isInterval ? "s" : "BPM")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(hasWarning ? Color.red : Color.secondary)
                }

                if let intervalWarning {
                    Text(intervalWarning)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let bpmWarning {
                    Text(bpmWarning)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let styleWarning {
                    Text(styleWarning)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .liquidPanel()
    }

    private var unitPicker: some View {
        HStack(spacing: 4) {
            ForEach(DisplayMode.allCases) { mode in
                Button {
                    displayModeBinding.wrappedValue = mode
                    focusedField = nil
                } label: {
                    Text(mode.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.settings.displayMode == mode ? Color.primary : Color.secondary)
                .background {
                    if store.settings.displayMode == mode {
                        Capsule(style: .continuous)
                            .fill(.background.opacity(0.72))
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    }
                }
            }
        }
        .padding(4)
        .background(.thinMaterial, in: Capsule(style: .continuous))
    }

    private var stylePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(title: "Style", systemImage: "waveform.path.ecg")

            Text("Choose a style for a single pulse or the next step you add.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: styleColumns, spacing: 10) {
                ForEach(HapticStyle.allCases) { style in
                    styleButton(style)
                }
            }
        }
        .padding(18)
        .liquidPanel()
    }

    private func styleButton(_ style: HapticStyle) -> some View {
        let isSelected = store.settings.hapticStyle == style
        let isUnsupported = displayedSettings.isStyleUnsupported(style)
        let styleColor = isUnsupported ? Color.red : (isSelected ? Color.accentColor : Color.primary)

        return Button {
            store.update { settings in
                settings.hapticStyle = style
            }
        } label: {
            VStack(spacing: 7) {
                Image(systemName: style.symbolName)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)

                Text(style.label)
                    .font(.caption2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .foregroundStyle(styleColor)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(styleColor.opacity(0.65), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var behaviorPanel: some View {
        HStack(spacing: 12) {
            panelHeader(title: "Flip to start/stop", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")

            Spacer()

            Toggle("Flip to start/stop", isOn: motionToggleBinding)
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(18)
        .liquidPanel()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Flip to start or stop")
    }

    private var phonePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader(title: "iPhone", systemImage: "iphone.radiowaves.left.and.right")
            Button {
                focusedField = nil
                player.isRunning ? player.stop() : player.start(store.settings)
            } label: {
                Label(L10n.text(player.isRunning ? "Stop" : "Start"), systemImage: player.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!player.supportsHaptics || (!player.isRunning && displayedSettings.isBelowStyleMinimum))
            .accessibilityIdentifier("phonePlayback")

            Text(player.status ?? L10n.text(player.supportsHaptics
                 ? "Haptics play while HapTick is open on iPhone."
                 : "Haptics are unavailable on this device."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .liquidPanel()
    }

    private var compositionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { store.settings.compositionEnabled },
                set: { enabled in store.update { $0.compositionEnabled = enabled } }
            )) {
                Label("Loop composition", systemImage: "repeat")
                    .font(.headline)
            }
            .accessibilityIdentifier("compositionEnabled")

            Text(store.settings.compositionLabel + "  ↻")
                .font(.title2.monospaced().weight(.semibold))
                .accessibilityLabel(L10n.format("Repeating sequence: %@", store.settings.compositionLabel))
                .accessibilityIdentifier("compositionSummary")
                .fixedSize(horizontal: false, vertical: true)

            Text("Each abbreviation is a haptic style. Tap a step to change, move, duplicate, or remove it. The interval applies to every step.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.settings.composition.indices, id: \.self) { index in
                        compositionStep(index)
                    }
                }
            }

            HStack {
                Button {
                    store.update { $0.composition.append($0.hapticStyle) }
                } label: {
                    Label("Add step", systemImage: "plus")
                }
                .disabled(store.settings.composition.count >= HapTickSettings.maximumCompositionLength)
                .accessibilityIdentifier("addCompositionStep")

                Spacer()

                Button("Example sequence") {
                    store.update {
                        $0.composition = HapTickSettings.exampleComposition
                        $0.compositionEnabled = true
                    }
                }
                .accessibilityIdentifier("compositionExample")
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .liquidPanel()
    }

    private func compositionStep(_ index: Int) -> some View {
        let style = store.settings.composition[index]
        return Menu {
            Picker("Style", selection: Binding(
                get: { store.settings.composition[index] },
                set: { style in store.update { $0.composition[index] = style } }
            )) {
                ForEach(HapticStyle.allCases) { style in
                    Label(style.label, systemImage: style.symbolName).tag(style)
                }
            }
            Button("Move left", systemImage: "arrow.left") {
                store.update { $0.composition.swapAt(index, index - 1) }
            }
            .disabled(index == 0)
            Button("Move right", systemImage: "arrow.right") {
                store.update { $0.composition.swapAt(index, index + 1) }
            }
            .disabled(index == store.settings.composition.count - 1)
            Button("Duplicate", systemImage: "plus.square.on.square") {
                store.update { $0.composition.insert(style, at: index + 1) }
            }
            .disabled(store.settings.composition.count >= HapTickSettings.maximumCompositionLength)
            Button("Remove", systemImage: "trash", role: .destructive) {
                store.update { $0.composition.remove(at: index) }
            }
            .disabled(store.settings.composition.count == 1)
        } label: {
            VStack(spacing: 6) {
                Text(style.abbreviation).font(.title3.monospaced().bold())
                Image(systemName: style.symbolName)
                Text(style.label).font(.caption2).lineLimit(2)
            }
            .frame(width: 86, height: 88)
            .foregroundStyle(displayedSettings.isStyleUnsupported(style) ? Color.red : Color.primary)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityLabel(L10n.format("Step %ld: %@", index + 1, style.label))
    }

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                panelHeader(title: "Watch", systemImage: "applewatch.radiowaves.left.and.right")

                Spacer()

                Button {
                    store.sendCurrentSettings()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(.thinMaterial, in: Circle())
                .accessibilityLabel("Send settings to Apple Watch")
            }

            HStack(spacing: 10) {
                Button {
                    focusedField = nil
                    store.startWatchTimer()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(displayedSettings.isBelowStyleMinimum)

                Button {
                    focusedField = nil
                    store.stopWatchTimer()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text(store.syncStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(18)
        .liquidPanel()
    }

    private func panelHeader(title: String, systemImage: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)

            Text(L10n.text(title))
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { store.settings.displayMode },
            set: { mode in
                store.update { settings in
                    settings.displayMode = mode
                }
            }
        )
    }

    private var motionToggleBinding: Binding<Bool> {
        Binding(
            get: { store.settings.motionToggleEnabled },
            set: { enabled in
                store.update { settings in
                    settings.motionToggleEnabled = enabled
                }
            }
        )
    }

    private var bpmLimitWarning: String? {
        guard store.settings.displayMode == .bpm,
              let bpm = numericValue(from: bpmText),
              bpm > HapTickSettings.maximumBPM
        else {
            return nil
        }

        let maximumText = HapTickSettings.formattedNumber(HapTickSettings.maximumBPM, maximumFractionDigits: 0)
        return L10n.format("The maximum supported is %@ BPM.", maximumText)
    }

    private var intervalLimitWarning: String? {
        guard store.settings.displayMode == .interval,
              let interval = numericValue(from: intervalText),
              interval >= 0,
              interval + 0.0001 < HapTickSettings.minimumInterval
        else {
            return nil
        }

        let minimumText = HapTickSettings.formattedNumber(HapTickSettings.minimumInterval, maximumFractionDigits: 2)
        return L10n.format("The minimum supported interval is %@s.", minimumText)
    }

    private var styleSpeedWarning: String? {
        displayedSettings.styleSpeedWarning
    }

    private var displayedSettings: HapTickSettings {
        var settings = store.settings
        settings.intervalSeconds = displayedIntervalSeconds
        return settings
    }

    private var displayedIntervalSeconds: Double {
        switch store.settings.displayMode {
        case .interval:
            if let interval = numericValue(from: intervalText), interval >= 0 {
                return HapTickSettings.normalizedInterval(interval)
            }
        case .bpm:
            if let bpm = numericValue(from: bpmText), bpm > 0 {
                return HapTickSettings.normalizedInterval(HapTickSettings.interval(forBPM: bpm))
            }
        }

        return store.settings.intervalSeconds
    }

    private func applyIntervalText(_ text: String) {
        guard let interval = numericValue(from: text), interval > 0 else { return }
        store.setInterval(interval)
    }

    private func applyBPMText(_ text: String) {
        guard let bpm = numericValue(from: text),
              bpm > 0,
              bpm <= HapTickSettings.maximumBPM
        else {
            return
        }

        store.setBPM(bpm)
    }

    private func commitFocusedInput(_ field: EditedField?) {
        switch field {
        case .interval:
            applyIntervalText(intervalText)
        case .bpm:
            applyBPMText(bpmText)
        case nil:
            break
        }
    }

    private func syncInputText() {
        intervalText = HapTickSettings.formattedNumber(store.settings.intervalSeconds, maximumFractionDigits: 3)

        let maximumFractionDigits = store.settings.bpmValue < 10 ? 1 : 0
        bpmText = HapTickSettings.formattedNumber(store.settings.bpmValue, maximumFractionDigits: maximumFractionDigits)
    }

    private func numericValue(from text: String) -> Double? {
        HapTickSettings.numericValue(from: text)
    }

}

#Preview {
    PhoneSettingsView()
}

private struct LiquidPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

private extension View {
    func liquidPanel() -> some View {
        modifier(LiquidPanelModifier())
    }
}
