import SwiftUI
import Combine
import ApplicationServices
import AVFoundation
import AppKit
import Carbon

struct SettingsView: View {
    private enum Layout {
        static let contentMaxWidth: CGFloat = 980
        static let bentoBreakpoint: CGFloat = 860
        static let sectionSpacing: CGFloat = 14
        static let contentPadding: CGFloat = 20
        static let sideColumnMaxWidth: CGFloat = 330
    }

    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var costTracker: CostTracker
    @ObservedObject private var localization = LocalizationStore.shared

    @State private var apiKeyInput = ""
    @State private var statusMessage = ""
    @State private var showingMaskedAPIKey = false
    @State private var hasAXPermission = AXIsProcessTrusted()
    @State private var hasMicPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?
    @State private var permissionPollingTask: Task<Void, Never>?

    var body: some View {
        let _ = localization.refreshToken

        GeometryReader { proxy in
            let useTwoColumns = proxy.size.width >= Layout.bentoBreakpoint

            ScrollView {
                VStack(spacing: Layout.sectionSpacing) {
                    headerCard

                    if useTwoColumns {
                        apiAndModelCard

                        HStack(alignment: .top, spacing: Layout.sectionSpacing) {
                            behaviorCard
                                .layoutPriority(1)

                            VStack(spacing: Layout.sectionSpacing) {
                                permissionsCard
                                costCard
                            }
                            .frame(maxWidth: Layout.sideColumnMaxWidth)
                        }

                        statusCard
                    } else {
                        apiAndModelCard
                        behaviorCard
                        permissionsCard
                        costCard
                        statusCard
                    }
                }
                .padding(Layout.contentPadding)
                .frame(maxWidth: Layout.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            syncAPIKeyInputFromStorage()
            refreshPermissionSnapshot()
            startPermissionPolling()
        }
        .onChange(of: settings.apiKeySourceState) { _ in
            syncAPIKeyInputFromStorage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsWindowController.didShowNotification)) { _ in
            refreshPermissionSnapshot()
            startPermissionPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsWindowController.didCloseNotification)) { _ in
            stopPermissionPolling()
        }
        .onDisappear {
            stopHotkeyCapture()
            stopPermissionPolling()
        }
        .background(backgroundLayer)
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    UITheme.electricBlue.opacity(0.16),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 580
            )
        }
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        SettingsCard(accent: UITheme.electricBlue) {
            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(UITheme.electricBlue.opacity(0.16))
                            .frame(width: 36, height: 36)
                        Image(systemName: "mic.and.signal.meter")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(UITheme.electricBlue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PressTalk ASR")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(L10n.tr("settings.header.subtitle_format", settings.hotkeyShortcut.displayText))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Spacer(minLength: 12)

                SettingsLiveStatusModule(
                    statusText: viewModel.sessionStatus.title,
                    statusColor: viewModel.sessionStatus.color,
                    isIdle: !viewModel.isRecording && !viewModel.isTranscribing
                )
            }
        }
    }

    private var apiAndModelCard: some View {
        SettingsAPIModelCard(
            viewModel: viewModel,
            settings: settings,
            apiKeyInput: $apiKeyInput,
            statusMessage: $statusMessage,
            showingMaskedAPIKey: $showingMaskedAPIKey,
            onSyncAPIKeyInputFromStorage: syncAPIKeyInputFromStorage
        )
    }

    private var behaviorCard: some View {
        SettingsBehaviorCard(
            viewModel: viewModel,
            settings: settings,
            statusMessage: $statusMessage,
            isRecordingHotkey: $isRecordingHotkey,
            onStartHotkeyCapture: startHotkeyCapture,
            onStopHotkeyCapture: stopHotkeyCapture
        )
    }

    private var permissionsCard: some View {
        SettingsCard(accent: UITheme.electricBlue.opacity(0.8)) {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle(L10n.tr("settings.card.permissions"), "lock.shield")

                permissionRow(
                    title: L10n.tr("settings.permission.microphone"),
                    granted: hasMicPermission,
                    actionTitle: L10n.tr("settings.permission.open_microphone_settings"),
                    action: { PermissionHelper.openMicrophoneSettings() }
                )

                permissionRow(
                    title: L10n.tr("settings.permission.accessibility"),
                    granted: hasAXPermission,
                    actionTitle: L10n.tr("settings.permission.open_accessibility_settings"),
                    action: { PermissionHelper.openAccessibilitySettings() }
                )
            }
        }
    }

    private var costCard: some View {
        SettingsCard(accent: UITheme.electricBlue.opacity(0.7)) {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle(L10n.tr("settings.card.cost"), "chart.line.uptrend.xyaxis")

                Text(L10n.tr("settings.cost.today_duration_format", formatDuration(costTracker.secondsToday())))
                    .font(.system(size: 13, weight: .medium, design: .rounded))

                HStack(spacing: 10) {
                    metricPill(L10n.tr("settings.metric.mini"), String(format: "$%.4f", costTracker.estimatedCostTodayMini()))
                    metricPill(L10n.tr("settings.metric.accurate"), String(format: "$%.4f", costTracker.estimatedCostTodayAccurate()))
                }
            }
        }
    }

    private var statusCard: some View {
        SettingsCard(accent: UITheme.electricBlue.opacity(0.6)) {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle(L10n.tr("settings.card.last_status"), "text.bubble")
                Text(statusMessageText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(UITheme.secondaryText)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
    }

    private var statusMessageText: String {
        if !statusMessage.isEmpty {
            return statusMessage
        }
        if !viewModel.lastMessage.isEmpty {
            return viewModel.lastMessage
        }
        return L10n.tr("settings.status.ready")
    }

    private func cardTitle(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(UITheme.electricBlue)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
    }

    private func metricPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(UITheme.tertiaryText)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.8)
        )
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(granted ? UITheme.listeningColor : UITheme.errorColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(UITheme.electricBlue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.8)
        )
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func syncAPIKeyInputFromStorage() {
        if let masked = settings.maskedAPIKeyDisplay() {
            apiKeyInput = masked
            showingMaskedAPIKey = true
        } else {
            apiKeyInput = ""
            showingMaskedAPIKey = false
        }
    }

    private func refreshPermissionSnapshot() {
        hasMicPermission = PermissionHelper.microphoneStatus() == .granted
        hasAXPermission = PermissionHelper.accessibilityStatus() == .granted
    }

    private func startPermissionPolling() {
        guard permissionPollingTask == nil else { return }
        permissionPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                refreshPermissionSnapshot()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollingTask?.cancel()
        permissionPollingTask = nil
    }

    private func startHotkeyCapture() {
        stopHotkeyCapture()
        isRecordingHotkey = true
        statusMessage = L10n.tr("settings.status.hotkey_capture_prompt")

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isRecordingHotkey else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                stopHotkeyCapture()
                statusMessage = L10n.tr("settings.status.hotkey_capture_cancelled")
                return nil
            }

            guard !event.isARepeat else { return nil }

            guard let shortcut = HotkeyShortcut.from(event: event) else {
                statusMessage = L10n.tr("settings.status.hotkey_invalid")
                return nil
            }

            statusMessage = viewModel.updateHotkeyShortcut(shortcut)
            stopHotkeyCapture()
            return nil
        }
    }

    private func stopHotkeyCapture() {
        isRecordingHotkey = false
        if let hotkeyMonitor {
            NSEvent.removeMonitor(hotkeyMonitor)
            self.hotkeyMonitor = nil
        }
    }
}

private struct SettingsLiveStatusModule: View {
    let statusText: String
    let statusColor: Color
    let isIdle: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let breathe = 0.58 + 0.42 * (0.5 + 0.5 * sin(phase * 2.2))

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.25 * breathe))
                        .frame(width: 24, height: 24)
                        .blur(radius: isIdle ? 1.6 : 0.4)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    SettingsMiniWaveform(phase: phase, color: statusColor, active: !isIdle)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.8)
            )
        }
        .frame(width: 138)
    }
}

private struct SettingsMiniWaveform: View {
    let phase: TimeInterval
    let color: Color
    let active: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<9, id: \.self) { index in
                let base = active ? 5.0 : 2.8
                let amp = active ? 7.0 : 2.2
                let value = 0.5 + 0.5 * sin(phase * 3.0 + Double(index) * 0.7)

                Capsule(style: .continuous)
                    .fill(color.opacity(active ? 0.9 : 0.55))
                    .frame(width: 2.2, height: base + amp * value)
            }
        }
        .frame(height: 12)
    }
}
