import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let didShowNotification = Notification.Name("SettingsWindowController.didShow")
    static let didCloseNotification = Notification.Name("SettingsWindowController.didClose")

    private var hasBeenShown = false
    private enum Layout {
        static let initialSize = NSSize(width: 900, height: 720)
        static let minSize = NSSize(width: 760, height: 640)
        static let maxSize = NSSize(width: 1100, height: 960)
    }

    init(viewModel: AppViewModel, settings: AppSettings, costTracker: CostTracker) {
        let rootView = SettingsView(viewModel: viewModel, settings: settings, costTracker: costTracker)
            .frame(width: Layout.initialSize.width, height: Layout.initialSize.height)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.tr("settings.window.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Layout.initialSize)
        window.minSize = Layout.minSize
        window.maxSize = Layout.maxSize
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.title = L10n.tr("settings.window.title")
        if !hasBeenShown {
            window.center()
            hasBeenShown = true
        }
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: Self.didShowNotification, object: window)
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.didCloseNotification, object: window)
    }
}
