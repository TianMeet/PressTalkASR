import SwiftUI

struct SettingsAPIModelCard: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettings

    @Binding var apiKeyInput: String
    @Binding var statusMessage: String
    @Binding var showingMaskedAPIKey: Bool

    let onSyncAPIKeyInputFromStorage: () -> Void

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("API & Model", "cloud")

                HStack {
                    Text("API Key Source")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(settings.apiKeySource().title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(UITheme.secondaryText)
                }

                HStack(spacing: 8) {
                    Group {
                        if showingMaskedAPIKey {
                            HStack(spacing: 8) {
                                Text(apiKeyInput)
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Saved")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                            )
                        } else {
                            SecureField("sk-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Button(showingMaskedAPIKey ? "Replace" : "Save") {
                        if showingMaskedAPIKey {
                            apiKeyInput = ""
                            showingMaskedAPIKey = false
                            statusMessage = "请输入新的 Token 并保存。"
                            return
                        }

                        if let error = APIKeyFingerprint.validationError(for: apiKeyInput) {
                            statusMessage = error
                            return
                        }

                        statusMessage = viewModel.saveAPIKey(apiKeyInput)
                        onSyncAPIKeyInputFromStorage()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear") {
                        statusMessage = viewModel.clearAPIKey()
                        onSyncAPIKeyInputFromStorage()
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Model", selection: $settings.selectedModelRawValue) {
                    Text("mini").tag(OpenAIModel.gpt4oMiniTranscribe.rawValue)
                    Text("accurate").tag(OpenAIModel.gpt4oTranscribe.rawValue)
                }
                .pickerStyle(.segmented)

                Picker("Language", selection: $settings.languageModeRawValue) {
                    ForEach(AppSettings.LanguageMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    modelHint(
                        title: "gpt-4o-mini-transcribe",
                        subtitle: "$0.003/min, 成本优先",
                        selected: settings.selectedModel == .gpt4oMiniTranscribe
                    )
                    modelHint(
                        title: "gpt-4o-transcribe",
                        subtitle: "$0.006/min, 准确率优先",
                        selected: settings.selectedModel == .gpt4oTranscribe
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt（术语表 / 标点风格）")
                        .font(.system(size: 12, weight: .medium))
                    TextEditor(text: $settings.customPrompt)
                        .font(.system(size: 13))
                        .frame(minHeight: 92)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                        )

                    Toggle("满足条件时发送 Prompt", isOn: $settings.promptEnabled)
                        .font(.system(size: 12, weight: .medium))

                    HStack {
                        Text("最短录音时长后才发送")
                            .font(.system(size: 12))
                            .foregroundStyle(UITheme.secondaryText)
                        Spacer()
                        Stepper(value: $settings.promptMinDurationSeconds, in: 0.2...8.0, step: 0.2) {
                            Text(String(format: "%.1f s", settings.promptMinDurationSeconds))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .controlSize(.small)
                    }

                    Text("仅在 Prompt 非空且录音时长达到阈值时发送。")
                        .font(.system(size: 11))
                        .foregroundStyle(UITheme.secondaryText)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(UITheme.secondaryText)
                }
            }
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

    private func modelHint(title: String, subtitle: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(UITheme.secondaryText)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? UITheme.successColor.opacity(0.16) : Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? UITheme.successColor.opacity(0.35) : Color.black.opacity(0.07), lineWidth: 0.8)
        )
    }
}
