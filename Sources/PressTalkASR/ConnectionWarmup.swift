import Foundation

final class PrewarmGate: @unchecked Sendable {
    private let lock = NSLock()
    private let minInterval: TimeInterval
    private var lastStartAt: Date = .distantPast
    private var inFlight = false

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    func beginIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        guard !inFlight else { return false }
        guard now.timeIntervalSince(lastStartAt) >= minInterval else { return false }
        inFlight = true
        lastStartAt = now
        return true
    }

    func finish() {
        lock.lock()
        inFlight = false
        lock.unlock()
    }
}

final class KeepWarmController: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.xingkong.PressTalkASR.keep-warm")
    private var timer: DispatchSourceTimer?
    private var keepWarmUntil: Date = .distantPast

    deinit {
        cancelTimer()
    }

    func extendWindow(
        by seconds: TimeInterval,
        tickInterval: TimeInterval,
        onTick: @escaping @Sendable () -> Void
    ) {
        var timerToResume: DispatchSourceTimer?

        lock.lock()
        let deadline = Date().addingTimeInterval(seconds)
        if deadline > keepWarmUntil {
            keepWarmUntil = deadline
        }
        if timer == nil {
            let newTimer = DispatchSource.makeTimerSource(queue: queue)
            newTimer.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
            newTimer.setEventHandler { [weak self] in
                guard let self else { return }
                if self.isExpired() {
                    self.cancelTimer()
                    return
                }
                onTick()
            }
            timer = newTimer
            timerToResume = newTimer
        }
        lock.unlock()

        timerToResume?.resume()
    }

    private func isExpired() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date() >= keepWarmUntil
    }

    private func cancelTimer() {
        lock.lock()
        let existing = timer
        timer = nil
        lock.unlock()
        existing?.cancel()
    }
}
