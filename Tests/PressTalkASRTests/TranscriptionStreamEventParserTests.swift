import XCTest
@testable import PressTalkASR

final class TranscriptionStreamEventParserTests: XCTestCase {
    private let parser = TranscriptionStreamEventParser()

    func testParseDeltaEvent() {
        let payload = #"{"type":"response.delta","delta":"你好"}"#
        XCTAssertEqual(parser.parse(payload: payload), .delta("你好"))
    }

    func testParseDoneEvent() {
        let payload = #"{"event":"transcript.done","text":"final text"}"#
        XCTAssertEqual(parser.parse(payload: payload), .done("final text", nil))
    }

    func testParseDoneEventUsage() {
        let payload = #"{"type":"transcript.text.done","text":"final","usage":{"input_tokens":14,"output_tokens":45,"total_tokens":59,"input_token_details":{"audio_tokens":14,"text_tokens":0}}}"#
        let usage = TranscriptionUsage(
            inputTokens: 14,
            outputTokens: 45,
            totalTokens: 59,
            audioInputTokens: 14,
            textInputTokens: 0
        )
        XCTAssertEqual(parser.parse(payload: payload), .done("final", usage))
    }

    func testParseNestedErrorMessage() {
        let payload = #"{"type":"error","error":{"message":"quota exceeded"}}"#
        XCTAssertEqual(parser.parse(payload: payload), .error("quota exceeded"))
    }

    func testIgnoreInvalidJSON() {
        XCTAssertEqual(parser.parse(payload: "not-json"), .ignore)
    }
}
