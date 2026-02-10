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
                cardTitle(L10n.tr("settings.card.api_model"), "cloud")

                HStack {
                    Text(L10n.tr("settings.api_key_source"))
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
                                Text(L10n.tr("settings.api_key.saved"))
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
                            SecureField(L10n.tr("settings.api_key.placeholder"), text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Button(showingMaskedAPIKey ? L10n.tr("settings.api_key.replace") : L10n.tr("settings.api_key.save")) {
                        if showingMaskedAPIKey {
                            apiKeyInput = ""
                            showingMaskedAPIKey = false
                            statusMessage = L10n.tr("settings.api_key.enter_new")
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

                    Button(L10n.tr("settings.api_key.clear")) {
                        statusMessage = viewModel.clearAPIKey()
                        onSyncAPIKeyInputFromStorage()
                    }
                    .buttonStyle(.bordered)
                }

                Picker(L10n.tr("settings.model.picker"), selection: deferredModelBinding) {
                    Text(L10n.tr("settings.model.mini_short")).tag(OpenAIModel.gpt4oMiniTranscribe.rawValue)
                    Text(L10n.tr("settings.model.accurate_short")).tag(OpenAIModel.gpt4oTranscribe.rawValue)
                }
                .pickerStyle(.segmented)

                Picker(L10n.tr("settings.language.picker"), selection: deferredLanguageBinding) {
                    ForEach(AppSettings.LanguageMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    modelHint(
                        title: "gpt-4o-mini-transcribe",
                        subtitle: L10n.tr("settings.model.mini.subtitle"),
                        selected: settings.selectedModel == .gpt4oMiniTranscribe
                    )
                    modelHint(
                        title: "gpt-4o-transcribe",
                        subtitle: L10n.tr("settings.model.accurate.subtitle"),
                        selected: settings.selectedModel == .gpt4oTranscribe
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("settings.prompt.title"))
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

                    Toggle(L10n.tr("settings.prompt.enable"), isOn: $settings.promptEnabled)
                        .font(.system(size: 12, weight: .medium))

                    HStack {
                        Text(L10n.tr("settings.prompt.min_duration"))
                            .font(.system(size: 12))
                            .foregroundStyle(UITheme.secondaryText)
                        Spacer()
                        Stepper(value: $settings.promptMinDurationSeconds, in: 0.2...8.0, step: 0.2) {
                            Text(L10n.tr("unit.seconds_format", settings.promptMinDurationSeconds))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .controlSize(.small)
                    }

                    Text(L10n.tr("settings.prompt.hint"))
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

    private var deferredModelBinding: Binding<String> {
        Binding(
            get: { settings.selectedModelRawValue },
            set: { newValue in
                guard settings.selectedModelRawValue != newValue else { return }
                DispatchQueue.main.async {
                    settings.selectedModelRawValue = newValue
                }
            }
        )
    }

    private var deferredLanguageBinding: Binding<String> {
        Binding(
            get: { settings.languageModeRawValue },
            set: { newValue in
                guard settings.languageModeRawValue != newValue else { return }
                DispatchQueue.main.async {
                    settings.languageModeRawValue = newValue
                }
            }
        )
    }
}
