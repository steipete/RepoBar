import Foundation

/// A small, injectable localization boundary shared by the app and command line tool.
/// Passing a locale makes tests and non-UI clients deterministic; when omitted the
/// user's environment is used and unsupported languages fall back to English.
public struct RepoBarLocalizer: @unchecked Sendable {
    public let locale: Locale
    private let bundle: Bundle

    public init(locale: Locale = .autoupdatingCurrent, bundle: Bundle? = nil) {
        self.locale = locale
        self.bundle = bundle ?? .module
    }

    public func string(_ key: String, _ arguments: CVarArg...) -> String {
        let language = self.locale.language.languageCode?.identifier ?? "en"
        let localization = self.bundle.localizations.contains(language) ? language : "en"
        let localizedBundle = self.bundle.path(forResource: localization, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? self.bundle
        let format = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: self.locale, arguments: arguments)
    }
}

public enum RepoBarLocalization {
    public static func environmentLocale(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Locale {
        if let override = environment["REPOBAR_LANGUAGE"], !override.isEmpty {
            return Locale(identifier: override)
        }
        if let lang = environment["LANG"], !lang.isEmpty, lang != "C", lang != "POSIX" {
            return Locale(identifier: lang.replacingOccurrences(of: ".UTF-8", with: ""))
        }
        return .autoupdatingCurrent
    }

    public static func localizer(locale: Locale? = nil) -> RepoBarLocalizer {
        RepoBarLocalizer(locale: locale ?? self.environmentLocale())
    }
}
