import Foundation
import RepoBarCore

struct RepoRow {
    let repo: Repository
    let activityDate: Date?
    let activityLabel: String
    let activityLine: String
}

struct RepoOutput: Codable {
    let fullName: String
    let owner: String
    let name: String
    let repoUrl: URL
    let openIssues: Int
    let openPulls: Int
    let stars: Int
    let pushedAt: Date?
    let latestRelease: Release?
    let activityDate: Date?
    let activityTitle: String?
    let activityActor: String?
    let activityUrl: URL?
    let error: String?
}

struct StatusOutput: Codable {
    let authenticated: Bool
    let host: String?
    let expiresAt: Date?
    let expiresIn: String?
    let expired: Bool?
}

struct RepoTableContext {
    let useColor: Bool
    let includeURL: Bool
    let includeRelease: Bool
    let includeEvent: Bool
    let baseHost: URL
    let now: Date

    init(
        useColor: Bool,
        includeURL: Bool,
        includeRelease: Bool,
        includeEvent: Bool,
        baseHost: URL,
        now: Date = Date()
    ) {
        self.useColor = useColor
        self.includeURL = includeURL
        self.includeRelease = includeRelease
        self.includeEvent = includeEvent
        self.baseHost = baseHost
        self.now = now
    }
}

func prepareRows(repos: [Repository], now: Date = Date()) -> [RepoRow] {
    repos.map { repo in
        let activityDate = repo.activityDate
        let activityLabel = activityDate.map { RelativeFormatter.string(from: $0, relativeTo: now) } ?? "-"
        let activityLine = repo.activityLine(fallbackToPush: true) ?? "-"
        return RepoRow(repo: repo, activityDate: activityDate, activityLabel: activityLabel, activityLine: activityLine)
    }
}

func renderTable(_ rows: [RepoRow], context: RepoTableContext) {
    for line in tableLines(rows, context: context) {
        Swift.print(line)
    }
}

func tableLines(_ rows: [RepoRow], context: RepoTableContext) -> [String] {
    let activityHeader = "ACTIVITY"
    let issuesHeader = "ISSUES"
    let pullsHeader = "PR"
    let starsHeader = "STAR"
    let eventHeader = "EVENT"
    let releaseHeader = "REL"
    let releasedHeader = "RELEASED"
    let repoHeader = "REPO"

    let issuesWidth = max(issuesHeader.count, rows.map { String($0.repo.stats.openIssues).count }.max() ?? 1)
    let pullsWidth = max(pullsHeader.count, rows.map { String($0.repo.stats.openPulls).count }.max() ?? 1)
    let starsWidth = max(starsHeader.count, rows.map { String($0.repo.stats.stars).count }.max() ?? 1)
    let activityWidth = max(activityHeader.count, rows.map(\.activityLabel.count).max() ?? 1)
    let eventWidth = max(eventHeader.count, rows.map(\.activityLine.count).max() ?? 1)
    let releaseWidth = max(releaseHeader.count, rows.map { $0.repo.latestRelease?.tag.count ?? 1 }.max() ?? 1)
    let releasedWidth = max(
        releasedHeader.count,
        rows.map { $0.repo.latestRelease.map { ReleaseFormatter.releasedLabel(for: $0.publishedAt, now: context.now).count } ?? 1 }
            .max() ?? 1
    )

    var headerParts = [
        padRight(activityHeader, to: activityWidth),
        padLeft(issuesHeader, to: issuesWidth),
        padLeft(pullsHeader, to: pullsWidth),
        padLeft(starsHeader, to: starsWidth)
    ]
    if context.includeEvent {
        headerParts.append(padRight(eventHeader, to: eventWidth))
    }
    if context.includeRelease {
        headerParts.append(padRight(releaseHeader, to: releaseWidth))
        headerParts.append(padRight(releasedHeader, to: releasedWidth))
    }
    headerParts.append(repoHeader)

    let header = headerParts.joined(separator: "  ")

    var lines: [String] = []
    lines.append(context.useColor ? Ansi.bold.wrap(header) : header)

    for row in rows {
        let issues = padLeft(String(row.repo.stats.openIssues), to: issuesWidth)
        let pulls = padLeft(String(row.repo.stats.openPulls), to: pullsWidth)
        let stars = padLeft(String(row.repo.stats.stars), to: starsWidth)
        let activity = padRight(row.activityLabel, to: activityWidth)
        let event = padRight(row.activityLine.singleLine, to: eventWidth)
        let rel = padRight(row.repo.latestRelease?.tag ?? "-", to: releaseWidth)
        let released = padRight(
            row.repo.latestRelease.map { ReleaseFormatter.releasedLabel(for: $0.publishedAt, now: context.now) } ?? "-",
            to: releasedWidth
        )
        let repoName = row.repo.fullName
        let repoURL = makeRepoURL(baseHost: context.baseHost, repo: row.repo)
        let repoLabel = formatRepoLabel(
            repoName: repoName,
            repoURL: repoURL,
            includeURL: context.includeURL,
            linkEnabled: Ansi.supportsLinks
        )

        let coloredActivity = context.useColor ? Ansi.gray.wrap(activity) : activity
        let coloredIssues = context.useColor
            ? (row.repo.stats.openIssues > 0 ? Ansi.red.wrap(issues) : Ansi.gray.wrap(issues))
            : issues
        let coloredPulls = context.useColor
            ? (row.repo.stats.openPulls > 0 ? Ansi.magenta.wrap(pulls) : Ansi.gray.wrap(pulls))
            : pulls
        let coloredStars = context.useColor
            ? (row.repo.stats.stars > 0 ? Ansi.yellow.wrap(stars) : Ansi.gray.wrap(stars))
            : stars
        let coloredRel = context.useColor ? (row.repo.latestRelease == nil ? Ansi.gray.wrap(rel) : rel) : rel
        let coloredReleased = context.useColor ? (row.repo.latestRelease == nil ? Ansi.gray.wrap(released) : released) : released
        let coloredRepo = context.useColor ? Ansi.cyan.wrap(repoLabel) : repoLabel
        let coloredEvent = context.useColor ? Ansi.gray.wrap(event) : event

        var outputParts = [
            coloredActivity,
            coloredIssues,
            coloredPulls,
            coloredStars
        ]
        if context.includeEvent {
            outputParts.append(coloredEvent)
        }
        if context.includeRelease {
            outputParts.append(coloredRel)
            outputParts.append(coloredReleased)
        }
        outputParts.append(coloredRepo)

        let output = outputParts.joined(separator: "  ")
        lines.append(output)

        if let error = row.repo.error {
            let message = "  ! \(error)"
            lines.append(context.useColor ? Ansi.red.wrap(message) : message)
        }
    }

    return lines
}

func renderJSONData(_ rows: [RepoRow], baseHost: URL) throws -> Data {
    let items = rows.map { row in
        RepoOutput(
            fullName: row.repo.fullName,
            owner: row.repo.owner,
            name: row.repo.name,
            repoUrl: makeRepoURL(baseHost: baseHost, repo: row.repo),
            openIssues: row.repo.stats.openIssues,
            openPulls: row.repo.stats.openPulls,
            stars: row.repo.stats.stars,
            pushedAt: row.repo.stats.pushedAt,
            latestRelease: row.repo.latestRelease,
            activityDate: row.activityDate,
            activityTitle: row.repo.latestActivity?.title,
            activityActor: row.repo.latestActivity?.actor,
            activityUrl: row.repo.latestActivity?.url,
            error: row.repo.error
        )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(items)
}

func renderJSON(_ rows: [RepoRow], baseHost: URL) throws {
    let data = try renderJSONData(rows, baseHost: baseHost)
    if let json = String(data: data, encoding: .utf8) {
        // JSON is a machine-readable contract and must remain byte-for-byte stable.
        Swift.print(json)
    }
}

func padLeft(_ value: String, to width: Int) -> String {
    let pad = max(0, width - value.count)
    return String(repeating: " ", count: pad) + value
}

func padRight(_ value: String, to width: Int) -> String {
    let pad = max(0, width - value.count)
    return value + String(repeating: " ", count: pad)
}

func makeRepoURL(baseHost: URL, repo: Repository) -> URL {
    baseHost.appending(path: "/\(repo.owner)/\(repo.name)")
}

func formatRepoLabel(
    repoName: String,
    repoURL: URL,
    includeURL: Bool,
    linkEnabled: Bool
) -> String {
    guard includeURL else { return repoName }

    if linkEnabled {
        return Ansi.link(repoName, url: repoURL, enabled: true)
    }
    return repoURL.absoluteString
}

func formatEventLabel(
    text: String,
    url: URL?,
    includeURL: Bool,
    linkEnabled: Bool
) -> String {
    guard includeURL, let url else { return text }

    return formatURL(url, linkEnabled: linkEnabled)
}

func formatURL(_ url: URL, linkEnabled: Bool) -> String {
    if linkEnabled {
        return Ansi.link(url.absoluteString, url: url, enabled: true)
    }
    return url.absoluteString
}
