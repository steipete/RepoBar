import RepoBarCore
import SwiftUI

struct NotificationSettingsView: View {
    @Bindable var session: Session
    let appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Pull request notifications", isOn: self.$session.settings.gitHubPullRequestNotifications.enabled)
                    .onChange(of: self.session.settings.gitHubPullRequestNotifications.enabled) { _, enabled in
                        if enabled {
                            self.appState.resetGitHubPullRequestNotificationSnapshots()
                            self.appState.requestRefresh(cancelInFlight: true)
                        }
                        self.appState.persistSettings()
                    }

                if self.session.settings.gitHubPullRequestNotifications.enabled {
                    Toggle("New pull requests", isOn: self.$session.settings.gitHubPullRequestNotifications.newPullRequests)
                        .onChange(of: self.session.settings.gitHubPullRequestNotifications.newPullRequests) { _, _ in
                            self.appState.persistSettings()
                        }
                    Toggle("Pull request updates", isOn: self.$session.settings.gitHubPullRequestNotifications.pullRequestUpdates)
                        .onChange(of: self.session.settings.gitHubPullRequestNotifications.pullRequestUpdates) { _, _ in
                            self.appState.persistSettings()
                        }
                    Toggle("Review requested", isOn: self.$session.settings.gitHubPullRequestNotifications.reviewRequests)
                        .onChange(of: self.session.settings.gitHubPullRequestNotifications.reviewRequests) { _, _ in
                            self.appState.persistSettings()
                        }
                    Toggle("New comments", isOn: self.$session.settings.gitHubPullRequestNotifications.comments)
                        .onChange(of: self.session.settings.gitHubPullRequestNotifications.comments) { _, _ in
                            self.appState.persistSettings()
                        }
                    Picker("When clicked", selection: self.$session.settings.gitHubPullRequestNotifications.clickAction) {
                        ForEach(GitHubPullRequestNotificationClickAction.allCases, id: \.self) { action in
                            Text(action.label)
                                .tag(action)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: self.session.settings.gitHubPullRequestNotifications.clickAction) { _, _ in
                        self.appState.persistSettings()
                    }
                }
            } header: {
                Text("GitHub")
            } footer: {
                Text("Scoped to pinned repositories. The first refresh records the current state without sending notifications.")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
