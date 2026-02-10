import Foundation

enum SessionPhase: String, Sendable, Equatable {
    case idle
    case listening
    case transcribing

    var isRecording: Bool {
        self == .listening
    }

    var isTranscribing: Bool {
        self == .transcribing
    }

    var menuBarIconName: String {
        switch self {
        case .idle:
            return "mic"
        case .listening:
            return "mic.fill"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        }
    }
}
