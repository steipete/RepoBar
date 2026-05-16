import RepoBarCore
import SwiftUI

struct RepoSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var newRepoInput = ""
    @State private var newRepoVisibility: RepoVisibility = .pinned
    @State private var searchQuery = ""
    @State private var selection = Set<String>()
    @State private var allRows: [RepoBrowserRow] = []
    @State private var filteredRows: [RepoBrowserRow] = []
    @State private var statusLine = ""
    @State private var sortOrder: [KeyPathComparator<RepoBrowserRow>] = [
        KeyPathComparator(\RepoBrowserRow.visibilitySortKey, order: .forward),
        KeyPathComparator(\RepoBrowserRow.fullName, order: .forward)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Browse repositories RepoBar can access and choose what stays pinned or hidden.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Search repositories", text: self.$searchQuery)
                    .textFieldStyle(.roundedBorder)

                Button {
                    self.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
                .disabled(self.searchQuery.isEmpty)
            }

            RepoInputRow(
                placeholder: "owner/name",
                buttonTitle: "Add Rule",
                text: self.$newRepoInput,
                onCommit: self.addNewRepo,
                session: self.session,
                appState: self.appState
            ) {
                Picker("Visibility", selection: self.$newRepoVisibility) {
                    ForEach([RepoVisibility.pinned, .hidden], id: \.id) { vis in
                        Text(vis.label).tag(vis)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Table(self.filteredRows, selection: self.$selection, sortOrder: self.$sortOrder) {
                TableColumn("Repository", value: \RepoBrowserRow.fullName) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.fullName)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 6) {
                            if row.isFork {
                                Label("Fork", systemImage: "tuningfork")
                                    .labelStyle(.titleAndIcon)
                            }
                            if row.isArchived {
                                Label("Archived", systemImage: "archivebox")
                                    .labelStyle(.titleAndIcon)
                            }
                            if row.isManual {
                                Label("Manual", systemImage: "pencil")
                                    .labelStyle(.titleAndIcon)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .width(min: 300, ideal: 420, max: .infinity)

                TableColumn("Issues", value: \RepoBrowserRow.sortableIssues) { row in
                    Text(row.issueLabel)
                        .monospacedDigit()
                        .foregroundStyle(row.isManual ? .secondary : .primary)
                }
                .width(min: 56, ideal: 64, max: 76)

                TableColumn("PRs", value: \RepoBrowserRow.sortablePulls) { row in
                    Text(row.pullRequestLabel)
                        .monospacedDigit()
                        .foregroundStyle(row.isManual ? .secondary : .primary)
                }
                .width(min: 44, ideal: 52, max: 64)

                TableColumn("Stars", value: \RepoBrowserRow.sortableStars) { row in
                    Text(row.starLabel)
                        .monospacedDigit()
                        .foregroundStyle(row.isManual ? .secondary : .primary)
                }
                .width(min: 52, ideal: 64, max: 76)

                TableColumn("Updated", value: \RepoBrowserRow.sortablePushedAt) { row in
                    Text(row.updatedLabel)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 96, max: 120)

                TableColumn("Visibility", value: \RepoBrowserRow.visibilitySortKey) { row in
                    RepoVisibilityMenu(visibility: row.visibility) { newValue in
                        Task { await self.set(row.fullName, to: newValue) }
                    }
                    .frame(width: 128, alignment: .leading)
                }
                .width(min: 128, ideal: 136, max: 144)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 280)
            .onDeleteCommand { self.deleteSelection() }
            .contextMenu(forSelectionType: String.self) { selection in
                Button("Pin") { Task { await self.bulkSet(selection, to: .pinned) } }
                Button("Hide") { Task { await self.bulkSet(selection, to: .hidden) } }
                Button("Set Visible") { Task { await self.bulkSet(selection, to: .visible) } }
            }

            HStack(spacing: 10) {
                Text(self.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Pin") {
                    Task { await self.bulkSet(self.selection, to: .pinned) }
                }
                .disabled(self.selection.isEmpty)

                Button {
                    self.deleteSelection()
                } label: {
                    Label("Set Visible", systemImage: "eye")
                }
                .disabled(self.selection.isEmpty)

                Button("Refresh Now") {
                    self.appState.requestRefresh(cancelInFlight: true)
                }
            }
        }
        .padding()
        .onAppear {
            self.rebuildRows()
            Task { try? await self.appState.github.prefetchedRepositories() }
        }
        .onChange(of: self.searchQuery) { _, _ in self.applySearch() }
        .onChange(of: self.sortOrder) { _, _ in self.applySearch() }
        .onChange(of: self.session.accessibleRepositories) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.repositories) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.menuSnapshot) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.settings.repoList.pinnedRepositories) { _, _ in self.rebuildRows() }
        .onChange(of: self.session.settings.repoList.hiddenRepositories) { _, _ in self.rebuildRows() }
    }

    private var browserRepositories: [Repository] {
        if !self.session.accessibleRepositories.isEmpty {
            return self.session.accessibleRepositories
        }
        if let snapshotRepos = self.session.menuSnapshot?.repositories, !snapshotRepos.isEmpty {
            return snapshotRepos
        }
        return self.session.repositories
    }

    private func addNewRepo(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.newRepoInput = ""
        Task { await self.set(trimmed, to: self.newRepoVisibility) }
    }

    private func set(_ name: String, to visibility: RepoVisibility) async {
        await self.appState.setVisibility(for: name, to: visibility)
    }

    private func bulkSet(_ ids: Set<String>, to visibility: RepoVisibility) async {
        let selectedRows = self.allRows.filter { ids.contains($0.id) }
        for row in selectedRows {
            await self.set(row.fullName, to: visibility)
        }
        await MainActor.run { self.selection.removeAll() }
    }

    private func deleteSelection() {
        let ids = self.selection
        Task {
            await self.bulkSet(ids, to: .visible)
        }
    }

    private func rebuildRows() {
        self.allRows = RepoBrowserRows.make(
            repositories: self.browserRepositories,
            pinnedRepositories: self.session.settings.repoList.pinnedRepositories,
            hiddenRepositories: self.session.settings.repoList.hiddenRepositories,
            now: Date()
        )
        self.applySearch()
    }

    private func applySearch() {
        var rows = RepoBrowserRows.filter(self.allRows, query: self.searchQuery)
        if !self.sortOrder.isEmpty {
            // Append a stable fullName tiebreaker so equal-count rows keep a
            // predictable order even when a header click reduces sortOrder
            // to a single comparator.
            var effective = self.sortOrder
            effective.append(KeyPathComparator(\RepoBrowserRow.fullName, order: .forward))
            rows.sort(using: effective)
        }
        self.filteredRows = rows
        self.selection.formIntersection(Set(self.filteredRows.map(\.id)))
        self.statusLine = RepoBrowserRows.statusLine(allRows: self.allRows, filteredRows: self.filteredRows)
    }
}

private struct RepoVisibilityMenu: View {
    let visibility: RepoVisibility
    var onChange: (RepoVisibility) -> Void

    var body: some View {
        Menu {
            ForEach(RepoVisibility.allCases) { item in
                Button {
                    self.onChange(item)
                } label: {
                    if item == self.visibility {
                        Label(item.label, systemImage: "checkmark")
                    } else {
                        Text(item.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(self.visibility.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Autocomplete helper

private struct RepoInputRow<Accessory: View>: View {
    let placeholder: String
    let buttonTitle: String
    @Binding var text: String
    var onCommit: (String) -> Void
    @Bindable var session: Session
    let appState: AppState
    var accessory: () -> Accessory
    @State private var suggestions: [Repository] = []
    @State private var isLoading = false
    @State private var showSuggestions = false
    @State private var selectedIndex = -1
    @State private var keyboardNavigating = false
    @State private var textFieldSize: CGSize = .zero
    @FocusState private var isFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    private var trimmedText: String {
        self.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField(self.placeholder, text: self.$text)
                    .textFieldStyle(.roundedBorder)
                    .focused(self.$isFocused)
                    .onChange(of: self.text) { _, newValue in
                        self.keyboardNavigating = false
                        self.scheduleSearch(query: newValue, immediate: true)
                    }
                    .onSubmit { self.commit() }
                    .onTapGesture {
                        self.showSuggestions = true
                        self.scheduleSearch(query: self.text, immediate: true)
                    }
                    .onMoveCommand(perform: self.handleMove)
                    .overlay(alignment: .trailing) {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                            .opacity(self.isLoading ? 1 : 0)
                            .accessibilityHidden(!self.isLoading)
                            .allowsHitTesting(false)
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear { self.textFieldSize = geometry.size }
                                .onChange(of: geometry.size) { _, newSize in
                                    self.textFieldSize = newSize
                                }
                        }
                    )
                    .background(
                        RepoAutocompleteWindowView(
                            suggestions: self.suggestions,
                            selectedIndex: self.$selectedIndex,
                            keyboardNavigating: self.keyboardNavigating,
                            onSelect: { suggestion in
                                self.commit(suggestion)
                                DispatchQueue.main.async {
                                    self.isFocused = true
                                }
                            },
                            width: self.textFieldSize.width,
                            isShowing: Binding(
                                get: {
                                    self.showSuggestions && self.isFocused && !self.suggestions.isEmpty
                                },
                                set: { self.showSuggestions = $0 }
                            )
                        )
                    )

                self.accessory()

                Button(self.buttonTitle) { self.commit() }
                    .disabled(self.trimmedText.isEmpty)
            }
        }
        .onChange(of: self.isFocused) { _, newValue in
            if newValue {
                self.scheduleSearch(query: self.text, immediate: true)
            } else {
                self.hideSuggestionsSoon()
            }
        }
        .onDisappear { self.searchTask?.cancel() }
    }

    private func commit(_ value: String? = nil) {
        let trimmed = (value ?? self.trimmedText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.text = ""
        self.suggestions = []
        self.showSuggestions = false
        self.selectedIndex = -1
        self.onCommit(trimmed)
    }

    private func scheduleSearch(query: String, immediate: Bool = false) {
        self.searchTask?.cancel()
        self.searchTask = Task {
            // Local-only filtering; keep it snappy.
            if !immediate {
                do {
                    try await Task.sleep(nanoseconds: 150_000_000)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            await self.loadSuggestions(query: query)
        }
    }

    private func loadSuggestions(query: String) async {
        await MainActor.run {
            self.isLoading = true
            self.showSuggestions = self.isFocused
        }
        defer {
            Task { @MainActor in self.isLoading = false }
        }

        let includeForks = await MainActor.run { self.session.settings.repoList.showForks }
        let includeArchived = await MainActor.run { self.session.settings.repoList.showArchived }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefetched = try? await self.appState.github.prefetchedRepositories()

        let filteredPrefetched = prefetched.map {
            RepositoryFilter.apply($0, includeForks: includeForks, includeArchived: includeArchived)
        }

        let repos = RepoAutocompleteSuggestions.suggestions(
            query: trimmed,
            prefetched: filteredPrefetched ?? [],
            limit: AppLimits.Autocomplete.settingsSearchLimit
        )

        guard !Task.isCancelled else { return }

        await MainActor.run {
            self.suggestions = repos
            if self.selectedIndex >= self.suggestions.count {
                self.selectedIndex = -1
            }
            // Keep suggestions visible while typing even if focus flickers.
            self.showSuggestions = !self.suggestions.isEmpty && (self.isFocused || !self.trimmedText.isEmpty)
        }
    }

    private func hideSuggestionsSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.showSuggestions = false
            self.selectedIndex = -1
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        guard !self.suggestions.isEmpty else { return }

        switch direction {
        case .down:
            self.keyboardNavigating = true
            let next = self.selectedIndex + 1
            self.selectedIndex = min(next, self.suggestions.count - 1)
        case .up:
            self.keyboardNavigating = true
            let prev = self.selectedIndex - 1
            self.selectedIndex = max(prev, 0)
        default:
            break
        }
    }
}
