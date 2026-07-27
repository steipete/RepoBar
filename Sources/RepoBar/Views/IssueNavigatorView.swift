import RepoBarCore
import SwiftUI

struct IssueNavigatorView: View {
    private enum Metrics {
        static let sidebarMinWidth: CGFloat = 380
        static let sidebarIdealWidth: CGFloat = 470
        static let sidebarMaxWidth: CGFloat = 560
        static let sidebarPadding: CGFloat = 14
        static let controlHeight: CGFloat = 28
        static let controlCornerRadius: CGFloat = 10
    }

    let appState: AppState
    @State private var model: IssueNavigatorModel

    init(
        appState: AppState,
        initialMatches: [GitHubReferenceMatch] = [],
        browserStore: IssueNavigatorBrowserStore
    ) {
        self.appState = appState
        self._model = State(
            initialValue: IssueNavigatorModel(
                appState: appState,
                initialMatches: initialMatches,
                browserStore: browserStore
            )
        )
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
        .frame(minWidth: 1080, minHeight: 620)
        .onAppear {
            self.model.start(
                seedClipboard: Self.shouldSeedClipboardOnAppear(hasInitialMatches: self.model.results.isEmpty == false)
            )
        }
        .onDisappear {
            self.model.stop()
        }
        .onReceive(
            Timer.publish(every: 1, tolerance: 0.25, on: .main, in: .common).autoconnect()
        ) { _ in
            self.model.updateClipboard(seedIfEmpty: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorUseClipboard)) { _ in
            self.model.useClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorRefresh)) { _ in
            self.model.scheduleSearch(immediate: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorCopy)) { _ in
            self.model.copySelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .issueNavigatorOpen)) { _ in
            self.model.openSelected()
        }
        .onChange(of: self.model.searchText) { _, _ in self.model.scheduleSearch() }
        .onChange(of: self.model.kindFilter) { _, _ in self.model.scheduleSearch(immediate: true) }
        .onChange(of: self.model.selectedScope) { _, _ in self.model.scheduleSearch(immediate: true) }
        .onChange(of: self.appState.session.settings.aiSummaries) { _, settings in
            self.model.aiSummarySettingsDidChange(settings)
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
        @Bindable var model = self.model

        return VStack(alignment: .leading, spacing: 8) {
            IssueNavigatorSearchField(
                text: $model.searchText,
                placeholder: "Search issues and pull requests",
                onSubmit: {
                    self.model.submitSearch()
                }
            )
            .frame(height: Metrics.controlHeight)

            HStack(spacing: 8) {
                IssueNavigatorScopePopUp(selection: $model.selectedScope, scopes: self.model.scopes)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.controlHeight)

                if self.model.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            IssueNavigatorKindSegmentedControl(selection: $model.kindFilter)
                .frame(height: Metrics.controlHeight)

            if self.model.shouldShowClipboardPrompt {
                Button {
                    self.model.useClipboard()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Clipboard: \(self.model.clipboardDisplayText)")
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

            Text(self.model.statusLine)
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
                IssueNavigatorCountBadge(count: self.model.results.count)
                Spacer()
                Text("Updated newest first")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Metrics.sidebarPadding)
            .padding(.top, 2)
            .padding(.bottom, 10)

            if let errorText = self.model.errorText {
                self.sidebarMessage(
                    title: "Search failed",
                    message: errorText,
                    systemImage: "exclamationmark.triangle"
                )
            } else if self.model.results.isEmpty {
                self.sidebarMessage(
                    title: "No matches",
                    message: self.model.statusText,
                    systemImage: "tray"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(self.model.results, id: \.url) { match in
                            IssueNavigatorResultRow(
                                match: self.model.displayMatch(match),
                                now: Date(),
                                isSelected: self.model.selectedURL == match.url,
                                onOpen: { self.model.open(match) }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                self.model.select(match)
                            }
                            .contextMenu {
                                Button("Open in Browser") { self.model.open(match) }
                                Button("Copy URL") { self.model.copy(match) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 14)
                }
                .onChange(of: self.model.selectedURL) { _, _ in
                    self.model.ensureSelection()
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

    @ViewBuilder
    private var previewPane: some View {
        if let match = self.model.selectedMatch {
            VStack(spacing: 0) {
                self.previewHeader(for: match)
                IssueNavigatorBrowserPreview(url: match.url, store: self.model.browserStore)
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

    private func previewHeader(for match: GitHubReferenceMatch) -> some View {
        let canGoBack = self.model.browserStore.canGoBack(match.url)

        return HStack(spacing: 12) {
            Button {
                self.model.browserStore.goBack(match.url)
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
        .id(self.model.browserNavigationVersion)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    nonisolated static func shouldSeedClipboardOnAppear(hasInitialMatches: Bool) -> Bool {
        !hasInitialMatches
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
