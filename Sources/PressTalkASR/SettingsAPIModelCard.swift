import SwiftUI

struct SettingsAPIModelCard: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettings

    @Binding var apiKeyInput: String
    @Binding var statusMessage: String
    @Binding var showingMaskedAPIKey: Bool

    let onSyncAPIKeyInputFromStorage: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SettingsCard(accent: UITheme.electricBlue) {
            VStack(alignment: .leading, spacing: 16) {
                cardTitle(L10n.tr("settings.card.api_model"), "cloud")

                sourceRow
                apiInputRow

                VStack(alignment: .leading, spacing: 10) {
                    subtleTag(L10n.tr("settings.model.picker"))
                    Picker(L10n.tr("settings.model.picker"), selection: deferredModelBinding) {
                        Text(L10n.tr("settings.model.mini_short")).tag(OpenAIModel.gpt4oMiniTranscribe.rawValue)
                        Text(L10n.tr("settings.model.accurate_short")).tag(OpenAIModel.gpt4oTranscribe.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .tint(UITheme.electricBlue)

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
                }

                VStack(alignment: .leading, spacing: 10) {
                    subtleTag(L10n.tr("settings.language.picker"))
                    Picker(L10n.tr("settings.language.picker"), selection: deferredLanguageBinding) {
                        ForEach(AppSettings.LanguageMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(UITheme.electricBlue)
                }

                promptEditorBlock

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(UITheme.secondaryText)
                }
            }
        }
    }

    private var sourceRow: some View {
        HStack {
            Text(L10n.tr("settings.api_key_source"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(UITheme.tertiaryText)
            Spacer()
            Text(settings.apiKeySource().title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(UITheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
    }

    private var apiInputRow: some View {
        HStack(spacing: 10) {
            Group {
                if showingMaskedAPIKey {
                    HStack(spacing: 8) {
                        Text(apiKeyInput)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(L10n.tr("settings.api_key.saved"))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.8)
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
            .tint(UITheme.electricBlue)

            Button(L10n.tr("settings.api_key.clear")) {
                statusMessage = viewModel.clearAPIKey()
                onSyncAPIKeyInputFromStorage()
            }
            .buttonStyle(.bordered)
        }
    }

    private var promptEditorBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            subtleTag(L10n.tr("settings.prompt.title"))

            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 0.98, green: 0.38, blue: 0.35)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.96, green: 0.78, blue: 0.28)).frame(width: 7, height: 7)
                    Circle().fill(Color(red: 0.29, green: 0.80, blue: 0.43)).frame(width: 7, height: 7)
                    Text("prompt.md")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(UITheme.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )

                TextEditor(text: $settings.customPrompt)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .frame(minHeight: 112)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(editorBackground)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(UITheme.electricBlue.opacity(0.28), lineWidth: 0.8)
            )

            Toggle(L10n.tr("settings.prompt.enable"), isOn: $settings.promptEnabled)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .toggleStyle(.switch)
                .tint(UITheme.electricBlue)

            HStack {
                Text(L10n.tr("settings.prompt.min_duration"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(UITheme.secondaryText)
                Spacer()
                Stepper(value: $settings.promptMinDurationSeconds, in: 0.2...8.0, step: 0.2) {
                    Text(L10n.tr("unit.seconds_format", settings.promptMinDurationSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .controlSize(.small)
            }

            Text(L10n.tr("settings.prompt.hint"))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(UITheme.tertiaryText)
        }
    }

    private var editorBackground: some View {
        Group {
            if colorScheme == .dark {
                Color(red: 0.10, green: 0.12, blue: 0.16)
            } else {
                Color(red: 0.95, green: 0.97, blue: 1.0)
            }
        }
    }

    private func cardTitle(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(UITheme.electricBlue)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
    }

    private func subtleTag(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(UITheme.tertiaryText)
    }

    private func modelHint(title: String, subtitle: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(UITheme.secondaryText)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? UITheme.electricBlue.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? UITheme.electricBlue.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.8)
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
