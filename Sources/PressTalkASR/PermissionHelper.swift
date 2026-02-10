import AppKit
import AVFoundation
import ApplicationServices

enum PermissionState {
    case granted
    case notGranted
    case unknown

    var label: String {
        switch self {
        case .granted:
            return "Granted"
        case .notGranted:
            return "Not Granted"
        case .unknown:
            return "Unknown"
        }
    }
}

enum PermissionSetting {
    case microphone
    case accessibility

    var deeplink: String {
        switch self {
        case .microphone:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

enum PermissionHelper {
    static func microphoneStatus() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .notGranted
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    static func accessibilityStatus() -> PermissionState {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    static func settingsURL(for setting: PermissionSetting) -> URL? {
        URL(string: setting.deeplink)
    }

    static func openSettings(for setting: PermissionSetting) {
        guard let url = settingsURL(for: setting) else { return }
        NSWorkspace.shared.open(url)
    }

    static func openMicrophoneSettings() {
        openSettings(for: .microphone)
    }

    static func openAccessibilitySettings() {
        openSettings(for: .accessibility)
    }
}
