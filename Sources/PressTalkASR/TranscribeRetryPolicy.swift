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
        case .timeout, .network:
            return true
        case .server(let status, _):
            return status == 408 || status == 429 || status >= 500
        default:
            return false
        }
    }

    func nextDelay(after currentDelay: UInt64) -> UInt64 {
        currentDelay * 2
    }
}
