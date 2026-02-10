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
                cardTitle("Behavior", "switch.2")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Global Hotkey")
                            Text("用于开始/结束录音")
                                .font(.system(size: 11))
                                .foregroundStyle(UITheme.secondaryText)
                        }

                        Spacer()
                        KeycapView(settings.hotkeyShortcut.keycapTokens)
                    }

                    HStack(spacing: 8) {
                        Button(isRecordingHotkey ? "Press Keys..." : "Record Shortcut") {
                            if isRecordingHotkey {
                                onStopHotkeyCapture()
                                statusMessage = "已取消快捷键录制。"
                            } else {
                                onStartHotkeyCapture()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Reset Default") {
                            onStopHotkeyCapture()
                            statusMessage = viewModel.resetHotkeyToDefault()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if isRecordingHotkey {
                        Text("按下新的组合键（需包含 ⌘ / ⌥ / ⌃ / ⇧），按 Esc 取消。")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Divider()

                Toggle(isOn: $settings.enableVADTrim) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable VAD Trim")
                        Text("录音前后自动裁剪静音片段")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Toggle(isOn: $settings.autoPasteEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Paste")
                        Text("复制后自动发送 Cmd+V 到前台应用")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Toggle(isOn: $settings.enableAutoStopOnSilence) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Stop on Silence")
                        Text("说完停顿后自动结束并转写")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HUD Position")
                        Text("转写浮窗显示位置")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                    Spacer()
                    Picker("HUD Position", selection: hudAnchorSelection) {
                        ForEach(HUDAnchorPosition.allCases) { anchor in
                            Text(anchor.displayName).tag(anchor.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 138)
                }

                DisclosureGroup("Advanced (Auto Stop)") {
                    VStack(alignment: .leading, spacing: 8) {
                        stepperRow(
                            title: "Silence Threshold",
                            valueText: String(format: "%.0f dB", settings.silenceThresholdDB)
                        ) {
                            Stepper("", value: $settings.silenceThresholdDB, in: -70 ... -20, step: 1)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        stepperRow(
                            title: "Silence Duration",
                            valueText: String(format: "%.0f ms", settings.silenceDurationMs)
                        ) {
                            Stepper("", value: $settings.silenceDurationMs, in: 300 ... 3000, step: 100)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        stepperRow(
                            title: "Start Guard",
                            valueText: String(format: "%.0f ms", settings.autoStopStartGuardMs)
                        ) {
                            Stepper("", value: $settings.autoStopStartGuardMs, in: 100 ... 1200, step: 50)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Toggle("Require speech before auto-stop", isOn: $settings.requireSpeechBeforeAutoStop)
                            .font(.system(size: 12, weight: .medium))

                        stepperRow(
                            title: "Speech Activate Threshold",
                            valueText: String(format: "%.0f dB", settings.speechActivateThresholdDB)
                        ) {
                            Stepper("", value: $settings.speechActivateThresholdDB, in: -60 ... -20, step: 1)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Toggle("Debug Auto-stop Logs", isOn: $settings.autoStopDebugLogs)
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
