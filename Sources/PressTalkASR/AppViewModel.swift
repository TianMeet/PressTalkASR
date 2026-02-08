import Foundation
import Combine
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    enum PopoverFeedback: Equatable {
        case none
        case success(String)
        case error(String)
    }

    enum SessionStatus {
        case idle
        case listening
        case transcribing

        var title: String {
            switch self {
            case .idle: return "Idle"
            case .listening: return "Listening"
            case .transcribing: return "Transcribing"
            }
        }

        var color: Color {
            switch self {
            case .idle: return UITheme.successColor
            case .listening: return UITheme.listeningColor
            case .transcribing: return UITheme.transcribingColor
            }
        }
    }

    enum WorkflowError: LocalizedError {
        case missingAPIKey
        case recordingTooShort
        case audioFileNotReady

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "未找到 API Key，请在 Settings 中输入并保存。"
            case .recordingTooShort:
                return "录音太短，请按住至少 0.2 秒再松开。"
            case .audioFileNotReady:
                return "音频文件尚未准备好，请稍后再试。"
            }
        }
    }

    private enum StopTrigger {
        case manual
        case autoSilence
    }

    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var lastMessage = ""
    @Published private(set) var popoverFeedback: PopoverFeedback = .none

    let settings = AppSettings()
    let costTracker = CostTracker()

    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private let vadTrimmer = VADTrimmer()
    private let transcribeClient = OpenAITranscribeClient()
    private let hudPresenter = HUDPresenter()
    private var settingsWindowController: SettingsWindowController?
    private let minimumRecordingSeconds: TimeInterval = 0.2

    private var transcribeTask: Task<Void, Never>?
    private var pendingAutoStopTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var silenceAutoStopDetector = SilenceAutoStopDetector()
    private var recordingStartedAt: Date?
    private var isStoppingRecording = false
    private var hasAutoStopFiredForSession = false
    private var lastAutoStopLogTime = Date.distantPast

    var menuBarIconName: String {
        if isRecording { return "mic.fill" }
        if isTranscribing { return "waveform.badge.magnifyingglass" }
        return "mic"
    }

    var sessionStatus: SessionStatus {
        if isRecording { return .listening }
        if isTranscribing { return .transcribing }
        return .idle
    }

    init() {
        audioRecorder.onMeterSample = { [weak self] sample in
            Task { @MainActor in
                guard let self else { return }
                self.hudPresenter.updateRMS(sample.rms)
                self.processSilenceAutoStop(sample: sample)
            }
        }

        hotkeyManager.onKeyDown = { [weak self] in
            Task { await self?.handleHotkeyDown() }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            Task { await self?.handleHotkeyUp() }
        }

        hudPresenter.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }

        hudPresenter.onRetry = { [weak self] in
            Task { await self?.startListening() }
        }

        settings.$autoPasteEnabled
            .combineLatest(settings.$selectedModelRawValue)
            .sink { [weak self] autoPaste, model in
                self?.hudPresenter.updateDisplaySettings(
                    autoPasteEnabled: autoPaste,
                    languageMode: "Auto",
                    modelMode: model
                )
            }
            .store(in: &cancellables)

        do {
            try hotkeyManager.registerDefaultHotkey()
        } catch {
            showError(error.localizedDescription)
        }
    }

    func toggleManualRecording() async {
        if isRecording {
            await stopAndTranscribe(trigger: .manual)
        } else {
            await startListening()
        }
    }

    func beginPushToTalk() async {
        guard !isRecording, !isTranscribing else { return }
        await startListening()
    }

    func endPushToTalk() async {
        guard isRecording else { return }
        await stopAndTranscribe(trigger: .manual)
    }

    func consumePopoverFeedback() {
        popoverFeedback = .none
    }

    func openSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                viewModel: self,
                settings: settings,
                costTracker: costTracker
            )
        }
        settingsWindowController?.show()
    }

    func runHUDDemo() {
        hudPresenter.runDemoSequence()
    }

    private func handleHotkeyDown() async {
        guard !isRecording, !isTranscribing else { return }
        await startListening()
    }

    private func handleHotkeyUp() async {
        guard isRecording else { return }
        await stopAndTranscribe(trigger: .manual)
    }

    private func startListening() async {
        guard !isTranscribing else { return }
        popoverFeedback = .none

        let permissionGranted = await audioRecorder.requestPermission()
        guard permissionGranted else {
            showError("没有麦克风权限，请在 Settings > Permissions 打开 Microphone 设置授权。")
            return
        }

        do {
            pendingAutoStopTask?.cancel()
            pendingAutoStopTask = nil
            silenceAutoStopDetector = SilenceAutoStopDetector(configuration: settings.autoStopConfiguration)
            recordingStartedAt = Date()
            isStoppingRecording = false
            hasAutoStopFiredForSession = false

            _ = try audioRecorder.startRecording()
            isRecording = true
            lastMessage = "Listening…"
            hudPresenter.showListening()
        } catch {
            showError("录音启动失败：\(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe(trigger: StopTrigger) async {
        guard isRecording else { return }
        guard !isStoppingRecording else { return }
        if trigger == .autoSilence, hasAutoStopFiredForSession {
            return
        }

        pendingAutoStopTask?.cancel()
        pendingAutoStopTask = nil
        isStoppingRecording = true
        if trigger == .autoSilence {
            hasAutoStopFiredForSession = true
        }

        popoverFeedback = .none

        let sourceURL: URL
        do {
            sourceURL = try audioRecorder.stopRecording()
        } catch {
            isStoppingRecording = false
            showError("停止录音失败：\(error.localizedDescription)")
            return
        }

        isRecording = false
        isStoppingRecording = false
        recordingStartedAt = nil
        isTranscribing = true
        lastMessage = "Transcribing…"
        hudPresenter.showTranscribing()

        let recordedSeconds = audioRecorder.lastDuration
        if recordedSeconds < minimumRecordingSeconds {
            isTranscribing = false
            showError(WorkflowError.recordingTooShort.localizedDescription)
            return
        }

        transcribeTask?.cancel()
        transcribeTask = Task { [weak self] in
            await self?.runTranscription(sourceURL: sourceURL, recordedSeconds: recordedSeconds)
        }
    }

    private func processSilenceAutoStop(sample: AudioRecorder.MeterSample) {
        guard isRecording else { return }
        guard settings.enableAutoStopOnSilence else {
            pendingAutoStopTask?.cancel()
            pendingAutoStopTask = nil
            return
        }
        guard !isStoppingRecording else { return }
        guard pendingAutoStopTask == nil else { return }
        guard let recordingStartedAt else { return }

        silenceAutoStopDetector.updateConfiguration(settings.autoStopConfiguration)

        let elapsedMs = Date().timeIntervalSince(recordingStartedAt) * 1000
        let (shouldAutoStop, debugInfo) = silenceAutoStopDetector.ingest(
            dbInstant: sample.dbInstant,
            frameDurationMs: sample.frameDurationMs,
            recordingElapsedMs: elapsedMs
        )

        if settings.autoStopDebugLogs {
            maybePrintAutoStopDebug(debugInfo)
        }

        guard shouldAutoStop, !hasAutoStopFiredForSession else { return }

        pendingAutoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            await self?.stopAndTranscribe(trigger: .autoSilence)
        }
    }

    private func maybePrintAutoStopDebug(_ info: SilenceAutoStopDetector.DebugInfo) {
        let now = Date()
        guard now.timeIntervalSince(lastAutoStopLogTime) >= 0.15 || info.shouldAutoStop else { return }
        lastAutoStopLogTime = now

        print(
            String(
                format: "[AutoStop] db=%.1f ema=%.1f silence=%.0fms spoken=%@ elapsed=%.0fms trigger=%@",
                info.dbInstant,
                info.dbEma,
                info.silenceAccumMs,
                info.hasSpoken ? "Y" : "N",
                info.recordingElapsedMs,
                info.shouldAutoStop ? "Y" : "N"
            )
        )
    }

    private func runTranscription(sourceURL: URL, recordedSeconds: TimeInterval) async {
        var urlsToDelete = [sourceURL]
        var requestURL = sourceURL

        defer {
            urlsToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        do {
            guard await waitForStableAudioFile(at: sourceURL) else {
                throw WorkflowError.audioFileNotReady
            }

            if settings.enableVADTrim {
                let trimmedURL = try await vadTrimmer.trimSilence(inputURL: sourceURL)
                if trimmedURL != sourceURL {
                    requestURL = trimmedURL
                    urlsToDelete.append(trimmedURL)
                }
            }

            guard let apiKey = settings.resolvedAPIKey() else {
                throw WorkflowError.missingAPIKey
            }

            let promptToSend = settings.effectivePrompt(forRecordingSeconds: recordedSeconds)
            let text = try await transcribeClient.transcribe(
                fileURL: requestURL,
                model: settings.selectedModel,
                prompt: promptToSend,
                apiKey: apiKey
            )

            ClipboardManager.copyToPasteboard(text)
            lastMessage = text
            hudPresenter.showSuccess(text)
            popoverFeedback = .success("Copied")

            if settings.autoPasteEnabled {
                do {
                    try ClipboardManager.autoPaste()
                } catch {
                    showError(error.localizedDescription)
                    isTranscribing = false
                    return
                }
            }

            costTracker.add(seconds: recordedSeconds)
            isTranscribing = false
        } catch {
            showError(error.localizedDescription)
            isTranscribing = false
        }
    }

    private func waitForStableAudioFile(at url: URL) async -> Bool {
        var previousSize = -1
        var stableCount = 0

        for _ in 0..<8 {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 1024 {
                if size == previousSize {
                    stableCount += 1
                } else {
                    stableCount = 0
                }
                if stableCount >= 1 {
                    return true
                }
            }
            previousSize = size
            try? await Task.sleep(nanoseconds: 70_000_000)
        }

        return false
    }

    func saveAPIKey(_ value: String) -> String {
        settings.saveAPIKey(value)
        return "API Key 已缓存到本地。"
    }

    func clearAPIKey() -> String {
        settings.clearAPIKey()
        return "本地缓存的 API Key 已清除。"
    }

    private func showError(_ message: String) {
        lastMessage = message
        hudPresenter.showError(message)
        popoverFeedback = .error(message)
    }
}
