import XCTest
@testable import PressTalkASR

final class TranscribeRetryPolicyTests: XCTestCase {
    private let policy = TranscribeRetryPolicy(maxAttempts: 3, initialDelayNs: 400_000_000)

    func testRetryableErrors() {
        XCTAssertTrue(policy.shouldRetry(.timeout))
        XCTAssertTrue(policy.shouldRetry(.network("offline")))
        XCTAssertTrue(policy.shouldRetry(.server(status: 429, message: "busy")))
        XCTAssertTrue(policy.shouldRetry(.server(status: 503, message: "down")))
    }

    func testNonRetryableErrors() {
        XCTAssertFalse(policy.shouldRetry(.unauthorized))
        XCTAssertFalse(policy.shouldRetry(.fileTooLarge))
        XCTAssertFalse(policy.shouldRetry(.server(status: 400, message: "bad request")))
    }

    func testBackoffDoublesDelay() {
        XCTAssertEqual(policy.nextDelay(after: 400_000_000), 800_000_000)
        XCTAssertEqual(policy.nextDelay(after: 800_000_000), 1_600_000_000)
    }
}
