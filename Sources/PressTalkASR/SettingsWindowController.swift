import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let didShowNotification = Notification.Name("SettingsWindowController.didShow")
    static let didCloseNotification = Notification.Name("SettingsWindowController.didClose")

    private var hasBeenShown = false

    init(viewModel: AppViewModel, settings: AppSettings, costTracker: CostTracker) {
        let rootView = SettingsView(viewModel: viewModel, settings: settings, costTracker: costTracker)
            .frame(width: 620, height: 660)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.tr("settings.window.title")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 660))
        window.minSize = NSSize(width: 620, height: 620)
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
