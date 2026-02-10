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
    private var recordingStartedUptime: TimeInterval?
    private var isStoppingRecording = false
    private var hasAutoStopFiredForSession = false
    private let uptimeProvider: @Sendable () -> TimeInterval

    init(uptimeProvider: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptimeProvider = uptimeProvider
    }

    func beginSession(configuration: SilenceAutoStopDetector.Configuration) {
        silenceAutoStopDetector = SilenceAutoStopDetector(configuration: configuration)
        recordingStartedUptime = uptimeProvider()
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
        recordingStartedUptime = nil
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
        guard let recordingStartedUptime else {
            return AutoStopDecision(shouldAutoStop: false, debugInfo: nil)
        }

        silenceAutoStopDetector.updateConfiguration(configuration)

        let elapsedMs = max(0, uptimeProvider() - recordingStartedUptime) * 1000
        let (shouldAutoStop, debugInfo) = silenceAutoStopDetector.ingest(
            dbInstant: sample.dbInstant,
            frameDurationMs: sample.frameDurationMs,
            recordingElapsedMs: elapsedMs
        )
        return AutoStopDecision(shouldAutoStop: shouldAutoStop, debugInfo: debugInfo)
    }
}
