import Foundation
import Combine
import os
import SwiftUI

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.xingkong.PressTalkASR",
    category: "AppViewModel"
)

private final class PreviewDeltaCoalescer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.xingkong.PressTalkASR.preview-coalescer")
    private let interval: TimeInterval
    private var latest = ""
    private var pendingWorkItem: DispatchWorkItem?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func push(_ text: String, onFlush: @escaping @Sendable (String) -> Void) {
        queue.async {
            self.latest = text
            guard self.pendingWorkItem == nil else { return }

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let snapshot = self.latest
                self.latest = ""
                self.pendingWorkItem = nil
                guard !snapshot.isEmpty else { return }
                onFlush(snapshot)
            }

            self.pendingWorkItem = work
            self.queue.asyncAfter(deadline: .now() + self.interval, execute: work)
        }
    }

    func reset() {
        queue.async {
            self.latest = ""
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = nil
        }
    }
}

private final class DeltaTimingProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var firstDeltaAt: Date?

    func markFirstDeltaIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        if firstDeltaAt == nil {
            firstDeltaAt = Date()
        }
    }

    func snapshot() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return firstDeltaAt
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    enum PopoverFeedback: Equatable {
        case none
        case success(String)
        case warning(String)
        case error(String)
    }

    enum SessionStatus {
        case idle
        case listening
        case transcribing

        init(phase: SessionPhase) {
            switch phase {
            case .idle:
                self = .idle
            case .listening:
                self = .listening
            case .transcribing:
                self = .transcribing
            }
        }

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

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "未找到 API Key，请在 Settings 中输入并保存。"
            case .recordingTooShort:
                return "录音太短，请按住至少 0.2 秒再松开。"
            }
        }
    }

    private enum StopTrigger {
        case manual
        case autoSilence
        case maxDuration
    }

    private enum Constants {
        /// 录音最短有效时长
        static let minimumRecordingSeconds: TimeInterval = 0.2
        /// 最大录音时长保护
        static let maximumRecordingSeconds: TimeInterval = 120
        /// Auto-paste 前的剪贴板同步等待，避免部分应用粘贴旧值
        static let autoPasteDelayNs: UInt64 = 60_000_000        // 60 ms
        /// 转写预览增量刷新节流间隔
        static let previewThrottleSeconds: TimeInterval = 0.08   // 80 ms
        /// 静音自动结束触发前延迟
        static let autoStopDebounceNs: UInt64 = 80_000_000      // 80 ms
        /// Debug 日志最小输出间隔
        static let debugLogMinInterval: TimeInterval = 0.15
    }

    @Published private(set) var sessionPhase: SessionPhase = .idle
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var lastMessage = ""
    @Published private(set) var popoverFeedback: PopoverFeedback = .none

    let settings: AppSettings
    let costTracker: CostTracker

    private let hotkeyManager: any HotkeyManaging
    private let audioRecorder: any AudioRecordingServicing
    private let transcribeClient: any TranscriptionServicing
    private let hudPresenter: any HUDPresenting
    private let clipboardService: any ClipboardManaging
    private let transcriptionCoordinator: TranscriptionCoordinator
    private let recordingSessionCoordinator: RecordingSessionCoordinator
    private var settingsWindowController: SettingsWindowController?

    private var transcribeTask: Task<Void, Never>?
    private var activeTranscriptionToken: UUID?
    private var pendingAutoStopTask: Task<Void, Never>?
    private var pendingMaxDurationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var lastAutoStopLogTime = Date.distantPast
    private let maxRecordingDurationSeconds: TimeInterval

    var menuBarIconName: String {
        sessionPhase.menuBarIconName
    }

    var sessionStatus: SessionStatus {
        SessionStatus(phase: sessionPhase)
    }

    init(
        settings: AppSettings = AppSettings(),
        costTracker: CostTracker = CostTracker(),
        hotkeyManager: any HotkeyManaging = HotkeyManager(),
        audioRecorder: any AudioRecordingServicing = AudioRecorder(),
        vadTrimmer: any SilenceTrimming = VADTrimmer(),
        transcribeClient: any TranscriptionServicing = OpenAITranscribeClient(),
        hudPresenter: any HUDPresenting = HUDPresenter(),
        clipboardService: any ClipboardManaging = SystemClipboardService(),
        recordingSessionCoordinator: RecordingSessionCoordinator = RecordingSessionCoordinator(),
        maxRecordingDurationSeconds: TimeInterval = Constants.maximumRecordingSeconds
    ) {
        self.settings = settings
        self.costTracker = costTracker
        self.hotkeyManager = hotkeyManager
        self.audioRecorder = audioRecorder
        self.transcribeClient = transcribeClient
        self.hudPresenter = hudPresenter
        self.clipboardService = clipboardService
        self.recordingSessionCoordinator = recordingSessionCoordinator
        self.maxRecordingDurationSeconds = maxRecordingDurationSeconds
        self.transcriptionCoordinator = TranscriptionCoordinator(
            transcribeClient: transcribeClient,
            vadTrimmer: vadTrimmer
        )

        audioRecorder.onMeterSample = { [weak self] sample in
            guard let self else { return }
            self.hudPresenter.updateRMS(sample.rms)
            self.processSilenceAutoStop(sample: sample)
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
            .combineLatest(settings.$selectedModelRawValue, settings.$languageModeRawValue)
            .sink { [weak self] autoPaste, model, language in
                DispatchQueue.main.async { [weak self] in
                    self?.hudPresenter.updateDisplaySettings(
                        autoPasteEnabled: autoPaste,
                        languageMode: language,
                        modelMode: model
                    )
                }
            }
            .store(in: &cancellables)

        settings.$hudAnchorPositionRawValue
            .sink { [weak self] rawValue in
                let anchor = HUDAnchorPosition(rawValue: rawValue) ?? .bottomRight
                DispatchQueue.main.async { [weak self] in
                    self?.hudPresenter.updateHUDAnchor(anchor)
                }
            }
            .store(in: &cancellables)

        registerConfiguredHotkeyOrFallback()
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
        guard popoverFeedback != .none else { return }
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
        if isTranscribing {
            cancelActiveTranscription()
            return
        }

        guard !isRecording else { return }
        await startListening()
    }

    private func handleHotkeyUp() async {
        guard isRecording else { return }
        await stopAndTranscribe(trigger: .manual)
    }

    private func mapStopTrigger(_ trigger: StopTrigger) -> RecordingStopTrigger {
        switch trigger {
        case .manual:
            return .manual
        case .autoSilence:
            return .autoSilence
        case .maxDuration:
            return .manual
        }
    }

    private func transition(to phase: SessionPhase) {
        sessionPhase = phase
        isRecording = phase.isRecording
        isTranscribing = phase.isTranscribing
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
            pendingMaxDurationTask?.cancel()
            pendingMaxDurationTask = nil
            recordingSessionCoordinator.beginSession(configuration: settings.autoStopConfiguration)

            _ = try audioRecorder.startRecording()
            transition(to: .listening)
            lastMessage = "Listening…"
            hudPresenter.showListening()
            scheduleMaxRecordingGuard()

            // 录音开始即进入短周期连接保温，降低松开后冷连接概率。
            transcribeClient.keepWarmForInteractionWindow()
        } catch {
            showError("录音启动失败：\(error.localizedDescription)")
        }
    }

    private func stopAndTranscribe(trigger: StopTrigger) async {
        guard isRecording else { return }
        guard recordingSessionCoordinator.beginStop(trigger: mapStopTrigger(trigger)) else {
            return
        }

        pendingAutoStopTask?.cancel()
        pendingAutoStopTask = nil
        pendingMaxDurationTask?.cancel()
        pendingMaxDurationTask = nil

        popoverFeedback = .none

        let sourceURL: URL
        do {
            sourceURL = try audioRecorder.stopRecording()
        } catch {
            recordingSessionCoordinator.abortStop()
            showError("停止录音失败：\(error.localizedDescription)")
            return
        }

        recordingSessionCoordinator.finishStop()

        let recordedSeconds = audioRecorder.lastDuration
        if recordedSeconds < Constants.minimumRecordingSeconds {
            try? FileManager.default.removeItem(at: sourceURL)
            transition(to: .idle)
            lastMessage = ""
            hudPresenter.dismiss()
            return
        }

        transition(to: .transcribing)
        lastMessage = "Transcribing…"
        hudPresenter.showTranscribing()
        // 停止录音后继续保温一小段时间，覆盖上传与首字阶段。
        transcribeClient.keepWarmForInteractionWindow()

        transcribeTask?.cancel()
        let transcriptionToken = UUID()
        activeTranscriptionToken = transcriptionToken
        transcribeTask = Task { [weak self] in
            await self?.runTranscription(
                sourceURL: sourceURL,
                recordedSeconds: recordedSeconds,
                token: transcriptionToken
            )
        }
    }

    private func processSilenceAutoStop(sample: AudioRecorder.MeterSample) {
        guard isRecording else { return }
        guard settings.enableAutoStopOnSilence else {
            pendingAutoStopTask?.cancel()
            pendingAutoStopTask = nil
            return
        }
        guard pendingAutoStopTask == nil else { return }
        let decision = recordingSessionCoordinator.evaluateAutoStop(
            sample: sample,
            isEnabled: settings.enableAutoStopOnSilence,
            configuration: settings.autoStopConfiguration
        )

        if settings.autoStopDebugLogs, let debugInfo = decision.debugInfo {
            maybePrintAutoStopDebug(debugInfo)
        }

        guard decision.shouldAutoStop else { return }

        pendingAutoStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.autoStopDebounceNs)
            guard !Task.isCancelled else { return }
            await self?.stopAndTranscribe(trigger: .autoSilence)
        }
    }

    private func scheduleMaxRecordingGuard() {
        pendingMaxDurationTask?.cancel()
        pendingMaxDurationTask = Task { [weak self] in
            let duration = max(0.01, self?.maxRecordingDurationSeconds ?? Constants.maximumRecordingSeconds)
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.stopAndTranscribe(trigger: .maxDuration)
        }
    }

    private func maybePrintAutoStopDebug(_ info: SilenceAutoStopDetector.DebugInfo) {
        let now = Date()
        guard now.timeIntervalSince(lastAutoStopLogTime) >= Constants.debugLogMinInterval || info.shouldAutoStop else { return }
        lastAutoStopLogTime = now

        let message = String(
            format: "[AutoStop] db=%.1f ema=%.1f silence=%.0fms spoken=%@ elapsed=%.0fms trigger=%@",
            info.dbInstant,
            info.dbEma,
            info.silenceAccumMs,
            info.hasSpoken ? "Y" : "N",
            info.recordingElapsedMs,
            info.shouldAutoStop ? "Y" : "N"
        )
        logger.debug("\(message, privacy: .public)")
    }

    private func runTranscription(sourceURL: URL, recordedSeconds: TimeInterval, token: UUID) async {
        let transcriptionStartedAt = Date()
        let deltaTimingProbe = DeltaTimingProbe()
        let previewCoalescer = PreviewDeltaCoalescer(interval: Constants.previewThrottleSeconds)

        defer {
            previewCoalescer.reset()
            if activeTranscriptionToken == token {
                activeTranscriptionToken = nil
                transcribeTask = nil
            }
        }

        do {
            // Fail fast: check API key before doing any audio processing.
            guard let apiKey = settings.resolvedAPIKey() else {
                throw WorkflowError.missingAPIKey
            }

            let options = TranscriptionRequestOptions(
                enableVADTrim: settings.enableVADTrim,
                model: settings.selectedModel,
                prompt: settings.effectivePrompt(forRecordingSeconds: recordedSeconds),
                languageCode: settings.preferredLanguageCode
            )

            let text = try await transcriptionCoordinator.transcribe(
                sourceURL: sourceURL,
                recordedSeconds: recordedSeconds,
                options: options,
                apiKey: apiKey,
                onDelta: { [weak self] preview in
                    deltaTimingProbe.markFirstDeltaIfNeeded()
                    previewCoalescer.push(preview) { latest in
                        Task { @MainActor in
                            guard let self, self.isTranscribing else { return }
                            self.lastMessage = latest
                            self.hudPresenter.updateTranscribingPreview(latest)
                        }
                    }
                }
            )

            logTranscriptionTiming(
                startedAt: transcriptionStartedAt,
                firstDeltaAt: deltaTimingProbe.snapshot(),
                endedAt: Date(),
                recordedSeconds: recordedSeconds,
                error: nil
            )

            guard activeTranscriptionToken == token, isTranscribing else { return }
            clipboardService.copyToPasteboard(text)
            lastMessage = text
            hudPresenter.showSuccess(text)
            popoverFeedback = .success("Copied")

            if settings.autoPasteEnabled {
                do {
                    try await Task.sleep(nanoseconds: Constants.autoPasteDelayNs)
                    try clipboardService.autoPaste()
                } catch is CancellationError {
                    // Transcription task canceled after copy; skip auto-paste.
                } catch {
                    popoverFeedback = .warning("已复制，自动粘贴失败")
                    logger.notice("Auto-paste failed after copy: \(error.localizedDescription, privacy: .public)")
                }
            }

            costTracker.add(seconds: recordedSeconds)
            transition(to: .idle)
        } catch {
            logTranscriptionTiming(
                startedAt: transcriptionStartedAt,
                firstDeltaAt: deltaTimingProbe.snapshot(),
                endedAt: Date(),
                recordedSeconds: recordedSeconds,
                error: error
            )
            guard activeTranscriptionToken == token else { return }
            if Task.isCancelled {
                transition(to: .idle)
                lastMessage = ""
                hudPresenter.dismiss()
                return
            }
            showError(error.localizedDescription)
            transition(to: .idle)
        }
    }

    private func cancelActiveTranscription() {
        guard isTranscribing else { return }
        transcribeTask?.cancel()
        transcribeTask = nil
        activeTranscriptionToken = nil
        popoverFeedback = .none
        transition(to: .idle)
        lastMessage = ""
        hudPresenter.dismiss()
    }

    private func logTranscriptionTiming(
        startedAt: Date,
        firstDeltaAt: Date?,
        endedAt: Date,
        recordedSeconds: TimeInterval,
        error: Error?
    ) {
        let totalMs = Int(endedAt.timeIntervalSince(startedAt) * 1000)
        let firstDeltaMs = firstDeltaAt.map { Int($0.timeIntervalSince(startedAt) * 1000) } ?? -1
        let status = error == nil ? "ok" : "error"
        let message = String(
            format: "[TranscriptionTiming] status=%@ rec=%.2fs ttfd=%dms total=%dms",
            status,
            recordedSeconds,
            firstDeltaMs,
            totalMs
        )
        logger.notice("\(message, privacy: .public)")
    }

    func saveAPIKey(_ value: String) -> String {
        settings.saveAPIKey(value)
        return "API Key 已缓存到本地。"
    }

    func updateHotkeyShortcut(_ shortcut: HotkeyShortcut) -> String {
        guard shortcut.isValid else {
            return "快捷键无效：请至少包含一个修饰键。"
        }

        let previous = settings.hotkeyShortcut
        do {
            try hotkeyManager.registerHotkey(shortcut)
            settings.hotkeyShortcut = shortcut
            return "快捷键已更新为 \(shortcut.displayText)。"
        } catch {
            try? hotkeyManager.registerHotkey(previous)
            return "快捷键更新失败：\(error.localizedDescription)"
        }
    }

    func resetHotkeyToDefault() -> String {
        updateHotkeyShortcut(.defaultPushToTalk)
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

    private func registerConfiguredHotkeyOrFallback() {
        do {
            try hotkeyManager.registerHotkey(settings.hotkeyShortcut)
        } catch {
            settings.hotkeyShortcut = .defaultPushToTalk
            do {
                try hotkeyManager.registerHotkey(.defaultPushToTalk)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }
}
