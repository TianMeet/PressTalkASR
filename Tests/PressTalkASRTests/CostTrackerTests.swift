import XCTest
@testable import PressTalkASR

@MainActor
final class CostTrackerTests: XCTestCase {
    func testUsesTokenUsageWhenAvailable() {
        let tracker = CostTracker(defaults: makeDefaults())
        let usage = TranscriptionUsage(inputTokens: 14, outputTokens: 45, totalTokens: 59)

        tracker.add(seconds: 60, usage: usage)

        XCTAssertEqual(tracker.secondsToday(), 60, accuracy: 0.001)
        XCTAssertEqual(tracker.estimatedCostTodayMini(), 0.0002425, accuracy: 0.0000001)
        XCTAssertEqual(tracker.estimatedCostTodayAccurate(), 0.000485, accuracy: 0.0000001)
    }

    func testFallsBackToDurationEstimateWithoutUsage() {
        let tracker = CostTracker(defaults: makeDefaults())

        tracker.add(seconds: 60, usage: nil)

        XCTAssertEqual(tracker.estimatedCostTodayMini(), 0.003, accuracy: 0.0000001)
        XCTAssertEqual(tracker.estimatedCostTodayAccurate(), 0.006, accuracy: 0.0000001)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CostTrackerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
