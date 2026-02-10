import Foundation
import Combine

@MainActor
final class HUDSettingsStore: ObservableObject {
    @Published var autoPasteEnabled: Bool = false
    @Published var languageMode: String = L10n.tr("settings.language.auto")
    @Published var modelMode: String = OpenAIModel.gpt4oMiniTranscribe.displayName
}
