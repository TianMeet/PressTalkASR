import Foundation

struct TranscribeRetryPolicy {
    let maxAttempts: Int
    let initialDelayNs: UInt64

    init(maxAttempts: Int = 3, initialDelayNs: UInt64 = 400_000_000) {
        self.maxAttempts = maxAttempts
        self.initialDelayNs = initialDelayNs
    }

    func shouldRetry(_ error: OpenAITranscribeError) -> Bool {
        switch error {
        case .timeout, .network, .rateLimited:
            return true
        case .server(let status, _):
            return status == 408 || status == 429 || status >= 500
        default:
            return false
        }
    }

    func delayNanoseconds(for error: OpenAITranscribeError, fallback: UInt64) -> UInt64 {
        guard case .rateLimited(_, let retryAfter) = error else {
            return fallback
        }
        guard let retryAfter else {
            return max(fallback, 1_000_000_000)
        }
        let clampedSeconds = max(0.1, min(60, retryAfter))
        return UInt64(clampedSeconds * 1_000_000_000)
    }

    func nextDelay(after currentDelay: UInt64) -> UInt64 {
        currentDelay * 2
    }
}
