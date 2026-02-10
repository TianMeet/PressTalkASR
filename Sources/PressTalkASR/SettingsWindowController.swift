import SwiftUI
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController {
    private var hasBeenShown = false

    init(viewModel: AppViewModel, settings: AppSettings, costTracker: CostTracker) {
        let rootView = SettingsView(viewModel: viewModel, settings: settings, costTracker: costTracker)
            .frame(width: 620, height: 660)

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 660))
        window.minSize = NSSize(width: 620, height: 620)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !hasBeenShown {
            window.center()
            hasBeenShown = true
        }
        window.makeKeyAndOrderFront(nil)
    }
}
