import Foundation

public struct GitHubReferenceParsedURL: Sendable, Hashable {
    public let query: GitHubReferenceQuery
    public let url: URL
    public let kind: GitHubReferenceKind
}

struct GitHubReferenceIssueNumberTokenMatch {
    let query: GitHubReferenceQuery
    let tokenIndex: Int
}

struct IssueNumberToken: Hashable {
    let number: Int
    let tokenIndex: Int
}

public enum GitHubReferenceTranslator {
    public static let defaultMinimumBareDigits = 1
    private static let maxScannedTextLength = 8000
    private static let maxIssueSeriesCount = 100

    public static func query(
        from rawText: String,
        minimumBareDigits: Int = Self.defaultMinimumBareDigits
    ) -> GitHubReferenceQuery? {
        self.queries(from: rawText, minimumBareDigits: minimumBareDigits).first
    }

    public static func queries(
        from rawText: String,
        minimumBareDigits: Int = Self.defaultMinimumBareDigits,
        repositoryContextOverride: String? = nil
    ) -> [GitHubReferenceQuery] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query = self.urlQuery(from: text) {
            return [query]
        }

        if let query = self.tokenQuery(
            from: text,
            minimumBareDigits: minimumBareDigits,
            allowBareIssueNumber: true,
            allowNumericCommitHash: true
        ) {
            return [self.applyingRepositoryContext(repositoryContextOverride, to: query)]
        }

        let scannedText = rawText.trimmingCharacters(in: .newlines)
        guard scannedText.count <= Self.maxScannedTextLength else { return [] }

        let repositoryHeadingListBlockParse = self.repositoryHeadingListBlockParse(
            in: scannedText,
            minimumBareDigits: minimumBareDigits
        )
        if repositoryHeadingListBlockParse.consumedLineIndexes.isEmpty == false {
            return self.queriesMergingRepositoryHeadingListBlocks(
                in: scannedText,
                minimumBareDigits: minimumBareDigits,
                repositoryContextOverride: repositoryContextOverride,
                repositoryHeadingListBlockParse: repositoryHeadingListBlockParse
            )
        }

        return self.normalQueries(
            from: repositoryHeadingListBlockParse.remainingText,
            minimumBareDigits: minimumBareDigits,
            repositoryContextOverride: repositoryContextOverride
        )
    }

    static func normalQueries(
        from parseText: String,
        minimumBareDigits: Int,
        repositoryContextOverride: String?
    ) -> [GitHubReferenceQuery] {
        let tokens = self.referenceTokens(in: parseText)
        let groupedQueries = self.groupedRepositoryIssueQueries(in: parseText)
        let lineScopedQueries = self.lineScopedRepositoryIssueQueries(in: parseText, minimumBareDigits: minimumBareDigits)
        let repositoryContext = repositoryContextOverride
            ?? self.repositoryContext(in: parseText)
            ?? self.listItemRepositoryContext(in: parseText)
        let primaryListQueries = self.primaryListItemQueries(
            in: parseText,
            repositoryContext: repositoryContext
        )
        if let shortcutQueries = self.primaryURLShortcutQueries(
            tokens: tokens,
            primaryListQueries: primaryListQueries
        ) {
            return shortcutQueries
        }

        var queries: [GitHubReferenceQuery] = []
        var seen: Set<String> = []
        func append(_ query: GitHubReferenceQuery) {
            guard seen.insert(self.dedupeKey(for: query)).inserted else { return }

            queries.append(query)
        }

        if primaryListQueries.count >= 2 {
            for query in primaryListQueries {
                append(query)
            }
        }

        for token in tokens {
            if let query = self.urlQuery(from: token) {
                append(query)
            }
            for query in self.compoundRepositoryIssueQueries(from: token) {
                append(query)
            }
        }

        for query in groupedQueries {
            append(query)
        }
        for query in lineScopedQueries {
            append(query)
        }
        for query in self.contextualBareIssueQueries(
            in: parseText,
            minimumBareDigits: minimumBareDigits,
            suppressLineScopedDuplicates: true
        ) {
            append(self.applyingRepositoryContext(repositoryContext, to: query))
        }

        let allowsNumericCommitHash = self.hasCommitContext(parseText)
        for line in parseText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            for sentence in self.lineScopedSentenceFragments(in: line) {
                let lineScopedIssueTokens = self.scopedIssueNumberTokens(
                    inLine: sentence,
                    minimumBareDigits: minimumBareDigits
                )
                for (index, token) in self.referenceTokens(in: sentence).enumerated() {
                    if let query = self.tokenQuery(
                        from: token,
                        minimumBareDigits: minimumBareDigits,
                        allowBareIssueNumber: false,
                        allowNumericCommitHash: allowsNumericCommitHash
                    ) {
                        let isLineScopedIssueToken = query.issueNumber.map {
                            lineScopedIssueTokens.contains(.init(number: $0, tokenIndex: index))
                        } ?? false
                        if isLineScopedIssueToken {
                            continue
                        }
                        append(self.applyingRepositoryContext(repositoryContext, to: query))
                    }
                }
            }
        }

        return queries
    }

    static func contextualBareIssueQueries(
        in text: String,
        minimumBareDigits: Int,
        suppressLineScopedDuplicates: Bool = true
    ) -> [GitHubReferenceQuery] {
        var previousHadReferenceContext = false
        var queries: [GitHubReferenceQuery] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                previousHadReferenceContext = false
                continue
            }

            for sentence in self.lineScopedSentenceFragments(in: line) {
                if self.isIssueCountSummary(sentence) {
                    previousHadReferenceContext = false
                    continue
                }

                let lineScopedIssueTokens = suppressLineScopedDuplicates
                    ? self.scopedIssueNumberTokens(inLine: sentence, minimumBareDigits: minimumBareDigits)
                    : []
                let hasContext = self.hasIssueReferenceContext(sentence)
                defer { previousHadReferenceContext = hasContext }

                if hasContext {
                    queries.append(contentsOf: self.suppressLineScopedIssueDuplicates(
                        in: self.contextualBareIssueSeriesMatches(
                            in: sentence,
                            minimumBareDigits: minimumBareDigits
                        ),
                        lineScopedIssueTokens: lineScopedIssueTokens
                    ).map(\.query))
                }

                if previousHadReferenceContext, self.startsWithBackReference(sentence) {
                    queries.append(contentsOf: self.suppressLineScopedIssueDuplicates(
                        in: self.backReferenceBareIssueSeriesMatches(
                            in: sentence,
                            minimumBareDigits: minimumBareDigits
                        ),
                        lineScopedIssueTokens: lineScopedIssueTokens
                    ).map(\.query))
                }
            }
        }

        return queries
    }

    private static func suppressLineScopedIssueDuplicates(
        in matches: [GitHubReferenceIssueNumberTokenMatch],
        lineScopedIssueTokens: Set<IssueNumberToken>
    ) -> [GitHubReferenceIssueNumberTokenMatch] {
        matches.filter { match in
            guard case let .issueNumber(number) = match.query else { return true }

            return lineScopedIssueTokens.contains(.init(number: number, tokenIndex: match.tokenIndex)) == false
        }
    }

    private static func scopedIssueNumberTokens(inLine line: String, minimumBareDigits: Int) -> Set<IssueNumberToken> {
        Set(
            self.lineScopedRepositoryIssueNumberTokenMatches(
                inLine: line,
                minimumBareDigits: minimumBareDigits
            )
            .compactMap { match in
                guard let number = match.query.issueNumber else { return nil }

                return IssueNumberToken(number: number, tokenIndex: match.tokenIndex)
            }
        )
    }

    private static func contextualBareIssueSeriesMatches(
        in sentence: String,
        minimumBareDigits: Int
    ) -> [GitHubReferenceIssueNumberTokenMatch] {
        let tokens = self.referenceTokens(in: sentence)
        guard tokens.isEmpty == false else { return [] }

        var matches: [GitHubReferenceIssueNumberTokenMatch] = []
        for index in tokens.indices {
            let token = tokens[index].lowercased()
            if index > tokens.startIndex, self.isRepositoryFullName(tokens[tokens.index(before: index)]) {
                continue
            }
            let nextToken = tokens.indices.contains(index + 1) ? tokens[index + 1].lowercased() : nil
            let startIndex: Int? = if ["pr", "prs", "issue", "issues"].contains(token) {
                index + 1
            } else if token == "pull", nextToken == "request" || nextToken == "requests" {
                index + 2
            } else {
                nil
            }
            guard let startIndex else { continue }

            matches.append(contentsOf: self.bareIssueSeriesMatches(
                in: Array(tokens.dropFirst(startIndex)),
                minimumBareDigits: minimumBareDigits,
                tokenOffset: startIndex
            ))
        }

        return matches
    }

    static func backReferenceBareIssueSeriesQueries(in sentence: String, minimumBareDigits: Int) -> [GitHubReferenceQuery] {
        self.backReferenceBareIssueSeriesMatches(in: sentence, minimumBareDigits: minimumBareDigits).map(\.query)
    }

    private static func backReferenceBareIssueSeriesMatches(
        in sentence: String,
        minimumBareDigits: Int
    ) -> [GitHubReferenceIssueNumberTokenMatch] {
        let tokens = self.referenceTokens(in: sentence)
        guard tokens.count >= 2 else { return [] }

        let firstToken = tokens[0].lowercased()
        guard ["that", "this", "it", "they", "these", "those"].contains(firstToken) else { return [] }

        let firstSeriesIndex = ["is", "are", "was", "were"].contains(tokens[1].lowercased()) ? 2 : 1
        guard tokens.indices.contains(firstSeriesIndex) else { return [] }

        return self.bareIssueSeriesMatches(
            in: Array(tokens.dropFirst(firstSeriesIndex)),
            minimumBareDigits: minimumBareDigits,
            tokenOffset: firstSeriesIndex
        )
    }

    static func bareIssueSeriesQueries(in tokens: [String], minimumBareDigits: Int) -> [GitHubReferenceQuery] {
        self.bareIssueSeriesMatches(in: tokens, minimumBareDigits: minimumBareDigits).map(\.query)
    }

    static func bareIssueSeriesMatches(
        in tokens: [String],
        minimumBareDigits: Int,
        tokenOffset: Int = 0
    ) -> [GitHubReferenceIssueNumberTokenMatch] {
        var matches: [GitHubReferenceIssueNumberTokenMatch] = []

        for index in tokens.indices {
            let token = tokens[index]
            let normalized = token.lowercased()
            if let number = self.bareIssueSeriesNumber(from: token, minimumBareDigits: minimumBareDigits) {
                let startsDiffStat = token.hasPrefix("#") == false && self.startsDiffStat(in: tokens, at: index)
                if startsDiffStat, matches.isEmpty == false {
                    break
                }
                matches.append(.init(query: .issueNumber(number), tokenIndex: tokenOffset + index))
                if startsDiffStat {
                    break
                }
                continue
            }

            if ["and", "or", "maybe"].contains(normalized) {
                continue
            }

            break
        }

        return matches
    }

    private static func startsDiffStat(in tokens: [String], at index: Array<String>.Index) -> Bool {
        let nounIndex = index + 1
        guard tokens.indices.contains(nounIndex),
              self.isDiffStatNoun(tokens[nounIndex].lowercased())
        else { return false }

        let nextIndex = nounIndex + 1
        let noun = tokens[nounIndex].lowercased()
        guard tokens.indices.contains(nextIndex) else {
            return self.isStrongDiffStatNoun(noun)
        }

        let nextToken = tokens[nextIndex].lowercased()
        if nextToken == "/" {
            let countIndex = nextIndex + 1
            return tokens.indices.contains(countIndex) && Int(tokens[countIndex]) != nil
        }
        if nextToken == "changed" {
            return self.isStrongDiffStatNoun(noun)
        }
        if ["and", "or"].contains(nextToken) {
            let countIndex = nextIndex + 1
            return self.isStrongDiffStatNoun(noun) &&
                tokens.indices.contains(countIndex) &&
                Int(tokens[countIndex]) != nil
        }

        return Int(nextToken) != nil && self.isStrongDiffStatNoun(noun)
    }

    private static func isDiffStatNoun(_ token: String) -> Bool {
        [
            "add",
            "adds",
            "addition",
            "additions",
            "del",
            "dels",
            "delete",
            "deletes",
            "deletion",
            "deletions",
            "file",
            "files"
        ].contains(token)
    }

    private static func isStrongDiffStatNoun(_ token: String) -> Bool {
        [
            "addition",
            "additions",
            "deletion",
            "deletions",
            "file",
            "files"
        ].contains(token)
    }

    private static func bareIssueSeriesNumber(from token: String, minimumBareDigits: Int) -> Int? {
        if token.hasPrefix("#") {
            return self.issueNumber(from: token, minimumBareDigits: minimumBareDigits, allowBareNumber: false)
        }
        if token.lowercased().hasPrefix("gh-") {
            return self.issueNumber(from: token, minimumBareDigits: minimumBareDigits, allowBareNumber: false)
        }

        guard token.allSatisfy(\.isNumber),
              let number = self.issueNumber(
                  from: token,
                  minimumBareDigits: minimumBareDigits,
                  allowBareNumber: true
              )
        else { return nil }

        return number
    }

    private static func primaryListItemQueries(
        in text: String,
        repositoryContext: String?
    ) -> [GitHubReferenceQuery] {
        let allowsNumericCommitHash = self.hasCommitContext(text)
        var queries: [GitHubReferenceQuery] = []
        var seen: Set<String> = []

        func append(_ query: GitHubReferenceQuery) {
            guard seen.insert(self.dedupeKey(for: query)).inserted else { return }

            queries.append(query)
        }

        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            guard let body = self.listItemBody(in: line),
                  let firstToken = self.referenceTokens(in: body).first
            else { continue }

            if let query = self.urlQuery(from: firstToken) {
                append(query)
                continue
            }

            let bareSeriesQueries = self.compoundBareIssueQueries(from: firstToken)
            if bareSeriesQueries.isEmpty == false {
                bareSeriesQueries
                    .map { self.applyingRepositoryContext(repositoryContext, to: $0) }
                    .forEach(append)
                continue
            }

            let compoundQueries = self.compoundRepositoryIssueQueries(from: firstToken)
            if compoundQueries.isEmpty == false {
                compoundQueries.forEach(append)
                continue
            }

            guard let query = self.tokenQuery(
                from: firstToken,
                minimumBareDigits: 1,
                allowBareIssueNumber: false,
                allowNumericCommitHash: allowsNumericCommitHash
            ) else { continue }

            append(self.applyingRepositoryContext(repositoryContext, to: query))
        }

        return queries
    }

    private static func primaryURLShortcutQueries(
        tokens: [String],
        primaryListQueries: [GitHubReferenceQuery]
    ) -> [GitHubReferenceQuery]? {
        guard primaryListQueries.count >= 2,
              tokens.contains(where: { self.urlQuery(from: $0) != nil })
        else { return nil }

        return primaryListQueries
    }

    static func primaryURLShortcutDedupeKeys(
        in parseText: String,
        repositoryContextOverride: String?
    ) -> Set<String>? {
        let tokens = self.referenceTokens(in: parseText)
        let repositoryContext = repositoryContextOverride
            ?? self.repositoryContext(in: parseText)
            ?? self.listItemRepositoryContext(in: parseText)
        let primaryListQueries = self.primaryListItemQueries(
            in: parseText,
            repositoryContext: repositoryContext
        )
        guard let shortcutQueries = self.primaryURLShortcutQueries(
            tokens: tokens,
            primaryListQueries: primaryListQueries
        ) else { return nil }

        return Set(shortcutQueries.map(self.dedupeKey(for:)))
    }

    static func listItemBody(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        for marker in ["- ", "* ", "• "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var digitEnd = trimmed.startIndex
        while digitEnd < trimmed.endIndex, trimmed[digitEnd].isNumber {
            digitEnd = trimmed.index(after: digitEnd)
        }
        guard digitEnd > trimmed.startIndex,
              digitEnd < trimmed.endIndex,
              trimmed[digitEnd] == "." || trimmed[digitEnd] == ")"
        else { return nil }

        let markerEnd = trimmed.index(after: digitEnd)
        guard markerEnd == trimmed.endIndex || trimmed[markerEnd].isWhitespace else { return nil }

        return String(trimmed[markerEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func groupedRepositoryIssueQueries(in text: String) -> [GitHubReferenceQuery] {
        text
            .split(whereSeparator: \.isNewline)
            .flatMap { self.groupedRepositoryIssueQueries(inLine: String($0)) }
    }

    private static func groupedRepositoryIssueQueries(inLine line: String) -> [GitHubReferenceQuery] {
        self.lineScopedSentenceFragments(in: line).flatMap(self.groupedRepositoryIssueQueries(inSegment:))
    }

    private static func groupedRepositoryIssueQueries(inSegment segment: String) -> [GitHubReferenceQuery] {
        guard let colon = segment.firstIndex(of: ":") else { return [] }

        let prefixTokens = self.referenceTokens(in: String(segment[..<colon]))
        guard let repositoryFullName = prefixTokens.last(where: self.isRepositoryFullName) else { return [] }

        return self.referenceTokens(in: String(segment[segment.index(after: colon)...]))
            .compactMap { token in
                guard let number = self.issueNumber(from: token, minimumBareDigits: 1, allowBareNumber: false) else {
                    return nil
                }

                return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
            }
    }

    static func tokenQuery(
        from rawToken: String,
        minimumBareDigits: Int,
        allowBareIssueNumber: Bool,
        allowNumericCommitHash: Bool
    ) -> GitHubReferenceQuery? {
        let token = self.normalizedToken(from: rawToken)
        guard token.isEmpty == false else { return nil }

        if let scopedIssue = self.repositoryIssueNumber(from: token) {
            return scopedIssue
        }
        if let namedIssue = self.repositoryNameIssueNumber(from: token) {
            return namedIssue
        }
        if self.isCommitHash(token, allowNumericOnly: allowNumericCommitHash) {
            return .commitHash(token.lowercased())
        }
        if let number = self.issueNumber(from: token, minimumBareDigits: minimumBareDigits, allowBareNumber: allowBareIssueNumber) {
            return .issueNumber(number)
        }
        return nil
    }

    static func urlQuery(from rawText: String) -> GitHubReferenceQuery? {
        self.urlReference(from: rawText)?.query
    }
}

public extension GitHubReferenceTranslator {
    static func urlReferences(in rawText: String) -> [GitHubReferenceParsedURL] {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reference = self.urlReference(from: text) {
            return [reference]
        }
        guard text.count <= Self.maxScannedTextLength else { return [] }

        var references: [GitHubReferenceParsedURL] = []
        var seen: Set<String> = []
        for token in self.referenceTokens(in: text) {
            guard let reference = self.urlReference(from: token),
                  seen.insert(self.dedupeKey(for: reference.query)).inserted
            else { continue }

            references.append(reference)
        }
        return references
    }

    private static func urlReference(from rawText: String) -> GitHubReferenceParsedURL? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        let host = components.host?.lowercased() ?? ""
        guard host == "github.com" || host.hasSuffix(".github.com") else { return nil }

        let pathParts = components.path
            .split(separator: "/")
            .map(String.init)
        guard pathParts.count >= 4 else { return nil }

        let repositoryFullName = "\(pathParts[0])/\(pathParts[1])"
        switch pathParts[2].lowercased() {
        case "issues":
            guard let number = Int(pathParts[3]) else { return nil }

            return GitHubReferenceParsedURL(
                query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number),
                url: url,
                kind: .issue
            )
        case "pull":
            if let hash = self.commitHash(in: pathParts.dropFirst(4)) {
                return GitHubReferenceParsedURL(
                    query: .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash),
                    url: url,
                    kind: .commit
                )
            }
            guard let number = Int(pathParts[3]) else { return nil }

            return GitHubReferenceParsedURL(
                query: .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number),
                url: url,
                kind: .pullRequest
            )
        case "commit", "commits":
            let hash = pathParts[3].lowercased()
            guard self.isCommitHash(hash, allowNumericOnly: true) else { return nil }

            return GitHubReferenceParsedURL(
                query: .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash),
                url: url,
                kind: .commit
            )
        case "actions":
            guard pathParts.count >= 5,
                  pathParts[3].lowercased() == "runs",
                  let runID = Int64(pathParts[4])
            else { return nil }

            return GitHubReferenceParsedURL(
                query: .repositoryWorkflowRun(repositoryFullName: repositoryFullName, runID: runID),
                url: url,
                kind: .workflowRun
            )
        default:
            guard let hash = self.commitHash(in: pathParts.dropFirst(2)) else { return nil }

            return GitHubReferenceParsedURL(
                query: .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash),
                url: url,
                kind: .commit
            )
        }
    }
}

extension GitHubReferenceTranslator {
    private static func commitHash(in pathParts: some Sequence<String>) -> String? {
        pathParts
            .map { $0.lowercased() }
            .first { self.isCommitHash($0, allowNumericOnly: true) }
    }

    static func issueNumber(from token: String, minimumBareDigits: Int, allowBareNumber: Bool) -> Int? {
        if token.hasPrefix("#") {
            return Int(token.dropFirst())
        }
        if token.lowercased().hasPrefix("gh-") {
            return Int(token.dropFirst(3))
        }
        guard allowBareNumber else { return nil }
        guard token.count >= minimumBareDigits,
              token.allSatisfy(\.isNumber)
        else { return nil }

        return Int(token)
    }

    private static func repositoryIssueNumber(from token: String) -> GitHubReferenceQuery? {
        let parts = token.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let number = Int(parts[1]),
              self.isRepositoryFullName(parts[0])
        else { return nil }

        return .repositoryIssueNumber(repositoryFullName: parts[0], number: number)
    }

    private static func repositoryNameIssueNumber(from token: String) -> GitHubReferenceQuery? {
        let parts = token.split(separator: "#", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let number = Int(parts[1]),
              self.isRepositoryName(parts[0])
        else { return nil }

        return .repositoryNameIssueNumber(repositoryName: parts[0], number: number)
    }

    static func compoundRepositoryIssueQueries(from token: String) -> [GitHubReferenceQuery] {
        let parts = token.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              self.isRepositoryFullName(parts[0]),
              parts[1].contains("/") || parts[1].contains("-")
        else { return [] }

        let numberParts = parts[1]
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard numberParts.isEmpty == false else { return [] }

        var numbers: [Int] = []
        for numberPart in numberParts {
            guard let parsedNumbers = self.issueNumbers(fromSeriesPart: numberPart)
            else { return [] }

            numbers.append(contentsOf: parsedNumbers)
        }
        guard (1 ... Self.maxIssueSeriesCount).contains(numbers.count) else { return [] }

        return numbers.map { .repositoryIssueNumber(repositoryFullName: parts[0], number: $0) }
    }

    private static func issueNumbers(fromSeriesPart rawPart: String) -> [Int]? {
        let part = rawPart.hasPrefix("#") ? String(rawPart.dropFirst()) : rawPart
        guard part.isEmpty == false else { return nil }

        let rangeParts = part
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        if rangeParts.count == 2 {
            guard let start = self.issueSeriesNumber(from: rangeParts[0]),
                  let end = self.issueSeriesNumber(from: rangeParts[1]),
                  start <= end
            else { return nil }

            return Array(start ... end)
        }

        guard let number = self.issueSeriesNumber(from: part) else { return nil }

        return [number]
    }

    static func compoundBareIssueQueries(from token: String) -> [GitHubReferenceQuery] {
        guard token.hasPrefix("#"),
              token.contains("/") || token.contains("-")
        else { return [] }

        let numberParts = token
            .split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard numberParts.isEmpty == false else { return [] }

        var numbers: [Int] = []
        for numberPart in numberParts {
            guard let parsedNumbers = self.issueNumbers(fromSeriesPart: numberPart)
            else { return [] }

            numbers.append(contentsOf: parsedNumbers)
        }
        guard (1 ... Self.maxIssueSeriesCount).contains(numbers.count) else { return [] }

        return numbers.map { .issueNumber($0) }
    }

    private static func issueSeriesNumber(from rawNumber: String) -> Int? {
        let normalized = rawNumber.hasPrefix("#") ? String(rawNumber.dropFirst()) : rawNumber
        guard normalized.isEmpty == false,
              normalized.allSatisfy(\.isNumber)
        else { return nil }

        return Int(normalized)
    }

    static func isRepositoryFullName(_ value: String) -> Bool {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }

        return parts.allSatisfy { part in
            part.isEmpty == false && part.allSatisfy { character in
                character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
            }
        }
    }

    private static func isRepositoryName(_ value: String) -> Bool {
        value.isEmpty == false && value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" || character == "."
        }
    }

    static func repositoryContext(in text: String) -> String? {
        var repositoryFullNames: [String] = []
        var seen: Set<String> = []

        func append(_ repositoryFullName: String) {
            guard seen.insert(repositoryFullName.lowercased()).inserted else { return }

            repositoryFullNames.append(repositoryFullName)
        }

        var sawPrimaryListReference = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let lineHasPrimaryListReference = self.startsWithPrimaryListReference(in: line)
            let lineScopedRepositories = Set(
                self.lineScopedRepositoryIssueQueries(inLine: line, minimumBareDigits: 1)
                    .compactMap(\.repositoryFullName)
                    .map { $0.lowercased() }
            )
            let tokens = self.referenceTokens(in: line)
            for (index, token) in tokens.enumerated() {
                let isProseRepositoryContext = token.contains("#") == false
                    && sawPrimaryListReference == false
                    && lineHasPrimaryListReference == false
                    && self.isRepositoryFullName(token)
                    && lineScopedRepositories.contains(token.lowercased()) == false
                    && self.isLikelyRepositoryContextToken(at: index, in: tokens)
                if isProseRepositoryContext {
                    append(token)
                    continue
                }
                if let repositoryFullName = self.urlQuery(from: token)?.repositoryFullName {
                    append(repositoryFullName)
                    continue
                }
                if let repositoryFullName = self.repositoryIssueNumber(from: token)?.repositoryFullName {
                    append(repositoryFullName)
                }
            }
            if lineHasPrimaryListReference {
                sawPrimaryListReference = true
            }
        }

        return repositoryFullNames.count == 1 ? repositoryFullNames[0] : nil
    }

    private static func startsWithPrimaryListReference(in line: String) -> Bool {
        guard let body = self.listItemBody(in: line),
              let firstToken = self.referenceTokens(in: body).first
        else { return false }

        if self.urlQuery(from: firstToken) != nil {
            return true
        }
        if self.compoundBareIssueQueries(from: firstToken).isEmpty == false {
            return true
        }
        if self.compoundRepositoryIssueQueries(from: firstToken).isEmpty == false {
            return true
        }
        return self.tokenQuery(
            from: firstToken,
            minimumBareDigits: 1,
            allowBareIssueNumber: false,
            allowNumericCommitHash: self.hasCommitContext(line)
        ) != nil
    }

    static func listItemRepositoryContext(in text: String) -> String? {
        let repositories = text
            .split(whereSeparator: \.isNewline)
            .compactMap { self.listItemBody(in: String($0)) }
            .compactMap { body -> String? in
                let tokens = self.referenceTokens(in: body)
                guard tokens.count == 1,
                      let repositoryFullName = tokens.first,
                      self.isRepositoryFullName(repositoryFullName)
                else { return nil }

                return repositoryFullName
            }

        var uniqueRepositories: [String] = []
        var seen: Set<String> = []
        for repository in repositories {
            guard seen.insert(repository.lowercased()).inserted else { continue }

            uniqueRepositories.append(repository)
        }

        return uniqueRepositories.count == 1 ? uniqueRepositories[0] : nil
    }

    private static func isLikelyRepositoryContextToken(at index: Int, in tokens: [String]) -> Bool {
        guard tokens.indices.contains(index) else { return false }
        guard index > 0 else { return true }

        let previous = tokens[index - 1].lowercased()
        return ["in", "repo", "repository", "from", "for", "on", "inside"].contains(previous)
    }

    static func hasIssueReferenceContext(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let tokens = self.referenceTokens(in: normalized)
        if tokens.contains(where: { ["pr", "prs", "issue", "issues"].contains($0) }) {
            return true
        }

        return normalized.contains("pull request")
            || normalized.contains("security fix")
            || normalized.contains("fix/enhancement")
    }

    static func isIssueCountSummary(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains(":") else { return false }

        let tokens = self.referenceTokens(in: normalized)
        guard tokens.count >= 2,
              ["open", "closed"].contains(tokens[0]),
              ["prs", "issues"].contains(tokens[1])
        else { return false }

        if tokens.dropFirst(2).contains(where: { token in
            self.issueNumber(from: token, minimumBareDigits: 1, allowBareNumber: false) != nil
        }) {
            return false
        }

        let bareNumbers = tokens.dropFirst(2).compactMap { token in
            self.issueNumber(from: token, minimumBareDigits: 1, allowBareNumber: true)
        }
        return bareNumbers.count <= 1
    }

    private static func startsWithBackReference(_ text: String) -> Bool {
        guard let firstToken = self.referenceTokens(in: text).first?.lowercased() else { return false }

        return ["that", "this", "it", "they", "these", "those"].contains(firstToken)
    }

    static func applyingRepositoryContext(_ repositoryFullName: String?, to query: GitHubReferenceQuery) -> GitHubReferenceQuery {
        guard let repositoryFullName else { return query }

        switch query {
        case let .issueNumber(number):
            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case let .repositoryNameIssueNumber(repositoryName, number):
            guard repositoryFullName.split(separator: "/").last?.caseInsensitiveCompare(repositoryName) == .orderedSame else {
                return query
            }

            return .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
        case let .commitHash(hash):
            return .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
        case .repositoryIssueNumber, .repositoryCommitHash, .repositoryWorkflowRun:
            return query
        }
    }

    private static func normalizedToken(from rawToken: String) -> String {
        rawToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}<>\"'`"))
    }

    static func referenceTokens(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .map(self.normalizedToken)
            .filter { $0.isEmpty == false }
    }

    private static func hasCommitContext(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("sha") || normalized.contains("commit") || normalized.contains("hash")
    }

    static func dedupeKey(for query: GitHubReferenceQuery) -> String {
        switch query {
        case let .issueNumber(number):
            "issue:\(number)"
        case let .repositoryNameIssueNumber(repositoryName, number):
            "repo-name:\(repositoryName.lowercased())#\(number)"
        case let .repositoryIssueNumber(repositoryFullName, number):
            "repo:\(repositoryFullName.lowercased())#\(number)"
        case let .commitHash(hash):
            "commit:\(hash.lowercased())"
        case let .repositoryCommitHash(repositoryFullName, hash):
            "repo:\(repositoryFullName.lowercased())@\(hash.lowercased())"
        case let .repositoryWorkflowRun(repositoryFullName, runID):
            "repo:\(repositoryFullName.lowercased())/run/\(runID)"
        }
    }

    static func dedupedQueries(_ queries: [GitHubReferenceQuery]) -> [GitHubReferenceQuery] {
        var seen: Set<String> = []
        return queries.filter { seen.insert(self.dedupeKey(for: $0)).inserted }
    }

    private static func isCommitHash(_ token: String, allowNumericOnly: Bool) -> Bool {
        guard (7 ... 40).contains(token.count) else { return false }
        guard token.allSatisfy(\.isHexDigit) else { return false }
        guard allowNumericOnly || token.contains(where: \.isLetter) else { return false }

        return true
    }
}
