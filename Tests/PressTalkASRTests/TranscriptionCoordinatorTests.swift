import XCTest
@testable import PressTalkASR

@MainActor
final class TranscriptionCoordinatorTests: XCTestCase {
    func testThrowsWhenAudioFileNotReadyAndCleansUpSource() async {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-test-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data())

        let transcribeClient = CapturingTranscribeClient()
        let coordinator = TranscriptionCoordinator(
            transcribeClient: transcribeClient,
            vadTrimmer: PassthroughTrimmer()
        )
        let options = TranscriptionRequestOptions(
            enableVADTrim: true,
            model: .gpt4oMiniTranscribe,
            prompt: nil,
            languageCode: nil
        )

        do {
            _ = try await coordinator.transcribe(
                sourceURL: sourceURL,
                recordedSeconds: 0.4,
                options: options,
                apiKey: "sk-test",
                onDelta: nil
            )
            XCTFail("Expected to throw audioFileNotReady")
        } catch let error as TranscriptionExecutionError {
            XCTAssertEqual(error, .audioFileNotReady)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(transcribeClient.didCallTranscribe)
    }

    func testTranscribeSuccessCleansUpSourceFile() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-test-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let data = Data(repeating: 1, count: 2048)
        FileManager.default.createFile(atPath: sourceURL.path, contents: data)

        let transcribeClient = CapturingTranscribeClient()
        let coordinator = TranscriptionCoordinator(
            transcribeClient: transcribeClient,
            vadTrimmer: PassthroughTrimmer()
        )
        let options = TranscriptionRequestOptions(
            enableVADTrim: false,
            model: .gpt4oMiniTranscribe,
            prompt: nil,
            languageCode: nil
        )

        let result = try await coordinator.transcribe(
            sourceURL: sourceURL,
            recordedSeconds: 0.4,
            options: options,
            apiKey: "sk-test",
            onDelta: nil
        )

        XCTAssertEqual(result.text, "transcribed")
        XCTAssertTrue(transcribeClient.didCallTranscribe)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testVADTrimBudgetDoesNotBlockUpload() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-budget-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        FileManager.default.createFile(
            atPath: sourceURL.path,
            contents: Data(repeating: 1, count: 2048)
        )
        let client = CapturingTranscribeClient()
        let coordinator = TranscriptionCoordinator(
            transcribeClient: client,
            vadTrimmer: SlowCancellableTrimmer()
        )
        let options = TranscriptionRequestOptions(
            enableVADTrim: true,
            model: .gpt4oMiniTranscribe,
            prompt: nil,
            languageCode: nil
        )

        let started = ProcessInfo.processInfo.systemUptime
        _ = try await coordinator.transcribe(
            sourceURL: sourceURL,
            recordedSeconds: 2,
            options: options,
            apiKey: "sk-test",
            onDelta: nil
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertLessThan(elapsed, 1)
        XCTAssertTrue(client.didCallTranscribe)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func testCancellationDuringVADSkipsUploadAndCleansSource() async {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcription-cancel-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        FileManager.default.createFile(
            atPath: sourceURL.path,
            contents: Data(repeating: 1, count: 2048)
        )
        let client = CapturingTranscribeClient()
        let coordinator = TranscriptionCoordinator(
            transcribeClient: client,
            vadTrimmer: SlowCancellableTrimmer()
        )
        let options = TranscriptionRequestOptions(
            enableVADTrim: true,
            model: .gpt4oMiniTranscribe,
            prompt: nil,
            languageCode: nil
        )
        let task = Task {
            try await coordinator.transcribe(
                sourceURL: sourceURL,
                recordedSeconds: 2,
                options: options,
                apiKey: "sk-test",
                onDelta: nil
            )
        }

        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(client.didCallTranscribe)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }
}

private struct PassthroughTrimmer: SilenceTrimming {
    func trimSilence(inputURL: URL) async throws -> URL {
        inputURL
    }
}

private struct SlowCancellableTrimmer: SilenceTrimming {
    func trimSilence(inputURL: URL) async throws -> URL {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        return inputURL
    }
}

@MainActor
private final class CapturingTranscribeClient: TranscriptionServicing {
    private(set) var didCallTranscribe = false

    func keepWarmForInteractionWindow() {}

    func transcribe(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> TranscriptionResult {
        didCallTranscribe = true
        return TranscriptionResult(text: "transcribed")
    }
}
