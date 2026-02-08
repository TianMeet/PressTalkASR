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

    static func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
