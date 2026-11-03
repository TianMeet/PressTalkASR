import Foundation

enum TranscriptionStreamEvent: Equatable {
    case delta(String)
    case done(String, TranscriptionUsage?)
    case error(String)
    case ignore
}

struct TranscriptionStreamEventParser {
    func parse(payload: String) -> TranscriptionStreamEvent {
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
            return .done(text, extractUsage(from: object))
        }

        if let delta = extractString(from: object, keys: ["delta"]), !delta.isEmpty {
            return .delta(delta)
        }

        if let text = extractString(from: object, keys: ["text"]), !text.isEmpty {
            return .done(text, extractUsage(from: object))
        }

        return .ignore
    }

    private func extractUsage(from object: [String: Any]) -> TranscriptionUsage? {
        guard let usage = object["usage"] as? [String: Any],
              JSONSerialization.isValidJSONObject(usage),
              let data = try? JSONSerialization.data(withJSONObject: usage) else {
            return nil
        }
        return try? JSONDecoder().decode(TranscriptionUsage.self, from: data)
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
}
