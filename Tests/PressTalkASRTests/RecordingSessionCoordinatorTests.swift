import Foundation
import XCTest
@testable import PressTalkASR

private final class UptimeSequence: @unchecked Sendable {
    private let values: [TimeInterval]
    private var index = 0
    private let lock = NSLock()

    init(values: [TimeInterval]) {
        self.values = values
    }

    func next() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        let value = values[index]
        if index < values.count - 1 {
            index += 1
        }
        return value
    }
}

@MainActor
final class RecordingSessionCoordinatorTests: XCTestCase {
    func testAutoSilenceCanOnlyBeginStopOncePerSession() {
        let coordinator = RecordingSessionCoordinator()
        coordinator.beginSession(configuration: SilenceAutoStopDetector.Configuration())

        XCTAssertTrue(coordinator.beginStop(trigger: .autoSilence))
        coordinator.abortStop()
        XCTAssertFalse(coordinator.beginStop(trigger: .autoSilence))
    }

    func testEvaluateAutoStopReturnsTriggerAndDebugInfo() {
        let coordinator = RecordingSessionCoordinator()
        coordinator.beginSession(
            configuration: SilenceAutoStopDetector.Configuration(
                silenceThresholdDB: -40,
                silenceDurationMs: 100,
                startGuardMs: 0,
                requireSpeechBeforeAutoStop: false,
                speechActivateDB: -20,
                emaAlpha: 0.2
            )
        )

        let sample = AudioRecorder.MeterSample(
            rms: 0,
            dbInstant: -80,
            frameDurationMs: 400
        )

        let decision = coordinator.evaluateAutoStop(
            sample: sample,
            isEnabled: true,
            configuration: SilenceAutoStopDetector.Configuration(
                silenceThresholdDB: -40,
                silenceDurationMs: 100,
                startGuardMs: 0,
                requireSpeechBeforeAutoStop: false,
                speechActivateDB: -20,
                emaAlpha: 0.2
            )
        )

        XCTAssertTrue(decision.shouldAutoStop)
        XCTAssertNotNil(decision.debugInfo)
    }

    func testElapsedMsDoesNotGoNegativeWhenTimeSourceMovesBackward() {
        let timeline = UptimeSequence(values: [100, 98])
        let coordinator = RecordingSessionCoordinator(uptimeProvider: {
            timeline.next()
        })

        coordinator.beginSession(
            configuration: SilenceAutoStopDetector.Configuration(
                silenceThresholdDB: -40,
                silenceDurationMs: 100,
                startGuardMs: 0,
                requireSpeechBeforeAutoStop: false,
                speechActivateDB: -20,
                emaAlpha: 0.2
            )
        )

        let sample = AudioRecorder.MeterSample(
            rms: 0,
            dbInstant: -80,
            frameDurationMs: 400
        )

        let decision = coordinator.evaluateAutoStop(
            sample: sample,
            isEnabled: true,
            configuration: SilenceAutoStopDetector.Configuration(
                silenceThresholdDB: -40,
                silenceDurationMs: 100,
                startGuardMs: 0,
                requireSpeechBeforeAutoStop: false,
                speechActivateDB: -20,
                emaAlpha: 0.2
            )
        )

        XCTAssertEqual(decision.debugInfo?.recordingElapsedMs, 0)
        XCTAssertTrue(decision.shouldAutoStop)
    }
}
