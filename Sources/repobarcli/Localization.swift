import Foundation
import RepoBarCore

struct CLILocalizer: @unchecked Sendable {
    let locale: Locale
    private let bundle: Bundle

    init(locale: Locale? = nil, bundle: Bundle = .module) {
        self.locale = locale ?? RepoBarLocalization.environmentLocale()
        self.bundle = bundle
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        let language = self.locale.language.languageCode?.identifier ?? "en"
        let localization = self.bundle.localizations.contains(language) ? language : "en"
        let localizedBundle = self.bundle.path(forResource: localization, ofType: "lproj").flatMap(Bundle.init(path:)) ?? self.bundle
        let value = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
        guard arguments.isEmpty == false else { return value }

        return String(format: value, locale: self.locale, arguments: arguments)
    }
}

/// Localizes prose while leaving command tokens and machine-readable values untouched.
/// Exact catalog matches are preferred; the prefix table covers values that contain
/// GitHub names, paths, counts, or other runtime content.
func cliText(_ english: String, locale: Locale? = nil) -> String {
    let localizer = CLILocalizer(locale: locale)
    let exact = localizer.string(english)
    if exact != english {
        return exact
    }
    guard localizer.locale.language.languageCode?.identifier == "tr" else {
        return english
    }

    let prefixes: [(String, String)] = [
        ("Usage:", "Kullanım:"),
        ("Options:", "Seçenekler:"),
        ("Prerequisites:", "Ön koşullar:"),
        ("Only one repository can be specified", "Yalnızca bir depo belirtilebilir"),
        ("Only one repository or path can be specified", "Yalnızca bir depo veya yol belirtilebilir"),
        ("Missing repository name", "Depo adı eksik"),
        ("Repository must be in owner/name format", "Depo owner/name biçiminde olmalıdır"),
        ("Invalid ", "Geçersiz "),
        ("Missing ", "Eksik "),
        ("Unknown ", "Bilinmeyen "),
        ("No ", "Yok: "),
        ("Failed ", "Başarısız: "),
        ("User:", "Kullanıcı:"),
        ("Days:", "Gün:"),
        ("Total contributions:", "Toplam katkı:"),
        ("Repository:", "Depo:"),
        ("Repositories:", "Depolar:"),
        ("Issues:", "Sorunlar:"),
        ("Pull Requests:", "Çekme İstekleri:"),
        ("Releases:", "Sürümler:"),
        ("Branches:", "Dallar:"),
        ("Contributors:", "Katkıda Bulunanlar:"),
        ("Commits:", "İşlemeler:"),
        ("Activity:", "Etkinlik:"),
        ("Status:", "Durum:"),
        ("Host:", "Sunucu:"),
        ("Root:", "Kök:"),
        ("Depth:", "Derinlik:"),
        ("Error:", "Hata:"),
        ("Updated ", "Güncellendi "),
        ("Opened ", "Açıldı "),
        ("Logged in", "Giriş yapıldı"),
        ("Logged out", "Çıkış yapıldı"),
        ("Rate limited until ", "Hız sınırı bitişi: ")
    ]
    for (source, translated) in prefixes where english.hasPrefix(source) {
        return translated + english.dropFirst(source.count)
    }
    return english
}

/// Human-readable CLI output passes through the localization boundary. JSON and
/// stable machine output contain no catalog keys and therefore pass through byte-for-byte.
func cliPrint(_ value: String, terminator: String = "\n") {
    Swift.print(cliText(value), terminator: terminator)
}
