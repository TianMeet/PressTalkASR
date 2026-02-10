import XCTest
@testable import PressTalkASR

final class PopoverMessageFormatterTests: XCTestCase {
    func testShortErrorMapsNetworkMessageToChineseHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortError("Network timeout", preferredLanguages: ["zh-Hans"]), "网络异常")
        XCTAssertEqual(PopoverMessageFormatter.shortError("网络连接失败", preferredLanguages: ["zh-Hans"]), "网络异常")
    }

    func testShortErrorMapsNoSpeechMessageToChineseHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortError("未识别到可用文本", preferredLanguages: ["zh-Hans"]), "未识别语音")
        XCTAssertEqual(PopoverMessageFormatter.shortError("录音太短，请重试", preferredLanguages: ["zh-Hans"]), "未识别语音")
    }

    func testShortErrorFallsBackToRetryHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortError("unknown", preferredLanguages: ["zh-Hans"]), "请重试")
    }

    func testShortWarningMapsPasteMessageToChineseHint() {
        XCTAssertEqual(PopoverMessageFormatter.shortWarning("自动粘贴失败", preferredLanguages: ["zh-Hans"]), "粘贴失败")
        XCTAssertEqual(PopoverMessageFormatter.shortWarning("auto paste failed", preferredLanguages: ["zh-Hans"]), "粘贴失败")
    }

    func testShortErrorAndWarningMapToEnglishHints() {
        XCTAssertEqual(PopoverMessageFormatter.shortError("网络连接失败", preferredLanguages: ["en-US"]), "Network")
        XCTAssertEqual(PopoverMessageFormatter.shortError("未识别到可用文本", preferredLanguages: ["en-US"]), "No speech")
        XCTAssertEqual(PopoverMessageFormatter.shortError("unknown", preferredLanguages: ["en-US"]), "Try again")
        XCTAssertEqual(PopoverMessageFormatter.shortWarning("自动粘贴失败", preferredLanguages: ["en-US"]), "Paste failed")
    }

    func testSubtitlesFollowPreferredLanguage() {
        XCTAssertEqual(PopoverMessageFormatter.warningSubtitle(preferredLanguages: ["zh-Hans"]), "已复制，但自动粘贴失败")
        XCTAssertEqual(PopoverMessageFormatter.errorSubtitle(preferredLanguages: ["zh-Hans"]), "未识别语音或网络异常")
        XCTAssertEqual(PopoverMessageFormatter.warningSubtitle(preferredLanguages: ["en-US"]), "Copied, but auto paste failed")
        XCTAssertEqual(PopoverMessageFormatter.errorSubtitle(preferredLanguages: ["en-US"]), "No speech or network issue")
    }

    func testDisplayLanguageDetectionDefaultsToEnglish() {
        XCTAssertEqual(PopoverMessageFormatter.displayLanguage(preferredLanguages: ["zh-HK"]), .chinese)
        XCTAssertEqual(PopoverMessageFormatter.displayLanguage(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(PopoverMessageFormatter.displayLanguage(preferredLanguages: []), .english)
    }
}
