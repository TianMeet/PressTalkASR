import SwiftUI

struct PopoverRootView: View {
    @StateObject private var viewModel: PopoverViewModel
    @GestureState private var isHoldingPrimary = false

    init(appViewModel: AppViewModel) {
        _viewModel = StateObject(wrappedValue: PopoverViewModel(appViewModel: appViewModel))
    }

    var body: some View {
        VStack(spacing: 11) {
            headerSection
            primaryActionSection
            quickToggleSection
            footerSection
        }
        .padding(15)
        .frame(width: 340)
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("PressTalk ASR")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Cloud speech-to-text")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()
            PopoverStatusPill(model: viewModel.statusPillModel)
        }
    }

    private var primaryActionSection: some View {
        PopoverCard {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(buttonBackground)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.primaryTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(viewModel.primarySubtitle)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.88))
                                .lineLimit(1)
                        }

                        Spacer()
                        KeycapView(viewModel.hotkeyTokens)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 46)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isHoldingPrimary) { _, state, _ in
                            state = true
                        }
                        .onEnded { _ in
                            Task { @MainActor in
                                viewModel.primaryPressEnded()
                            }
                        }
                )
                .onChange(of: isHoldingPrimary) { isHolding in
                    guard isHolding else { return }
                    Task { @MainActor in
                        viewModel.primaryPressBegan()
                    }
                }

                if viewModel.state == .recording {
                    miniRecordingBars
                }

                HStack {
                    Text("Today \(viewModel.todayDurationText)")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    Text("Estimated \(viewModel.estimatedCostText)")
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Button("Click to Toggle Recording") {
                        viewModel.clickToggleRecording()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
    }

    private var quickToggleSection: some View {
        PopoverCard {
            VStack(spacing: 10) {
                SettingsRow(
                    icon: "waveform.and.mic",
                    title: "Enable VAD Trim",
                    subtitle: "Trim leading and trailing silence",
                    isOn: Binding(
                        get: { viewModel.vadEnabled },
                        set: { value in
                            Task { @MainActor in
                                viewModel.setVADEnabled(value)
                            }
                        }
                    )
                )

                Divider()

                SettingsRow(
                    icon: "arrow.down.doc",
                    title: "Auto Paste",
                    subtitle: "Paste recognized text to front app",
                    isOn: Binding(
                        get: { viewModel.autoPasteEnabled },
                        set: { value in
                            Task { @MainActor in
                                viewModel.setAutoPasteEnabled(value)
                            }
                        }
                    ),
                    isDisabled: viewModel.autoPasteNeedsPermission && !viewModel.autoPasteEnabled,
                    badgeText: viewModel.autoPasteNeedsPermission ? "Needs permission" : nil,
                    trailingActionTitle: viewModel.autoPasteNeedsPermission ? "Open" : nil,
                    trailingAction: viewModel.autoPasteNeedsPermission ? { viewModel.openAccessibilitySettings() } : nil
                )

                if viewModel.showAccessibilityHint {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text("Auto Paste requires Accessibility permission")
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        HStack(spacing: 8) {
            footerButton("Settings", "gearshape", action: viewModel.openSettings)
            footerButton("Quit", "xmark.circle", action: viewModel.quit)
        }
    }

    private func footerButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 29)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var buttonBackground: some ShapeStyle {
        LinearGradient(
            colors: [viewModel.primaryTint.opacity(0.92), viewModel.primaryTint.opacity(0.76)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var miniRecordingBars: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    let value = 0.35 + 0.65 * abs(sin(phase * 1.6 + Double(index) * 0.55))
                    RoundedRectangle(cornerRadius: 1.3, style: .continuous)
                        .fill(Color.red.opacity(0.35))
                        .frame(width: 2.5, height: 8 + 10 * value)
                }
            }
            .frame(height: 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PopoverCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.80))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            )
    }
}
