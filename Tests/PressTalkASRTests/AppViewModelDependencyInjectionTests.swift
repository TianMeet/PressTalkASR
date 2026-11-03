import XCTest
import Combine
import Carbon
@testable import PressTalkASR

@MainActor
final class AppViewModelDependencyInjectionTests: XCTestCase {
    func testInitRegistersConfiguredHotkeyOnInjectedManager() {
        let settings = makeTestSettings()
        settings.hotkeyShortcut = .defaultPushToTalk
        let hotkeyManager = MockHotkeyManager()

        _ = makeViewModel(settings: settings, hotkeyManager: hotkeyManager)

        XCTAssertEqual(hotkeyManager.registeredShortcuts.count, 1)
        XCTAssertEqual(hotkeyManager.registeredShortcuts.first, settings.hotkeyShortcut)
    }

    func testInitAppliesConfiguredHUDAnchorToPresenter() async {
        let settings = makeTestSettings()
        let hotkeyManager = MockHotkeyManager()
        let hudPresenter = MockHUDPresenter()

        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: hotkeyManager,
            audioRecorder: MockAudioRecorder(),
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: MockTranscribeClient(),
            hudPresenter: hudPresenter,
            clipboardService: MockClipboardService()
        )
        _ = viewModel

        settings.hudAnchorPosition = .topLeft
        await Task.yield()
        await Task.yield()

        XCTAssertTrue(hudPresenter.updatedAnchors.contains(.topLeft))
    }

    func testUpdateHotkeyShortcutFallsBackToPreviousOnFailure() {
        let settings = makeTestSettings()
        settings.hotkeyShortcut = .defaultPushToTalk
        let hotkeyManager = MockHotkeyManager()
        let viewModel = makeViewModel(settings: settings, hotkeyManager: hotkeyManager)
        let previous = settings.hotkeyShortcut

        let failingShortcut = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(optionKey)
        )
        hotkeyManager.failOnShortcuts = [failingShortcut]

        let message = viewModel.updateHotkeyShortcut(failingShortcut)

        XCTAssertTrue(message.contains("失败"))
        XCTAssertEqual(settings.hotkeyShortcut, previous)
        XCTAssertEqual(Array(hotkeyManager.registeredShortcuts.suffix(2)), [failingShortcut, previous])
    }

    func testStopRecordingTransitionsDirectlyToTranscribingWithoutIdleFlicker() async throws {
        let settings = makeTestSettings()
        try settings.saveAPIKey("sk-test-abcdefghijklmnopqrstuvwxyz")

        let hotkeyManager = MockHotkeyManager()
        let audioRecorder = MockAudioRecorder()
        let transcribeClient = BlockingTranscribeClient()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appvm-sequence-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let audioData = Data(repeating: 1, count: 2048)
        FileManager.default.createFile(atPath: sourceURL.path, contents: audioData)
        audioRecorder.recordingURL = sourceURL
        audioRecorder.lastDuration = 0.6

        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: hotkeyManager,
            audioRecorder: audioRecorder,
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: transcribeClient,
            hudPresenter: MockHUDPresenter(),
            clipboardService: MockClipboardService()
        )

        var phases = [SessionPhase]()
        var cancellables = Set<AnyCancellable>()
        let transcribingExpectation = expectation(description: "phase becomes transcribing")

        viewModel.$sessionPhase
            .sink { phase in
                phases.append(phase)
                if phase == .transcribing {
                    transcribingExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        await fulfillment(of: [transcribingExpectation], timeout: 1.0)

        let normalized = phases.reduce(into: [SessionPhase]()) { result, phase in
            if result.last != phase {
                result.append(phase)
            }
        }
        let listeningIndex = normalized.firstIndex(of: .listening)
        let transcribingIndex = normalized.firstIndex(of: .transcribing)
        XCTAssertNotNil(listeningIndex)
        XCTAssertNotNil(transcribingIndex)
        if let listeningIndex, let transcribingIndex {
            XCTAssertEqual(transcribingIndex, listeningIndex + 1)
        }

        transcribeClient.resume(with: "ok")
    }

    func testMaxRecordingDurationAutomaticallyStopsAndTranscribes() async throws {
        let settings = makeTestSettings()
        try settings.saveAPIKey("sk-test-abcdefghijklmnopqrstuvwxyz")

        let hotkeyManager = MockHotkeyManager()
        let audioRecorder = MockAudioRecorder()
        let transcribeClient = BlockingTranscribeClient()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appvm-max-duration-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let audioData = Data(repeating: 1, count: 2048)
        FileManager.default.createFile(atPath: sourceURL.path, contents: audioData)
        audioRecorder.recordingURL = sourceURL
        audioRecorder.lastDuration = 0.6

        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: hotkeyManager,
            audioRecorder: audioRecorder,
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: transcribeClient,
            hudPresenter: MockHUDPresenter(),
            clipboardService: MockClipboardService(),
            maxRecordingDurationSeconds: 0.05
        )

        var cancellables = Set<AnyCancellable>()
        let transcribingExpectation = expectation(description: "auto stop moves to transcribing")
        viewModel.$sessionPhase
            .sink { phase in
                if phase == .transcribing {
                    transcribingExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await viewModel.beginPushToTalk()
        await fulfillment(of: [transcribingExpectation], timeout: 1.0)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertTrue(viewModel.isTranscribing)

        transcribeClient.resume(with: "ok")
    }

    func testHotkeyDownDuringTranscribingCancelsCurrentTranscription() async throws {
        let settings = makeTestSettings()
        try settings.saveAPIKey("sk-test-abcdefghijklmnopqrstuvwxyz")

        let hotkeyManager = MockHotkeyManager()
        let audioRecorder = MockAudioRecorder()
        let transcribeClient = BlockingTranscribeClient()
        let hudPresenter = MockHUDPresenter()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appvm-hotkey-busy-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let audioData = Data(repeating: 1, count: 2048)
        FileManager.default.createFile(atPath: sourceURL.path, contents: audioData)
        audioRecorder.recordingURL = sourceURL
        audioRecorder.lastDuration = 0.6

        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: hotkeyManager,
            audioRecorder: audioRecorder,
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: transcribeClient,
            hudPresenter: hudPresenter,
            clipboardService: MockClipboardService()
        )

        var cancellables = Set<AnyCancellable>()
        let transcribingExpectation = expectation(description: "phase becomes transcribing")
        viewModel.$sessionPhase
            .sink { phase in
                if phase == .transcribing {
                    transcribingExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()
        await fulfillment(of: [transcribingExpectation], timeout: 1.0)

        hotkeyManager.onKeyDown?()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(viewModel.sessionPhase, .idle)
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.lastMessage, "")
        XCTAssertEqual(viewModel.popoverFeedback, .none)
        XCTAssertEqual(hudPresenter.dismissCallCount, 1)
        XCTAssertTrue(hudPresenter.showErrorReasons.isEmpty)

        // Resume blocked continuation to let canceled task unwind cleanly.
        transcribeClient.resume(with: "late result")
        await Task.yield()
    }

    func testAutoPasteWaitsBrieflyAfterCopy() async throws {
        let settings = makeTestSettings()
        try settings.saveAPIKey("sk-test-abcdefghijklmnopqrstuvwxyz")
        settings.autoPasteEnabled = true

        let hotkeyManager = MockHotkeyManager()
        let audioRecorder = MockAudioRecorder()
        let clipboardService = TimedMockClipboardService()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appvm-autopaste-delay-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let audioData = Data(repeating: 1, count: 2048)
        FileManager.default.createFile(atPath: sourceURL.path, contents: audioData)
        audioRecorder.recordingURL = sourceURL
        audioRecorder.lastDuration = 0.6

        let autoPasteExpectation = expectation(description: "auto paste called")
        clipboardService.onAutoPaste = {
            autoPasteExpectation.fulfill()
        }

        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: hotkeyManager,
            audioRecorder: audioRecorder,
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: MockTranscribeClient(),
            hudPresenter: MockHUDPresenter(),
            clipboardService: clipboardService
        )

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()
        await fulfillment(of: [autoPasteExpectation], timeout: 2.0)

        guard let copyTime = clipboardService.copyTime, let pasteTime = clipboardService.pasteTime else {
            XCTFail("Expected both copy and paste timestamps")
            return
        }
        XCTAssertGreaterThanOrEqual(pasteTime - copyTime, 0.05)
    }

    func testShortRecordingIsSilentlyDiscardedWithoutErrorHUD() async throws {
        let settings = makeTestSettings()
        try settings.saveAPIKey("sk-test-abcdefghijklmnopqrstuvwxyz")

        let hotkeyManager = MockHotkeyManager()
        let audioRecorder = MockAudioRecorder()
        let hudPresenter = MockHUDPresenter()
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appvm-short-recording-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let audioData = Data(repeating: 1, count: 512)
        FileManager.default.createFile(atPath: sourceURL.path, contents: audioData)
        audioRecorder.recordingURL = sourceURL
        audioRecorder.lastDuration = 0.05

        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: hotkeyManager,
            audioRecorder: audioRecorder,
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: MockTranscribeClient(),
            hudPresenter: hudPresenter,
            clipboardService: MockClipboardService()
        )

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()
        await Task.yield()

        XCTAssertEqual(viewModel.sessionPhase, .idle)
        XCTAssertEqual(viewModel.popoverFeedback, .none)
        XCTAssertEqual(viewModel.lastMessage, "")
        XCTAssertEqual(hudPresenter.showErrorReasons.count, 0)
        XCTAssertEqual(hudPresenter.dismissCallCount, 1)
    }

    func testMissingAPIKeyDoesNotStartRecording() async {
        let settings = makeTestSettings()
        let audioRecorder = MockAudioRecorder()
        let hudPresenter = MockHUDPresenter()
        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: MockHotkeyManager(),
            audioRecorder: audioRecorder,
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: MockTranscribeClient(),
            hudPresenter: hudPresenter,
            clipboardService: MockClipboardService()
        )

        await viewModel.beginPushToTalk()

        XCTAssertEqual(audioRecorder.startCallCount, 0)
        XCTAssertEqual(viewModel.sessionPhase, .idle)
        XCTAssertEqual(hudPresenter.showErrorReasons.count, 1)
    }

    func testStopFailureCancelsRecorderAndReturnsToIdle() async throws {
        let settings = makeTestSettings()
        try settings.saveAPIKey("sk-test-abcdefghijklmnopqrstuvwxyz")
        let audioRecorder = MockAudioRecorder()
        audioRecorder.stopError = MockAudioRecorderError.stopFailed
        let hudPresenter = MockHUDPresenter()
        let viewModel = AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: MockHotkeyManager(),
            audioRecorder: audioRecorder,
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: MockTranscribeClient(),
            hudPresenter: hudPresenter,
            clipboardService: MockClipboardService()
        )

        await viewModel.beginPushToTalk()
        await viewModel.endPushToTalk()

        XCTAssertEqual(viewModel.sessionPhase, .idle)
        XCTAssertEqual(audioRecorder.cancelCallCount, 1)
        XCTAssertEqual(hudPresenter.showErrorReasons.count, 1)
    }

    private func makeViewModel(
        settings: AppSettings,
        hotkeyManager: MockHotkeyManager
    ) -> AppViewModel {
        AppViewModel(
            settings: settings,
            costTracker: CostTracker(),
            hotkeyManager: hotkeyManager,
            audioRecorder: MockAudioRecorder(),
            vadTrimmer: MockVADTrimmer(),
            transcribeClient: MockTranscribeClient(),
            hudPresenter: MockHUDPresenter(),
            clipboardService: MockClipboardService()
        )
    }
}

private enum MockHotkeyError: Error {
    case failed
}

private enum MockAudioRecorderError: Error {
    case stopFailed
}

@MainActor
private final class MockHotkeyManager: HotkeyManaging {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var registeredShortcuts: [HotkeyShortcut] = []
    var failOnShortcuts: [HotkeyShortcut] = []

    func registerHotkey(_ shortcut: HotkeyShortcut) throws {
        registeredShortcuts.append(shortcut)
        if failOnShortcuts.contains(shortcut) {
            throw MockHotkeyError.failed
        }
    }
}

@MainActor
private final class MockAudioRecorder: AudioRecordingServicing {
    var onMeterSample: ((AudioRecorder.MeterSample) -> Void)?
    var lastDuration: TimeInterval = 0
    var recordingURL: URL?
    var stopError: Error?
    private(set) var startCallCount = 0
    private(set) var cancelCallCount = 0

    func requestPermission() async -> Bool { true }

    func startRecording() throws -> URL {
        startCallCount += 1
        if let recordingURL {
            return recordingURL
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
    }

    func stopRecording() throws -> URL {
        if let stopError { throw stopError }
        if let recordingURL {
            return recordingURL
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
    }

    func cancelRecording() {
        cancelCallCount += 1
    }
}

private struct MockVADTrimmer: SilenceTrimming {
    func trimSilence(inputURL: URL) async throws -> URL { inputURL }
}

@MainActor
private struct MockTranscribeClient: TranscriptionServicing {
    func keepWarmForInteractionWindow() {}

    func transcribe(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> TranscriptionResult {
        TranscriptionResult(text: "ok")
    }
}

@MainActor
private final class BlockingTranscribeClient: TranscriptionServicing {
    private var continuation: CheckedContinuation<TranscriptionResult, Never>?

    func keepWarmForInteractionWindow() {}

    func transcribe(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> TranscriptionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with text: String) {
        continuation?.resume(returning: TranscriptionResult(text: text))
        continuation = nil
    }
}

@MainActor
private func makeTestSettings() -> AppSettings {
    let suiteName = "PressTalkASRTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return AppSettings(
        defaults: defaults,
        apiKeyStore: InMemoryAPIKeyStore(),
        environment: [:]
    )
}

private final class InMemoryAPIKeyStore: APIKeyStoring {
    private var value: String?

    func read() throws -> String? { value }
    func save(_ value: String) throws { self.value = value }
    func delete() throws { value = nil }
}

@MainActor
private final class MockHUDPresenter: HUDPresenting {
    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private(set) var updatedAnchors: [HUDAnchorPosition] = []
    private(set) var showTranscribingCallCount = 0
    private(set) var transcribingPreviews: [String] = []
    private(set) var showErrorReasons: [String] = []
    private(set) var dismissCallCount = 0

    func updateDisplaySettings(autoPasteEnabled: Bool, languageMode: String, modelMode: String) {}
    func updateHUDAnchor(_ anchor: HUDAnchorPosition) {
        updatedAnchors.append(anchor)
    }
    func updateRecordingElapsed(_ seconds: Int) {}
    func updateRMS(_ rms: Float) {}
    func showListening() {}
    func showTranscribing() {
        showTranscribingCallCount += 1
    }
    func updateTranscribingPreview(_ text: String) {
        transcribingPreviews.append(text)
    }
    func showSuccess(_ text: String) {}
    func showError(_ reason: String) {
        showErrorReasons.append(reason)
    }
    func dismiss() {
        dismissCallCount += 1
    }
    func runDemoSequence() {}
}

private struct MockClipboardService: ClipboardManaging {
    func copyToPasteboard(_ text: String) {}
    func autoPaste() throws {}
}

private final class TimedMockClipboardService: ClipboardManaging {
    var onAutoPaste: (() -> Void)?
    private(set) var copyTime: TimeInterval?
    private(set) var pasteTime: TimeInterval?

    func copyToPasteboard(_ text: String) {
        copyTime = ProcessInfo.processInfo.systemUptime
    }

    func autoPaste() throws {
        pasteTime = ProcessInfo.processInfo.systemUptime
        onAutoPaste?()
    }
}
