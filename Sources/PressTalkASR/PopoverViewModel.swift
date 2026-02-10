import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
final class PopoverViewModel: ObservableObject {
    private enum Constants {
        static let metricsRefreshInterval: TimeInterval = 30
        static let permissionRefreshInterval: TimeInterval = 3
    }

    enum SessionState: Equatable {
        case idle
        case recording
        case transcribing
        case success
        case warning(String)
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
    @Published private(set) var hotkeyTokens: [String] = HotkeyShortcut.defaultPushToTalk.keycapTokens
    @Published private(set) var hotkeyDisplayText: String = HotkeyShortcut.defaultPushToTalk.displayText

    private let appViewModel: AppViewModel
    private var cancellables = Set<AnyCancellable>()
    private var metricsTimer: DispatchSourceTimer?
    private var permissionTimer: DispatchSourceTimer?
    private var resetTask: Task<Void, Never>?
    private var transientLock = false

    init(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel

        bindSettings()
        bindAppState()
        bindLifecycleEvents()
        refreshMetrics()
        refreshPermissions()
        refreshHotkeyDisplay()
    }

    deinit {
        metricsTimer?.cancel()
        permissionTimer?.cancel()
        resetTask?.cancel()
    }

    var statusPillModel: PopoverStatusPillModel {
        switch state {
        case .idle:
            return PopoverStatusPillModel(text: L10n.tr("popover.status.idle"), color: Color.blue.opacity(0.62), showsDot: true, showsSpinner: false)
        case .recording:
            return PopoverStatusPillModel(text: recordingElapsedText, color: Color.red.opacity(0.86), showsDot: true, showsSpinner: false)
        case .transcribing:
            return PopoverStatusPillModel(text: L10n.tr("popover.status.transcribing"), color: Color.indigo.opacity(0.86), showsDot: false, showsSpinner: true)
        case .success:
            return PopoverStatusPillModel(text: L10n.tr("popover.status.copied"), color: Color.green.opacity(0.82), showsDot: true, showsSpinner: false)
        case .warning(let message):
            return PopoverStatusPillModel(text: message, color: Color.orange.opacity(0.86), showsDot: true, showsSpinner: false)
        case .error(let reason):
            return PopoverStatusPillModel(text: reason, color: Color.red.opacity(0.78), showsDot: true, showsSpinner: false)
        }
    }

    var primaryTitle: String {
        if state == .recording || isPressingPrimary {
            return L10n.tr("popover.primary.release_to_send")
        }
        return L10n.tr("popover.primary.hold_to_talk")
    }

    var primarySubtitle: String {
        switch state {
        case .recording:
            return L10n.tr("popover.subtitle.listening")
        case .transcribing:
            return L10n.tr("popover.subtitle.recognizing")
        case .success:
            return L10n.tr("popover.subtitle.copied_to_clipboard")
        case .warning:
            return PopoverMessageFormatter.warningSubtitle()
        case .error:
            return PopoverMessageFormatter.errorSubtitle()
        case .idle:
            return L10n.tr("popover.subtitle.press_and_hold_format", hotkeyDisplayText)
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
        case .warning:
            return Color.orange.opacity(0.84)
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
        refreshPermissions()
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
        refreshPermissions()
    }

    func openSettings() {
        appViewModel.openSettingsWindow()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func handlePopoverAppear() {
        refreshMetrics()
        refreshPermissions()
        refreshHotkeyDisplay()
        startMetricsTimer()
        startPermissionTimer()
    }

    func handlePopoverDisappear() {
        stopMetricsTimer()
        stopPermissionTimer()
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
                // Defer publish to next runloop to avoid nested publishes
                // while another SwiftUI view tree is processing updates.
                DispatchQueue.main.async { [weak self] in
                    self?.refreshMetrics()
                }
            }
            .store(in: &cancellables)

        appViewModel.settings.$hotkeyKeyCode
            .combineLatest(appViewModel.settings.$hotkeyModifiers)
            .sink { [weak self] _, _ in
                self?.refreshHotkeyDisplay()
            }
            .store(in: &cancellables)

        appViewModel.costTracker.$dailySeconds
            .sink { [weak self] _ in
                self?.refreshMetrics()
            }
            .store(in: &cancellables)
    }

    private func bindAppState() {
        appViewModel.$sessionPhase
            .sink { [weak self] phase in
                self?.handleBaseState(phase: phase)
            }
            .store(in: &cancellables)

        appViewModel.$popoverFeedback
            .sink { [weak self] feedback in
                self?.handleFeedback(feedback)
            }
            .store(in: &cancellables)

        appViewModel.$recordingElapsedSeconds
            .sink { [weak self] elapsed in
                self?.recordingElapsedSeconds = elapsed
            }
            .store(in: &cancellables)
    }

    private func bindLifecycleEvents() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshPermissions()
            }
            .store(in: &cancellables)
    }

    private func handleBaseState(phase: SessionPhase) {
        switch phase {
        case .listening:
            transientLock = false
            showAccessibilityHint = false
            setState(.recording)
        case .transcribing:
            transientLock = false
            setState(.transcribing)
        case .idle:
            if !transientLock {
                setState(.idle)
            }
        }
    }

    private func handleFeedback(_ feedback: AppViewModel.PopoverFeedback) {
        switch feedback {
        case .none:
            break
        case .success:
            transientLock = true
            setState(.success)
            consumePopoverFeedbackDeferred()
            scheduleReset(after: 1.5)
        case .warning(let message):
            transientLock = true
            setState(.warning(PopoverMessageFormatter.shortWarning(message)))
            consumePopoverFeedbackDeferred()
            scheduleReset(after: 2.2)
        case .error(let message):
            transientLock = true
            setState(.error(PopoverMessageFormatter.shortError(message)))
            consumePopoverFeedbackDeferred()
            scheduleReset(after: 2.0)
        }
    }

    private func setState(_ newState: SessionState) {
        guard state != newState else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            state = newState
        }
    }

    private func scheduleReset(after delay: TimeInterval) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.transientLock = false
            if self.appViewModel.sessionPhase == .idle {
                self.setState(.idle)
            }
        }
    }

    private func startMetricsTimer() {
        guard metricsTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Constants.metricsRefreshInterval, repeating: Constants.metricsRefreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshMetrics()
        }
        timer.resume()
        metricsTimer = timer
    }

    private func stopMetricsTimer() {
        metricsTimer?.cancel()
        metricsTimer = nil
    }

    private func startPermissionTimer() {
        guard permissionTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Constants.permissionRefreshInterval, repeating: Constants.permissionRefreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshPermissions()
        }
        timer.resume()
        permissionTimer = timer
    }

    private func stopPermissionTimer() {
        permissionTimer?.cancel()
        permissionTimer = nil
    }

    private func refreshMetrics() {
        todayDurationSeconds = appViewModel.costTracker.secondsToday()
        estimatedCost = appViewModel.costTracker.estimatedCostToday(for: appViewModel.settings.selectedModel)
    }

    private func refreshPermissions() {
        micPermission = PermissionHelper.microphoneStatus()
        accessibilityPermission = PermissionHelper.accessibilityStatus()

        if accessibilityPermission == .granted {
            showAccessibilityHint = false
        }
    }

    private func refreshHotkeyDisplay() {
        let shortcut = appViewModel.settings.hotkeyShortcut
        hotkeyTokens = shortcut.keycapTokens
        hotkeyDisplayText = shortcut.displayText
    }

    private func consumePopoverFeedbackDeferred() {
        DispatchQueue.main.async { [weak self] in
            self?.appViewModel.consumePopoverFeedback()
        }
    }
}
