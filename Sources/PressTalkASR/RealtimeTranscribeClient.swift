import Foundation
@preconcurrency import AVFoundation

struct RealtimeTranscribeClient {
    struct Configuration: Sendable {
        var silenceDurationMs: Int = 600
        var prefixPaddingMs: Int = 240
    }

    private enum Constants {
        /// OpenAI API 文件上传大小上限
        static let maxFileSizeBytes = 25 * 1024 * 1024        // 25 MB
        static let requestTimeoutInterval: TimeInterval = 50
        static let resourceTimeoutInterval: TimeInterval = 60
        /// PCM16 音频分块大小（字节/每个 WebSocket 消息）
        /// 32000 bytes ≈ 0.67 秒 24kHz mono PCM16
        static let audioChunkSize = 32_000
        /// 转写结果最大等待时间
        static let transcriptionTimeoutSeconds: TimeInterval = 45
        /// OpenAI Realtime API 要求的 PCM16 采样率
        static let realtimeSampleRate: Double = 24_000
    }

    private let endpoint = URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.requestTimeoutInterval
        config.timeoutIntervalForResource = Constants.resourceTimeoutInterval
        session = URLSession(configuration: config)
    }

    /// 预热到 OpenAI 的 TLS 连接，录音期间提前握手以减少转写延迟。
    func prewarmConnection() {
        let session = self.session
        Task.detached(priority: .utility) {
            guard let url = URL(string: "https://api.openai.com") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            _ = try? await session.data(for: request)
        }
    }

    func transcribe(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String,
        config: Configuration,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if fileSize > Constants.maxFileSizeBytes {
            throw OpenAITranscribeError.fileTooLarge
        }

        let pcm16 = try decodeToPCM16Mono(fileURL: fileURL)
        if pcm16.isEmpty {
            throw OpenAITranscribeError.emptyText
        }

        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let socket = session.webSocketTask(with: request)
        socket.resume()

        do {
            try await sendSessionUpdate(
                socket: socket,
                model: model,
                prompt: prompt,
                languageCode: languageCode,
                config: config
            )

            let receiveTask = Task { try await receiveFinalText(socket: socket, onDelta: onDelta) }
            try await sendAudioBuffer(socket: socket, pcm16: pcm16)

            let final = try await withTimeout(seconds: Constants.transcriptionTimeoutSeconds) {
                try await receiveTask.value
            }
            socket.cancel(with: .normalClosure, reason: nil)
            return final
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            if let transcribeError = error as? OpenAITranscribeError {
                throw transcribeError
            }
            throw OpenAITranscribeError.network(error.localizedDescription)
        }
    }

    private func sendSessionUpdate(
        socket: URLSessionWebSocketTask,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        config: Configuration
    ) async throws {
        var sessionPayload: [String: Any] = [
            "type": "session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": model.rawValue
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "silence_duration_ms": config.silenceDurationMs,
                    "prefix_padding_ms": config.prefixPaddingMs
                ]
            ]
        ]

        if let languageCode, !languageCode.isEmpty,
           var session = sessionPayload["session"] as? [String: Any],
           var transcription = session["input_audio_transcription"] as? [String: Any] {
            transcription["language"] = languageCode
            session["input_audio_transcription"] = transcription
            sessionPayload["session"] = session
        }

        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           var session = sessionPayload["session"] as? [String: Any],
           var transcription = session["input_audio_transcription"] as? [String: Any] {
            transcription["prompt"] = prompt
            session["input_audio_transcription"] = transcription
            sessionPayload["session"] = session
        }

        try await sendJSON(socket: socket, object: sessionPayload)
    }

    private func sendAudioBuffer(socket: URLSessionWebSocketTask, pcm16: Data) async throws {
        let chunkSize = Constants.audioChunkSize
        var offset = 0

        while offset < pcm16.count {
            let end = min(pcm16.count, offset + chunkSize)
            let chunk = pcm16.subdata(in: offset ..< end)
            let base64 = chunk.base64EncodedString()

            let payload: [String: Any] = [
                "type": "input_audio_buffer.append",
                "audio": base64
            ]
            try await sendJSON(socket: socket, object: payload)
            offset = end

            // Yield briefly to let the receive task process any incoming events.
            if offset < pcm16.count {
                await Task.yield()
            }
        }

        try await sendJSON(socket: socket, object: ["type": "input_audio_buffer.commit"])
    }

    private func receiveFinalText(
        socket: URLSessionWebSocketTask,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String {
        var aggregated = ""

        while true {
            let message = try await socket.receive()
            let textPayload: String
            switch message {
            case .string(let string):
                textPayload = string
            case .data(let data):
                textPayload = String(data: data, encoding: .utf8) ?? ""
            @unknown default:
                continue
            }

            guard let data = textPayload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let eventType = (object["type"] as? String) ?? ""
            if eventType == "error" {
                let message = extractString(from: object, keys: ["message", "error"]) ?? "Realtime error"
                throw OpenAITranscribeError.server(status: 400, message: message)
            }

            if eventType.contains("delta") {
                if let delta = extractString(from: object, keys: ["delta", "text"]), !delta.isEmpty {
                    aggregated.append(delta)
                    onDelta?(aggregated)
                }
                continue
            }

            if eventType.contains("done") || eventType.contains("completed") {
                let final = extractString(from: object, keys: ["text", "transcript"]) ?? aggregated
                let normalized = final.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    return normalized
                }
            }

            if let text = extractString(from: object, keys: ["text"]), !text.isEmpty {
                aggregated = text
                onDelta?(aggregated)
            }
        }
    }

    private func sendJSON(socket: URLSessionWebSocketTask, object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenAITranscribeError.invalidResponse
        }
        try await socket.send(.string(text))
    }

    /// 将音频文件解码并重采样为 24kHz mono PCM16（OpenAI Realtime API 要求的格式）。
    private func decodeToPCM16Mono(fileURL: URL) throws -> Data {
        let input = try AVAudioFile(forReading: fileURL)
        let sourceFormat = input.processingFormat
        let frameCount = AVAudioFrameCount(input.length)
        guard frameCount > 0 else { return Data() }

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            return Data()
        }
        try input.read(into: sourceBuffer)

        // OpenAI Realtime API 要求 pcm16 格式为 24kHz mono little-endian
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.realtimeSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            return Data()
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return Data()
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 256
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedFrames) else {
            return Data()
        }

        nonisolated(unsafe) var hasProvidedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .endOfStream
                return nil
            }
            hasProvidedInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if status == .error {
            throw OpenAITranscribeError.network(
                "音频重采样失败：\(conversionError?.localizedDescription ?? "未知错误")"
            )
        }

        let totalFrames = Int(targetBuffer.frameLength)
        guard totalFrames > 0, let int16Data = targetBuffer.int16ChannelData else {
            return Data()
        }

        return Data(bytes: int16Data[0], count: totalFrames * MemoryLayout<Int16>.size)
    }

    private func extractString(from object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let nested = object[key] as? [String: Any],
               let nestedText = extractString(from: nested, keys: keys) {
                return nestedText
            }
            if let array = object[key] as? [[String: Any]] {
                for item in array {
                    if let nestedText = extractString(from: item, keys: keys) {
                        return nestedText
                    }
                }
            }
        }

        for value in object.values {
            if let nested = value as? [String: Any],
               let nestedText = extractString(from: nested, keys: keys) {
                return nestedText
            }
            if let array = value as? [[String: Any]] {
                for item in array {
                    if let nestedText = extractString(from: item, keys: keys) {
                        return nestedText
                    }
                }
            }
        }
        return nil
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw OpenAITranscribeError.timeout
            }

            guard let result = try await group.next() else {
                throw OpenAITranscribeError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}
