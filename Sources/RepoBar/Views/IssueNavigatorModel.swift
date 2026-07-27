import Algorithms
import AppKit
import Observation
import RepoBarCore

private struct IssueNavigatorAISummary {
    let signature: String
    let text: String
}

@MainActor
@Observable
final class IssueNavigatorModel {
    struct PlatformActions {
        var readClipboard: () -> String?
        var openURL: (URL) -> Void
        var copyURL: (URL) -> Void

        @MainActor static let live = PlatformActions(
            readClipboard: {
                NSPasteboard.general.string(forType: .string)
            },
            openURL: { url in
                _ = NSWorkspace.shared.open(url)
            },
            copyURL: { url in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
        )
    }

    var searchText = ""
    var kindFilter: IssueNavigatorKindFilter = .all
    var selectedScope = IssueNavigatorScope.all
    var results: [GitHubReferenceMatch]
    var selectedURL: URL?
    var isSearching = false
    var statusText: String
    var errorText: String?
    var browserNavigationVersion = 0

    private(set) var clipboardText: String?
    private(set) var clipboardQueries: [GitHubReferenceQuery] = []
    let browserStore: IssueNavigatorBrowserStore
    private let appState: AppState
    private let platform: PlatformActions
    private var searchTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var aiSummariesByURL: [URL: IssueNavigatorAISummary] = [:]
    private var searchGeneration = UUID()

    init(
        appState: AppState,
        initialMatches: [GitHubReferenceMatch],
        browserStore: IssueNavigatorBrowserStore,
        platform: PlatformActions = .live
    ) {
        let matches = initialMatches.issueNavigatorOrderPreservingDeduped()
        self.appState = appState
        self.browserStore = browserStore
        self.platform = platform
        self.results = matches
        self.selectedURL = matches.first?.url
        self.statusText = matches.isEmpty ? "Loading recent issues and pull requests." : "References in pasted order"
    }

    var scopes: [IssueNavigatorScope] {
        [.all] + self.appState.gitHubReferenceRepositories().map {
            IssueNavigatorScope(fullName: $0.fullName, title: $0.fullName)
        }
    }

    var selectedMatch: GitHubReferenceMatch? {
        guard let selectedURL else { return self.results.first }

        return self.results.first { $0.url == selectedURL } ?? self.results.first
    }

    var shouldShowClipboardPrompt: Bool {
        guard let clipboardText else { return false }

        return self.clipboardQueries.isEmpty == false && clipboardText != self.searchText
    }

    var clipboardDisplayText: String {
        self.clipboardQueries.map(\.displayText).joined(separator: ", ")
    }

    var statusLine: String {
        if self.isSearching {
            return "Searching…"
        }
        if let errorText {
            return errorText
        }
        return self.statusText
    }

    func start(seedClipboard: Bool) {
        self.browserStore.onNavigationStateChange = { [weak self] in
            self?.browserNavigationVersion &+= 1
        }
        self.updateClipboard(seedIfEmpty: seedClipboard)
        if self.results.isEmpty {
            self.scheduleSearch(immediate: true)
        } else {
            self.preloadPreviews(for: self.results)
            self.scheduleAISummaries(for: self.results, generation: self.searchGeneration)
        }
    }

    func stop() {
        self.searchGeneration = UUID()
        self.searchTask?.cancel()
        self.searchTask = nil
        self.summaryTask?.cancel()
        self.summaryTask = nil
        self.browserStore.onNavigationStateChange = nil
        self.browserStore.clear()
    }

    func aiSummarySettingsDidChange(_ settings: AISummarySettings) {
        self.summaryTask?.cancel()
        self.aiSummariesByURL = [:]
        if settings.enabled {
            self.scheduleAISummaries(for: self.results, generation: self.searchGeneration)
        }
    }

    func submitSearch() {
        if let selectedMatch {
            self.open(selectedMatch)
        } else {
            self.scheduleSearch(immediate: true)
        }
    }

    func scheduleSearch(immediate: Bool = false) {
        let generation = UUID()
        self.searchGeneration = generation
        self.searchTask?.cancel()
        self.summaryTask?.cancel()
        self.searchTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }

            await self?.performSearch(generation: generation)
        }
    }

    func updateClipboard(seedIfEmpty: Bool) {
        let text = self.platform.readClipboard()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, text.isEmpty == false else {
            self.clipboardText = nil
            self.clipboardQueries = []
            return
        }

        let queries = GitHubReferenceTranslator.queries(
            from: text,
            minimumBareDigits: AppLimits.GitHubReferenceMonitor.minimumBareDigits
        )
        self.clipboardText = text
        self.clipboardQueries = queries
        if seedIfEmpty, self.searchText.isEmpty, queries.isEmpty == false {
            self.searchText = text
        }
    }

    func useClipboard() {
        guard let clipboardText else { return }

        self.searchText = clipboardText
        self.scheduleSearch(immediate: true)
    }

    func displayMatch(_ match: GitHubReferenceMatch) -> GitHubReferenceMatch {
        let settings = self.appState.session.settings.aiSummaries
        guard settings.enabled,
              let summary = self.aiSummariesByURL[match.url],
              summary.signature == Self.aiSummarySignature(for: match, settings: settings)
        else { return match }

        return match.withAISummary(summary.text)
    }

    func select(_ match: GitHubReferenceMatch) {
        if self.selectedURL == match.url {
            self.browserStore.reloadInitialURL(match.url)
        }
        self.selectedURL = match.url
    }

    func ensureSelection() {
        guard self.selectedURL == nil, let first = self.results.first else { return }

        self.selectedURL = first.url
    }

    func open(_ match: GitHubReferenceMatch) {
        self.platform.openURL(match.url)
    }

    func openSelected() {
        if let selectedMatch {
            self.open(selectedMatch)
        }
    }

    func copy(_ match: GitHubReferenceMatch) {
        self.platform.copyURL(match.url)
    }

    func copySelected() {
        if let selectedMatch {
            self.copy(selectedMatch)
        }
    }

    func isCurrentSearch(_ generation: UUID) -> Bool {
        !Task.isCancelled && self.searchGeneration == generation
    }

    private func performSearch(generation: UUID) async {
        guard self.isCurrentSearch(generation) else { return }

        let trimmed = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedRepository = self.selectedScope.fullName
        let queries = GitHubReferenceTranslator.queries(
            from: trimmed,
            minimumBareDigits: AppLimits.GitHubReferenceMonitor.minimumBareDigits,
            repositoryContextOverride: selectedRepository
        )
        let canRunTextSearch = queries.isEmpty &&
            (selectedRepository != nil || trimmed.count >= AppLimits.IssueNavigator.minimumSearchCharacters)
        if trimmed.isEmpty || (queries.isEmpty && !canRunTextSearch) {
            self.isSearching = true
            self.errorText = nil
            defer {
                if self.isCurrentSearch(generation) {
                    self.isSearching = false
                }
            }

            do {
                let matches = try await self.appState.recentIssueReferences(
                    repositoryFullName: selectedRepository,
                    includeIssues: self.kindFilter.includeIssues,
                    includePullRequests: self.kindFilter.includePullRequests
                )
                guard self.isCurrentSearch(generation) else { return }

                self.results = matches
                self.selectedURL = matches.first?.url
                self.preloadPreviews(for: matches)
                self.scheduleAISummaries(for: matches, generation: generation)
                if matches.isEmpty {
                    self.statusText = "No recent issues or pull requests in this scope."
                } else if trimmed.isEmpty {
                    self.statusText = "Recent subscribed and accessible items"
                } else {
                    self.statusText = "Showing recent items; type at least \(AppLimits.IssueNavigator.minimumSearchCharacters) characters to search."
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isCurrentSearch(generation) else { return }

                self.results = []
                self.selectedURL = nil
                self.errorText = error.userFacingMessage
            }
            return
        }

        guard queries.isEmpty == false || canRunTextSearch else {
            guard self.isCurrentSearch(generation) else { return }

            self.results = []
            self.selectedURL = nil
            self.statusText = "Type at least \(AppLimits.IssueNavigator.minimumSearchCharacters) characters, or paste a GitHub reference."
            self.errorText = nil
            return
        }

        self.isSearching = true
        self.errorText = nil
        defer {
            if self.isCurrentSearch(generation) {
                self.isSearching = false
            }
        }

        do {
            async let referenceMatches = self.appState.resolveGitHubReferenceQueries(queries, sourceText: trimmed)
            async let textMatches: [GitHubReferenceMatch] = canRunTextSearch
                ? self.appState.searchIssueReferences(
                    matching: trimmed,
                    repositoryFullName: selectedRepository,
                    includeIssues: self.kindFilter.includeIssues,
                    includePullRequests: self.kindFilter.includePullRequests
                )
                : []

            let resolvedReferenceMatches = await referenceMatches
            let searchedTextMatches = try await textMatches
            guard self.isCurrentSearch(generation) else { return }

            let filteredReferenceMatches = resolvedReferenceMatches.filter { self.kindFilter.matches($0.kind) }
            let combined = queries.isEmpty
                ? Self.deduped(filteredReferenceMatches + searchedTextMatches)
                : (filteredReferenceMatches + searchedTextMatches).issueNavigatorOrderPreservingDeduped()
            self.results = combined
            self.selectedURL = combined.first?.url
            self.preloadPreviews(for: combined)
            self.scheduleAISummaries(for: combined, generation: generation)
            self.statusText = self.status(for: combined, searchedText: trimmed, preservesReferenceOrder: queries.isEmpty == false)
        } catch is CancellationError {
            return
        } catch {
            guard self.isCurrentSearch(generation) else { return }

            self.results = []
            self.selectedURL = nil
            self.errorText = error.userFacingMessage
        }
    }

    private func preloadPreviews(for matches: [GitHubReferenceMatch]) {
        self.browserStore.preload(
            matches
                .prefix(AppLimits.IssueNavigator.webPreviewPreloadLimit)
                .map(\.url)
        )
    }

    private func scheduleAISummaries(for matches: [GitHubReferenceMatch], generation: UUID) {
        self.summaryTask?.cancel()
        let urls = Set(matches.map(\.url))
        self.aiSummariesByURL = self.aiSummariesByURL.filter { urls.contains($0.key) }

        let settings = self.appState.session.settings.aiSummaries
        guard settings.enabled else {
            self.aiSummariesByURL = [:]
            return
        }

        let pending = matches.filter {
            $0.isResolved
                && self.aiSummariesByURL[$0.url]?.signature != Self.aiSummarySignature(for: $0, settings: settings)
        }
        guard pending.isEmpty == false else { return }

        self.summaryTask = Task { [weak self] in
            await self?.loadAISummaries(for: pending, settings: settings, generation: generation)
        }
    }

    private func loadAISummaries(for matches: [GitHubReferenceMatch], settings: AISummarySettings, generation: UUID) async {
        let summarizer = PullRequestAISummarizer()
        for chunk in matches.chunks(ofCount: AppLimits.IssueNavigator.aiSummaryConcurrencyLimit) {
            guard self.isCurrentSearch(generation),
                  self.appState.session.settings.aiSummaries == settings,
                  settings.enabled
            else { return }

            await withTaskGroup(of: (url: URL, signature: String, summary: String?).self) { group in
                for match in chunk {
                    let signature = Self.aiSummarySignature(for: match, settings: settings)
                    group.addTask {
                        let summary = try? await summarizer.summarize(match, settings: settings)
                        return (match.url, signature, summary)
                    }
                }

                for await (url, signature, summary) in group {
                    guard self.isCurrentSearch(generation),
                          self.appState.session.settings.aiSummaries == settings,
                          settings.enabled
                    else {
                        group.cancelAll()
                        return
                    }

                    if let summary {
                        self.aiSummariesByURL[url] = IssueNavigatorAISummary(signature: signature, text: summary)
                    }
                }
            }
        }
    }

    private static func aiSummarySignature(for match: GitHubReferenceMatch, settings: AISummarySettings) -> String {
        [
            settings.model,
            match.updatedAt.timeIntervalSinceReferenceDate.description,
            match.title,
            match.bodyPreview ?? "",
            match.authorLogin ?? ""
        ].joined(separator: "\u{1f}")
    }

    private static func deduped(_ matches: [GitHubReferenceMatch]) -> [GitHubReferenceMatch] {
        var seen: Set<URL> = []
        return matches
            .filter { seen.insert($0.url).inserted }
            .sorted {
                if $0.updatedAt != $1.updatedAt {
                    return $0.updatedAt > $1.updatedAt
                }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    private func status(
        for matches: [GitHubReferenceMatch],
        searchedText: String,
        preservesReferenceOrder: Bool = false
    ) -> String {
        if matches.isEmpty {
            searchedText.isEmpty ? "No recent items in this scope." : "No matching issues or pull requests."
        } else if preservesReferenceOrder {
            "References in pasted order"
        } else {
            "Updated newest first"
        }
    }
}
