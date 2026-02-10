import Foundation
import Combine

final class LocalizationStore: ObservableObject, @unchecked Sendable {
    static let shared = LocalizationStore()
    static let didChangeNotification = Notification.Name("LocalizationStore.didChange")

    @Published private(set) var refreshToken: Int = 0

    private let lock = NSLock()
    private var forcedLanguageIdentifier: String?

    private init() {}

    var preferredLanguages: [String] {
        lock.lock()
        let forced = forcedLanguageIdentifier
        lock.unlock()
        return forced.map { [$0] } ?? Locale.preferredLanguages
    }

    func setForcedLanguageIdentifier(_ identifier: String?) {
        let normalized = identifier.map { L10n.normalize($0) }

        lock.lock()
        let changed = forcedLanguageIdentifier != normalized
        forcedLanguageIdentifier = normalized
        lock.unlock()

        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshToken += 1
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}

enum L10n {
    static func tr(_ key: String) -> String {
        let bundle = bundle(for: LocalizationStore.shared.preferredLanguages)
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let bundle = bundle(for: LocalizationStore.shared.preferredLanguages)
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
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

    static func normalize(_ language: String) -> String {
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
