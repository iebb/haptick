import SwiftUI

struct PhoneSettingsView: View {
    @StateObject private var store = PhoneSettingsStore()

    private let styleColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Display", selection: displayModeBinding) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Interval", systemImage: "timer")
                            Spacer()
                            Text(store.settings.intervalLabel)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Stepper(
                            value: intervalPositionBinding,
                            in: 0...HapTickSettings.maximumIntervalPosition,
                            step: 1
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("BPM", systemImage: "metronome")
                            Spacer()
                            Text(store.settings.bpmLabel)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Stepper(
                            value: bpmBinding,
                            in: HapTickSettings.minimumBPM...HapTickSettings.maximumBPM,
                            step: store.settings.bpmValue < 10 ? 0.1 : 1
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
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
                    Toggle("Flip starts and stops", isOn: motionToggleBinding)
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

    private var intervalPositionBinding: Binding<Double> {
        Binding(
            get: { HapTickSettings.intervalPosition(for: store.settings.intervalSeconds) },
            set: { store.setIntervalPosition($0) }
        )
    }

    private var bpmBinding: Binding<Double> {
        Binding(
            get: { store.settings.bpmValue },
            set: { store.setBPM($0) }
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
}

#Preview {
    PhoneSettingsView()
}
