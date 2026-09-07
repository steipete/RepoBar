import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

@Suite("Localization")
struct LocalizationTests {
    @Test(arguments: ["tr", "tr-TR", "tr_TR"])
    func `turkish language preferences`(language: String) {
        let localizer = AppLocalizer(preferredLanguages: [language])
        #expect(localizer.string("Preferences…") == "Ayarlar…")
        #expect(localizer.string("Notifications") == "Bildirimler")
        #expect(localizer.string("Search repositories") == "Depolarda ara")
        #expect(localizer.string("Pinned") == "Sabitlenmiş")
    }

    @Test func `language priority and fallback`() {
        #expect(AppLocalizer(preferredLanguages: ["en-US", "tr"]).string("General") == "General")
        #expect(AppLocalizer(preferredLanguages: ["fr", "tr"]).string("General") == "Genel")
        #expect(AppLocalizer(preferredLanguages: ["ja-JP"]).string("General") == "General")
        #expect(AppLocalizer(preferredLanguages: []).string("General") == "General")
    }

    @Test func `unknown text is literal`() {
        let localizer = AppLocalizer(preferredLanguages: ["tr"])
        #expect(localizer.string("Invalid backup 100% %@") == "Invalid backup 100% %@")
        #expect(localizer.string("example-org/demo#42") == "example-org/demo#42")
    }

    @Test func `catalogs have matching keys and translate display settings`() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/RepoBar/Resources/Localizations")
        func catalog(_ language: String) throws -> [String: String] {
            let data = try Data(contentsOf: resources.appending(path: "\(language).lproj/Localizable.strings"))
            return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try catalog("en")
        let turkish = try catalog("tr")
        #expect(Set(english.keys) == Set(turkish.keys))
        let titles = MainMenuItemID.allCases.map(\.title) + RepoSubmenuItemID.allCases.map(\.title)
        let subtitles = MainMenuItemID.allCases.compactMap(\.subtitle) + RepoSubmenuItemID.allCases.compactMap(\.subtitle)
        for key in titles + subtitles {
            #expect(english[key] == key)
            #expect(turkish[key] != nil)
            #expect(turkish[key] != key)
        }
    }
}
