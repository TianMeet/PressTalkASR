import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    enum TranscriptionRoute: String, CaseIterable, Identifiable {
        case uploadStreaming = "uploadStreaming"
        case realtime = "realtime"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .uploadStreaming:
                return "Upload Streaming"
            case .realtime:
                return "Realtime"
            }
        }
    }

    enum APIKeySource {
        case localCache
        case environment
        case none

        var title: String {
            switch self {
            case .localCache:
                return "Local Cache"
            case .environment:
                return "Environment"
            case .none:
                return "Not Set"
            }
        }
    }

    enum LanguageMode: String, CaseIterable, Identifiable {
        case auto = "Auto"
        case chinese = "中文"
        case english = "English"

        var id: String { rawValue }
        var displayName: String { rawValue }
    }

    private enum Keys {
        static let autoPasteEnabled = "autoPasteEnabled"
        static let enableVADTrim = "enableVADTrim"
        static let enableAutoStopOnSilence = "enableAutoStopOnSilence"
        static let silenceThresholdDB = "silenceThresholdDB"
        static let silenceDurationMs = "silenceDurationMs"
        static let autoStopStartGuardMs = "autoStopStartGuardMs"
        static let requireSpeechBeforeAutoStop = "requireSpeechBeforeAutoStop"
        static let speechActivateThresholdDB = "speechActivateThresholdDB"
        static let autoStopDebugLogs = "autoStopDebugLogs"
        static let transcriptionRouteRawValue = "transcriptionRouteRawValue"
        static let realtimeSilenceDurationMs = "realtimeSilenceDurationMs"
        static let realtimePrefixPaddingMs = "realtimePrefixPaddingMs"
        static let modelRawValue = "modelRawValue"
        static let customPrompt = "customPrompt"
        static let promptEnabled = "promptEnabled"
        static let promptMinDurationSeconds = "promptMinDurationSeconds"
        static let languageModeRawValue = "languageModeRawValue"
        static let useFullWidthPunctuation = "useFullWidthPunctuation"
        static let apiKeyLocalCache = "apiKeyLocalCache"
    }

    private let defaults = UserDefaults.standard
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

    @Published var transcriptionRouteRawValue: String {
        didSet { defaults.set(transcriptionRouteRawValue, forKey: Keys.transcriptionRouteRawValue) }
    }

    @Published var realtimeSilenceDurationMs: Double {
        didSet { defaults.set(realtimeSilenceDurationMs, forKey: Keys.realtimeSilenceDurationMs) }
    }

    @Published var realtimePrefixPaddingMs: Double {
        didSet { defaults.set(realtimePrefixPaddingMs, forKey: Keys.realtimePrefixPaddingMs) }
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
        didSet { defaults.set(languageModeRawValue, forKey: Keys.languageModeRawValue) }
    }

    @Published var useFullWidthPunctuation: Bool {
        didSet { defaults.set(useFullWidthPunctuation, forKey: Keys.useFullWidthPunctuation) }
    }

    init() {
        autoPasteEnabled = defaults.object(forKey: Keys.autoPasteEnabled) as? Bool ?? false
        enableVADTrim = defaults.object(forKey: Keys.enableVADTrim) as? Bool ?? true
        enableAutoStopOnSilence = defaults.object(forKey: Keys.enableAutoStopOnSilence) as? Bool ?? true
        silenceThresholdDB = AppSettings.floatValue(defaults: defaults, key: Keys.silenceThresholdDB, fallback: -45)
        silenceDurationMs = AppSettings.doubleValue(defaults: defaults, key: Keys.silenceDurationMs, fallback: 1000)
        autoStopStartGuardMs = AppSettings.doubleValue(defaults: defaults, key: Keys.autoStopStartGuardMs, fallback: 300)
        requireSpeechBeforeAutoStop = defaults.object(forKey: Keys.requireSpeechBeforeAutoStop) as? Bool ?? true
        speechActivateThresholdDB = AppSettings.floatValue(defaults: defaults, key: Keys.speechActivateThresholdDB, fallback: -32)
        autoStopDebugLogs = defaults.object(forKey: Keys.autoStopDebugLogs) as? Bool ?? false
        transcriptionRouteRawValue = defaults.string(forKey: Keys.transcriptionRouteRawValue) ?? TranscriptionRoute.uploadStreaming.rawValue
        realtimeSilenceDurationMs = AppSettings.doubleValue(defaults: defaults, key: Keys.realtimeSilenceDurationMs, fallback: 600)
        realtimePrefixPaddingMs = AppSettings.doubleValue(defaults: defaults, key: Keys.realtimePrefixPaddingMs, fallback: 240)
        selectedModelRawValue = defaults.string(forKey: Keys.modelRawValue) ?? OpenAIModel.gpt4oMiniTranscribe.rawValue
        customPrompt = defaults.string(forKey: Keys.customPrompt) ?? ""
        promptEnabled = defaults.object(forKey: Keys.promptEnabled) as? Bool ?? true
        promptMinDurationSeconds = defaults.object(forKey: Keys.promptMinDurationSeconds) as? Double ?? 1.0
        languageModeRawValue = defaults.string(forKey: Keys.languageModeRawValue) ?? LanguageMode.auto.rawValue
        useFullWidthPunctuation = defaults.object(forKey: Keys.useFullWidthPunctuation) as? Bool ?? true
        refreshAPIKeyCache()
    }

    var selectedModel: OpenAIModel {
        get { OpenAIModel(rawValue: selectedModelRawValue) ?? .gpt4oMiniTranscribe }
        set { selectedModelRawValue = newValue.rawValue }
    }

    var transcriptionRoute: TranscriptionRoute {
        get { TranscriptionRoute(rawValue: transcriptionRouteRawValue) ?? .uploadStreaming }
        set { transcriptionRouteRawValue = newValue.rawValue }
    }

    var languageMode: LanguageMode {
        get { LanguageMode(rawValue: languageModeRawValue) ?? .auto }
        set { languageModeRawValue = newValue.rawValue }
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

        if let envValue = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envValue.isEmpty {
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
        apiKeySourceState == .localCache
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

    var realtimeConfiguration: RealtimeTranscribeClient.Configuration {
        RealtimeTranscribeClient.Configuration(
            silenceDurationMs: Int(realtimeSilenceDurationMs),
            prefixPaddingMs: Int(realtimePrefixPaddingMs)
        )
    }

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearAPIKey()
            return
        }

        defaults.set(trimmed, forKey: Keys.apiKeyLocalCache)
        cachedAPIKey = trimmed
        apiKeySourceState = .localCache
    }

    func clearAPIKey() {
        defaults.removeObject(forKey: Keys.apiKeyLocalCache)
        cachedAPIKey = nil

        if let envValue = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envValue.isEmpty {
            apiKeySourceState = .environment
        } else {
            apiKeySourceState = .none
        }
    }

    private func refreshAPIKeyCache() {
        if let value = defaults.string(forKey: Keys.apiKeyLocalCache), !value.isEmpty {
            cachedAPIKey = value
            apiKeySourceState = .localCache
            return
        }

        cachedAPIKey = nil
        if let envValue = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envValue.isEmpty {
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
}
