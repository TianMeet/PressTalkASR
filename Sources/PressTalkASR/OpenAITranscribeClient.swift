import Foundation

enum OpenAIModel: String, CaseIterable, Identifiable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case gpt4oTranscribe = "gpt-4o-transcribe"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gpt4oMiniTranscribe:
            return "gpt-4o-mini-transcribe (Cost)"
        case .gpt4oTranscribe:
            return "gpt-4o-transcribe (Accuracy)"
        }
    }

    var costPerMinuteUSD: Double {
        switch self {
        case .gpt4oMiniTranscribe:
            return 0.003
        case .gpt4oTranscribe:
            return 0.006
        }
    }
}

enum OpenAITranscribeError: LocalizedError {
    case fileTooLarge
    case unauthorized
    case timeout
    case network(String)
    case server(status: Int, message: String)
    case invalidResponse
    case emptyText

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "录音太长，请缩短（超过 25MB 上传限制）。"
        case .unauthorized:
            return "API Key 无效或未授权（401）。"
        case .timeout:
            return "请求超时，请检查网络后重试。"
        case .network(let message):
            return "网络错误：\(message)"
        case .server(let status, let message):
            return "服务错误（\(status)）：\(message)"
        case .invalidResponse:
            return "服务返回格式无法解析。"
        case .emptyText:
            return "未识别到可用文本。"
        }
    }

    /// Whether this error could potentially succeed if retried with a different
    /// code path (e.g. non-streaming fallback). Terminal errors like auth
    /// failures or validation issues will never recover on retry.
    var isRecoverable: Bool {
        switch self {
        case .unauthorized, .fileTooLarge, .emptyText:
            return false
        case .timeout, .network, .invalidResponse:
            return true
        case .server(let status, _):
            // 4xx client errors (except 408/429) are not recoverable
            return status == 408 || status == 429 || status >= 500
        }
    }
}

struct OpenAITranscribeClient {
    private enum Constants {
        /// OpenAI API 文件上传大小上限
        static let maxFileSizeBytes = 25 * 1024 * 1024       // 25 MB
        static let requestTimeoutInterval: TimeInterval = 45
        static let resourceTimeoutInterval: TimeInterval = 60
        static let maxRetryAttempts = 3
        static let initialRetryDelayNs: UInt64 = 400_000_000 // 400 ms
    }

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.requestTimeoutInterval
        configuration.timeoutIntervalForResource = Constants.resourceTimeoutInterval
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    /// 预热到 OpenAI 的 TLS 连接，录音期间提前握手以减少上传延迟。
    func prewarmConnection() {
        let session = self.session
        let endpoint = self.endpoint
        Task.detached(priority: .utility) {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            _ = try? await session.data(for: request)
        }
    }

    func transcribeWithStreamingFallback(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        do {
            return try await transcribeStreaming(
                fileURL: fileURL,
                model: model,
                prompt: prompt,
                languageCode: languageCode,
                apiKey: apiKey,
                onDelta: onDelta
            )
        } catch let error as OpenAITranscribeError where error.isRecoverable {
            // Only fall back to non-streaming for recoverable errors
            // (e.g. streaming not supported). Terminal errors (401, file too
            // large, empty) are re-thrown immediately to avoid a wasted request.
            return try await transcribe(
                fileURL: fileURL,
                model: model,
                prompt: prompt,
                languageCode: languageCode,
                apiKey: apiKey
            )
        }
    }

    func transcribe(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String
    ) async throws -> String {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if fileSize > Constants.maxFileSizeBytes {
            throw OpenAITranscribeError.fileTooLarge
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try makeBody(
            fileURL: fileURL,
            boundary: boundary,
            model: model,
            prompt: prompt,
            languageCode: languageCode,
            streaming: false
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        var retryDelay = Constants.initialRetryDelayNs
        for attempt in 0..<Constants.maxRetryAttempts {
            do {
                return try await performRequest(request)
            } catch let error as OpenAITranscribeError {
                let shouldRetry = shouldRetry(error: error)
                if !shouldRetry || attempt == 2 {
                    throw error
                }
                try await Task.sleep(nanoseconds: retryDelay)
                retryDelay *= 2
            } catch {
                if attempt == 2 { throw error }
                try await Task.sleep(nanoseconds: retryDelay)
                retryDelay *= 2
            }
        }

        throw OpenAITranscribeError.invalidResponse
    }

    func transcribeStreaming(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        apiKey: String,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if fileSize > Constants.maxFileSizeBytes {
            throw OpenAITranscribeError.fileTooLarge
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try makeBody(
            fileURL: fileURL,
            boundary: boundary,
            model: model,
            prompt: prompt,
            languageCode: languageCode,
            streaming: true
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenAITranscribeError.invalidResponse
            }

            guard (200...299).contains(http.statusCode) else {
                let payload = try await consumeBytes(bytes)
                if http.statusCode == 401 {
                    throw OpenAITranscribeError.unauthorized
                }
                let message = parseErrorMessage(from: payload) ?? "Unknown server error"
                throw OpenAITranscribeError.server(status: http.statusCode, message: message)
            }

            var aggregated = ""
            for try await line in bytes.lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continue
                }

                let payload: String
                if trimmed.hasPrefix("data:") {
                    payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    payload = trimmed
                }

                if payload == "[DONE]" {
                    break
                }

                switch parseStreamEvent(payload) {
                case .delta(let delta):
                    guard !delta.isEmpty else { continue }
                    aggregated.append(delta)
                    onDelta?(aggregated)
                case .done(let text):
                    let final = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !final.isEmpty {
                        return final
                    }
                case .error(let message):
                    throw OpenAITranscribeError.server(status: http.statusCode, message: message)
                case .ignore:
                    continue
                }
            }

            let fallbackFinal = aggregated.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackFinal.isEmpty {
                return fallbackFinal
            }
            throw OpenAITranscribeError.emptyText
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw OpenAITranscribeError.timeout
            default:
                throw OpenAITranscribeError.network(error.localizedDescription)
            }
        }
    }

    private func performRequest(_ request: URLRequest) async throws -> String {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenAITranscribeError.invalidResponse
            }

            switch http.statusCode {
            case 200...299:
                guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    throw OpenAITranscribeError.emptyText
                }
                return text

            case 401:
                throw OpenAITranscribeError.unauthorized

            case 408, 429, 500...599:
                let message = parseErrorMessage(from: data) ?? "Temporary server issue"
                throw OpenAITranscribeError.server(status: http.statusCode, message: message)

            default:
                let message = parseErrorMessage(from: data) ?? "Unknown server error"
                throw OpenAITranscribeError.server(status: http.statusCode, message: message)
            }
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw OpenAITranscribeError.timeout
            default:
                throw OpenAITranscribeError.network(error.localizedDescription)
            }
        }
    }

    private func shouldRetry(error: OpenAITranscribeError) -> Bool {
        switch error {
        case .timeout, .network:
            return true
        case .server(let status, _):
            return status == 408 || status == 429 || status >= 500
        default:
            return false
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let message = object["message"] as? String {
            return message
        }

        return nil
    }

    private func makeBody(
        fileURL: URL,
        boundary: String,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        streaming: Bool
    ) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL.pathExtension.lowercased())

        var data = Data()
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        data.appendUTF8("\(model.rawValue)\r\n")

        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        data.appendUTF8("\(streaming ? "json" : "text")\r\n")

        if streaming {
            data.appendUTF8("--\(boundary)\r\n")
            data.appendUTF8("Content-Disposition: form-data; name=\"stream\"\r\n\r\n")
            data.appendUTF8("true\r\n")
        }

        if let languageCode, !languageCode.isEmpty {
            data.appendUTF8("--\(boundary)\r\n")
            data.appendUTF8("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
            data.appendUTF8("\(languageCode)\r\n")
        }

        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data.appendUTF8("--\(boundary)\r\n")
            data.appendUTF8("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
            data.appendUTF8("\(prompt)\r\n")
        }

        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        data.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        data.appendUTF8("\r\n")
        data.appendUTF8("--\(boundary)--\r\n")

        return data
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "m4a":
            return "audio/mp4"
        case "mp3", "mpga":
            return "audio/mpeg"
        case "mp4", "mpeg":
            return "audio/mp4"
        case "webm":
            return "audio/webm"
        case "wav":
            return "audio/wav"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        default:
            return "application/octet-stream"
        }
    }

    private enum ParsedStreamEvent {
        case delta(String)
        case done(String)
        case error(String)
        case ignore
    }

    private func parseStreamEvent(_ payload: String) -> ParsedStreamEvent {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .ignore
        }

        let eventType = (object["type"] as? String) ?? (object["event"] as? String) ?? ""
        if eventType == "error" {
            let message = extractString(from: object, keys: ["message", "error"]) ?? "Unknown streaming error"
            return .error(message)
        }
        if let errorObject = object["error"] as? [String: Any],
           let message = errorObject["message"] as? String,
           !message.isEmpty {
            return .error(message)
        }

        if eventType.contains("delta") {
            let delta = extractString(from: object, keys: ["delta", "text"]) ?? ""
            return .delta(delta)
        }

        if eventType.contains("done") {
            let text = extractString(from: object, keys: ["text", "transcript"]) ?? ""
            return .done(text)
        }

        if let delta = extractString(from: object, keys: ["delta"]), !delta.isEmpty {
            return .delta(delta)
        }

        if let text = extractString(from: object, keys: ["text"]), !text.isEmpty {
            return .done(text)
        }

        return .ignore
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

    private func consumeBytes(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
}

private extension Data {
    mutating func appendUTF8(_ text: String) {
        append(Data(text.utf8))
    }
}
