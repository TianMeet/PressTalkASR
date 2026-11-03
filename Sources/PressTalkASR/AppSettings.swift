import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    enum APIKeySource {
        case keychain
        case localCache
        case environment
        case none

        var title: String {
            switch self {
            case .keychain:
                return L10n.tr("settings.api_source.keychain")
            case .localCache:
                return L10n.tr("settings.api_source.local_cache")
            case .environment:
                return L10n.tr("settings.api_source.environment")
            case .none:
                return L10n.tr("settings.api_source.not_set")
            }
        }
    }

    enum LanguageMode: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case chinese = "中文"
        case english = "English"

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .auto:
                return L10n.tr("settings.language.auto")
            case .chinese:
                return L10n.tr("settings.language.chinese")
            case .english:
                return L10n.tr("settings.language.english")
            }
        }
    }

    private enum Keys {
        static let autoPasteEnabled = "autoPasteEnabled"
        static let enableVADTrim = "enableVADTrim"
        static let enableAutoStopOnSilence = "enableAutoStopOnSilence"
        static let hudAnchorPositionRawValue = "hudAnchorPositionRawValue"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let silenceThresholdDB = "silenceThresholdDB"
        static let silenceDurationMs = "silenceDurationMs"
        static let autoStopStartGuardMs = "autoStopStartGuardMs"
        static let requireSpeechBeforeAutoStop = "requireSpeechBeforeAutoStop"
        static let speechActivateThresholdDB = "speechActivateThresholdDB"
        static let autoStopDebugLogs = "autoStopDebugLogs"
        static let modelRawValue = "modelRawValue"
        static let customPrompt = "customPrompt"
        static let promptEnabled = "promptEnabled"
        static let promptMinDurationSeconds = "promptMinDurationSeconds"
        static let languageModeRawValue = "languageModeRawValue"
        static let apiKeyLocalCache = "apiKeyLocalCache"
    }

    private let defaults: UserDefaults
    private let apiKeyStore: any APIKeyStoring
    private let environment: [String: String]
    private var cachedAPIKey: String?

    @Published private(set) var apiKeySourceState: APIKeySource = .none

    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: Keys.autoPasteEnabled) }
    }

    @Published var enableVADTrim: Bool {
        didSet { defaults.set(enableVADTrim, forKey: Keys.enableVADTrim) }
    }

    @Published var enableAutoStopOnSilence: Bool {
        didSet { defaults.set(enableAutoStopOnSilence, forKey: Keys.enableAutoStopOnSilence) }
    }

    @Published var hudAnchorPositionRawValue: String {
        didSet { defaults.set(hudAnchorPositionRawValue, forKey: Keys.hudAnchorPositionRawValue) }
    }

    @Published var hotkeyKeyCode: Int {
        didSet { defaults.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    @Published var hotkeyModifiers: Int {
        didSet { defaults.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    @Published var silenceThresholdDB: Float {
        didSet { defaults.set(silenceThresholdDB, forKey: Keys.silenceThresholdDB) }
    }

    @Published var silenceDurationMs: Double {
        didSet { defaults.set(silenceDurationMs, forKey: Keys.silenceDurationMs) }
    }

    @Published var autoStopStartGuardMs: Double {
        didSet { defaults.set(autoStopStartGuardMs, forKey: Keys.autoStopStartGuardMs) }
    }

    @Published var requireSpeechBeforeAutoStop: Bool {
        didSet { defaults.set(requireSpeechBeforeAutoStop, forKey: Keys.requireSpeechBeforeAutoStop) }
    }

    @Published var speechActivateThresholdDB: Float {
        didSet { defaults.set(speechActivateThresholdDB, forKey: Keys.speechActivateThresholdDB) }
    }

    @Published var autoStopDebugLogs: Bool {
        didSet { defaults.set(autoStopDebugLogs, forKey: Keys.autoStopDebugLogs) }
    }

    @Published var selectedModelRawValue: String {
        didSet { defaults.set(selectedModelRawValue, forKey: Keys.modelRawValue) }
    }

    @Published var customPrompt: String {
        didSet { defaults.set(customPrompt, forKey: Keys.customPrompt) }
    }

    @Published var promptEnabled: Bool {
        didSet { defaults.set(promptEnabled, forKey: Keys.promptEnabled) }
    }

    @Published var promptMinDurationSeconds: Double {
        didSet { defaults.set(promptMinDurationSeconds, forKey: Keys.promptMinDurationSeconds) }
    }

    @Published var languageModeRawValue: String {
        didSet {
            defaults.set(languageModeRawValue, forKey: Keys.languageModeRawValue)
            applyLocalizationPreference()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        apiKeyStore: any APIKeyStoring = KeychainAPIKeyStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.apiKeyStore = apiKeyStore
        self.environment = environment
        autoPasteEnabled = defaults.object(forKey: Keys.autoPasteEnabled) as? Bool ?? false
        enableVADTrim = defaults.object(forKey: Keys.enableVADTrim) as? Bool ?? true
        enableAutoStopOnSilence = defaults.object(forKey: Keys.enableAutoStopOnSilence) as? Bool ?? true
        hudAnchorPositionRawValue = defaults.string(forKey: Keys.hudAnchorPositionRawValue) ?? HUDAnchorPosition.bottomRight.rawValue
        hotkeyKeyCode = AppSettings.intValue(defaults: defaults, key: Keys.hotkeyKeyCode, fallback: Int(HotkeyShortcut.defaultPushToTalk.keyCode))
        hotkeyModifiers = AppSettings.intValue(defaults: defaults, key: Keys.hotkeyModifiers, fallback: Int(HotkeyShortcut.defaultPushToTalk.carbonModifiers))
        silenceThresholdDB = AppSettings.floatValue(defaults: defaults, key: Keys.silenceThresholdDB, fallback: -45)
        silenceDurationMs = AppSettings.doubleValue(defaults: defaults, key: Keys.silenceDurationMs, fallback: 1000)
        autoStopStartGuardMs = AppSettings.doubleValue(defaults: defaults, key: Keys.autoStopStartGuardMs, fallback: 300)
        requireSpeechBeforeAutoStop = defaults.object(forKey: Keys.requireSpeechBeforeAutoStop) as? Bool ?? true
        speechActivateThresholdDB = AppSettings.floatValue(defaults: defaults, key: Keys.speechActivateThresholdDB, fallback: -32)
        autoStopDebugLogs = defaults.object(forKey: Keys.autoStopDebugLogs) as? Bool ?? false
        selectedModelRawValue = defaults.string(forKey: Keys.modelRawValue) ?? OpenAIModel.gpt4oMiniTranscribe.rawValue
        customPrompt = defaults.string(forKey: Keys.customPrompt) ?? ""
        promptEnabled = defaults.object(forKey: Keys.promptEnabled) as? Bool ?? true
        promptMinDurationSeconds = defaults.object(forKey: Keys.promptMinDurationSeconds) as? Double ?? 1.0
        languageModeRawValue = defaults.string(forKey: Keys.languageModeRawValue) ?? LanguageMode.auto.rawValue
        refreshAPIKeyCache()
        applyLocalizationPreference()
    }

    var selectedModel: OpenAIModel {
        get { OpenAIModel(rawValue: selectedModelRawValue) ?? .gpt4oMiniTranscribe }
        set { selectedModelRawValue = newValue.rawValue }
    }

    var hotkeyShortcut: HotkeyShortcut {
        get {
            let shortcut = HotkeyShortcut(
                keyCode: UInt32(hotkeyKeyCode),
                carbonModifiers: UInt32(hotkeyModifiers)
            )
            return shortcut.isValid ? shortcut : .defaultPushToTalk
        }
        set {
            hotkeyKeyCode = Int(newValue.keyCode)
            hotkeyModifiers = Int(newValue.carbonModifiers)
        }
    }

    var languageMode: LanguageMode {
        get { LanguageMode(rawValue: languageModeRawValue) ?? .auto }
        set { languageModeRawValue = newValue.rawValue }
    }

    var hudAnchorPosition: HUDAnchorPosition {
        get { HUDAnchorPosition(rawValue: hudAnchorPositionRawValue) ?? .bottomRight }
        set { hudAnchorPositionRawValue = newValue.rawValue }
    }

    var preferredLanguageCode: String? {
        switch languageMode {
        case .auto:
            return nil
        case .chinese:
            return "zh"
        case .english:
            return "en"
        }
    }

    func resolvedAPIKey() -> String? {
        if let cachedAPIKey, !cachedAPIKey.isEmpty {
            return cachedAPIKey
        }

        if let envValue = environment["OPENAI_API_KEY"], !envValue.isEmpty {
            return envValue
        }

        return nil
    }

    func maskedAPIKeyDisplay() -> String? {
        guard let key = resolvedAPIKey() else { return nil }
        return APIKeyFingerprint.masked(key: key)
    }

    func apiKeySource() -> APIKeySource {
        apiKeySourceState
    }

    func hasStoredAPIKey() -> Bool {
        apiKeySourceState == .keychain || apiKeySourceState == .localCache
    }

    func effectivePrompt(forRecordingSeconds seconds: TimeInterval) -> String? {
        guard promptEnabled else { return nil }
        let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard seconds >= promptMinDurationSeconds else { return nil }
        return trimmed
    }

    var autoStopConfiguration: SilenceAutoStopDetector.Configuration {
        SilenceAutoStopDetector.Configuration(
            silenceThresholdDB: silenceThresholdDB,
            silenceDurationMs: silenceDurationMs,
            startGuardMs: autoStopStartGuardMs,
            requireSpeechBeforeAutoStop: requireSpeechBeforeAutoStop,
            speechActivateDB: speechActivateThresholdDB,
            emaAlpha: 0.2
        )
    }

    func saveAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try clearAPIKey()
            return
        }

        try apiKeyStore.save(trimmed)
        defaults.removeObject(forKey: Keys.apiKeyLocalCache)
        cachedAPIKey = trimmed
        apiKeySourceState = .keychain
    }

    func clearAPIKey() throws {
        try apiKeyStore.delete()
        defaults.removeObject(forKey: Keys.apiKeyLocalCache)
        cachedAPIKey = nil

        if let envValue = environment["OPENAI_API_KEY"], !envValue.isEmpty {
            apiKeySourceState = .environment
        } else {
            apiKeySourceState = .none
        }
    }

    private func refreshAPIKeyCache() {
        if let value = try? apiKeyStore.read(), !value.isEmpty {
            cachedAPIKey = value
            apiKeySourceState = .keychain
            defaults.removeObject(forKey: Keys.apiKeyLocalCache)
            return
        }

        // One-time migration from the legacy plaintext UserDefaults entry.
        if let value = defaults.string(forKey: Keys.apiKeyLocalCache), !value.isEmpty {
            do {
                try apiKeyStore.save(value)
                defaults.removeObject(forKey: Keys.apiKeyLocalCache)
                cachedAPIKey = value
                apiKeySourceState = .keychain
            } catch {
                // Preserve access for this launch if Keychain is temporarily
                // unavailable; the next launch will retry migration.
                cachedAPIKey = value
                apiKeySourceState = .localCache
            }
            return
        }

        cachedAPIKey = nil
        if let envValue = environment["OPENAI_API_KEY"], !envValue.isEmpty {
            apiKeySourceState = .environment
        } else {
            apiKeySourceState = .none
        }
    }

    private static func floatValue(defaults: UserDefaults, key: String, fallback: Float) -> Float {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }
        return number.floatValue
    }

    private static func doubleValue(defaults: UserDefaults, key: String, fallback: Double) -> Double {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }
        return number.doubleValue
    }

    private static func intValue(defaults: UserDefaults, key: String, fallback: Int) -> Int {
        guard let number = defaults.object(forKey: key) as? NSNumber else {
            return fallback
        }
        return number.intValue
    }

    private func applyLocalizationPreference() {
        switch languageMode {
        case .auto:
            LocalizationStore.shared.setForcedLanguageIdentifier(nil)
        case .chinese:
            LocalizationStore.shared.setForcedLanguageIdentifier("zh-Hans")
        case .english:
            LocalizationStore.shared.setForcedLanguageIdentifier("en")
        }
    }
}
