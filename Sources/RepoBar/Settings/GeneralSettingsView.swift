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
                    Toggle(AppLocalizer().string("Launch at login"), isOn: self.setting(\.launchAtLogin, effects: .launchAtLogin))
                } footer: {
                    Text(AppLocalizer().string("Automatically opens RepoBar when you start your Mac."))
                }

                Section {
                    Picker(AppLocalizer().string("Appearance"), selection: self.setting(\.appearance.colorScheme, effects: .appAppearance)) {
                        ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                            Text(AppLocalizer().string(scheme.label)).tag(scheme)
                        }
                    }
                    Toggle(AppLocalizer().string("Show contribution header"), isOn: self.setting(\.appearance.showContributionHeader))
                    Toggle(
                        AppLocalizer().string("Show REST and GraphQL quotas in menu bar"),
                        isOn: self.setting(\.appearance.showRateLimitMeterInMenuBar, effects: .menuDiagnostics)
                    )
                    Text(AppLocalizer().string("Top row: R = REST core requests left. Bottom row: G = GraphQL points left. These are separate budgets."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(AppLocalizer().string("Activity feed"), selection: self.setting(\.appearance.activityScope, effects: .refresh)) {
                        ForEach(GlobalActivityScope.allCases, id: \.self) { scope in
                            Text(AppLocalizer().string(scope.label)).tag(scope)
                        }
                    }
                    Picker(AppLocalizer().string("Repository heatmap"), selection: self.setting(\.heatmap.display)) {
                        ForEach(HeatmapDisplay.allCases, id: \.self) { display in
                            Text(AppLocalizer().string(display.label)).tag(display)
                        }
                    }
                    Picker(AppLocalizer().string("Heatmap window"), selection: self.setting(\.heatmap.span, effects: .heatmapRange)) {
                        ForEach(HeatmapSpan.allCases, id: \.self) { span in
                            Text(AppLocalizer().string(span.label)).tag(span)
                        }
                    }
                    Picker(AppLocalizer().string("Heatmap color"), selection: self.setting(\.appearance.accentTone)) {
                        ForEach(AccentTone.allCases, id: \.self) { tone in
                            Text(AppLocalizer().string(tone.label)).tag(tone)
                        }
                    }
                } header: {
                    Text(AppLocalizer().string("Display"))
                } footer: {
                    Text(AppLocalizer().string("Repository heatmaps show recent commit activity for each repository."))
                }

                Section {
                    Picker(AppLocalizer().string("Repositories shown"), selection: self.setting(\.repoList.displayLimit)) {
                        ForEach([3, 6, 9, 12], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker(AppLocalizer().string("Menu sort"), selection: self.setting(\.repoList.menuSortKey)) {
                        ForEach(RepositorySortKey.settingsCases, id: \.self) { sortKey in
                            Text(AppLocalizer().string(sortKey.settingsLabel)).tag(sortKey)
                        }
                    }
                    Toggle(
                        AppLocalizer().string("Include forked repositories"),
                        isOn: self.setting(\.repoList.showForks, effects: .cancelInFlightRefresh)
                    )
                    Toggle(
                        AppLocalizer().string("Include archived repositories"),
                        isOn: self.setting(\.repoList.showArchived, effects: .cancelInFlightRefresh)
                    )
                    Toggle(AppLocalizer().string("Show only my repositories"), isOn: Binding(
                        get: { self.showOnlyMyRepos },
                        set: { self.toggleShowOnlyMyRepos($0) }
                    ))
                    .disabled(self.normalizedCurrentUsername == nil)
                } header: {
                    Text(AppLocalizer().string("Repositories"))
                } footer: {
                    Text(AppLocalizer().string("Filters apply to repo lists and search. 'Show only my repositories' hides repos owned by organizations and other users."))
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(AppLocalizer().string("Quit RepoBar")) { NSApp.terminate(nil) }
            }
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
