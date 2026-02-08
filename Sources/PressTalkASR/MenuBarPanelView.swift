import SwiftUI
import AppKit

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var costTracker: CostTracker

    var body: some View {
        VStack(spacing: 12) {
            headerCard
            controlCard
            quickSwitchCard
            footerCard
        }
        .padding(14)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: UITheme.panelCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var headerCard: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(UITheme.successColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PressTalk ASR")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Cloud speech-to-text")
                        .font(.system(size: 11))
                        .foregroundStyle(UITheme.secondaryText)
                }

                Spacer()

                StatusChip(status: viewModel.sessionStatus)
            }
        }
    }

    private var controlCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await viewModel.toggleManualRecording() }
                } label: {
                    HStack {
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        Text(viewModel.isRecording ? "Stop Recording" : "Start Recording")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("⌥ Space")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(viewModel.isRecording ? UITheme.errorColor : UITheme.listeningColor)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                HStack {
                    Text("Today: \(formatDuration(costTracker.secondsToday()))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(UITheme.secondaryText)
                    Spacer()
                    Text(String(format: "$%.4f", costTracker.estimatedCostToday(for: settings.selectedModel)))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(UITheme.secondaryText)
                }
            }
        }
    }

    private var quickSwitchCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                Toggle(isOn: $settings.autoPasteEnabled) {
                    Label("Auto Paste", systemImage: "arrow.down.doc")
                }
                .toggleStyle(.switch)

                Toggle(isOn: $settings.enableVADTrim) {
                    Label("VAD Trim", systemImage: "waveform.and.mic")
                }
                .toggleStyle(.switch)
            }
            .font(.system(size: 12, weight: .medium))
        }
    }

    private var footerCard: some View {
        GlassCard {
            HStack(spacing: 8) {
                Button {
                    viewModel.runHUDDemo()
                } label: {
                    footerButtonLabel("HUD Demo", "sparkles")
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.openSettingsWindow()
                } label: {
                    footerButtonLabel("Settings", "gearshape")
                }
                .buttonStyle(.plain)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    footerButtonLabel("Quit", "xmark.circle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func footerButtonLabel(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.06))
        )
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let total = Int(value)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                    .fill(UITheme.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                    .stroke(UITheme.panelBorder, lineWidth: 0.8)
            )
    }
}

private struct StatusChip: View {
    let status: AppViewModel.SessionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text(status.title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(status.color.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(status.color.opacity(0.35), lineWidth: 0.8)
        )
    }
}
