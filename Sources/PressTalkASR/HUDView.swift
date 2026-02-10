import SwiftUI
import AppKit

struct HUDLayoutConfig {
    var width: CGFloat = 380
    var minHeight: CGFloat = 106
    var maxHeight: CGFloat = 200
    var horizontalInset: CGFloat = 17
    var verticalInset: CGFloat = 17
    var cornerRadius: CGFloat = 18
    var edgePadding: CGFloat = 24
}

struct HUDView: View {
    @ObservedObject var stateMachine: HUDStateMachine
    @ObservedObject var levelMeter: AudioLevelMeter
    @ObservedObject var settings: HUDSettingsStore
    @ObservedObject private var localization = LocalizationStore.shared

    let layout: HUDLayoutConfig
    let onClose: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    @State private var hoverVisible = false
    @State private var frozenMode: HUDMode = .hidden

    var body: some View {
        let _ = localization.refreshToken
        card
            .fixedSize(horizontal: true, vertical: true)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                hoverVisible = hovering
            }
            stateMachine.setHovering(hovering)
        }
        .onAppear {
            if case .hidden = stateMachine.mode {
                frozenMode = .hidden
            } else {
                frozenMode = stateMachine.mode
            }
        }
        .onChange(of: stateMachine.mode) { newMode in
            if case .hidden = newMode {
                return
            }
            frozenMode = newMode
        }
    }

    private var card: some View {
        cardSurface
            .overlay(alignment: .topTrailing) {
                if hoverVisible {
                    closeButton
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .transition(.opacity)
                }
            }
    }

    private var cardSurface: some View {
        VStack(alignment: .leading, spacing: 11) {
            topBar
            bodyContent
            footer
        }
        .padding(.horizontal, layout.horizontalInset)
        .padding(.vertical, layout.verticalInset)
        .frame(width: layout.width, alignment: .leading)
        .background(RoundedMaterialBackground(cornerRadius: layout.cornerRadius))
        .clipShape(cardShape)
        .overlay {
            cardShape
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .background {
            cardShape
                .fill(Color.black.opacity(0.001))
                .shadow(color: Color.black.opacity(0.20), radius: 18, y: 10)
                .shadow(color: Color.black.opacity(0.12), radius: 4, y: 1)
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)

            if showsInlineSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(stateColor)
            }

            Text(statusTitle)
                .font(.system(size: 13.5, weight: .semibold))

            Spacer(minLength: 8)

            if !trailingHint.isEmpty {
                Text(trailingHint)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch effectiveMode {
        case .listening:
            VStack(alignment: .leading, spacing: 6) {
                AudioDotWaveView(levels: levelMeter.levels, color: stateColor)
                Text(L10n.tr("hud.body.release_to_end_transcribe"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .transcribing(let preview):
            if preview.isEmpty {
                Text(L10n.tr("hud.body.processing_wait"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(preview)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        case .success(let text):
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
        case .error:
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("hud.body.retry_question"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(L10n.tr("hud.body.reduce_noise_hint"))
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if hoverVisible {
                    HStack(spacing: 12) {
                        Button(L10n.tr("hud.button.retry")) { onRetry() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)

                        Button(L10n.tr("hud.button.settings")) { onOpenSettings() }
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

    @ViewBuilder
    private var footer: some View {
        if !footerText.isEmpty {
            Text(footerText)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private var statusTitle: String {
        switch effectiveMode {
        case .listening:
            return L10n.tr("hud.status.listening")
        case .transcribing:
            return L10n.tr("hud.status.transcribing")
        case .success:
            return L10n.tr("hud.status.done")
        case .error:
            return L10n.tr("hud.status.retry")
        case .hidden:
            return ""
        }
    }

    private var trailingHint: String {
        switch effectiveMode {
        case .listening:
            return stateMachine.elapsedTimeText
        case .transcribing:
            return settings.autoPasteEnabled ? L10n.tr("hud.hint.auto_copy_paste") : L10n.tr("hud.hint.auto_copy")
        case .success:
            return settings.autoPasteEnabled ? L10n.tr("hud.hint.copied_pasted") : L10n.tr("hud.hint.copied")
        case .error:
            return L10n.tr("hud.hint.hold_retry")
        case .hidden:
            return ""
        }
    }

    private var footerText: String {
        switch effectiveMode {
        case .hidden:
            return ""
        default:
            return "\(settings.languageMode) · \(settings.modelMode)"
        }
    }

    private var showsInlineSpinner: Bool {
        if case .transcribing = effectiveMode {
            return true
        }
        return false
    }

    private var stateColor: Color {
        switch effectiveMode {
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

    private var effectiveMode: HUDMode {
        if case .hidden = stateMachine.mode {
            return frozenMode
        }
        return stateMachine.mode
    }
}

private struct AudioDotWaveView: View {
    let levels: [CGFloat]
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
            let energy = max(0, min(1, normalizedEnergy))
            let phase = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 4.5) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let envelope = centerEnvelope(for: index)
                    let levelInfluence = max(0, min(1, level))
                    let wave = 0.5 + 0.5 * sin(phase * 6.2 + Double(index) * 0.52)
                    let amplitude = (0.28 + energy * 0.72) * envelope
                    let pulse = (0.55 + 0.45 * wave) * (0.55 + 0.45 * levelInfluence)
                    let scale = 0.58 + amplitude * pulse * 1.45
                    let yOffset = -amplitude * pulse * 7.0
                    let opacity = 0.24 + amplitude * 0.74
                    let glow = 1.0 + amplitude * 3.8

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(opacity), color.opacity(opacity * 0.72)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 5.2, height: 5.2)
                        .scaleEffect(scale)
                        .offset(y: yOffset)
                        .shadow(color: color.opacity(0.28), radius: glow, x: 0, y: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
        }
    }

    private var normalizedEnergy: CGFloat {
        guard !levels.isEmpty else { return 0 }
        let sum = levels.reduce(0, +)
        return sum / CGFloat(levels.count)
    }

    private func centerEnvelope(for index: Int) -> CGFloat {
        let center = CGFloat(max(1, levels.count - 1)) / 2
        let distance = abs(CGFloat(index) - center) / max(1, center)
        return max(0.22, 1 - distance * distance)
    }
}

private struct RoundedMaterialBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> RoundedMaterialContainerView {
        RoundedMaterialContainerView(cornerRadius: cornerRadius)
    }

    func updateNSView(_ nsView: RoundedMaterialContainerView, context: Context) {
        nsView.updateCornerRadius(cornerRadius)
    }
}

private final class RoundedMaterialContainerView: NSView {
    private let effectView = NSVisualEffectView()
    private let maskLayer = CAShapeLayer()
    private var cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false

        effectView.state = .active
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.wantsLayer = true
        effectView.layer?.backgroundColor = NSColor.clear.cgColor
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        applyMask()
    }

    func updateCornerRadius(_ newValue: CGFloat) {
        guard abs(newValue - cornerRadius) > 0.001 else { return }
        cornerRadius = newValue
        needsLayout = true
    }

    private func applyMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        maskLayer.path = path
        effectView.layer?.mask = maskLayer
    }
}
