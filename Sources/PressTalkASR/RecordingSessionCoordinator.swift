import Foundation

enum RecordingStopTrigger {
    case manual
    case autoSilence
}

struct AutoStopDecision {
    let shouldAutoStop: Bool
    let debugInfo: SilenceAutoStopDetector.DebugInfo?
}

@MainActor
final class RecordingSessionCoordinator {
    private var silenceAutoStopDetector = SilenceAutoStopDetector()
    private var recordingStartedAt: Date?
    private var isStoppingRecording = false
    private var hasAutoStopFiredForSession = false

    func beginSession(configuration: SilenceAutoStopDetector.Configuration) {
        silenceAutoStopDetector = SilenceAutoStopDetector(configuration: configuration)
        recordingStartedAt = Date()
        isStoppingRecording = false
        hasAutoStopFiredForSession = false
    }

    func beginStop(trigger: RecordingStopTrigger) -> Bool {
        guard !isStoppingRecording else { return false }
        if trigger == .autoSilence, hasAutoStopFiredForSession {
            return false
        }

        isStoppingRecording = true
        if trigger == .autoSilence {
            hasAutoStopFiredForSession = true
        }
        return true
    }

    func abortStop() {
        isStoppingRecording = false
    }

    func finishStop() {
        isStoppingRecording = false
        recordingStartedAt = nil
    }

    func evaluateAutoStop(
        sample: AudioRecorder.MeterSample,
        isEnabled: Bool,
        configuration: SilenceAutoStopDetector.Configuration
    ) -> AutoStopDecision {
        guard isEnabled else {
            return AutoStopDecision(shouldAutoStop: false, debugInfo: nil)
        }
        guard !isStoppingRecording else {
            return AutoStopDecision(shouldAutoStop: false, debugInfo: nil)
        }
        guard let recordingStartedAt else {
            return AutoStopDecision(shouldAutoStop: false, debugInfo: nil)
        }

        silenceAutoStopDetector.updateConfiguration(configuration)

        let elapsedMs = Date().timeIntervalSince(recordingStartedAt) * 1000
        let (shouldAutoStop, debugInfo) = silenceAutoStopDetector.ingest(
            dbInstant: sample.dbInstant,
            frameDurationMs: sample.frameDurationMs,
            recordingElapsedMs: elapsedMs
        )
        return AutoStopDecision(shouldAutoStop: shouldAutoStop, debugInfo: debugInfo)
    }
}
