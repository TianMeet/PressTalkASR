import AppKit
import ApplicationServices

enum AutoPasteError: LocalizedError {
    case accessibilityPermissionMissing
    case eventBuildFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Auto Paste 需要在系统设置中授予辅助功能权限。"
        case .eventBuildFailed:
            return "无法创建粘贴事件。"
        }
    }
}

enum ClipboardManager {
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
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: false) else {
            throw AutoPasteError.eventBuildFailed
        }

        let commandFlag: CGEventFlags = .maskCommand
        commandDown.flags = commandFlag
        vDown.flags = commandFlag
        vUp.flags = commandFlag

        commandDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
    }
}
