import Foundation
import RepoBarCore

struct RepoRecentRow {
    let updatedLabel: String
    let primaryLabel: String
    let secondaryLabel: String
    let tertiaryLabel: String
    let url: URL?
}

private struct RecentTableHeaders {
    let updated: String
    let primary: String
    let secondary: String
    let tertiary: String
}

func releasesTableLines(
    _ releases: [RepoReleaseSummary],
    useColor: Bool,
    includeURL: Bool,
    now: Date = Date()
) -> [String] {
    guard releases.isEmpty == false else { return ["No releases."] }

    let rows = releases.map { release in
        RepoRecentRow(
            updatedLabel: RelativeFormatter.string(from: release.publishedAt, relativeTo: now),
            primaryLabel: release.tag,
            secondaryLabel: truncate(release.name.singleLine, max: 80),
            tertiaryLabel: release.authorLogin.map { "@\($0)" } ?? "-",
            url: release.url
        )
    }

    return recentTableLines(
        rows,
        headers: .init(updated: "RELEASED", primary: "TAG", secondary: "NAME", tertiary: "BY"),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.yellow
    )
}

func workflowRunsTableLines(
    _ runs: [RepoWorkflowRunSummary],
    useColor: Bool,
    includeURL: Bool,
    now: Date = Date()
) -> [String] {
    guard runs.isEmpty == false else { return ["No workflow runs."] }

    let rows = runs.map { run in
        let name = if let workflowName = run.workflowName, workflowName.isEmpty == false {
            "\(workflowName) · \(run.name)"
        } else {
            run.name
        }
        return RepoRecentRow(
            updatedLabel: RelativeFormatter.string(from: run.updatedAt, relativeTo: now),
            primaryLabel: ciStatusLabel(run.status, conclusion: run.conclusion),
            secondaryLabel: truncate(name.singleLine, max: 80),
            tertiaryLabel: run.branch ?? "-",
            url: run.url
        )
    }

    return recentTableLines(
        rows,
        headers: .init(updated: "UPDATED", primary: "STATUS", secondary: "NAME", tertiary: "BRANCH"),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.magenta
    )
}

func discussionsTableLines(
    _ discussions: [RepoDiscussionSummary],
    useColor: Bool,
    includeURL: Bool,
    now: Date = Date()
) -> [String] {
    guard discussions.isEmpty == false else { return ["No discussions."] }

    let rows = discussions.map { discussion in
        RepoRecentRow(
            updatedLabel: RelativeFormatter.string(from: discussion.updatedAt, relativeTo: now),
            primaryLabel: String(discussion.commentCount),
            secondaryLabel: truncate(discussion.title.singleLine, max: 80),
            tertiaryLabel: discussion.authorLogin.map { "@\($0)" } ?? "-",
            url: discussion.url
        )
    }

    return recentTableLines(
        rows,
        headers: .init(updated: "UPDATED", primary: "CMTS", secondary: "TITLE", tertiary: "BY"),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.cyan
    )
}

func tagsTableLines(
    _ tags: [RepoTagSummary],
    useColor: Bool,
    includeURL: Bool
) -> [String] {
    guard tags.isEmpty == false else { return ["No tags."] }

    let rows = tags.map { tag in
        RepoRecentRow(
            updatedLabel: "-",
            primaryLabel: tag.name,
            secondaryLabel: shortSHA(tag.commitSHA),
            tertiaryLabel: "-",
            url: nil
        )
    }

    return simpleTableLines(
        rows,
        headers: ("TAG", "SHA"),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.yellow
    )
}

func branchesTableLines(
    _ branches: [RepoBranchSummary],
    useColor: Bool,
    includeURL: Bool
) -> [String] {
    guard branches.isEmpty == false else { return ["No branches."] }

    let rows = branches.map { branch in
        RepoRecentRow(
            updatedLabel: "-",
            primaryLabel: branch.name,
            secondaryLabel: shortSHA(branch.commitSHA),
            tertiaryLabel: branch.isProtected ? "yes" : "-",
            url: nil
        )
    }

    return recentTableLines(
        rows,
        headers: .init(updated: "BRANCH", primary: "SHA", secondary: "PROTECTED", tertiary: ""),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.cyan,
        omitUpdatedColumn: true,
        omitURLColumn: true,
        omitTertiaryHeaderIfEmpty: false
    )
}

func contributorsTableLines(
    _ contributors: [RepoContributorSummary],
    useColor: Bool,
    includeURL: Bool
) -> [String] {
    guard contributors.isEmpty == false else { return ["No contributors."] }

    let rows = contributors.map { contributor in
        RepoRecentRow(
            updatedLabel: "-",
            primaryLabel: "@\(contributor.login)",
            secondaryLabel: String(contributor.contributions),
            tertiaryLabel: "-",
            url: contributor.url
        )
    }

    return simpleTableLines(
        rows,
        headers: ("USER", "CONTRIBS"),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.magenta
    )
}

func commitsTableLines(
    _ commits: [RepoCommitSummary],
    useColor: Bool,
    includeURL: Bool,
    now: Date = Date(),
    includeRepo: Bool = false
) -> [String] {
    guard commits.isEmpty == false else { return ["No commits."] }

    let rows = commits.map { commit in
        RepoRecentRow(
            updatedLabel: RelativeFormatter.string(from: commit.authoredAt, relativeTo: now),
            primaryLabel: shortSHA(commit.sha),
            secondaryLabel: truncate(commit.message.singleLine, max: 80),
            tertiaryLabel: commit.authorLogin ?? commit.authorName ?? "-",
            url: commit.url
        )
    }

    if includeRepo {
        return commitsWithRepoTableLines(
            commits,
            useColor: useColor,
            includeURL: includeURL,
            now: now
        )
    }

    return recentTableLines(
        rows,
        headers: .init(updated: "DATE", primary: "SHA", secondary: "MESSAGE", tertiary: "BY"),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.gray
    )
}

func activityTableLines(
    _ events: [ActivityEvent],
    useColor: Bool,
    includeURL: Bool,
    now: Date = Date()
) -> [String] {
    guard events.isEmpty == false else { return ["No activity."] }

    let rows = events.map { event in
        RepoRecentRow(
            updatedLabel: RelativeFormatter.string(from: event.date, relativeTo: now),
            primaryLabel: event.actor,
            secondaryLabel: truncate(event.title.singleLine, max: 90),
            tertiaryLabel: event.eventType.map { $0.lowercased() } ?? "-",
            url: event.url
        )
    }

    return recentTableLines(
        rows,
        headers: .init(updated: "DATE", primary: "BY", secondary: "TITLE", tertiary: "TYPE"),
        useColor: useColor,
        includeURL: includeURL,
        primaryColor: Ansi.gray
    )
}

func globalCommitsTableLines(
    _ commits: [RepoCommitSummary],
    useColor: Bool,
    includeURL: Bool,
    now: Date = Date()
) -> [String] {
    guard commits.isEmpty == false else { return ["No commits."] }

    let updatedHeader = "DATE"
    let repoHeader = "REPO"
    let shaHeader = "SHA"
    let messageHeader = "MESSAGE"
    let updatedWidth = max(updatedHeader.count, commits.map { RelativeFormatter.string(from: $0.authoredAt, relativeTo: now).count }.max() ?? 1)
    let repoWidth = max(repoHeader.count, commits.map { ($0.repoFullName ?? "-").count }.max() ?? 1)
    let shaWidth = max(shaHeader.count, commits.map { shortSHA($0.sha).count }.max() ?? 1)

    var headerParts = [
        padRight(updatedHeader, to: updatedWidth),
        padRight(repoHeader, to: repoWidth),
        padRight(shaHeader, to: shaWidth),
        messageHeader
    ]
    if includeURL, !Ansi.supportsLinks {
        headerParts.append("URL")
    }
    let header = headerParts.joined(separator: "  ")

    var lines: [String] = []
    lines.append(useColor ? Ansi.bold.wrap(header) : header)

    for commit in commits {
        let updated = padRight(RelativeFormatter.string(from: commit.authoredAt, relativeTo: now), to: updatedWidth)
        let repo = padRight(commit.repoFullName ?? "-", to: repoWidth)
        let sha = padRight(shortSHA(commit.sha), to: shaWidth)
        let message = truncate(commit.message.singleLine, max: 90)
        let rowURL = commit.url
        let linkLabel: String = if includeURL, Ansi.supportsLinks {
            Ansi.link(message, url: rowURL, enabled: true)
        } else {
            message
        }

        var parts = [
            useColor ? Ansi.gray.wrap(updated) : updated,
            useColor ? Ansi.cyan.wrap(repo) : repo,
            useColor ? Ansi.gray.wrap(sha) : sha,
            linkLabel
        ]

        if includeURL, !Ansi.supportsLinks {
            parts.append(rowURL.absoluteString)
        }

        lines.append(parts.joined(separator: "  "))
    }

    return lines
}

func globalActivityTableLines(
    _ events: [ActivityEvent],
    useColor: Bool,
    includeURL: Bool,
    now: Date = Date(),
    repoHost: URL
) -> [String] {
    guard events.isEmpty == false else { return ["No activity."] }

    let updatedHeader = "DATE"
    let repoHeader = "REPO"
    let actorHeader = "BY"
    let titleHeader = "TITLE"

    let updatedValues = events.map { RelativeFormatter.string(from: $0.date, relativeTo: now) }
    let repoValues = events.map { repoName(from: $0.url, host: repoHost) ?? "-" }
    let actorValues = events.map { "@\($0.actor)" }

    let updatedWidth = max(updatedHeader.count, updatedValues.map(
        \.count
    ).max() ?? 1)
    let repoWidth = max(repoHeader.count, repoValues.map(\.count).max() ?? 1)
    let actorWidth = max(actorHeader.count, actorValues.map(\.count).max() ?? 1)

    var headerParts = [
        padRight(updatedHeader, to: updatedWidth),
        padRight(repoHeader, to: repoWidth),
        padRight(actorHeader, to: actorWidth),
        titleHeader
    ]
    if includeURL, !Ansi.supportsLinks {
        headerParts.append("URL")
    }
    let header = headerParts.joined(separator: "  ")

    var lines: [String] = []
    lines.append(useColor ? Ansi.bold.wrap(header) : header)

    for (index, event) in events.enumerated() {
        let updated = padRight(updatedValues[index], to: updatedWidth)
        let repo = padRight(repoValues[index], to: repoWidth)
        let actor = padRight(actorValues[index], to: actorWidth)
        let title = truncate(event.title.singleLine, max: 90)
        let linkLabel: String = if includeURL, Ansi.supportsLinks {
            Ansi.link(title, url: event.url, enabled: true)
        } else {
            title
        }

        var parts = [
            useColor ? Ansi.gray.wrap(updated) : updated,
            useColor ? Ansi.cyan.wrap(repo) : repo,
            useColor ? Ansi.gray.wrap(actor) : actor,
            linkLabel
        ]

        if includeURL, !Ansi.supportsLinks {
            parts.append(event.url.absoluteString)
        }

        lines.append(parts.joined(separator: "  "))
    }

    return lines
}

private func recentTableLines(
    _ rows: [RepoRecentRow],
    headers: RecentTableHeaders,
    useColor: Bool,
    includeURL: Bool,
    primaryColor: Ansi.Code,
    omitUpdatedColumn: Bool = false,
    omitURLColumn: Bool = false,
    omitTertiaryHeaderIfEmpty: Bool = true
) -> [String] {
    let updatedHeader = headers.updated
    let primaryHeader = headers.primary
    let secondaryHeader = headers.secondary
    let tertiaryHeader = headers.tertiary

    let updatedWidth = max(updatedHeader.count, rows.map(\.updatedLabel.count).max() ?? 1)
    let primaryWidth = max(primaryHeader.count, rows.map(\.primaryLabel.count).max() ?? 1)
    let tertiaryValues = rows.map(\.tertiaryLabel)
    let tertiaryMax = tertiaryValues.map(\.count).max() ?? 1
    let tertiaryWidth = max(tertiaryHeader.count, tertiaryMax)

    var headerParts: [String] = []
    if !omitUpdatedColumn {
        headerParts.append(padRight(updatedHeader, to: updatedWidth))
    }
    headerParts.append(padRight(primaryHeader, to: primaryWidth))
    headerParts.append(secondaryHeader)

    if !omitTertiaryHeaderIfEmpty || tertiaryValues.contains(where: { $0 != "-" }) {
        headerParts.append(padRight(tertiaryHeader, to: tertiaryWidth))
    }
    if includeURL, !Ansi.supportsLinks, !omitURLColumn {
        headerParts.append("URL")
    }

    let header = headerParts.joined(separator: "  ")

    var lines: [String] = []
    lines.append(useColor ? Ansi.bold.wrap(header) : header)

    for row in rows {
        var parts: [String] = []
        if !omitUpdatedColumn {
            let updated = padRight(row.updatedLabel, to: updatedWidth)
            parts.append(useColor ? Ansi.gray.wrap(updated) : updated)
        }

        let primary = padRight(row.primaryLabel, to: primaryWidth)
        let coloredPrimary = useColor ? primaryColor.wrap(primary) : primary
        parts.append(coloredPrimary)

        let title: String = if includeURL, Ansi.supportsLinks, let url = row.url {
            Ansi.link(row.secondaryLabel, url: url, enabled: true)
        } else {
            row.secondaryLabel
        }
        parts.append(title)

        if !omitTertiaryHeaderIfEmpty || row.tertiaryLabel != "-" {
            let tertiary = padRight(row.tertiaryLabel, to: tertiaryWidth)
            parts.append(useColor ? Ansi.gray.wrap(tertiary) : tertiary)
        }

        if includeURL, !Ansi.supportsLinks, !omitURLColumn, let url = row.url {
            parts.append(url.absoluteString)
        }

        lines.append(parts.joined(separator: "  "))
    }

    return lines
}

private func simpleTableLines(
    _ rows: [RepoRecentRow],
    headers: (String, String),
    useColor: Bool,
    includeURL: Bool,
    primaryColor: Ansi.Code
) -> [String] {
    let primaryHeader = headers.0
    let secondaryHeader = headers.1

    let primaryWidth = max(primaryHeader.count, rows.map(\.primaryLabel.count).max() ?? 1)
    let secondaryWidth = max(secondaryHeader.count, rows.map(\.secondaryLabel.count).max() ?? 1)

    var headerParts = [
        padRight(primaryHeader, to: primaryWidth),
        padRight(secondaryHeader, to: secondaryWidth)
    ]
    if includeURL, !Ansi.supportsLinks {
        headerParts.append("URL")
    }
    let header = headerParts.joined(separator: "  ")

    var lines: [String] = []
    lines.append(useColor ? Ansi.bold.wrap(header) : header)

    for row in rows {
        let primary = padRight(row.primaryLabel, to: primaryWidth)
        let secondary = padRight(row.secondaryLabel, to: secondaryWidth)
        let coloredPrimary = useColor ? primaryColor.wrap(primary) : primary
        let coloredSecondary = useColor ? Ansi.gray.wrap(secondary) : secondary

        var parts = [coloredPrimary, coloredSecondary]
        if includeURL, !Ansi.supportsLinks, let url = row.url {
            parts.append(url.absoluteString)
        }
        lines.append(parts.joined(separator: "  "))
    }

    return lines
}

private func commitsWithRepoTableLines(
    _ commits: [RepoCommitSummary],
    useColor: Bool,
    includeURL: Bool,
    now: Date
) -> [String] {
    let updatedHeader = "DATE"
    let repoHeader = "REPO"
    let shaHeader = "SHA"
    let messageHeader = "MESSAGE"

    let updatedValues = commits.map { RelativeFormatter.string(from: $0.authoredAt, relativeTo: now) }
    let repoValues = commits.map { $0.repoFullName ?? "-" }
    let shaValues = commits.map { shortSHA($0.sha) }

    let updatedWidth = max(updatedHeader.count, updatedValues.map(\.count).max() ?? 1)
    let repoWidth = max(repoHeader.count, repoValues.map(\.count).max() ?? 1)
    let shaWidth = max(shaHeader.count, shaValues.map(\.count).max() ?? 1)

    var headerParts = [
        padRight(updatedHeader, to: updatedWidth),
        padRight(repoHeader, to: repoWidth),
        padRight(shaHeader, to: shaWidth),
        messageHeader
    ]
    if includeURL, !Ansi.supportsLinks {
        headerParts.append("URL")
    }
    let header = headerParts.joined(separator: "  ")

    var lines: [String] = []
    lines.append(useColor ? Ansi.bold.wrap(header) : header)

    for (index, commit) in commits.enumerated() {
        let updated = padRight(updatedValues[index], to: updatedWidth)
        let repo = padRight(repoValues[index], to: repoWidth)
        let sha = padRight(shaValues[index], to: shaWidth)
        let message = truncate(commit.message.singleLine, max: 90)
        let label: String = if includeURL, Ansi.supportsLinks {
            Ansi.link(message, url: commit.url, enabled: true)
        } else {
            message
        }

        var parts = [
            useColor ? Ansi.gray.wrap(updated) : updated,
            useColor ? Ansi.cyan.wrap(repo) : repo,
            useColor ? Ansi.gray.wrap(sha) : sha,
            label
        ]

        if includeURL, !Ansi.supportsLinks {
            parts.append(commit.url.absoluteString)
        }

        lines.append(parts.joined(separator: "  "))
    }

    return lines
}

private func ciStatusLabel(_ status: CIStatus, conclusion: String?) -> String {
    switch status {
    case .passing:
        "passing"
    case .failing:
        "failing"
    case .pending:
        conclusion ?? "pending"
    case .unknown:
        conclusion ?? "unknown"
    }
}

private func repoName(from url: URL, host: URL) -> String? {
    guard url.host == host.host else { return nil }

    let parts = url.path.split(separator: "/").map(String.init)
    guard parts.count >= 2 else { return nil }

    return "\(parts[0])/\(parts[1])"
}

private func shortSHA(_ sha: String) -> String {
    let trimmed = sha.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(trimmed.prefix(7))
}

private func truncate(_ text: String, max: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > max else { return trimmed }

    return String(trimmed.prefix(max)) + "…"
}
