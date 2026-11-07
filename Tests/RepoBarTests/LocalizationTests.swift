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

    @Test(arguments: ["zh-Hans", "zh-CN", "zh_CN", "zh-Hans-CN"])
    func `simplified chinese language preferences`(language: String) {
        let localizer = AppLocalizer(preferredLanguages: [language])
        #expect(localizer.string("Preferences…") == "偏好设置…")
        #expect(localizer.string("Notifications") == "通知")
        #expect(localizer.string("Search repositories") == "搜索仓库")
        #expect(localizer.string("Pinned") == "已固定")
    }

    @Test func `language priority and fallback`() {
        #expect(AppLocalizer(preferredLanguages: ["en-US", "tr"]).string("General") == "General")
        #expect(AppLocalizer(preferredLanguages: ["zh-Hans", "en"]).string("General") == "通用")
        #expect(AppLocalizer(preferredLanguages: ["fr", "tr"]).string("General") == "Genel")
        #expect(AppLocalizer(preferredLanguages: ["ja-JP"]).string("General") == "General")
        #expect(AppLocalizer(preferredLanguages: []).string("General") == "General")
    }

    @Test @MainActor func `branch and worktree identifiers remain literal even on catalog collisions`() {
        let localizer = AppLocalizer(preferredLanguages: ["tr"])
        #expect(localizer.string("Invalid backup 100% %@") == "Invalid backup 100% %@")
        #expect(localizer.string("example-org/demo#42") == "example-org/demo#42")
        let chineseLocalizer = AppLocalizer(preferredLanguages: ["zh-Hans"])
        #expect(chineseLocalizer.string("feature/branch-name") == "feature/branch-name")
        #expect(chineseLocalizer.string("worktree-name") == "worktree-name")

        // "Work" collides with catalog keys ("工作" in zh-Hans, "İş" in tr), but must remain literal in row views
        let model = LocalRefMenuRowViewModel(
            kind: .worktree,
            title: "/tmp/worktree",
            detail: "Work",
            isCurrent: true,
            isDetached: false,
            upstream: nil,
            aheadCount: nil,
            behindCount: nil,
            lastCommitDate: nil,
            lastCommitAuthor: nil,
            dirtySummary: nil
        )
        let worktreeRow = LocalWorktreeMenuRowView(model: model)
        #expect(worktreeRow.model.detail == "Work")

        let recentRow = RecentListSubmenuRowView(
            title: "Repo",
            systemImage: "folder",
            detailText: "Work"
        )
        #expect(recentRow.detailText == "Work")
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
        let chinese = try catalog("zh-Hans")
        #expect(Set(english.keys) == Set(turkish.keys))
        #expect(Set(english.keys) == Set(chinese.keys))
        let titles = MainMenuItemID.allCases.map(\.title) + RepoSubmenuItemID.allCases.map(\.title)
        let subtitles = MainMenuItemID.allCases.compactMap(\.subtitle) + RepoSubmenuItemID.allCases.compactMap(\.subtitle)
        for key in titles + subtitles {
            #expect(english[key] == key)
            #expect(turkish[key] != nil)
            #expect(turkish[key] != key)
            #expect(chinese[key] != nil)
            #expect(chinese[key] != key)
        }
    }
}
