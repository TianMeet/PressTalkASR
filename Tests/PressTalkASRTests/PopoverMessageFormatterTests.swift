import XCTest
@testable import PressTalkASR

final class PopoverMessageFormatterTests: XCTestCase {
    func testShortErrorMapsNetworkMessageToChineseHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortError("Network timeout"), "网络异常")
        XCTAssertEqual(PopoverMessageFormatter.shortError("网络连接失败"), "网络异常")
    }

    func testShortErrorMapsNoSpeechMessageToChineseHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortError("未识别到可用文本"), "未识别语音")
        XCTAssertEqual(PopoverMessageFormatter.shortError("录音太短，请重试"), "未识别语音")
    }

    func testShortErrorFallsBackToRetryHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortError("unknown"), "请重试")
    }

    func testShortWarningMapsPasteMessageToChineseHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortWarning("自动粘贴失败"), "粘贴失败")
        XCTAssertEqual(PopoverMessageFormatter.shortWarning("auto paste failed"), "粘贴失败")
    }
}
