import Foundation
import Carbon

enum HotkeyError: LocalizedError {
    case invalidShortcut
    case installHandlerFailed(OSStatus)
    case registerHotkeyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidShortcut:
            return L10n.tr("error.hotkey.invalid_shortcut")
        case .installHandlerFailed(let status):
            return L10n.tr("error.hotkey.install_handler_failed_format", status)
        case .registerHotkeyFailed(let status):
            return L10n.tr("error.hotkey.register_failed_format", status)
        }
    }
}

final class HotkeyManager {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: fourCharCode("PTTK"), id: 1)

    deinit {
        unregister()
    }

    func registerHotkey(_ shortcut: HotkeyShortcut = .defaultPushToTalk) throws {
        guard shortcut.isValid else {
            throw HotkeyError.invalidShortcut
        }
        unregister()

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var incomingID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &incomingID
                )

                guard
                    status == noErr,
                    incomingID.id == manager.hotKeyID.id,
                    incomingID.signature == manager.hotKeyID.signature
                else {
                    return noErr
                }

                let kind = GetEventKind(eventRef)
                if kind == UInt32(kEventHotKeyPressed) {
                    manager.onKeyDown?()
                } else if kind == UInt32(kEventHotKeyReleased) {
                    manager.onKeyUp?()
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotkeyError.installHandlerFailed(installStatus)
        }

        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            if let handler = eventHandlerRef {
                RemoveEventHandler(handler)
                eventHandlerRef = nil
            }
            throw HotkeyError.registerHotkeyFailed(registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
