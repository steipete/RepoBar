import RepoBarCore
import SwiftUI

struct AddRepoView: View {
    @Binding var isPresented: Bool
    @Bindable var session: Session
    let appState: AppState
    var onSelect: (Repository) -> Void
    @State private var query = ""
    @State private var results: [Repository] = []
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin a repository")
                .font(.headline)
            TextField("owner/name", text: self.$query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await self.search() }
                }
            if self.isLoading {
                ProgressView().padding(.vertical, 8)
            }
            List(self.results) { repo in
                Button {
                    self.onSelect(repo)
                    self.isPresented = false
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(repo.fullName).bold()
                            if let lang = repo.language, !lang.isEmpty {
                                Badge(text: lang)
                            }
                            if repo.isFork {
                                Badge(text: "Fork")
                            }
                            if repo.isArchived {
                                Badge(text: "Archived")
                            }
                        }
                        if let description = repo.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Issues: \(repo.stats.openIssues) • Owner: \(repo.owner)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Cancel") { self.isPresented = false }
            }
        }
        .padding(16)
        .frame(width: 380, height: 420)
        .onAppear { Task { await self.searchDefault() } }
    }

    private func searchDefault() async {
        await self.search()
    }

    private func search() async {
        self.isLoading = true
        defer { self.isLoading = false }
        do {
            let includeForks = await MainActor.run { self.session.settings.repoList.showForks }
            let includeArchived = await MainActor.run { self.session.settings.repoList.showArchived }
            let trimmed = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let repos: [Repository] = if trimmed.isEmpty {
                try await self.appState.github.recentRepositories(limit: AppLimits.Autocomplete.addRepoRecentLimit)
            } else {
                try await self.appState.github.searchRepositories(matching: trimmed)
            }
            let filtered = RepositoryFilter.apply(repos, includeForks: includeForks, includeArchived: includeArchived)
            await MainActor.run { self.results = filtered }
        } catch {
            // Ignored; UI stays empty
        }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }
}
