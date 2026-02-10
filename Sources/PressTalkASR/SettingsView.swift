import SwiftUI
import Combine
import ApplicationServices
import AVFoundation
import AppKit
import Carbon

struct SettingsView: View {
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
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                apiAndModelCard
                behaviorCard
                permissionsCard
                costCard
                statusCard
            }
            .padding(16)
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
        .background(
            LinearGradient(
                colors: [Color.white, Color(red: 0.95, green: 0.97, blue: 0.99)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var headerCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Image(systemName: "mic.and.signal.meter")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(UITheme.successColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text("PressTalk ASR")
                        .font(.system(size: 17, weight: .semibold))
                    Text(L10n.tr("settings.header.subtitle_format", settings.hotkeyShortcut.displayText))
                        .font(.system(size: 12))
                        .foregroundStyle(UITheme.secondaryText)
                }

                Spacer()

                SessionStatusBadge(status: viewModel.sessionStatus)
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
        SettingsCard {
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
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle(L10n.tr("settings.card.cost"), "chart.line.uptrend.xyaxis")

                Text(L10n.tr("settings.cost.today_duration_format", formatDuration(costTracker.secondsToday())))
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 10) {
                    metricPill(L10n.tr("settings.metric.mini"), String(format: "$%.4f", costTracker.estimatedCostTodayMini()))
                    metricPill(L10n.tr("settings.metric.accurate"), String(format: "$%.4f", costTracker.estimatedCostTodayAccurate()))
                }
            }
        }
    }

    private var statusCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle(L10n.tr("settings.card.last_status"), "text.bubble")
                Text(viewModel.lastMessage.isEmpty ? L10n.tr("settings.status.ready") : viewModel.lastMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(UITheme.secondaryText)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
        }
    }

    private func cardTitle(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(UITheme.successColor)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
        }
    }

    private func metricPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(UITheme.secondaryText)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(granted ? UITheme.successColor : UITheme.errorColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
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
