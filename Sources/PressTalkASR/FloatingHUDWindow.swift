import SwiftUI
import AppKit

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
final class FloatingHUDWindow {
    private enum Animation {
        static let showDuration: TimeInterval = 0.24
        static let resizeDuration: TimeInterval = 0.16
        static let hideDuration: TimeInterval = 0.46
        static let showOffsetX: CGFloat = 9
        static let showOffsetY: CGFloat = -6
        static let hideDriftY: CGFloat = 6
        static let hideAlphaPower: CGFloat = 1.75
        // 60 FPS is enough for HUD transitions and avoids extra wakeups on most displays.
        static let tickMilliseconds = 16
    }

    private let panel: HUDPanel
    private let layout: HUDLayoutConfig
    private let hostingView: TransparentHostingView<HUDView>
    private var animationTimer: DispatchSourceTimer?
    private var animationToken: UInt64 = 0
    private var anchorPosition: HUDAnchorPosition = .bottomRight

    deinit {
        animationTimer?.cancel()
    }

    init(rootView: HUDView, layout: HUDLayoutConfig) {
        self.layout = layout
        self.panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: layout.width, height: layout.minHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = false

        hostingView = TransparentHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: layout.width, height: layout.minHeight)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false

        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
        clearWindowChromeArtifacts()
        panel.setFrame(anchorFrame(width: layout.width, height: layout.minHeight), display: true)
    }

    func setRootView(_ rootView: HUDView) {
        hostingView.rootView = rootView
    }

    func setAnchorPosition(_ anchor: HUDAnchorPosition) {
        guard anchorPosition != anchor else { return }
        anchorPosition = anchor

        let targetFrame = anchorFrame(width: panel.frame.width, height: panel.frame.height)
        if panel.isVisible {
            animateFrameTransition(from: panel.frame, to: targetFrame, duration: Animation.resizeDuration)
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    func show(height: CGFloat) {
        clearWindowChromeArtifacts()
        let finalFrame = anchorFrame(width: layout.width, height: height)
        panel.setContentSize(NSSize(width: layout.width, height: height))

        if panel.isVisible {
            animateFrameTransition(from: panel.frame, to: finalFrame, duration: Animation.resizeDuration)
            return
        }

        let startFrame = NSRect(
            x: finalFrame.origin.x + Animation.showOffsetX,
            y: finalFrame.origin.y + Animation.showOffsetY,
            width: finalFrame.width,
            height: finalFrame.height
        )

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: true)
        panel.orderFrontRegardless()

        animatePanel(duration: Animation.showDuration) { [weak self] progress in
            guard let self else { return }
            let eased = smootherStep(progress)
            panel.alphaValue = eased
            panel.setFrame(interpolateFrame(from: startFrame, to: finalFrame, progress: eased), display: false)
        } completion: { [weak self] in
            guard let self else { return }
            panel.alphaValue = 1
            panel.setFrame(finalFrame, display: true)
        }
    }

    func resize(height: CGFloat) {
        guard panel.isVisible else { return }
        clearWindowChromeArtifacts()
        let finalFrame = anchorFrame(width: layout.width, height: height)
        panel.setContentSize(NSSize(width: layout.width, height: height))
        animateFrameTransition(from: panel.frame, to: finalFrame, duration: Animation.resizeDuration)
    }

    func hide() {
        guard panel.isVisible else { return }

        let startFrame = panel.frame
        let targetFrame = NSRect(
            x: startFrame.origin.x,
            y: startFrame.origin.y - Animation.hideDriftY,
            width: startFrame.width,
            height: startFrame.height
        )
        let startAlpha = panel.alphaValue

        animatePanel(duration: Animation.hideDuration) { [weak self] progress in
            guard let self else { return }
            let eased = smootherStep(progress)
            let fade = pow(max(0, 1 - eased), Animation.hideAlphaPower)
            panel.alphaValue = startAlpha * fade
            panel.setFrame(interpolateFrame(from: startFrame, to: targetFrame, progress: eased), display: false)
        } completion: { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.setContentSize(NSSize(width: layout.width, height: layout.minHeight))
            panel.setFrame(anchorFrame(width: layout.width, height: layout.minHeight), display: true)
        }
    }

    private func anchorFrame(width: CGFloat, height: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }

        let visible = screen.visibleFrame
        let x: CGFloat
        let y: CGFloat

        switch anchorPosition {
        case .bottomRight:
            x = visible.maxX - width - layout.edgePadding
            y = visible.minY + layout.edgePadding
        case .bottomLeft:
            x = visible.minX + layout.edgePadding
            y = visible.minY + layout.edgePadding
        case .topRight:
            x = visible.maxX - width - layout.edgePadding
            y = visible.maxY - height - layout.edgePadding
        case .topLeft:
            x = visible.minX + layout.edgePadding
            y = visible.maxY - height - layout.edgePadding
        }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func clearWindowChromeArtifacts() {
        panel.backgroundColor = .clear
        clearBackgroundRecursively(panel.contentView)
        clearBackgroundRecursively(panel.contentView?.superview)
    }

    private func clearBackgroundRecursively(_ view: NSView?) {
        guard let view else { return }
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.borderWidth = 0
        for subview in view.subviews {
            clearBackgroundRecursively(subview)
        }
    }

    private func animateFrameTransition(from: NSRect, to: NSRect, duration: TimeInterval) {
        animatePanel(duration: duration) { [weak self] progress in
            guard let self else { return }
            let eased = smootherStep(progress)
            panel.setFrame(interpolateFrame(from: from, to: to, progress: eased), display: false)
        } completion: {
            self.panel.setFrame(to, display: true)
        }
    }

    private func animatePanel(
        duration: TimeInterval,
        step: @escaping @MainActor (CGFloat) -> Void,
        completion: @escaping @MainActor () -> Void
    ) {
        animationToken &+= 1
        let token = animationToken
        animationTimer?.cancel()
        animationTimer = nil

        guard duration > 0 else {
            step(1)
            completion()
            return
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(Animation.tickMilliseconds))
        timer.setEventHandler { [weak self] in
            guard let self else {
                timer.cancel()
                return
            }
            guard token == self.animationToken else {
                timer.cancel()
                return
            }

            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let linear = max(0, min(1, CGFloat(elapsed / duration)))
            step(linear)

            if linear >= 1 {
                timer.cancel()
                if token == self.animationToken {
                    self.animationTimer = nil
                    completion()
                }
            }
        }

        animationTimer = timer
        timer.resume()
    }

    private func smootherStep(_ t: CGFloat) -> CGFloat {
        let x = max(0, min(1, t))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private func interpolateFrame(from: NSRect, to: NSRect, progress: CGFloat) -> NSRect {
        NSRect(
            x: from.origin.x + (to.origin.x - from.origin.x) * progress,
            y: from.origin.y + (to.origin.y - from.origin.y) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }
}
