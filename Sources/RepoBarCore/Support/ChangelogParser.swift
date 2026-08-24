import Foundation

public struct ChangelogSection: Equatable, Sendable {
    public let title: String
    public let entryCount: Int

    public var isUnreleased: Bool {
        self.title.localizedCaseInsensitiveContains("unreleased")
    }
}

public struct ChangelogParsed: Equatable, Sendable {
    public let sections: [ChangelogSection]
}

public struct ChangelogRowPresentation: Hashable, Sendable {
    public let title: String
    public let badgeText: String?
    public let detailText: String?
}

public enum ChangelogParser {
    public static func parse(markdown: String) -> ChangelogParsed {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var sections: [ChangelogSection] = []
        var currentTitle: String?
        var currentEntries = 0

        for rawLine in lines {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let heading = self.headingTitle(from: trimmed) {
                if let currentTitle {
                    sections.append(ChangelogSection(title: currentTitle, entryCount: currentEntries))
                }
                currentTitle = heading
                currentEntries = 0
                continue
            }

            guard currentTitle != nil else { continue }

            if self.isListItemLine(trimmed) {
                currentEntries += 1
            }
        }

        if let currentTitle {
            sections.append(ChangelogSection(title: currentTitle, entryCount: currentEntries))
        }

        return ChangelogParsed(sections: sections)
    }

    public static func headline(parsed: ChangelogParsed) -> String? {
        guard parsed.sections.isEmpty == false else { return nil }

        if let release = parsed.sections.first(where: { self.versionMatch(in: $0.title) != nil }) {
            return release.title
        }
        return parsed.sections.first?.title
    }

    public static func presentation(parsed: ChangelogParsed, releaseTag: String?) -> ChangelogRowPresentation? {
        guard parsed.sections.isEmpty == false else { return nil }

        if let unreleased = parsed.sections.first(where: \.isUnreleased), unreleased.entryCount > 0 {
            return ChangelogRowPresentation(
                title: "Changelog • Unreleased",
                badgeText: "\(unreleased.entryCount)",
                detailText: nil
            )
        }

        // An empty Unreleased heading does not mean there is nothing new. Dated sections
        // between it and the tracked release can still hold unseen entries, so fall through
        // to the release comparison instead of reporting "Up to date" here.
        let hasUnreleased = parsed.sections.contains(where: \.isUnreleased)
        let upToDate = ChangelogRowPresentation(
            title: "Changelog",
            badgeText: nil,
            detailText: "Up to date"
        )

        guard let releaseTag, let releaseVersion = self.normalizedVersion(from: releaseTag) else {
            return hasUnreleased ? upToDate : nil
        }
        guard let matchIndex = parsed.sections.firstIndex(where: {
            self.sectionMatchesVersion($0, releaseVersion: releaseVersion)
        }) else {
            return hasUnreleased ? upToDate : nil
        }

        let count = parsed.sections.prefix(matchIndex).reduce(0) { $0 + $1.entryCount }
        if count > 0 {
            let label = releaseTag.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChangelogRowPresentation(
                title: "Changelog • Since \(label)",
                badgeText: "\(count)",
                detailText: nil
            )
        }

        return upToDate
    }

    private static func headingTitle(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        let hashes = trimmed.prefix { $0 == "#" }
        let level = hashes.count
        guard level > 0, level <= 2 else { return nil }

        let remainder = trimmed.dropFirst(level)
        guard remainder.first == " " else { return nil }

        let title = remainder.dropFirst().trimmingCharacters(in: .whitespaces)
        if level == 1, title.localizedCaseInsensitiveContains("changelog") {
            return nil
        }
        return title.isEmpty ? nil : title
    }

    private static func isListItemLine(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        let regex = try? NSRegularExpression(pattern: "^\\d+\\.\\s")
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex?.firstMatch(in: trimmed, range: range) != nil
    }

    private static func normalizedVersion(from text: String) -> String? {
        guard let match = self.versionMatch(in: text) else { return nil }

        return match.lowercased().hasPrefix("v") ? String(match.dropFirst()) : match
    }

    private static func sectionMatchesVersion(_ section: ChangelogSection, releaseVersion: String) -> Bool {
        guard let match = self.versionMatch(in: section.title) else { return false }

        let normalized = match.lowercased().hasPrefix("v") ? String(match.dropFirst()) : match
        return normalized == releaseVersion
    }

    private static func versionMatch(in text: String) -> String? {
        let pattern = "(?i)\\bv?\\d+(?:\\.\\d+){1,3}\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, range: range),
              let range = Range(match.range, in: text)
        else { return nil }

        return String(text[range])
    }
}
