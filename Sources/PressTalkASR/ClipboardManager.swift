import AppKit
import ApplicationServices
import Carbon

enum AutoPasteError: LocalizedError {
    case accessibilityPermissionMissing
    case eventBuildFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return L10n.tr("error.autopaste.permission_missing")
        case .eventBuildFailed:
            return L10n.tr("error.autopaste.event_build_failed")
        }
    }
}

enum ClipboardManager {
    private enum Constants {
        static let keyEventIntervalSeconds: TimeInterval = 0.012
        static let commandKeyCode: CGKeyCode = CGKeyCode(kVK_Command)
        static let pasteKeyCode: CGKeyCode = CGKeyCode(kVK_ANSI_V)
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func autoPaste() throws {
        guard PermissionHelper.accessibilityStatus() == .granted else {
            throw AutoPasteError.accessibilityPermissionMissing
        }

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: Constants.commandKeyCode, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: Constants.pasteKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: Constants.pasteKeyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: Constants.commandKeyCode, keyDown: false) else {
            throw AutoPasteError.eventBuildFailed
        }

        let commandFlag: CGEventFlags = .maskCommand
        commandDown.flags = commandFlag
        vDown.flags = commandFlag
        vUp.flags = commandFlag
        commandUp.flags = []

        commandDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Constants.keyEventIntervalSeconds)
        vDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Constants.keyEventIntervalSeconds)
        vUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: Constants.keyEventIntervalSeconds)
        commandUp.post(tap: .cghidEventTap)
    }
}
