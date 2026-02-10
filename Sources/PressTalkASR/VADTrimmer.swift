import Foundation
import AVFoundation

struct VADTrimmer: Sendable {
    struct Configuration: Sendable {
        var threshold: Float = 0.015
        var paddingSeconds: Double = 0.08
    }

    private let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    func trimSilence(inputURL: URL) async throws -> URL {
        try await Task.detached(priority: .userInitiated) { [configuration] in
            try Task.checkCancellation()
            let inputFile = try AVAudioFile(forReading: inputURL)
            let format = inputFile.processingFormat
            let frameCount = AVAudioFrameCount(inputFile.length)

            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return inputURL
            }

            try inputFile.read(into: buffer)
            try Task.checkCancellation()

            let totalFrames = Int(buffer.frameLength)
            guard totalFrames > 0 else { return inputURL }
            var speechStart: Int?
            var speechEnd: Int?

            switch format.commonFormat {
            case .pcmFormatFloat32:
                guard let channels = buffer.floatChannelData else { return inputURL }
                let mono = channels[0]
                for idx in 0..<totalFrames where abs(mono[idx]) > configuration.threshold {
                    if idx.isMultiple(of: 4096) {
                        try Task.checkCancellation()
                    }
                    speechStart = idx
                    break
                }
                if let first = speechStart {
                    for idx in stride(from: totalFrames - 1, through: first, by: -1)
                    where abs(mono[idx]) > configuration.threshold {
                        if idx.isMultiple(of: 4096) {
                            try Task.checkCancellation()
                        }
                        speechEnd = idx
                        break
                    }
                }

            case .pcmFormatInt16:
                guard let channels = buffer.int16ChannelData else { return inputURL }
                let mono = channels[0]
                for idx in 0..<totalFrames {
                    if idx.isMultiple(of: 4096) {
                        try Task.checkCancellation()
                    }
                    let normalized = abs(Float(mono[idx])) / Float(Int16.max)
                    if normalized > configuration.threshold {
                        speechStart = idx
                        break
                    }
                }
                if let first = speechStart {
                    for idx in stride(from: totalFrames - 1, through: first, by: -1) {
                        if idx.isMultiple(of: 4096) {
                            try Task.checkCancellation()
                        }
                        let normalized = abs(Float(mono[idx])) / Float(Int16.max)
                        if normalized > configuration.threshold {
                            speechEnd = idx
                            break
                        }
                    }
                }

            default:
                return inputURL
            }

            guard let first = speechStart else {
                return inputURL
            }

            guard let last = speechEnd, last >= first else {
                return inputURL
            }

            let padding = Int(Double(format.sampleRate) * configuration.paddingSeconds)
            let startFrame = max(0, first - padding)
            let endFrame = min(totalFrames - 1, last + padding)
            let trimmedFrames = endFrame - startFrame + 1

            if trimmedFrames >= totalFrames {
                return inputURL
            }
            try Task.checkCancellation()

            guard let trimmedBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(trimmedFrames)
            ) else {
                return inputURL
            }
            trimmedBuffer.frameLength = AVAudioFrameCount(trimmedFrames)

            let channelCount = Int(format.channelCount)

            switch format.commonFormat {
            case .pcmFormatFloat32:
                guard
                    let src = buffer.floatChannelData,
                    let dst = trimmedBuffer.floatChannelData
                else {
                    return inputURL
                }
                let bytes = trimmedFrames * MemoryLayout<Float>.size
                for channel in 0..<channelCount {
                    memcpy(dst[channel], src[channel].advanced(by: startFrame), bytes)
                }

            case .pcmFormatInt16:
                guard
                    let src = buffer.int16ChannelData,
                    let dst = trimmedBuffer.int16ChannelData
                else {
                    return inputURL
                }
                let bytes = trimmedFrames * MemoryLayout<Int16>.size
                for channel in 0..<channelCount {
                    memcpy(dst[channel], src[channel].advanced(by: startFrame), bytes)
                }

            default:
                return inputURL
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("press-talk-trimmed-\(UUID().uuidString)")
                .appendingPathExtension("wav")

            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            try Task.checkCancellation()
            try outputFile.write(from: trimmedBuffer)

            // If the trimmed WAV is larger than the original compressed file
            // (e.g. m4a/AAC input), prefer the original — smaller upload = faster.
            let originalSize = (try? inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let trimmedSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if trimmedSize >= originalSize && originalSize > 0 {
                try? FileManager.default.removeItem(at: outputURL)
                return inputURL
            }

            return outputURL
        }.value
    }
}
