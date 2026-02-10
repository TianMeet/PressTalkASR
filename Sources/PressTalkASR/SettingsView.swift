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

    @State private var apiKeyInput = ""
    @State private var statusMessage = ""
    @State private var showingMaskedAPIKey = false
    @State private var hasAXPermission = AXIsProcessTrusted()
    @State private var hasMicPermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var isRecordingHotkey = false
    @State private var hotkeyMonitor: Any?
    @State private var permissionPollingTask: Task<Void, Never>?

    var body: some View {
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
                    Text("按住 \(settings.hotkeyShortcut.displayText) 说话，松开自动转写并复制")
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
                cardTitle("Permissions", "lock.shield")

                permissionRow(
                    title: "Microphone",
                    granted: hasMicPermission,
                    actionTitle: "Open Microphone Settings",
                    action: { PermissionHelper.openMicrophoneSettings() }
                )

                permissionRow(
                    title: "Accessibility",
                    granted: hasAXPermission,
                    actionTitle: "Open Accessibility Settings",
                    action: { PermissionHelper.openAccessibilitySettings() }
                )
            }
        }
    }

    private var costCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Cost", "chart.line.uptrend.xyaxis")

                Text("今日累计时长：\(formatDuration(costTracker.secondsToday()))")
                    .font(.system(size: 13, weight: .medium))

                HStack(spacing: 10) {
                    metricPill("mini", String(format: "$%.4f", costTracker.estimatedCostTodayMini()))
                    metricPill("accurate", String(format: "$%.4f", costTracker.estimatedCostTodayAccurate()))
                }
            }
        }
    }

    private var statusCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle("Last Status", "text.bubble")
                Text(viewModel.lastMessage.isEmpty ? "Ready" : viewModel.lastMessage)
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
        statusMessage = "请按下新的快捷键组合…"

        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard isRecordingHotkey else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                stopHotkeyCapture()
                statusMessage = "已取消快捷键录制。"
                return nil
            }

            guard !event.isARepeat else { return nil }

            guard let shortcut = HotkeyShortcut.from(event: event) else {
                statusMessage = "快捷键至少需要一个修饰键，并且不能只按修饰键。"
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
