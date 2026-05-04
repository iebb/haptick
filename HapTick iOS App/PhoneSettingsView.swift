import SwiftUI

struct PhoneSettingsView: View {
    @StateObject private var store = PhoneSettingsStore()
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
            Form {
                Section {
                    Picker("Unit", selection: displayModeBinding) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if store.settings.displayMode == .interval {
                        numericInputRow(
                            title: "Interval",
                            systemImage: "timer",
                            unit: "s",
                            text: $intervalText,
                            field: .interval
                        )
                    } else {
                        numericInputRow(
                            title: "BPM",
                            systemImage: "metronome",
                            unit: "BPM",
                            text: $bpmText,
                            field: .bpm
                        )
                    }
                }

                Section("Style") {
                    LazyVGrid(columns: styleColumns, spacing: 10) {
                        ForEach(HapticStyle.allCases) { style in
                            Button {
                                store.update { settings in
                                    settings.hapticStyle = style
                                }
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: style.symbolName)
                                        .font(.system(size: 20, weight: .medium))

                                    Text(style.label)
                                        .font(.caption2)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.72)
                                }
                                .frame(maxWidth: .infinity, minHeight: 72)
                            }
                            .buttonStyle(.bordered)
                            .tint(store.settings.hapticStyle == style ? .cyan : .gray)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Flip to start/stop", isOn: motionToggleBinding)
                }

                Section {
                    Button {
                        store.sendCurrentSettings()
                    } label: {
                        Label("Send to Apple Watch", systemImage: "applewatch.radiowaves.left.and.right")
                    }

                    Text(store.syncStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("HapTick")
            .onAppear(perform: syncInputText)
            .onChange(of: store.settings) { _, _ in
                guard focusedField == nil else { return }
                syncInputText()
            }
            .onChange(of: focusedField) { oldValue, newValue in
                if oldValue != nil, newValue == nil {
                    commitFocusedInput(oldValue)
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

    private func numericInputRow(
        title: String,
        systemImage: String,
        unit: String,
        text: Binding<String>,
        field: EditedField
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)

            Spacer()

            TextField(title, text: text)
                .focused($focusedField, equals: field)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(minWidth: 88)

            Text(unit)
                .foregroundStyle(.secondary)
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

    private func applyIntervalText(_ text: String) {
        guard let interval = numericValue(from: text), interval >= HapTickSettings.minimumInterval else { return }
        store.setInterval(interval)
    }

    private func applyBPMText(_ text: String) {
        guard let bpm = numericValue(from: text), bpm > 0 else { return }
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
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

#Preview {
    PhoneSettingsView()
}
