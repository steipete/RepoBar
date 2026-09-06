import Foundation
@testable import repobarcli
import RepoBarCore
import Testing

struct CLIOutputTests {
    @Test
    func `unmatched percent output remains literal`() {
        #expect(cliText("Repository is 100% complete", locale: Locale(identifier: "tr_TR")) == "Repository is 100% complete")
    }

    @Test
    func `repo label uses name when UR ls disabled`() throws {
        let url = try #require(URL(string: "https://github.com/steipete/RepoBar"))
        let label = formatRepoLabel(
            repoName: "steipete/RepoBar",
            repoURL: url,
            includeURL: false,
            linkEnabled: true
        )
        #expect(label == "steipete/RepoBar")
    }

    @Test
    func `repo label uses URL when enabled`() throws {
        let url = try #require(URL(string: "https://github.com/steipete/RepoBar"))
        let label = formatRepoLabel(
            repoName: "steipete/RepoBar",
            repoURL: url,
            includeURL: true,
            linkEnabled: false
        )
        #expect(label == url.absoluteString)
    }

    @Test
    func `event label uses text without URL`() {
        let label = formatEventLabel(
            text: "push",
            url: nil,
            includeURL: true,
            linkEnabled: false
        )
        #expect(label == "push")
    }

    @Test
    func `event label uses URL when enabled`() throws {
        let url = try #require(URL(string: "https://github.com/steipete/RepoBar/pull/1"))
        let label = formatEventLabel(
            text: "PullRequestEvent",
            url: url,
            includeURL: true,
            linkEnabled: false
        )
        #expect(label == url.absoluteString)
    }

    @Test
    func `release date formatting is stable`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 26, hour: 23, minute: 59)))
        let now = try #require(calendar.date(byAdding: .day, value: 10, to: date))
        #expect(ReleaseFormatter.releasedLabel(for: date, now: now) == "2025-12-26")
    }

    @Test
    func `render table includes release columns when enabled`() throws {
        let baseHost = try #require(URL(string: "https://github.com"))
        let releaseDate = Date(timeIntervalSinceReferenceDate: 12345)
        let repo = Repository(
            id: "1",
            name: "RepoBar",
            owner: "steipete",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 1,
            openPulls: 2,
            stars: 3,
            pushedAt: nil,
            latestRelease: Release(name: "v1.0.0", tag: "v1.0.0", publishedAt: releaseDate, url: baseHost),
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let row = RepoRow(repo: repo, activityDate: nil, activityLabel: "-", activityLine: "push")

        let now = Date(timeIntervalSinceReferenceDate: 99999)
        let withRelease = tableLines(
            [row],
            context: RepoTableContext(
                useColor: false,
                includeURL: false,
                includeRelease: true,
                includeEvent: false,
                baseHost: baseHost,
                now: now
            )
        )
        .joined(separator: "\n")
        #expect(withRelease.contains("REL"))
        #expect(withRelease.contains("RELEASED"))
        #expect(withRelease.contains("v1.0.0"))
        #expect(withRelease.contains(ReleaseFormatter.releasedLabel(for: releaseDate, now: now)))

        let withoutRelease = tableLines(
            [row],
            context: RepoTableContext(
                useColor: false,
                includeURL: false,
                includeRelease: false,
                includeEvent: false,
                baseHost: baseHost,
                now: now
            )
        )
        .joined(separator: "\n")
        #expect(withoutRelease.contains("REL") == false)
        #expect(withoutRelease.contains("RELEASED") == false)
        #expect(withoutRelease.contains("v1.0.0") == false)
    }

    @Test
    func `render JSON includes latest release`() throws {
        let baseHost = try #require(URL(string: "https://github.com"))
        let releaseDate = Date(timeIntervalSinceReferenceDate: 777)
        let repo = Repository(
            id: "1",
            name: "RepoBar",
            owner: "steipete",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            pushedAt: nil,
            latestRelease: Release(name: "v0.1.0", tag: "v0.1.0", publishedAt: releaseDate, url: baseHost),
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let row = RepoRow(repo: repo, activityDate: nil, activityLabel: "-", activityLine: "push")

        let data = try renderJSONData([row], baseHost: baseHost)
        let decoded = try JSONDecoder().decode([RepoOutput].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0].latestRelease?.tag == "v0.1.0")
        #expect(decoded[0].latestRelease?.publishedAt == releaseDate)
    }

    @Test
    func `table hides event column by default`() throws {
        let baseHost = try #require(URL(string: "https://github.com"))
        let repo = Repository(
            id: "1",
            name: "RepoBar",
            owner: "steipete",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let row = RepoRow(repo: repo, activityDate: nil, activityLabel: "-", activityLine: "EVENTLINE-123")

        let output = tableLines(
            [row],
            context: RepoTableContext(
                useColor: false,
                includeURL: false,
                includeRelease: false,
                includeEvent: false,
                baseHost: baseHost
            )
        )
        .joined(separator: "\n")
        #expect(output.contains("EVENT") == false)
        #expect(output.contains("EVENTLINE-123") == false)
    }

    @Test
    func `table shows event column when enabled`() throws {
        let baseHost = try #require(URL(string: "https://github.com"))
        let repo = Repository(
            id: "1",
            name: "RepoBar",
            owner: "steipete",
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
        let row = RepoRow(repo: repo, activityDate: nil, activityLabel: "-", activityLine: "EVENTLINE-123")

        let output = tableLines(
            [row],
            context: RepoTableContext(
                useColor: false,
                includeURL: false,
                includeRelease: false,
                includeEvent: true,
                baseHost: baseHost
            )
        )
        .joined(separator: "\n")
        #expect(output.contains("EVENT"))
        #expect(output.contains("EVENTLINE-123"))
    }

    @Test
    func `released uses today and yesterday labels`() throws {
        var calendar = Calendar.current
        calendar.timeZone = Calendar.current.timeZone

        let now = try #require(calendar.date(from: DateComponents(year: 2025, month: 12, day: 26, hour: 12)))
        let today = try #require(calendar.date(byAdding: .hour, value: -2, to: now))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let older = try #require(calendar.date(byAdding: .day, value: -6, to: now))

        #expect(ReleaseFormatter.releasedLabel(for: today, now: now) == "today")
        #expect(ReleaseFormatter.releasedLabel(for: yesterday, now: now) == "yesterday")
        #expect(ReleaseFormatter.releasedLabel(for: older, now: now) == Self.dateLabel(for: older))
    }

    private static func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
