import Foundation

enum TranscriptionExecutionError: LocalizedError, Equatable {
    case audioFileNotReady

    var errorDescription: String? {
        switch self {
        case .audioFileNotReady:
            return L10n.tr("error.transcription.audio_file_not_ready")
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
    private enum TrimAttemptResult: Sendable {
        case completed(URL)
        case timeout
        case failed
    }

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
    ) async throws -> TranscriptionResult {
        var urlsToDelete = [sourceURL]
        var requestURL = sourceURL

        defer {
            urlsToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
        }

        try Task.checkCancellation()

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

        try Task.checkCancellation()

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
        return await withTaskGroup(of: TrimAttemptResult.self) { group in
            group.addTask {
                do {
                    return .completed(try await trimmer.trimSilence(inputURL: inputURL))
                } catch {
                    return .failed
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: Constants.trimBudgetNs)
                    return .timeout
                } catch {
                    return .failed
                }
            }

            let first = await group.next() ?? .failed
            group.cancelAll()

            if case .completed(let url) = first {
                return url
            }

            // Drain the canceled trim task so a result that raced with the
            // timeout cannot leave an unowned temporary WAV behind.
            for await result in group {
                if case .completed(let url) = result, url != inputURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            return inputURL
        }
    }
}
