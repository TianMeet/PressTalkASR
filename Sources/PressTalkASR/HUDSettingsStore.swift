import Foundation
import Combine

@MainActor
final class HUDSettingsStore: ObservableObject {
    @Published var autoPasteEnabled: Bool = false
    @Published var languageMode: String = "Auto"
    @Published var modelMode: String = "gpt-4o-mini-transcribe"
}
