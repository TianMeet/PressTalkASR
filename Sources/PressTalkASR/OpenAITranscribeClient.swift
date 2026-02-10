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
    private struct MultipartStaticSections {
        let preamble: Data
        let epilogue: Data
        let contentLength: Int64
    }

    private struct StreamingMultipartRequest {
        let request: URLRequest
        let writerTask: Task<Void, Error>
    }

    private enum Constants {
        /// OpenAI API 文件上传大小上限
        static let maxFileSizeBytes = 25 * 1024 * 1024       // 25 MB
        static let requestTimeoutInterval: TimeInterval = 45
        static let resourceTimeoutInterval: TimeInterval = 60
        static let maxRetryAttempts = 3
        static let initialRetryDelayNs: UInt64 = 400_000_000 // 400 ms
        static let prewarmMinInterval: TimeInterval = 7
        static let keepWarmWindowSeconds: TimeInterval = 40
        static let keepWarmTickIntervalSeconds: TimeInterval = 8
        static let boundStreamBufferBytes = 256 * 1024
        static let fileReadChunkBytes = 256 * 1024
        static let streamBackpressureSleepSeconds: TimeInterval = 0.002
        static let streamStallTimeoutSeconds: TimeInterval = 8
    }

    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let session: URLSession
    private let prewarmGate = PrewarmGate(minInterval: Constants.prewarmMinInterval)
    private let keepWarmController = KeepWarmController()
    private let streamEventParser = TranscriptionStreamEventParser()
    private let retryPolicy = TranscribeRetryPolicy(
        maxAttempts: Constants.maxRetryAttempts,
        initialDelayNs: Constants.initialRetryDelayNs
    )

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.requestTimeoutInterval
        configuration.timeoutIntervalForResource = Constants.resourceTimeoutInterval
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldUsePipelining = true
        session = URLSession(configuration: configuration)
    }

    /// 预热到 OpenAI 的 TLS 连接，录音期间提前握手以减少上传延迟。
    func prewarmConnection() {
        schedulePrewarmPingIfNeeded()
    }

    /// 连接保温：立即预热一次，并在短窗口内按固定间隔补充预热，降低冷连接概率。
    func keepWarmForInteractionWindow() {
        schedulePrewarmPingIfNeeded()
        keepWarmController.extendWindow(
            by: Constants.keepWarmWindowSeconds,
            tickInterval: Constants.keepWarmTickIntervalSeconds
        ) { [session, endpoint, prewarmGate] in
            OpenAITranscribeClient.schedulePrewarmPing(
                session: session,
                endpoint: endpoint,
                prewarmGate: prewarmGate
            )
        }
    }

    /// 默认先走 streaming，遇到可恢复错误自动回退到非流式请求。
    func transcribe(
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
            return try await transcribeNonStreaming(
                fileURL: fileURL,
                model: model,
                prompt: prompt,
                languageCode: languageCode,
                apiKey: apiKey
            )
        }
    }

    private func transcribeNonStreaming(
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

        var retryDelay = retryPolicy.initialDelayNs
        for attempt in 0..<retryPolicy.maxAttempts {
            do {
                let multipart = try makeStreamingMultipartRequest(
                    fileURL: fileURL,
                    model: model,
                    prompt: prompt,
                    languageCode: languageCode,
                    streaming: false,
                    apiKey: apiKey
                )
                return try await performDataRequest(
                    request: multipart.request,
                    writerTask: multipart.writerTask
                )
            } catch let error as OpenAITranscribeError {
                if !retryPolicy.shouldRetry(error) || attempt == retryPolicy.maxAttempts - 1 {
                    throw error
                }
                try await Task.sleep(nanoseconds: retryDelay)
                retryDelay = retryPolicy.nextDelay(after: retryDelay)
            } catch {
                if attempt == retryPolicy.maxAttempts - 1 { throw error }
                try await Task.sleep(nanoseconds: retryDelay)
                retryDelay = retryPolicy.nextDelay(after: retryDelay)
            }
        }

        throw OpenAITranscribeError.invalidResponse
    }

    private func transcribeStreaming(
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
        let multipart = try makeStreamingMultipartRequest(
            fileURL: fileURL,
            model: model,
            prompt: prompt,
            languageCode: languageCode,
            streaming: true,
            apiKey: apiKey
        )

        do {
            let (bytes, response) = try await session.bytes(for: multipart.request)
            try await awaitWriterCompletion(multipart.writerTask)
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

                switch streamEventParser.parse(payload: payload) {
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
            multipart.writerTask.cancel()
            switch error.code {
            case .timedOut:
                throw OpenAITranscribeError.timeout
            default:
                throw OpenAITranscribeError.network(error.localizedDescription)
            }
        } catch {
            multipart.writerTask.cancel()
            throw error
        }
    }

    private func performDataRequest(request: URLRequest, writerTask: Task<Void, Error>) async throws -> String {
        do {
            let (data, response) = try await session.data(for: request)
            try await awaitWriterCompletion(writerTask)
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
            writerTask.cancel()
            switch error.code {
            case .timedOut:
                throw OpenAITranscribeError.timeout
            default:
                throw OpenAITranscribeError.network(error.localizedDescription)
            }
        } catch {
            writerTask.cancel()
            throw error
        }
    }

    private func makeBaseRequest(apiKey: String, boundary: String, contentLength: Int64) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(String(contentLength), forHTTPHeaderField: "Content-Length")
        request.networkServiceType = .responsiveData
        return request
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

    private func makeStreamingMultipartRequest(
        fileURL: URL,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        streaming: Bool,
        apiKey: String
    ) throws -> StreamingMultipartRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        let sections = try makeMultipartStaticSections(
            fileURL: fileURL,
            boundary: boundary,
            model: model,
            prompt: prompt,
            languageCode: languageCode,
            streaming: streaming
        )
        var request = makeBaseRequest(
            apiKey: apiKey,
            boundary: boundary,
            contentLength: sections.contentLength
        )

        let (input, output) = createBoundPairStreams(bufferSize: Constants.boundStreamBufferBytes)
        request.httpBodyStream = input
        if streaming {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let writerTask = Task.detached(priority: .userInitiated) {
            try self.streamMultipartBody(
                preamble: sections.preamble,
                fileURL: fileURL,
                epilogue: sections.epilogue,
                outputStream: output
            )
        }

        return StreamingMultipartRequest(request: request, writerTask: writerTask)
    }

    private func makeMultipartStaticSections(
        fileURL: URL,
        boundary: String,
        model: OpenAIModel,
        prompt: String?,
        languageCode: String?,
        streaming: Bool
    ) throws -> MultipartStaticSections {
        let filename = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL.pathExtension.lowercased())
        var preamble = Data()
        preamble.append(formField(name: "model", value: model.rawValue, boundary: boundary))
        preamble.append(formField(name: "response_format", value: streaming ? "json" : "text", boundary: boundary))
        if streaming {
            preamble.append(formField(name: "stream", value: "true", boundary: boundary))
        }
        if let languageCode, !languageCode.isEmpty {
            preamble.append(formField(name: "language", value: languageCode, boundary: boundary))
        }
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preamble.append(formField(name: "prompt", value: prompt, boundary: boundary))
        }
        preamble.append(Data("--\(boundary)\r\n".utf8))
        preamble.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        preamble.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))

        let epilogue = Data("\r\n--\(boundary)--\r\n".utf8)
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let contentLength = Int64(preamble.count) + Int64(fileSize) + Int64(epilogue.count)
        return MultipartStaticSections(
            preamble: preamble,
            epilogue: epilogue,
            contentLength: contentLength
        )
    }

    private func formField(name: String, value: String, boundary: String) -> Data {
        var data = Data()
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        data.append(Data("\(value)\r\n".utf8))
        return data
    }

    private func createBoundPairStreams(bufferSize: Int) -> (InputStream, OutputStream) {
        var readRef: Unmanaged<CFReadStream>?
        var writeRef: Unmanaged<CFWriteStream>?
        CFStreamCreateBoundPair(nil, &readRef, &writeRef, bufferSize)
        let input = readRef!.takeRetainedValue() as InputStream
        let output = writeRef!.takeRetainedValue() as OutputStream
        return (input, output)
    }

    private func streamMultipartBody(
        preamble: Data,
        fileURL: URL,
        epilogue: Data,
        outputStream: OutputStream
    ) throws {
        outputStream.open()
        defer { outputStream.close() }

        try writeToStream(outputStream, data: preamble)

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        while true {
            if Task.isCancelled {
                throw CancellationError()
            }

            let chunk = try fileHandle.read(upToCount: Constants.fileReadChunkBytes) ?? Data()
            if chunk.isEmpty {
                break
            }
            try writeToStream(outputStream, data: chunk)
        }

        try writeToStream(outputStream, data: epilogue)
    }

    private func writeToStream(_ stream: OutputStream, data: Data) throws {
        if data.isEmpty { return }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            var written = 0
            var stalledAt: Date?
            while written < data.count {
                if Task.isCancelled {
                    throw CancellationError()
                }

                if !stream.hasSpaceAvailable {
                    if let streamError = stream.streamError {
                        throw OpenAITranscribeError.network("写入上传流失败：\(streamError.localizedDescription)")
                    }
                    if stream.streamStatus == .closed || stream.streamStatus == .error {
                        throw OpenAITranscribeError.network("上传流已关闭。")
                    }
                    if stalledAt == nil { stalledAt = Date() }
                    if let stalledAt, Date().timeIntervalSince(stalledAt) > Constants.streamStallTimeoutSeconds {
                        throw OpenAITranscribeError.network("上传写入等待超时。")
                    }
                    Thread.sleep(forTimeInterval: Constants.streamBackpressureSleepSeconds)
                    continue
                }

                let count = stream.write(baseAddress.advanced(by: written), maxLength: data.count - written)
                if count > 0 {
                    written += count
                    stalledAt = nil
                    continue
                }
                if count < 0 {
                    let message = stream.streamError?.localizedDescription ?? "Unknown stream write error"
                    throw OpenAITranscribeError.network("写入上传流失败：\(message)")
                }

                if stream.streamStatus == .atEnd || stream.streamStatus == .closed || stream.streamStatus == .error {
                    throw OpenAITranscribeError.network("上传流提前结束。")
                }

                if stalledAt == nil { stalledAt = Date() }
                if let stalledAt, Date().timeIntervalSince(stalledAt) > Constants.streamStallTimeoutSeconds {
                    throw OpenAITranscribeError.network("上传写入等待超时。")
                }
                Thread.sleep(forTimeInterval: Constants.streamBackpressureSleepSeconds)
            }
        }
    }

    private func awaitWriterCompletion(_ writerTask: Task<Void, Error>) async throws {
        do {
            try await writerTask.value
        } catch is CancellationError {
            throw OpenAITranscribeError.network("上传被取消。")
        } catch let error as OpenAITranscribeError {
            throw error
        } catch {
            throw OpenAITranscribeError.network("上传流写入失败：\(error.localizedDescription)")
        }
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

    private func consumeBytes(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func schedulePrewarmPingIfNeeded() {
        OpenAITranscribeClient.schedulePrewarmPing(
            session: session,
            endpoint: endpoint,
            prewarmGate: prewarmGate
        )
    }

    private static func schedulePrewarmPing(
        session: URLSession,
        endpoint: URL,
        prewarmGate: PrewarmGate
    ) {
        guard prewarmGate.beginIfNeeded() else { return }
        Task.detached(priority: .utility) {
            defer { prewarmGate.finish() }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 5
            _ = try? await session.data(for: request)
        }
    }
}
