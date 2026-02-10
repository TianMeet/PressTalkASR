import XCTest
@testable import PressTalkASR

final class PermissionHelperTests: XCTestCase {
    func testMicrophoneSettingsURL() {
        let url = PermissionHelper.settingsURL(for: .microphone)
        XCTAssertEqual(
            url?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testAccessibilitySettingsURL() {
        let url = PermissionHelper.settingsURL(for: .accessibility)
        XCTAssertEqual(
            url?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }
}
