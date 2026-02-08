import Foundation

struct SilenceAutoStopDetector: Sendable {
    struct Configuration: Sendable {
        var silenceThresholdDB: Float = -45
        var silenceDurationMs: Double = 1000
        var startGuardMs: Double = 300
        var requireSpeechBeforeAutoStop: Bool = true
        var speechActivateDB: Float = -32
        var emaAlpha: Float = 0.2
    }

    struct DebugInfo: Sendable {
        let dbInstant: Float
        let dbEma: Float
        let frameDurationMs: Double
        let recordingElapsedMs: Double
        let silenceAccumMs: Double
        let hasSpoken: Bool
        let shouldAutoStop: Bool
    }

    private(set) var configuration: Configuration

    private var dbEma: Float = -120
    private var hasInitialized = false
    private(set) var hasSpoken = false
    private(set) var silenceAccumMs: Double = 0

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    mutating func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    mutating func reset() {
        dbEma = -120
        hasInitialized = false
        hasSpoken = false
        silenceAccumMs = 0
    }

    mutating func ingest(
        dbInstant: Float,
        frameDurationMs: Double,
        recordingElapsedMs: Double
    ) -> (shouldAutoStop: Bool, debugInfo: DebugInfo) {
        let clampedAlpha = max(0.01, min(0.95, configuration.emaAlpha))
        if hasInitialized {
            dbEma = (1 - clampedAlpha) * dbEma + clampedAlpha * dbInstant
        } else {
            dbEma = dbInstant
            hasInitialized = true
        }

        if dbEma >= configuration.speechActivateDB {
            hasSpoken = true
        }

        let guardPassed = recordingElapsedMs >= configuration.startGuardMs
        let speechReady = !configuration.requireSpeechBeforeAutoStop || hasSpoken

        if guardPassed && speechReady {
            if dbEma < configuration.silenceThresholdDB {
                silenceAccumMs += frameDurationMs
            } else {
                silenceAccumMs = 0
            }
        } else {
            silenceAccumMs = 0
        }

        let shouldStop = guardPassed
            && speechReady
            && silenceAccumMs >= configuration.silenceDurationMs

        let debug = DebugInfo(
            dbInstant: dbInstant,
            dbEma: dbEma,
            frameDurationMs: frameDurationMs,
            recordingElapsedMs: recordingElapsedMs,
            silenceAccumMs: silenceAccumMs,
            hasSpoken: hasSpoken,
            shouldAutoStop: shouldStop
        )
        return (shouldStop, debug)
    }
}
