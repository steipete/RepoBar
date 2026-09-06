import Foundation
import RepoBarCore
import Testing

@Suite("Localization")
struct LocalizationTests {
    @Test func `turkish and english are deterministic`() {
        let english = RepoBarLocalizer(locale: Locale(identifier: "en_US"))
        let turkish = RepoBarLocalizer(locale: Locale(identifier: "tr_TR"))

        #expect(english.string("error.noInternet") == "No internet connection.")
        #expect(turkish.string("error.noInternet") == "İnternet bağlantısı yok.")
    }

    @Test func `unsupported locale falls back to english`() {
        let localizer = RepoBarLocalizer(locale: Locale(identifier: "ja_JP"))
        #expect(localizer.string("error.timeout") == "Request timed out.")
    }

    @Test func `relative formatter uses requested locale`() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(RelativeFormatter.string(from: now - 30, relativeTo: now, locale: Locale(identifier: "en_US")) == "30 sec. ago")
        #expect(RelativeFormatter.string(from: now - 30, relativeTo: now, locale: Locale(identifier: "tr_TR")) == "30 sn. önce")
    }

    @Test func `machine relative formatter remains english`() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(RelativeFormatter.machineString(from: now - 30, relativeTo: now) == "30 sec. ago")
    }

    @Test func `environment override has priority`() {
        let locale = RepoBarLocalization.environmentLocale(["REPOBAR_LANGUAGE": "tr_TR", "LANG": "en_US.UTF-8"])
        #expect(locale.language.languageCode?.identifier == "tr")
    }
}
