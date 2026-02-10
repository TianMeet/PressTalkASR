import Foundation

enum TranscriptionExecutionError: LocalizedError, Equatable {
    case audioFileNotReady

    var errorDescription: String? {
        switch self {
        case .audioFileNotReady:
            return "音频文件尚未准备好，请稍后再试。"
        }
    }
}

struct TranscriptionRequestOptions {
    let enableVADTrim: Bool
    let model: OpenAIModel
    let prompt: String?
    let languageCode: String?
}

struct TranscriptionCoordinator {
    private enum Constants {
        static let trimMinDurationSecondsForUpload: TimeInterval = 1.2
        static let trimMinDurationSecondsForCompressed: TimeInterval = 8.0
        static let trimBudgetNs: UInt64 = 220_000_000
        static let fileStabilityMinBytes = 1024
        static let compressedAudioExtensions: Set<String> = ["m4a", "mp3", "mpga", "mp4", "mpeg", "webm", "ogg", "flac"]
    }

    private let transcribeClient: any TranscriptionServicing
    private let vadTrimmer: any SilenceTrimming

    init(
        transcribeClient: any TranscriptionServicing,
        vadTrimmer: any SilenceTrimming
    ) {
        self.transcribeClient = transcribeClient
        self.vadTrimmer = vadTrimmer
    }

    @MainActor
    func transcribe(
        sourceURL: URL,
        recordedSeconds: TimeInterval,
        options: TranscriptionRequestOptions,
        apiKey: String,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String {
        var urlsToDelete = [sourceURL]
        var requestURL = sourceURL

        defer {
            urlsToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        let fileSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard fileSize > Constants.fileStabilityMinBytes else {
            throw TranscriptionExecutionError.audioFileNotReady
        }

        let sourceExtension = sourceURL.pathExtension.lowercased()
        let isCompressedSource = Constants.compressedAudioExtensions.contains(sourceExtension)
        let shouldRunTrimForSpeed = options.enableVADTrim
            && recordedSeconds >= Constants.trimMinDurationSecondsForUpload
            && (!isCompressedSource || recordedSeconds >= Constants.trimMinDurationSecondsForCompressed)

        if shouldRunTrimForSpeed {
            let trimmedURL = await trimSilenceBestEffort(inputURL: sourceURL)
            if trimmedURL != sourceURL {
                requestURL = trimmedURL
                urlsToDelete.append(trimmedURL)
            }
        }

        return try await transcribeClient.transcribe(
            fileURL: requestURL,
            model: options.model,
            prompt: options.prompt,
            languageCode: options.languageCode,
            apiKey: apiKey,
            onDelta: onDelta
        )
    }

    @MainActor
    private func trimSilenceBestEffort(inputURL: URL) async -> URL {
        let trimmer = vadTrimmer
        do {
            return try await withThrowingTaskGroup(of: URL.self) { group in
                group.addTask {
                    try await trimmer.trimSilence(inputURL: inputURL)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: Constants.trimBudgetNs)
                    return inputURL
                }
                let chosen = try await group.next() ?? inputURL
                group.cancelAll()
                return chosen
            }
        } catch is CancellationError {
            return inputURL
        } catch {
            return inputURL
        }
    }
}
