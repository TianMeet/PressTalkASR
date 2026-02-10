import Foundation
import Combine
import SwiftUI

enum HUDMode: Equatable {
    case hidden
    case listening
    case transcribing(String)
    case success(String)
    case error(String)
}

@MainActor
final class HUDStateMachine: ObservableObject {
    struct AutoDismiss {
        var successDelay: TimeInterval = 1.5
        var errorDelay: TimeInterval = 3.0
    }

    private enum Animation {
        static let dismissDuration: TimeInterval = 0.46
    }

    @Published private(set) var mode: HUDMode = .hidden
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var isHovering: Bool = false
    @Published private(set) var transitionID = UUID()

    var onModeChanged: ((HUDMode) -> Void)?

    private let autoDismiss: AutoDismiss
    private var elapsedTimer: DispatchSourceTimer?
    private var dismissTask: Task<Void, Never>?
    private var dismissStartedAt: Date?
    private var dismissDelay: TimeInterval?
    private var dismissRemaining: TimeInterval?

    init(autoDismiss: AutoDismiss = AutoDismiss()) {
        self.autoDismiss = autoDismiss
    }

    func showListening() {
        transition(to: .listening)
        startListeningTimer()
    }

    func showTranscribing() {
        transition(to: .transcribing(""))
    }

    func updateTranscribingPreview(_ text: String) {
        guard case .transcribing = mode else { return }
        mode = .transcribing(text)
        transitionID = UUID()
        onModeChanged?(mode)
    }

    func showSuccess(_ text: String) {
        transition(to: .success(text))
        scheduleDismiss(after: autoDismiss.successDelay)
    }

    func showError(_ reason: String) {
        transition(to: .error(reason))
        scheduleDismiss(after: autoDismiss.errorDelay)
    }

    func dismiss() {
        stopListeningTimer()
        cancelDismissTask()
        withAnimation(.timingCurve(0.22, 0.61, 0.36, 1.0, duration: Animation.dismissDuration)) {
            mode = .hidden
            transitionID = UUID()
        }
        onModeChanged?(.hidden)
    }

    func setHovering(_ hovering: Bool) {
        isHovering = hovering

        guard case .success = mode else { return }
        if hovering {
            pauseSuccessDismiss()
        } else {
            resumeSuccessDismiss()
        }
    }

    var elapsedTimeText: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func transition(to newMode: HUDMode) {
        stopListeningTimer()
        cancelDismissTask()
        elapsedSeconds = 0
        dismissStartedAt = nil
        dismissDelay = nil
        dismissRemaining = nil

        withAnimation(.easeOut(duration: 0.12)) {
            mode = newMode
            transitionID = UUID()
        }
        onModeChanged?(newMode)
    }

    private func startListeningTimer() {
        stopListeningTimer()
        elapsedSeconds = 0

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.elapsedSeconds += 1
        }
        timer.resume()
        elapsedTimer = timer
    }

    private func stopListeningTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        dismissStartedAt = Date()
        dismissDelay = delay
        dismissRemaining = delay

        dismissTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    private func pauseSuccessDismiss() {
        guard let startedAt = dismissStartedAt,
              let delay = dismissDelay else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        dismissRemaining = max(0.05, delay - elapsed)
        cancelDismissTask()
    }

    private func resumeSuccessDismiss() {
        guard let remaining = dismissRemaining else { return }
        scheduleDismiss(after: remaining)
    }

    private func cancelDismissTask() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}
