import XCTest
@testable import PressTalkASR

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
}
