import Foundation

@MainActor
protocol HotkeyManaging: AnyObject {
    var onKeyDown: (() -> Void)? { get set }
    var onKeyUp: (() -> Void)? { get set }
    func registerHotkey(_ shortcut: HotkeyShortcut) throws
}

@MainActor
protocol AudioRecordingServicing: AnyObject {
    var onMeterSample: ((AudioRecorder.MeterSample) -> Void)? { get set }
    var lastDuration: TimeInterval { get }
    func requestPermission() async -> Bool
    func startRecording() throws -> URL
    func stopRecording() throws -> URL
}

protocol SilenceTrimming: Sendable {
    func trimSilence(inputURL: URL) async throws -> URL
}

@MainActor
protocol TranscriptionServicing {
    func keepWarmForInteractionWindow()
    func transcribe(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String
}

@MainActor
protocol HUDPresenting: AnyObject {
    var onRetry: (() -> Void)? { get set }
    var onOpenSettings: (() -> Void)? { get set }
    func updateDisplaySettings(autoPasteEnabled: Bool, languageMode: String, modelMode: String)
    func updateHUDAnchor(_ anchor: HUDAnchorPosition)
    func updateRMS(_ rms: Float)
    func showListening()
    func showTranscribing()
    func updateTranscribingPreview(_ text: String)
    func showSuccess(_ text: String)
    func showError(_ reason: String)
    func dismiss()
    func runDemoSequence()
}

protocol ClipboardManaging {
    func copyToPasteboard(_ text: String)
    func autoPaste() throws
}

struct SystemClipboardService: ClipboardManaging {
    func copyToPasteboard(_ text: String) {
        ClipboardManager.copyToPasteboard(text)
    }

    func autoPaste() throws {
        try ClipboardManager.autoPaste()
    }
}

@MainActor extension HotkeyManager: HotkeyManaging {}
@MainActor extension AudioRecorder: AudioRecordingServicing {}
extension VADTrimmer: SilenceTrimming {}
@MainActor extension OpenAITranscribeClient: TranscriptionServicing {}
@MainActor extension HUDPresenter: HUDPresenting {}
