import XCTest
@testable import PressTalkASR

final class HUDStateMachineTests: XCTestCase {
    func testSuccessDelayUsesMinimumForShortText() {
        let autoDismiss = HUDStateMachine.AutoDismiss(
            successDelayMin: 1.5,
            successDelayMax: 4.0,
            successDelayCharsPerSecond: 15.0,
            errorDelay: 3.0
        )

        XCTAssertEqual(autoDismiss.successDelay(for: "ok"), 1.5, accuracy: 0.0001)
        XCTAssertEqual(autoDismiss.successDelay(for: "   "), 1.5, accuracy: 0.0001)
    }

    func testSuccessDelayScalesWithTextLengthWithinRange() {
        let autoDismiss = HUDStateMachine.AutoDismiss(
            successDelayMin: 1.5,
            successDelayMax: 4.0,
            successDelayCharsPerSecond: 15.0,
            errorDelay: 3.0
        )

        let text = String(repeating: "a", count: 45)
        XCTAssertEqual(autoDismiss.successDelay(for: text), 3.0, accuracy: 0.0001)
    }

    func testSuccessDelayCapsAtMaximum() {
        let autoDismiss = HUDStateMachine.AutoDismiss(
            successDelayMin: 1.5,
            successDelayMax: 4.0,
            successDelayCharsPerSecond: 15.0,
            errorDelay: 3.0
        )

        let text = String(repeating: "b", count: 200)
        XCTAssertEqual(autoDismiss.successDelay(for: text), 4.0, accuracy: 0.0001)
    }
}
