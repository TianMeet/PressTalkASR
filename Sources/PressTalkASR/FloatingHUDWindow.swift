import SwiftUI
import AppKit

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingHUDWindow {
    private let panel: HUDPanel
    private let layout: HUDLayoutConfig
    private let hostingView: NSHostingView<HUDView>

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
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow

        hostingView = NSHostingView(rootView: rootView)
        panel.contentView = hostingView
        panel.setFrame(anchorFrame(width: layout.width, height: layout.minHeight), display: true)
    }

    func setRootView(_ rootView: HUDView) {
        hostingView.rootView = rootView
    }

    func show(height: CGFloat) {
        let finalFrame = anchorFrame(width: layout.width, height: height)

        if panel.isVisible {
            resize(height: height)
            return
        }

        let startFrame = NSRect(
            x: finalFrame.origin.x + 10,
            y: finalFrame.origin.y - 6,
            width: finalFrame.width,
            height: finalFrame.height
        )

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: true)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    func resize(height: CGFloat) {
        guard panel.isVisible else { return }
        let frame = anchorFrame(width: layout.width, height: height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func hide() {
        guard panel.isVisible else { return }

        var target = panel.frame
        target.origin.y -= 8

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(target, display: true)
        } completionHandler: {
            Task { @MainActor in
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
                self.panel.setFrame(self.anchorFrame(width: self.layout.width, height: self.layout.minHeight), display: true)
            }
        }
    }

    private func anchorFrame(width: CGFloat, height: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: height)
        }

        let visible = screen.visibleFrame
        let x = visible.maxX - width - layout.edgePadding
        let y = visible.minY + layout.edgePadding
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
