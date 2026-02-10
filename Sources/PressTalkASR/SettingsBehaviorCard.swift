import SwiftUI

struct SettingsBehaviorCard: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettings

    @Binding var statusMessage: String
    @Binding var isRecordingHotkey: Bool

    let onStartHotkeyCapture: () -> Void
    let onStopHotkeyCapture: () -> Void

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle(L10n.tr("settings.card.behavior"), "switch.2")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.hotkey.title"))
                            Text(L10n.tr("settings.hotkey.subtitle"))
                                .font(.system(size: 11))
                                .foregroundStyle(UITheme.secondaryText)
                        }

                        Spacer()
                        KeycapView(settings.hotkeyShortcut.keycapTokens)
                    }

                    HStack(spacing: 8) {
                        Button(isRecordingHotkey ? L10n.tr("settings.hotkey.recording_button") : L10n.tr("settings.hotkey.record_button")) {
                            if isRecordingHotkey {
                                onStopHotkeyCapture()
                                statusMessage = L10n.tr("settings.status.hotkey_capture_cancelled")
                            } else {
                                onStartHotkeyCapture()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(L10n.tr("settings.hotkey.reset_default")) {
                            onStopHotkeyCapture()
                            statusMessage = viewModel.resetHotkeyToDefault()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if isRecordingHotkey {
                        Text(L10n.tr("settings.hotkey.capture_hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Divider()

                Toggle(isOn: $settings.enableVADTrim) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.toggle.vad_trim.title"))
                        Text(L10n.tr("settings.toggle.vad_trim.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Toggle(isOn: $settings.autoPasteEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.toggle.auto_paste.title"))
                        Text(L10n.tr("settings.toggle.auto_paste.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Toggle(isOn: $settings.enableAutoStopOnSilence) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.toggle.auto_stop_silence.title"))
                        Text(L10n.tr("settings.toggle.auto_stop_silence.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.hud.position.title"))
                        Text(L10n.tr("settings.hud.position.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                    Spacer()
                    Picker(L10n.tr("settings.hud.position.picker"), selection: hudAnchorSelection) {
                        ForEach(HUDAnchorPosition.allCases) { anchor in
                            Text(anchor.displayName).tag(anchor.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 138)
                }

                DisclosureGroup(L10n.tr("settings.advanced.auto_stop")) {
                    VStack(alignment: .leading, spacing: 8) {
                        stepperRow(
                            title: L10n.tr("settings.advanced.silence_threshold"),
                            valueText: L10n.tr("unit.db_format", settings.silenceThresholdDB)
                        ) {
                            Stepper("", value: $settings.silenceThresholdDB, in: -70 ... -20, step: 1)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        stepperRow(
                            title: L10n.tr("settings.advanced.silence_duration"),
                            valueText: L10n.tr("unit.ms_format", settings.silenceDurationMs)
                        ) {
                            Stepper("", value: $settings.silenceDurationMs, in: 300 ... 3000, step: 100)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        stepperRow(
                            title: L10n.tr("settings.advanced.start_guard"),
                            valueText: L10n.tr("unit.ms_format", settings.autoStopStartGuardMs)
                        ) {
                            Stepper("", value: $settings.autoStopStartGuardMs, in: 100 ... 1200, step: 50)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Toggle(L10n.tr("settings.advanced.require_speech_before_auto_stop"), isOn: $settings.requireSpeechBeforeAutoStop)
                            .font(.system(size: 12, weight: .medium))

                        stepperRow(
                            title: L10n.tr("settings.advanced.speech_activate_threshold"),
                            valueText: L10n.tr("unit.db_format", settings.speechActivateThresholdDB)
                        ) {
                            Stepper("", value: $settings.speechActivateThresholdDB, in: -60 ... -20, step: 1)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Toggle(L10n.tr("settings.advanced.debug_auto_stop_logs"), isOn: $settings.autoStopDebugLogs)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private func cardTitle(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(UITheme.successColor)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
    }

    private func stepperRow<Control: View>(
        title: String,
        valueText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(UITheme.secondaryText)
            Spacer()
            Text(valueText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            control()
        }
    }

    private var hudAnchorSelection: Binding<String> {
        Binding(
            get: { settings.hudAnchorPositionRawValue },
            set: { rawValue in
                guard settings.hudAnchorPositionRawValue != rawValue else { return }
                DispatchQueue.main.async {
                    settings.hudAnchorPositionRawValue = rawValue
                }
            }
        )
    }
}
