import XCTest
@testable import PressTalkASR

final class OpenAITranscribeClientTests: XCTestCase {
    func testGPT4oTranscriptionResponseFormatIsJSON() {
        XCTAssertEqual(OpenAITranscribeClient.transcriptionResponseFormat, "json")
    }

    func testDecodeNonStreamingJSONResponseWithUsage() throws {
        let data = Data(#"{"text":"  hello world  ","usage":{"type":"tokens","input_tokens":14,"output_tokens":45,"total_tokens":59,"input_token_details":{"audio_tokens":14,"text_tokens":0}}}"#.utf8)

        let result = try OpenAITranscribeClient.decodeTranscriptionResponse(data)

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.usage?.inputTokens, 14)
        XCTAssertEqual(result.usage?.outputTokens, 45)
        XCTAssertEqual(result.usage?.audioInputTokens, 14)
    }

    func testDecodeRejectsEmptyText() {
        let data = Data(#"{"text":"   "}"#.utf8)
        XCTAssertThrowsError(try OpenAITranscribeClient.decodeTranscriptionResponse(data)) { error in
            guard case OpenAITranscribeError.emptyText = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRecoverableStreamingFailureFallsBackToNonStreamingJSON() async throws {
        MockURLProtocol.setResponses([
            .init(status: 500, headers: [:], body: Data(#"{"error":{"message":"temporary"}}"#.utf8)),
            .init(
                status: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"text":"fallback worked","usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15}}"#.utf8)
            )
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = OpenAITranscribeClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://unit.test/v1/audio/transcriptions")!
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-client-\(UUID().uuidString).wav")
        try Data(repeating: 1, count: 2048).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await client.transcribe(
            fileURL: fileURL,
            model: .gpt4oMiniTranscribe,
            prompt: nil,
            languageCode: nil,
            apiKey: "sk-test",
            onDelta: nil
        )

        XCTAssertEqual(result.text, "fallback worked")
        XCTAssertEqual(result.usage?.totalTokens, 15)
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }

    func testRateLimitRetriesStreamingAfterRetryAfterDelay() async throws {
        MockURLProtocol.setResponses([
            .init(
                status: 429,
                headers: ["Retry-After": "0.1"],
                body: Data(#"{"error":{"message":"slow down"}}"#.utf8)
            ),
            .init(
                status: 200,
                headers: ["Content-Type": "text/event-stream"],
                body: Data(
                    "data: {\"type\":\"transcript.text.done\",\"text\":\"retried\",\"usage\":{\"input_tokens\":8,\"output_tokens\":3,\"total_tokens\":11}}\n\n".utf8
                )
            )
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = OpenAITranscribeClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://unit.test/v1/audio/transcriptions")!
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-rate-limit-\(UUID().uuidString).wav")
        try Data(repeating: 1, count: 2048).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let result = try await client.transcribe(
            fileURL: fileURL,
            model: .gpt4oMiniTranscribe,
            prompt: nil,
            languageCode: nil,
            apiKey: "sk-test",
            onDelta: nil
        )

        XCTAssertEqual(result.text, "retried")
        XCTAssertEqual(MockURLProtocol.requestCount, 2)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var responses: [Response] = []
    private nonisolated(unsafe) static var recordedRequestCount = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequestCount
    }

    static func setResponses(_ newResponses: [Response]) {
        lock.lock()
        responses = newResponses
        recordedRequestCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response: Response?
        Self.lock.lock()
        Self.recordedRequestCount += 1
        response = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        Self.lock.unlock()

        guard let response,
              let url = request.url,
              let http = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: response.headers
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
