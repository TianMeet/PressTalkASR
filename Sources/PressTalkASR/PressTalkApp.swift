import SwiftUI
import AppKit

@main
struct PressTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView(appViewModel: viewModel)
        } label: {
            Image(systemName: viewModel.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
