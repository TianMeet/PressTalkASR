import SwiftUI

struct HUDLayoutConfig {
    var width: CGFloat = 380
    var minHeight: CGFloat = 92
    var maxHeight: CGFloat = 180
    var horizontalInset: CGFloat = 16
    var verticalInset: CGFloat = 12
    var cornerRadius: CGFloat = 18
    var edgePadding: CGFloat = 24
}

struct HUDView: View {
    @ObservedObject var stateMachine: HUDStateMachine
    @ObservedObject var levelMeter: AudioLevelMeter
    @ObservedObject var settings: HUDSettingsStore

    let layout: HUDLayoutConfig
    let onClose: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    @State private var hoverVisible = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                topBar
                    .frame(height: 24)

                middleFeedback
                    .frame(height: 24)

                bottomContent
            }
            .id(stateMachine.transitionID)
            .transition(.opacity)
            .padding(.horizontal, layout.horizontalInset)
            .padding(.vertical, layout.verticalInset)
            .frame(width: layout.width, alignment: .leading)
            .background(HUDMaterialBackground(cornerRadius: layout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)

            if hoverVisible {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                hoverVisible = hovering
            }
            stateMachine.setHovering(hovering)
        }
        .animation(.easeOut(duration: 0.14), value: stateMachine.transitionID)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            Text(statusTitle)
                .font(.system(size: 13.5, weight: .semibold))

            Spacer(minLength: 8)

            Text(trailingHint)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var middleFeedback: some View {
        switch stateMachine.mode {
        case .listening:
            AudioBarsView(levels: levelMeter.levels, color: stateColor)
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(stateColor)
                Text("识别中")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .success, .error:
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        case .hidden:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bottomContent: some View {
        switch stateMachine.mode {
        case .listening:
            VStack(alignment: .leading, spacing: 2) {
                Text("松开结束并转写")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(settings.languageMode) · \(settings.modelMode)")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        case .transcribing:
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.autoPasteEnabled ? "识别中…（将自动复制并粘贴）" : "识别中…（将自动复制）")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(settings.languageMode) · \(settings.modelMode)")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        case .success(let text):
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
        case .error:
            VStack(alignment: .leading, spacing: 2) {
                Text("没听清楚，再试一次？")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("尽量靠近麦克风或减少噪声")
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if hoverVisible {
                    HStack(spacing: 12) {
                        Button("重试") { onRetry() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)

                        Button("设置") { onOpenSettings() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
        case .hidden:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch stateMachine.mode {
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .success:
            return "Success"
        case .error:
            return "Error"
        case .hidden:
            return ""
        }
    }

    private var trailingHint: String {
        switch stateMachine.mode {
        case .listening:
            return stateMachine.elapsedTimeText
        case .transcribing:
            return "松开完成"
        case .success:
            return settings.autoPasteEnabled ? "已复制并粘贴" : "已复制"
        case .error:
            return "按住重试"
        case .hidden:
            return ""
        }
    }

    private var stateColor: Color {
        switch stateMachine.mode {
        case .listening:
            return Color(red: 0.231, green: 0.510, blue: 0.965)
        case .transcribing:
            return Color(red: 0.388, green: 0.400, blue: 0.945)
        case .success:
            return Color(red: 0.133, green: 0.773, blue: 0.369)
        case .error:
            return Color(red: 0.937, green: 0.267, blue: 0.267)
        case .hidden:
            return .secondary
        }
    }
}

private struct AudioBarsView: View {
    let levels: [CGFloat]
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(color.opacity(0.40))
                    .frame(width: 3, height: max(4, 20 * level))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HUDMaterialBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.layer?.cornerRadius = cornerRadius
    }
}
