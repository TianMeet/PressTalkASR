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
        XCTAssertEqual(parser.parse(payload: payload), .done("final text"))
    }

    func testParseNestedErrorMessage() {
        let payload = #"{"type":"error","error":{"message":"quota exceeded"}}"#
        XCTAssertEqual(parser.parse(payload: payload), .error("quota exceeded"))
    }

    func testIgnoreInvalidJSON() {
        XCTAssertEqual(parser.parse(payload: "not-json"), .ignore)
    }
}
