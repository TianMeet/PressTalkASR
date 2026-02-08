import Foundation
import Combine
import CoreGraphics

@MainActor
final class AudioLevelMeter: ObservableObject {
    struct Configuration {
        var barCount: Int = 10
        var minLevel: CGFloat = 0.12
        var maxLevel: CGFloat = 1.0
        var smoothFactor: CGFloat = 0.24
        var decayFactor: CGFloat = 0.85
    }

    @Published private(set) var levels: [CGFloat]

    private let config: Configuration
    private var smoothed: CGFloat = 0
    private var isActive = false

    init(config: Configuration = Configuration()) {
        self.config = config
        self.levels = Array(repeating: config.minLevel, count: config.barCount)
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active {
            smoothed = 0
            for index in levels.indices {
                levels[index] = max(config.minLevel, levels[index] * config.decayFactor)
            }
        }
    }

    func ingestRMS(_ rms: Float) {
        guard isActive else { return }

        let incoming = max(0, min(1, CGFloat(rms)))
        smoothed = smoothed * (1 - config.smoothFactor) + incoming * config.smoothFactor

        let center = CGFloat(max(1, config.barCount - 1)) / 2
        for index in levels.indices {
            let distance = abs(CGFloat(index) - center) / max(1, center)
            let attenuation = 1 - (distance * 0.35)
            let jitter = CGFloat.random(in: -0.04...0.04)
            let target = config.minLevel + (smoothed * attenuation) + jitter
            let clamped = max(config.minLevel, min(config.maxLevel, target))
            levels[index] = levels[index] * 0.68 + clamped * 0.32
        }
    }
}
