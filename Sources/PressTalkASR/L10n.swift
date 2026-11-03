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
    private static let moduleResourceBundleName = "PressTalkASR_PressTalkASR"
    private static let moduleBundle: Bundle = resolveModuleBundle()

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
        let moduleBundle = self.moduleBundle
        for language in preferredLanguages {
            let normalized = normalize(language)
            if let path = moduleBundle.path(forResource: normalized, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return moduleBundle
    }

    private static func resolveModuleBundle() -> Bundle {
        let bundleFileName = "\(moduleResourceBundleName).bundle"

        var candidateURLs: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidateURLs.append(resourceURL.appendingPathComponent(bundleFileName, isDirectory: true))
        }
        if let executableURL = Bundle.main.executableURL {
            let executableDir = executableURL.deletingLastPathComponent()
            candidateURLs.append(executableDir.appendingPathComponent(bundleFileName, isDirectory: true))
            var current = executableDir
            for _ in 0..<6 {
                candidateURLs.append(current.appendingPathComponent(bundleFileName, isDirectory: true))
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path {
                    break
                }
                current = parent
            }
        }
        candidateURLs.append(Bundle.main.bundleURL.appendingPathComponent(bundleFileName, isDirectory: true))
        appendBuildDirectoryCandidates(
            from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
            bundleFileName: bundleFileName,
            to: &candidateURLs
        )
        appendBuildDirectoryCandidates(
            from: URL(fileURLWithPath: #filePath, isDirectory: false)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent(),
            bundleFileName: bundleFileName,
            to: &candidateURLs
        )

        for candidateURL in candidateURLs {
            if let bundle = Bundle(url: candidateURL) {
                return bundle
            }
        }

        return Bundle.main
    }

    private static func appendBuildDirectoryCandidates(
        from rootURL: URL,
        bundleFileName: String,
        to candidates: inout [URL]
    ) {
        let buildRoot = rootURL.appendingPathComponent(".build", isDirectory: true)
        candidates.append(buildRoot.appendingPathComponent("debug/\(bundleFileName)", isDirectory: true))
        candidates.append(buildRoot.appendingPathComponent("release/\(bundleFileName)", isDirectory: true))

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: buildRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else {
            return
        }

        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            candidates.append(entry.appendingPathComponent("debug/\(bundleFileName)", isDirectory: true))
            candidates.append(entry.appendingPathComponent("release/\(bundleFileName)", isDirectory: true))
        }
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
