import Algorithms
import AppKit
import RepoBarCore
import SwiftUI

// swiftlint:disable file_length

private struct IssueNavigatorAISummary {
    let signature: String
    let text: String
}

struct IssueNavigatorView: View {
    private enum Metrics {
        static let sidebarMinWidth: CGFloat = 340
        static let sidebarIdealWidth: CGFloat = 390
        static let sidebarMaxWidth: CGFloat = 430
        static let sidebarPadding: CGFloat = 14
        static let controlHeight: CGFloat = 28
        static let controlCornerRadius: CGFloat = 10
    }

    let appState: AppState
    @State private var searchText = ""
    @State private var kindFilter: IssueNavigatorKindFilter = .all
    @State private var selectedScope = IssueNavigatorScope.all
    @State private var results: [GitHubReferenceMatch] = []
    @State private var selectedURL: URL?
    @State private var isSearching = false
    @State private var statusText = "Loading recent issues and pull requests."
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var summaryTask: Task<Void, Never>?
    @State private var aiSummariesByURL: [URL: IssueNavigatorAISummary] = [:]
    @State private var searchGeneration = UUID()
    @State private var clipboardText: String?
    @State private var clipboardQueries: [GitHubReferenceQuery] = []
    @State private var browserNavigationVersion = 0
    private let browserStore: IssueNavigatorBrowserStore

    private var repositories: [Repository] {
        self.appState.gitHubReferenceRepositories()
    }

    private var scopes: [IssueNavigatorScope] {
        [.all] + self.repositories.map { IssueNavigatorScope(fullName: $0.fullName, title: $0.fullName) }
    }

    private var selectedMatch: GitHubReferenceMatch? {
        guard let selectedURL else { return self.results.first }

        return self.results.first { $0.url == selectedURL } ?? self.results.first
    }

    init(
        appState: AppState,
        initialMatches: [GitHubReferenceMatch] = [],
        browserStore: IssueNavigatorBrowserStore
    ) {
        let matches = initialMatches.issueNavigatorOrderPreservingDeduped()
        self.appState = appState
        self.browserStore = browserStore
        self._results = State(initialValue: matches)
        self._selectedURL = State(initialValue: matches.first?.url)
        self._statusText = State(initialValue: matches.isEmpty ? "Loading recent issues and pull requests." : "References in pasted order")
    }

    var body: some View {
        IssueNavigatorSplitView(
            sidebarMinWidth: Metrics.sidebarMinWidth,
            sidebarIdealWidth: Metrics.sidebarIdealWidth,
            sidebarMaxWidth: Metrics.sidebarMaxWidth
        ) {
            self.sidebar
        } detail: {
            self.previewPane
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 980, minHeight: 620)
        .onAppear {
            self.browserStore.onNavigationStateChange = {
                self.browserNavigationVersion &+= 1
            }
            self.updateClipboard(seedIfEmpty: Self.shouldSeedClipboardOnAppear(hasInitialMatches: self.results.isEmpty == false))
            if self.results.isEmpty {
                self.scheduleSearch(immediate: true)
            } else {
                self.preloadPreviews(for: self.results)
                self.scheduleAISummaries(for: self.results, generation: self.searchGeneration)
            }
        }
        .onDisappear {
            self.searchGeneration = UUID()
            self.searchTask?.cancel()
            self.summaryTask?.cancel()
            self.browserStore.onNavigationStateChange = nil
            self.browserStore.clear()
        }
        .onReceive(
            Timer.publish(every: 1, tolerance: 0.25, on: .main, in: .common).autoconnect()
        ) { _ in
            self.updateClipboard(seedIfEmpty: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorUseClipboard)) { _ in
            self.useClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorRefresh)) { _ in
            self.scheduleSearch(immediate: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorCopy)) { _ in
            if let match = self.selectedMatch {
                self.copy(match)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorOpen)) { _ in
            if let match = self.selectedMatch {
                self.open(match)
            }
        }
        .onChange(of: self.searchText) { _, _ in self.scheduleSearch() }
        .onChange(of: self.kindFilter) { _, _ in self.scheduleSearch(immediate: true) }
        .onChange(of: self.selectedScope) { _, _ in self.scheduleSearch(immediate: true) }
        .onChange(of: self.appState.session.settings.aiSummaries) { _, settings in
            self.summaryTask?.cancel()
            self.aiSummariesByURL = [:]
            if settings.enabled {
                self.scheduleAISummaries(for: self.results, generation: self.searchGeneration)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            self.sidebarControls
            self.resultPane
        }
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
    }

    private var sidebarControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            IssueNavigatorSearchField(
                text: self.$searchText,
                placeholder: "Search issues and pull requests",
                onSubmit: {
                    if let match = self.selectedMatch {
                        self.open(match)
                    } else {
                        self.scheduleSearch(immediate: true)
                    }
                }
            )
            .frame(height: Metrics.controlHeight)

            HStack(spacing: 8) {
                IssueNavigatorScopePopUp(selection: self.$selectedScope, scopes: self.scopes)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.controlHeight)

                if self.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            IssueNavigatorKindSegmentedControl(selection: self.$kindFilter)
                .frame(height: Metrics.controlHeight)

            if self.shouldShowClipboardPrompt {
                Button {
                    self.useClipboard()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Clipboard: \(self.clipboardDisplayText)")
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.turn.down.left")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 11)
                .frame(height: Metrics.controlHeight)
                .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22))
                )
            }

            Text(self.statusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Metrics.sidebarPadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                IssueNavigatorCountBadge(count: self.results.count)
                Spacer()
                Text("Updated newest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Metrics.sidebarPadding)
            .padding(.top, 2)
            .padding(.bottom, 10)

            if let errorText {
                self.sidebarMessage(
                    title: "Search failed",
                    message: errorText,
                    systemImage: "exclamationmark.triangle"
                )
            } else if self.results.isEmpty {
                self.sidebarMessage(
                    title: "No matches",
                    message: self.statusText,
                    systemImage: "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(self.results, id: \.url) { match in
                            IssueNavigatorResultRow(
                                match: self.displayMatch(match),
                                now: Date(),
                                isSelected: self.selectedURL == match.url,
                                onOpen: { self.open(match) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.select(match)
                            }
                            .contextMenu {
                                Button("Open in Browser") { self.open(match) }
                                Button("Copy URL") { self.copy(match) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
                }
                .onChange(of: self.selectedURL) { _, newValue in
                    guard newValue == nil, let first = self.results.first else { return }

                    self.selectedURL = first.url
                }
            }
        }
    }

    private func sidebarMessage(title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 68)
            .padding(.bottom, 20)

            Spacer(minLength: 0)
        }
    }

    private var previewPane: some View {
        Group {
            if let match = self.selectedMatch {
                VStack(spacing: 0) {
                    self.previewHeader(for: match)
                    IssueNavigatorBrowserPreview(url: match.url, store: self.browserStore)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(.tertiary)
                    Text("Pick a result")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Search by title, URL, owner/repo#number, or commit SHA.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .padding(26)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func previewHeader(for match: GitHubReferenceMatch) -> some View {
        let canGoBack = self.browserStore.canGoBack(match.url)

        return HStack(spacing: 12) {
            Button {
                self.browserStore.goBack(match.url)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoBack)
            .help("Back")

            ZStack {
                Circle()
                    .fill(self.tint(for: match).opacity(0.16))
                Image(systemName: self.symbolName(for: match))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(self.tint(for: match))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(match.issueNavigatorHeaderTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(match.repositoryFullName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(match.query.displayText)
                    if let state = match.state?.label {
                        Text(state)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .id(self.browserNavigationVersion)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var shouldShowClipboardPrompt: Bool {
        guard let clipboardText else { return false }

        return self.clipboardQueries.isEmpty == false && clipboardText != self.searchText
    }

    private var clipboardDisplayText: String {
        self.clipboardQueries.map(\.displayText).joined(separator: ", ")
    }

    private var statusLine: String {
        if self.isSearching { return "Searching…" }
        if let errorText { return errorText }
        return self.statusText
    }

    private func scheduleSearch(immediate: Bool = false) {
        let generation = UUID()
        self.searchGeneration = generation
        self.searchTask?.cancel()
        self.summaryTask?.cancel()
        self.searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }

            await self.performSearch(generation: generation)
        }
    }

    nonisolated static func shouldSeedClipboardOnAppear(hasInitialMatches: Bool) -> Bool {
        !hasInitialMatches
    }

    @MainActor
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

    func isCurrentSearch(_ generation: UUID) -> Bool {
        !Task.isCancelled && self.searchGeneration == generation
    }

    private func updateClipboard(seedIfEmpty: Bool) {
        let text = NSPasteboard.general.string(forType: .string)?
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

    private func useClipboard() {
        guard let clipboardText else { return }

        self.searchText = clipboardText
        self.scheduleSearch(immediate: true)
    }

    private func preloadPreviews(for matches: [GitHubReferenceMatch]) {
        self.browserStore.preload(
            matches
                .prefix(AppLimits.IssueNavigator.webPreviewPreloadLimit)
                .map(\.url)
        )
    }

    private func displayMatch(_ match: GitHubReferenceMatch) -> GitHubReferenceMatch {
        let settings = self.appState.session.settings.aiSummaries
        guard settings.enabled,
              let summary = self.aiSummariesByURL[match.url],
              summary.signature == Self.aiSummarySignature(for: match, settings: settings)
        else { return match }

        return match.withAISummary(summary.text)
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
            $0.kind == .pullRequest && self.aiSummariesByURL[$0.url]?.signature != Self.aiSummarySignature(for: $0, settings: settings)
        }
        guard pending.isEmpty == false else { return }

        self.summaryTask = Task {
            await self.loadAISummaries(for: pending, settings: settings, generation: generation)
        }
    }

    @MainActor
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
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    private func select(_ match: GitHubReferenceMatch) {
        if self.selectedURL == match.url {
            self.browserStore.reloadInitialURL(match.url)
        }
        self.selectedURL = match.url
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

    private func open(_ match: GitHubReferenceMatch) {
        NSWorkspace.shared.open(match.url)
    }

    private func copy(_ match: GitHubReferenceMatch) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(match.url.absoluteString, forType: .string)
    }

    private func symbolName(for match: GitHubReferenceMatch) -> String {
        switch match.kind {
        case .issue:
            match.state == .closed ? "checkmark.circle" : "exclamationmark.circle"
        case .pullRequest:
            switch match.state {
            case .merged: "arrow.triangle.merge"
            case .closed: "xmark.circle"
            case .open, nil: "arrow.triangle.pull"
            }
        case .commit:
            "number.square"
        case .workflowRun:
            "play.circle"
        }
    }

    private func tint(for match: GitHubReferenceMatch) -> Color {
        switch match.kind {
        case .issue:
            match.state == .closed ? .purple : .green
        case .pullRequest:
            match.state == .merged ? .purple : (match.state == .closed ? .red : .green)
        case .commit, .workflowRun:
            .secondary
        }
    }
}

private struct IssueNavigatorResultRow: View {
    let match: GitHubReferenceMatch
    let now: Date
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: self.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(self.iconForeground)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.match.issueNavigatorTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(self.primaryForeground)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(self.match.repositoryFullName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let state = match.state?.label {
                        Text(state)
                    }
                    Text(RelativeFormatter.string(from: self.match.updatedAt, relativeTo: self.now))
                }
                .font(.caption)
                .foregroundStyle(self.secondaryForeground)
                let summary = self.match.aiSummary ?? self.match.bodyPreview
                if let summary, summary.isEmpty == false {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(self.secondaryForeground)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(self.rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture(count: 2, perform: self.onOpen)
    }

    private var symbolName: String {
        switch self.match.kind {
        case .issue:
            self.match.state == .closed ? "checkmark.circle" : "exclamationmark.circle"
        case .pullRequest:
            switch self.match.state {
            case .merged: "arrow.triangle.merge"
            case .closed: "xmark.circle"
            case .open, nil: "arrow.triangle.branch.circle"
            }
        case .commit:
            "number.square"
        case .workflowRun:
            "play.circle"
        }
    }

    private var tint: Color {
        switch self.match.kind {
        case .issue:
            self.match.state == .closed ? .purple : .green
        case .pullRequest:
            self.match.state == .merged ? .purple : (self.match.state == .closed ? .red : .green)
        case .commit, .workflowRun:
            .secondary
        }
    }

    private var primaryForeground: Color {
        self.isSelected ? .white : .primary
    }

    private var secondaryForeground: Color {
        self.isSelected ? Color.white.opacity(0.76) : .secondary
    }

    private var iconForeground: Color {
        self.isSelected ? Color.white.opacity(0.92) : self.tint
    }

    private var rowBackground: Color {
        self.isSelected ? Color.accentColor.opacity(0.86) : .clear
    }
}

private struct IssueNavigatorCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Text("\(self.count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(self.count == 1 ? "match" : "matches")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
    }
}

private struct IssueNavigatorSplitView<Sidebar: View, Detail: View>: NSViewRepresentable {
    let sidebarMinWidth: CGFloat
    let sidebarIdealWidth: CGFloat
    let sidebarMaxWidth: CGFloat
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sidebarMinWidth: self.sidebarMinWidth,
            sidebarIdealWidth: self.sidebarIdealWidth,
            sidebarMaxWidth: self.sidebarMaxWidth
        )
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = IssueNavigatorNSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let sidebarHost = NSHostingView(rootView: self.sidebar())
        sidebarHost.translatesAutoresizingMaskIntoConstraints = false
        sidebarHost.wantsLayer = false
        let detailHost = NSHostingView(rootView: self.detail())
        detailHost.translatesAutoresizingMaskIntoConstraints = false
        detailHost.wantsLayer = false

        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost

        splitView.addArrangedSubview(sidebarHost)
        splitView.addArrangedSubview(detailHost)
        sidebarHost.widthAnchor.constraint(greaterThanOrEqualToConstant: self.sidebarMinWidth).isActive = true
        sidebarHost.widthAnchor.constraint(lessThanOrEqualToConstant: self.sidebarMaxWidth).isActive = true
        detailHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 560).isActive = true
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(240), forSubviewAt: 0)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(230), forSubviewAt: 1)

        DispatchQueue.main.async {
            splitView.setPosition(self.sidebarIdealWidth, ofDividerAt: 0)
        }

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        context.coordinator.sidebarMinWidth = self.sidebarMinWidth
        context.coordinator.sidebarIdealWidth = self.sidebarIdealWidth
        context.coordinator.sidebarMaxWidth = self.sidebarMaxWidth
        context.coordinator.sidebarHost?.rootView = self.sidebar()
        context.coordinator.detailHost?.rootView = self.detail()

        if splitView.frame.width > 0, splitView.subviews.first?.frame.width == 0 {
            splitView.setPosition(self.sidebarIdealWidth, ofDividerAt: 0)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        var sidebarMinWidth: CGFloat
        var sidebarIdealWidth: CGFloat
        var sidebarMaxWidth: CGFloat
        var sidebarHost: NSHostingView<Sidebar>?
        var detailHost: NSHostingView<Detail>?

        init(sidebarMinWidth: CGFloat, sidebarIdealWidth: CGFloat, sidebarMaxWidth: CGFloat) {
            self.sidebarMinWidth = sidebarMinWidth
            self.sidebarIdealWidth = sidebarIdealWidth
            self.sidebarMaxWidth = sidebarMaxWidth
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt _: Int
        ) -> CGFloat {
            let maximum = min(self.sidebarMaxWidth, splitView.bounds.width - 560 - splitView.dividerThickness)
            return min(max(proposedPosition, self.sidebarMinWidth), maximum)
        }
    }
}

private final class IssueNavigatorNSSplitView: NSSplitView {
    override var dividerThickness: CGFloat {
        1
    }

    override func drawDivider(in rect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        rect.fill()
    }
}

private struct IssueNavigatorSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: self.$text, onSubmit: self.onSubmit)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = self.placeholder
        field.controlSize = .regular
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = self.$text
        context.coordinator.onSubmit = self.onSubmit
        if field.stringValue != self.text {
            field.stringValue = self.text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }

            self.text.wrappedValue = field.stringValue
        }

        func control(
            _: NSControl,
            textView _: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }

            self.onSubmit()
            return true
        }
    }
}

private struct IssueNavigatorScopePopUp: NSViewRepresentable {
    @Binding var selection: IssueNavigatorScope
    let scopes: [IssueNavigatorScope]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: self.$selection, scopes: self.scopes)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .regular
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.select(_:))
        context.coordinator.configure(popup)
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.selection = self.$selection
        context.coordinator.scopes = self.scopes
        context.coordinator.configure(popup)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<IssueNavigatorScope>
        var scopes: [IssueNavigatorScope]

        init(selection: Binding<IssueNavigatorScope>, scopes: [IssueNavigatorScope]) {
            self.selection = selection
            self.scopes = scopes
        }

        func configure(_ popup: NSPopUpButton) {
            let representedIDs = popup.itemArray.compactMap { $0.representedObject as? String }
            let scopeIDs = self.scopes.map(\.id)
            if representedIDs != scopeIDs {
                popup.removeAllItems()
                for scope in self.scopes {
                    popup.addItem(withTitle: scope.title)
                    popup.lastItem?.representedObject = scope.id
                }
            }
            if let index = self.scopes.firstIndex(of: self.selection.wrappedValue) {
                popup.selectItem(at: index)
            }
        }

        @objc func select(_ popup: NSPopUpButton) {
            let index = popup.indexOfSelectedItem
            guard self.scopes.indices.contains(index) else { return }

            self.selection.wrappedValue = self.scopes[index]
        }
    }
}

private struct IssueNavigatorKindSegmentedControl: NSViewRepresentable {
    @Binding var selection: IssueNavigatorKindFilter

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: self.$selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: IssueNavigatorKindFilter.allCases.map(\.title),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.select(_:))
        )
        control.controlSize = .regular
        control.segmentStyle = .rounded
        context.coordinator.configure(control)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = self.$selection
        context.coordinator.configure(control)
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<IssueNavigatorKindFilter>

        init(selection: Binding<IssueNavigatorKindFilter>) {
            self.selection = selection
        }

        func configure(_ control: NSSegmentedControl) {
            let cases = IssueNavigatorKindFilter.allCases
            control.segmentCount = cases.count
            for (index, filter) in cases.enumerated() {
                control.setLabel(filter.title, forSegment: index)
                control.setWidth(0, forSegment: index)
            }
            control.selectedSegment = cases.firstIndex(of: self.selection.wrappedValue) ?? 0
        }

        @objc func select(_ control: NSSegmentedControl) {
            let index = control.selectedSegment
            let cases = IssueNavigatorKindFilter.allCases
            guard cases.indices.contains(index) else { return }

            self.selection.wrappedValue = cases[index]
        }
    }
}

private struct IssueNavigatorBrowserPreview: NSViewRepresentable {
    let url: URL
    let store: IssueNavigatorBrowserStore

    func makeNSView(context _: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context _: Context) {
        let webView = self.store.webView(for: self.url)
        guard webView.superview !== container else {
            webView.frame = container.bounds
            return
        }

        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    static func dismantleNSView(_ container: NSView, coordinator _: ()) {
        for subview in container.subviews {
            subview.removeFromSuperview()
        }
    }
}
