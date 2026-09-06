import Foundation

struct AppLocalizer: @unchecked Sendable {
    let locale: Locale
    private let bundle: Bundle

    init(locale: Locale = .autoupdatingCurrent, bundle: Bundle = .module) {
        self.locale = locale
        self.bundle = bundle
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        let language = self.locale.language.languageCode?.identifier ?? "en"
        let localization = self.bundle.localizations.contains(language) ? language : "en"
        let localizedBundle = self.bundle.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:)) ?? self.bundle
        return String(format: localizedBundle.localizedString(forKey: key, value: nil, table: nil), locale: self.locale, arguments: arguments)
    }
}
