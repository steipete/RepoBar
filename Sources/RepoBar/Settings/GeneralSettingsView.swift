import AppKit
import RepoBarCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    private var normalizedCurrentUsername: String? {
        guard case let .loggedIn(user) = self.session.account else { return nil }

        return user.username.lowercased()
    }

    private var showOnlyMyRepos: Bool {
        guard let username = self.normalizedCurrentUsername else { return false }

        return OwnerFilter.normalize(self.session.settings.repoList.ownerFilter) == [username]
    }

    private func toggleShowOnlyMyRepos(_ enabled: Bool) {
        guard let username = self.normalizedCurrentUsername else { return }

        self.appState.updateSetting(
            \.repoList.ownerFilter,
            to: enabled ? [username] : [],
            effects: .cancelInFlightRefresh
        )
    }

    private func setting<Value>(
        _ keyPath: WritableKeyPath<UserSettings, Value>,
        effects: SettingsUpdateEffects = []
    ) -> Binding<Value> {
        Binding(
            get: { self.session.settings[keyPath: keyPath] },
            set: { value in
                self.appState.updateSetting(keyPath, to: value, effects: effects)
            }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            Form {
                Section {
                    Toggle("Launch at login", isOn: self.setting(\.launchAtLogin, effects: .launchAtLogin))
                } footer: {
                    Text("Automatically opens RepoBar when you start your Mac.")
                }

                Section {
                    Toggle("Show contribution header", isOn: self.setting(\.appearance.showContributionHeader))
                    Toggle(
                        "Show GitHub rate-limit meter in menu bar",
                        isOn: self.setting(\.appearance.showRateLimitMeterInMenuBar, effects: .menuDiagnostics)
                    )
                    Picker("Activity feed", selection: self.setting(\.appearance.activityScope, effects: .refresh)) {
                        ForEach(GlobalActivityScope.allCases, id: \.self) { scope in
                            Text(scope.label).tag(scope)
                        }
                    }
                    Picker("Repository heatmap", selection: self.setting(\.heatmap.display)) {
                        ForEach(HeatmapDisplay.allCases, id: \.self) { display in
                            Text(display.label).tag(display)
                        }
                    }
                    Picker("Heatmap window", selection: self.setting(\.heatmap.span, effects: .heatmapRange)) {
                        ForEach(HeatmapSpan.allCases, id: \.self) { span in
                            Text(span.label).tag(span)
                        }
                    }
                    Picker("Heatmap color", selection: self.setting(\.appearance.accentTone)) {
                        ForEach(AccentTone.allCases, id: \.self) { tone in
                            Text(tone.label).tag(tone)
                        }
                    }
                } header: {
                    Text("Heatmap")
                } footer: {
                    Text("Repository heatmaps show recent commit activity for each repository.")
                }

                Section {
                    Picker("Repositories shown", selection: self.setting(\.repoList.displayLimit)) {
                        ForEach([3, 6, 9, 12], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Menu sort", selection: self.setting(\.repoList.menuSortKey)) {
                        ForEach(RepositorySortKey.settingsCases, id: \.self) { sortKey in
                            Text(sortKey.settingsLabel).tag(sortKey)
                        }
                    }
                    Toggle(
                        "Include forked repositories",
                        isOn: self.setting(\.repoList.showForks, effects: .cancelInFlightRefresh)
                    )
                    Toggle(
                        "Include archived repositories",
                        isOn: self.setting(\.repoList.showArchived, effects: .cancelInFlightRefresh)
                    )
                    Toggle("Show only my repositories", isOn: Binding(
                        get: { self.showOnlyMyRepos },
                        set: { self.toggleShowOnlyMyRepos($0) }
                    ))
                    .disabled(self.normalizedCurrentUsername == nil)
                } header: {
                    Text("Repositories")
                } footer: {
                    Text("Filters apply to repo lists and search. 'Show only my repositories' hides repos owned by organizations and other users.")
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Quit RepoBar") { NSApp.terminate(nil) }
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
