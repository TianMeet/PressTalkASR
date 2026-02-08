import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
final class PopoverViewModel: ObservableObject {
    enum SessionState: Equatable {
        case idle
        case recording
        case transcribing
        case success
        case error(String)
    }

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var recordingElapsedSeconds: Int = 0
    @Published private(set) var todayDurationSeconds: TimeInterval = 0
    @Published private(set) var estimatedCost: Double = 0
    @Published private(set) var micPermission: PermissionState = .unknown
    @Published private(set) var accessibilityPermission: PermissionState = .unknown
    @Published private(set) var vadEnabled: Bool = false
    @Published private(set) var autoPasteEnabled: Bool = false
    @Published private(set) var isPressingPrimary = false
    @Published private(set) var showAccessibilityHint = false

    private let appViewModel: AppViewModel
    private var cancellables = Set<AnyCancellable>()
    private var recordingTimer: DispatchSourceTimer?
    private var refreshTimer: DispatchSourceTimer?
    private var resetTask: Task<Void, Never>?
    private var transientLock = false

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel

        bindSettings()
        bindAppState()
        refreshMetricsAndPermissions()
        startRefreshTimer()
    }

    deinit {
        recordingTimer?.cancel()
        refreshTimer?.cancel()
        resetTask?.cancel()
    }

    var statusPillModel: PopoverStatusPillModel {
        switch state {
        case .idle:
            return PopoverStatusPillModel(text: "Idle", color: Color.blue.opacity(0.62), showsDot: true, showsSpinner: false)
        case .recording:
            return PopoverStatusPillModel(text: recordingElapsedText, color: Color.red.opacity(0.86), showsDot: true, showsSpinner: false)
        case .transcribing:
            return PopoverStatusPillModel(text: "Transcribing", color: Color.indigo.opacity(0.86), showsDot: false, showsSpinner: true)
        case .success:
            return PopoverStatusPillModel(text: "Copied", color: Color.green.opacity(0.82), showsDot: true, showsSpinner: false)
        case .error(let reason):
            return PopoverStatusPillModel(text: reason, color: Color.red.opacity(0.78), showsDot: true, showsSpinner: false)
        }
    }

    var primaryTitle: String {
        if state == .recording || isPressingPrimary {
            return "Release to Send"
        }
        return "Hold to Talk"
    }

    var primarySubtitle: String {
        switch state {
        case .recording:
            return "Listening…"
        case .transcribing:
            return "Recognizing…"
        case .success:
            return "Copied to clipboard"
        case .error:
            return "No speech / Network"
        case .idle:
            return "Press and hold Option + Space"
        }
    }

    var primaryTint: Color {
        switch state {
        case .recording:
            return Color.red.opacity(0.82)
        case .transcribing:
            return Color.indigo.opacity(0.86)
        case .success:
            return Color.green.opacity(0.82)
        case .error:
            return Color.red.opacity(0.72)
        case .idle:
            return .accentColor
        }
    }

    var recordingElapsedText: String {
        let mins = recordingElapsedSeconds / 60
        let secs = recordingElapsedSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var todayDurationText: String {
        let total = Int(todayDurationSeconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var estimatedCostText: String {
        String(format: "$%.4f", estimatedCost)
    }

    var autoPasteNeedsPermission: Bool {
        accessibilityPermission != .granted
    }

    func primaryPressBegan() {
        guard !isPressingPrimary else { return }
        isPressingPrimary = true
        resetTask?.cancel()
        transientLock = false
        Task { [weak self] in
            await self?.appViewModel.beginPushToTalk()
        }
    }

    func primaryPressEnded() {
        guard isPressingPrimary else { return }
        isPressingPrimary = false
        Task { [weak self] in
            await self?.appViewModel.endPushToTalk()
        }
    }

    func clickToggleRecording() {
        Task { [weak self] in
            await self?.appViewModel.toggleManualRecording()
        }
    }

    func setVADEnabled(_ enabled: Bool) {
        appViewModel.settings.enableVADTrim = enabled
    }

    func setAutoPasteEnabled(_ enabled: Bool) {
        if enabled && autoPasteNeedsPermission {
            showAccessibilityHint = true
            appViewModel.settings.autoPasteEnabled = false
            return
        }
        showAccessibilityHint = false
        appViewModel.settings.autoPasteEnabled = enabled
    }

    func openAccessibilitySettings() {
        PermissionHelper.openAccessibilitySettings()
        refreshMetricsAndPermissions()
    }

    func openSettings() {
        appViewModel.openSettingsWindow()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func bindSettings() {
        appViewModel.settings.$enableVADTrim
            .sink { [weak self] value in
                self?.vadEnabled = value
            }
            .store(in: &cancellables)

        appViewModel.settings.$autoPasteEnabled
            .sink { [weak self] value in
                self?.autoPasteEnabled = value
            }
            .store(in: &cancellables)

        appViewModel.settings.$selectedModelRawValue
            .sink { [weak self] _ in
                self?.refreshMetricsAndPermissions()
            }
            .store(in: &cancellables)

        appViewModel.costTracker.$dailySeconds
            .sink { [weak self] _ in
                self?.refreshMetricsAndPermissions()
            }
            .store(in: &cancellables)
    }

    private func bindAppState() {
        appViewModel.$isRecording
            .combineLatest(appViewModel.$isTranscribing)
            .sink { [weak self] isRecording, isTranscribing in
                self?.handleBaseState(isRecording: isRecording, isTranscribing: isTranscribing)
            }
            .store(in: &cancellables)

        appViewModel.$popoverFeedback
            .sink { [weak self] feedback in
                self?.handleFeedback(feedback)
            }
            .store(in: &cancellables)
    }

    private func handleBaseState(isRecording: Bool, isTranscribing: Bool) {
        if isRecording {
            transientLock = false
            showAccessibilityHint = false
            setState(.recording)
            startRecordingTimer()
            return
        }

        stopRecordingTimer()

        if isTranscribing {
            transientLock = false
            setState(.transcribing)
            return
        }

        if !transientLock {
            setState(.idle)
        }
    }

    private func handleFeedback(_ feedback: AppViewModel.PopoverFeedback) {
        switch feedback {
        case .none:
            break
        case .success:
            transientLock = true
            setState(.success)
            appViewModel.consumePopoverFeedback()
            scheduleReset(after: 1.5)
        case .error(let message):
            transientLock = true
            setState(.error(shortError(message)))
            appViewModel.consumePopoverFeedback()
            scheduleReset(after: 2.0)
        }
    }

    private func setState(_ newState: SessionState) {
        guard state != newState else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            state = newState
        }
    }

    private func shortError(_ message: String) -> String {
        if message.lowercased().contains("network") || message.contains("网络") {
            return "Network"
        }
        if message.contains("未识别") || message.contains("太短") {
            return "No speech"
        }
        return "Error"
    }

    private func scheduleReset(after delay: TimeInterval) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.transientLock = false
            if !self.appViewModel.isRecording && !self.appViewModel.isTranscribing {
                self.setState(.idle)
            }
        }
    }

    private func startRecordingTimer() {
        guard recordingTimer == nil else { return }
        recordingElapsedSeconds = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.recordingElapsedSeconds += 1
        }
        timer.resume()
        recordingTimer = timer
    }

    private func stopRecordingTimer() {
        recordingTimer?.cancel()
        recordingTimer = nil
        recordingElapsedSeconds = 0
    }

    private func startRefreshTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.refreshMetricsAndPermissions()
        }
        timer.resume()
        refreshTimer = timer
    }

    private func refreshMetricsAndPermissions() {
        todayDurationSeconds = appViewModel.costTracker.secondsToday()
        estimatedCost = appViewModel.costTracker.estimatedCostToday(for: appViewModel.settings.selectedModel)
        micPermission = PermissionHelper.microphoneStatus()
        accessibilityPermission = PermissionHelper.accessibilityStatus()

        if accessibilityPermission == .granted {
            showAccessibilityHint = false
        }
    }
}
