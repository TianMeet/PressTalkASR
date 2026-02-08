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
}

struct OpenAITranscribeClient {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
    }

    func transcribe(fileURL: URL, model: OpenAIModel, prompt: String?, apiKey: String) async throws -> String {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if fileSize > 25 * 1024 * 1024 {
            throw OpenAITranscribeError.fileTooLarge
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try makeBody(
            fileURL: fileURL,
            boundary: boundary,
            model: model,
            prompt: prompt
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        var retryDelay: UInt64 = 400_000_000
        for attempt in 0..<3 {
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

    private func makeBody(fileURL: URL, boundary: String, model: OpenAIModel, prompt: String?) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mimeType = mimeType(for: fileURL.pathExtension.lowercased())

        var data = Data()
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        data.appendUTF8("\(model.rawValue)\r\n")

        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        data.appendUTF8("text\r\n")

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
            return "audio/m4a"
        case "wav":
            return "audio/wav"
        default:
            return "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ text: String) {
        append(Data(text.utf8))
    }
}
