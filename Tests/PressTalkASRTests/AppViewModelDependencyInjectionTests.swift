import XCTest
import Carbon
@testable import PressTalkASR

@MainActor
final class AppViewModelDependencyInjectionTests: XCTestCase {
    func testInitRegistersConfiguredHotkeyOnInjectedManager() {
        let settings = AppSettings()
        settings.hotkeyShortcut = .defaultPushToTalk
        let hotkeyManager = MockHotkeyManager()

        _ = makeViewModel(settings: settings, hotkeyManager: hotkeyManager)

        XCTAssertEqual(hotkeyManager.registeredShortcuts.count, 1)
        XCTAssertEqual(hotkeyManager.registeredShortcuts.first, settings.hotkeyShortcut)
    }

    func testUpdateHotkeyShortcutFallsBackToPreviousOnFailure() {
        let settings = AppSettings()
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

    func requestPermission() async -> Bool { true }

    func startRecording() throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
    }

    func stopRecording() throws -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
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
    ) async throws -> String {
        "ok"
    }
}

@MainActor
private final class MockHUDPresenter: HUDPresenting {
    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    func updateDisplaySettings(autoPasteEnabled: Bool, languageMode: String, modelMode: String) {}
    func updateRMS(_ rms: Float) {}
    func showListening() {}
    func showTranscribing() {}
    func updateTranscribingPreview(_ text: String) {}
    func showSuccess(_ text: String) {}
    func showError(_ reason: String) {}
    func runDemoSequence() {}
}

private struct MockClipboardService: ClipboardManaging {
    func copyToPasteboard(_ text: String) {}
    func autoPaste() throws {}
}
