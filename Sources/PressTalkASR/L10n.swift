import Foundation

enum L10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = tr(key)
        return String(format: format, locale: Locale.current, arguments: args)
    }

    static func tr(_ key: String, preferredLanguages: [String], _ args: CVarArg...) -> String {
        let bundle = bundle(for: preferredLanguages)
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String(format: format, locale: Locale.current, arguments: args)
    }

    private static func bundle(for preferredLanguages: [String]) -> Bundle {
        for language in preferredLanguages {
            let normalized = normalize(language)
            if let path = Bundle.module.path(forResource: normalized, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return Bundle.module
    }

    private static func normalize(_ language: String) -> String {
        let lower = language.lowercased()
        if lower.hasPrefix("zh") {
            return "zh-Hans"
        }
        if lower.hasPrefix("en") {
            return "en"
        }
        return language
    }
}
