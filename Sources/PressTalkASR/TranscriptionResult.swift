import Foundation

struct TranscriptionUsage: Sendable, Equatable, Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let audioInputTokens: Int?
    let textInputTokens: Int?
    let durationSeconds: Double?

    init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        audioInputTokens: Int? = nil,
        textInputTokens: Int? = nil,
        durationSeconds: Double? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.audioInputTokens = audioInputTokens
        self.textInputTokens = textInputTokens
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokenDetails = "input_token_details"
        case seconds
    }

    private enum InputTokenDetailsKeys: String, CodingKey {
        case audioTokens = "audio_tokens"
        case textTokens = "text_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
        totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .seconds)

        if container.contains(.inputTokenDetails) {
            let details = try container.nestedContainer(
                keyedBy: InputTokenDetailsKeys.self,
                forKey: .inputTokenDetails
            )
            audioInputTokens = try details.decodeIfPresent(Int.self, forKey: .audioTokens)
            textInputTokens = try details.decodeIfPresent(Int.self, forKey: .textTokens)
        } else {
            audioInputTokens = nil
            textInputTokens = nil
        }
    }

    var hasTokenCounts: Bool {
        inputTokens != nil || outputTokens != nil
    }
}

struct TranscriptionResult: Sendable, Equatable {
    let text: String
    let usage: TranscriptionUsage?

    init(text: String, usage: TranscriptionUsage? = nil) {
        self.text = text
        self.usage = usage
    }
}
