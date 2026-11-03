import Foundation
import Combine

@MainActor
final class CostTracker: ObservableObject {
    private enum Keys {
        static let dailySeconds = "dailyTranscriptionSeconds"
        static let dailyInputTokens = "dailyTranscriptionInputTokens"
        static let dailyOutputTokens = "dailyTranscriptionOutputTokens"
        static let dailyTokenPricedSeconds = "dailyTranscriptionTokenPricedSeconds"
    }

    @Published private(set) var dailySeconds: [String: TimeInterval]

    private var dailyInputTokens: [String: Int]
    private var dailyOutputTokens: [String: Int]
    private var dailyTokenPricedSeconds: [String: TimeInterval]
    private let defaults: UserDefaults
    private let calendar = Calendar(identifier: .gregorian)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dailySeconds = Self.decode([String: TimeInterval].self, key: Keys.dailySeconds, defaults: defaults) ?? [:]
        dailyInputTokens = Self.decode([String: Int].self, key: Keys.dailyInputTokens, defaults: defaults) ?? [:]
        dailyOutputTokens = Self.decode([String: Int].self, key: Keys.dailyOutputTokens, defaults: defaults) ?? [:]
        dailyTokenPricedSeconds = Self.decode(
            [String: TimeInterval].self,
            key: Keys.dailyTokenPricedSeconds,
            defaults: defaults
        ) ?? [:]
    }

    func add(seconds: TimeInterval, on date: Date = Date()) {
        guard seconds > 0 else { return }
        let key = dayKey(for: date)
        dailySeconds[key, default: 0] += seconds
        persist()
    }

    func add(
        seconds: TimeInterval,
        usage: TranscriptionUsage?,
        on date: Date = Date()
    ) {
        guard seconds > 0 else { return }
        let key = dayKey(for: date)
        dailySeconds[key, default: 0] += seconds

        if let usage, usage.hasTokenCounts {
            dailyInputTokens[key, default: 0] += max(0, usage.inputTokens ?? 0)
            dailyOutputTokens[key, default: 0] += max(0, usage.outputTokens ?? 0)
            dailyTokenPricedSeconds[key, default: 0] += seconds
        }
        persist()
    }

    func secondsToday() -> TimeInterval {
        dailySeconds[dayKey(for: Date())] ?? 0
    }

    func estimatedCostToday(for model: OpenAIModel) -> Double {
        let key = dayKey(for: Date())
        let inputCost = Double(dailyInputTokens[key] ?? 0)
            * model.inputCostPerMillionTokensUSD / 1_000_000
        let outputCost = Double(dailyOutputTokens[key] ?? 0)
            * model.outputCostPerMillionTokensUSD / 1_000_000

        let totalSeconds = dailySeconds[key] ?? 0
        let tokenPricedSeconds = min(totalSeconds, dailyTokenPricedSeconds[key] ?? 0)
        let durationFallbackCost = max(0, totalSeconds - tokenPricedSeconds) / 60.0
            * model.costPerMinuteUSD
        return inputCost + outputCost + durationFallbackCost
    }

    func estimatedCostTodayMini() -> Double {
        estimatedCostToday(for: .gpt4oMiniTranscribe)
    }

    func estimatedCostTodayAccurate() -> Double {
        estimatedCostToday(for: .gpt4oTranscribe)
    }

    private func persist() {
        persist(dailySeconds, key: Keys.dailySeconds)
        persist(dailyInputTokens, key: Keys.dailyInputTokens)
        persist(dailyOutputTokens, key: Keys.dailyOutputTokens)
        persist(dailyTokenPricedSeconds, key: Keys.dailyTokenPricedSeconds)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let encoded = try? JSONEncoder().encode(value) else { return }
        defaults.set(encoded, forKey: key)
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
