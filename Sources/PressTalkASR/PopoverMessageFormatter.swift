import Foundation

enum PopoverMessageFormatter {
    enum DisplayLanguage {
        case chinese
        case english
    }

    static func displayLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> DisplayLanguage {
        guard let first = preferredLanguages.first?.lowercased() else {
            return .english
        }
        return first.hasPrefix("zh") ? .chinese : .english
    }

    static func shortError(_ message: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let language = displayLanguage(preferredLanguages: preferredLanguages)
        if message.lowercased().contains("network") || message.contains("网络") {
            return language == .chinese ? "网络异常" : "Network"
        }
        if message.contains("未识别") || message.contains("太短") || message.lowercased().contains("no speech") {
            return language == .chinese ? "未识别语音" : "No speech"
        }
        return language == .chinese ? "请重试" : "Try again"
    }

    static func shortWarning(_ message: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let language = displayLanguage(preferredLanguages: preferredLanguages)
        if message.contains("自动粘贴") || message.lowercased().contains("paste") {
            return language == .chinese ? "粘贴失败" : "Paste failed"
        }
        return language == .chinese ? "警告" : "Warning"
    }

    static func warningSubtitle(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let language = displayLanguage(preferredLanguages: preferredLanguages)
        return language == .chinese ? "已复制，但自动粘贴失败" : "Copied, but auto paste failed"
    }

    static func errorSubtitle(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        let language = displayLanguage(preferredLanguages: preferredLanguages)
        return language == .chinese ? "未识别语音或网络异常" : "No speech or network issue"
    }
}
