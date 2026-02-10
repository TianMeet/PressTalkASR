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
        if message.lowercased().contains("network") || message.contains("网络") {
            return L10n.tr("popover.error.network", preferredLanguages: preferredLanguages)
        }
        if message.contains("未识别") || message.contains("太短") || message.lowercased().contains("no speech") {
            return L10n.tr("popover.error.no_speech", preferredLanguages: preferredLanguages)
        }
        return L10n.tr("popover.error.try_again", preferredLanguages: preferredLanguages)
    }

    static func shortWarning(_ message: String, preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        if message.contains("自动粘贴") || message.lowercased().contains("paste") {
            return L10n.tr("popover.warning.paste_failed", preferredLanguages: preferredLanguages)
        }
        return L10n.tr("popover.warning.generic", preferredLanguages: preferredLanguages)
    }

    static func warningSubtitle(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        return L10n.tr("popover.warning.subtitle", preferredLanguages: preferredLanguages)
    }

    static func errorSubtitle(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        return L10n.tr("popover.error.subtitle", preferredLanguages: preferredLanguages)
    }
}
