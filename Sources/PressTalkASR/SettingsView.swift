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
    private let permissionRefreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
        }
        .onChange(of: settings.apiKeySourceState) { _ in
            syncAPIKeyInputFromStorage()
        }
        .onReceive(permissionRefreshTimer) { _ in
            refreshPermissionSnapshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionSnapshot()
        }
        .onDisappear {
            stopHotkeyCapture()
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

                StatusPill(status: viewModel.sessionStatus)
            }
        }
    }

    private var apiAndModelCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("API & Model", "cloud")

                HStack {
                    Text("API Key Source")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(settings.apiKeySource().title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(UITheme.secondaryText)
                }

                HStack(spacing: 8) {
                    Group {
                        if showingMaskedAPIKey {
                            HStack(spacing: 8) {
                                Text(apiKeyInput)
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("Saved")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.9))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.black.opacity(0.12), lineWidth: 0.8)
                            )
                        } else {
                            SecureField("sk-...", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Button(showingMaskedAPIKey ? "Replace" : "Save") {
                        if showingMaskedAPIKey {
                            apiKeyInput = ""
                            showingMaskedAPIKey = false
                            statusMessage = "请输入新的 Token 并保存。"
                            return
                        }

                        if let error = APIKeyFingerprint.validationError(for: apiKeyInput) {
                            statusMessage = error
                            return
                        }

                        statusMessage = viewModel.saveAPIKey(apiKeyInput)
                        syncAPIKeyInputFromStorage()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear") {
                        statusMessage = viewModel.clearAPIKey()
                        syncAPIKeyInputFromStorage()
                    }
                    .buttonStyle(.bordered)
                }

                Picker("Model", selection: $settings.selectedModelRawValue) {
                    Text("mini").tag(OpenAIModel.gpt4oMiniTranscribe.rawValue)
                    Text("accurate").tag(OpenAIModel.gpt4oTranscribe.rawValue)
                }
                .pickerStyle(.segmented)

                Picker("Language", selection: $settings.languageModeRawValue) {
                    ForEach(AppSettings.LanguageMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    modelHint(
                        title: "gpt-4o-mini-transcribe",
                        subtitle: "$0.003/min, 成本优先",
                        selected: settings.selectedModel == .gpt4oMiniTranscribe
                    )
                    modelHint(
                        title: "gpt-4o-transcribe",
                        subtitle: "$0.006/min, 准确率优先",
                        selected: settings.selectedModel == .gpt4oTranscribe
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Prompt（术语表 / 标点风格）")
                        .font(.system(size: 12, weight: .medium))
                    TextEditor(text: $settings.customPrompt)
                        .font(.system(size: 13))
                        .frame(minHeight: 92)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
                        )

                    Toggle("满足条件时发送 Prompt", isOn: $settings.promptEnabled)
                        .font(.system(size: 12, weight: .medium))

                    HStack {
                        Text("最短录音时长后才发送")
                            .font(.system(size: 12))
                            .foregroundStyle(UITheme.secondaryText)
                        Spacer()
                        Stepper(value: $settings.promptMinDurationSeconds, in: 0.2...8.0, step: 0.2) {
                            Text(String(format: "%.1f s", settings.promptMinDurationSeconds))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .controlSize(.small)
                    }

                    Text("仅在 Prompt 非空且录音时长达到阈值时发送。")
                        .font(.system(size: 11))
                        .foregroundStyle(UITheme.secondaryText)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(UITheme.secondaryText)
                }
            }
        }
    }

    private var behaviorCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Behavior", "switch.2")

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Global Hotkey")
                            Text("用于开始/结束录音")
                                .font(.system(size: 11))
                                .foregroundStyle(UITheme.secondaryText)
                        }

                        Spacer()
                        KeycapView(settings.hotkeyShortcut.keycapTokens)
                    }

                    HStack(spacing: 8) {
                        Button(isRecordingHotkey ? "Press Keys..." : "Record Shortcut") {
                            if isRecordingHotkey {
                                stopHotkeyCapture()
                                statusMessage = "已取消快捷键录制。"
                            } else {
                                startHotkeyCapture()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Reset Default") {
                            stopHotkeyCapture()
                            statusMessage = viewModel.resetHotkeyToDefault()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if isRecordingHotkey {
                        Text("按下新的组合键（需包含 ⌘ / ⌥ / ⌃ / ⇧），按 Esc 取消。")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Divider()

                Toggle(isOn: $settings.enableVADTrim) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable VAD Trim")
                        Text("录音前后自动裁剪静音片段")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Toggle(isOn: $settings.autoPasteEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Paste")
                        Text("复制后自动发送 Cmd+V 到前台应用")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                Toggle(isOn: $settings.enableAutoStopOnSilence) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Stop on Silence")
                        Text("说完停顿后自动结束并转写")
                            .font(.system(size: 11))
                            .foregroundStyle(UITheme.secondaryText)
                    }
                }

                DisclosureGroup("Advanced (Auto Stop)") {
                    VStack(alignment: .leading, spacing: 8) {
                        stepperRow(
                            title: "Silence Threshold",
                            valueText: String(format: "%.0f dB", settings.silenceThresholdDB)
                        ) {
                            Stepper("", value: $settings.silenceThresholdDB, in: -70 ... -20, step: 1)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        stepperRow(
                            title: "Silence Duration",
                            valueText: String(format: "%.0f ms", settings.silenceDurationMs)
                        ) {
                            Stepper("", value: $settings.silenceDurationMs, in: 300 ... 3000, step: 100)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        stepperRow(
                            title: "Start Guard",
                            valueText: String(format: "%.0f ms", settings.autoStopStartGuardMs)
                        ) {
                            Stepper("", value: $settings.autoStopStartGuardMs, in: 100 ... 1200, step: 50)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Toggle("Require speech before auto-stop", isOn: $settings.requireSpeechBeforeAutoStop)
                            .font(.system(size: 12, weight: .medium))

                        stepperRow(
                            title: "Speech Activate Threshold",
                            valueText: String(format: "%.0f dB", settings.speechActivateThresholdDB)
                        ) {
                            Stepper("", value: $settings.speechActivateThresholdDB, in: -60 ... -20, step: 1)
                                .labelsHidden()
                                .controlSize(.small)
                        }

                        Toggle("Debug Auto-stop Logs", isOn: $settings.autoStopDebugLogs)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
        }
    }

    private var permissionsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("Permissions", "lock.shield")

                permissionRow(
                    title: "Microphone",
                    granted: hasMicPermission,
                    actionTitle: "Open Microphone Settings",
                    action: { ClipboardManager.openMicrophoneSettings() }
                )

                permissionRow(
                    title: "Accessibility",
                    granted: hasAXPermission,
                    actionTitle: "Open Accessibility Settings",
                    action: { ClipboardManager.openAccessibilitySettings() }
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

    private func modelHint(title: String, subtitle: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(UITheme.secondaryText)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? UITheme.successColor.opacity(0.16) : Color.white.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? UITheme.successColor.opacity(0.35) : Color.black.opacity(0.07), lineWidth: 0.8)
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

    private func stepperRow<Control: View>(
        title: String,
        valueText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(UITheme.secondaryText)
            Spacer()
            Text(valueText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            control()
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

private struct StatusPill: View {
    let status: AppViewModel.SessionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text(status.title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(status.color.opacity(0.15))
        )
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                    .fill(UITheme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                    .stroke(UITheme.panelBorder, lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 2)
    }
}
