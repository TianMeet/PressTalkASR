import Foundation
import Combine

@MainActor
final class CostTracker: ObservableObject {
    private enum Keys {
        static let dailySeconds = "dailyTranscriptionSeconds"
    }

    @Published private(set) var dailySeconds: [String: TimeInterval]

    private let defaults = UserDefaults.standard
    private let calendar = Calendar(identifier: .gregorian)

    init() {
        if let data = defaults.data(forKey: Keys.dailySeconds),
           let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            dailySeconds = decoded
        } else {
            dailySeconds = [:]
        }
    }

    func add(seconds: TimeInterval, on date: Date = Date()) {
        guard seconds > 0 else { return }
        let key = dayKey(for: date)
        dailySeconds[key, default: 0] += seconds
        persist()
    }

    func secondsToday() -> TimeInterval {
        dailySeconds[dayKey(for: Date())] ?? 0
    }

    func estimatedCostToday(for model: OpenAIModel) -> Double {
        let minutes = secondsToday() / 60.0
        return minutes * model.costPerMinuteUSD
    }

    func estimatedCostTodayMini() -> Double {
        let minutes = secondsToday() / 60.0
        return minutes * OpenAIModel.gpt4oMiniTranscribe.costPerMinuteUSD
    }

    func estimatedCostTodayAccurate() -> Double {
        let minutes = secondsToday() / 60.0
        return minutes * OpenAIModel.gpt4oTranscribe.costPerMinuteUSD
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(dailySeconds) else { return }
        defaults.set(encoded, forKey: Keys.dailySeconds)
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
