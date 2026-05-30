import AppKit
import RepoBarCore
import SwiftUI

@MainActor
struct AboutSettingsView: View {
    @State private var iconHover = false
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled: Bool = true
    @State private var didSyncUpdater = false

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "RepoBar"
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RepoBarBuildTimestamp") as? String else { return nil }

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    private var gitCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "RepoBarGitCommit") as? String
    }

    var body: some View {
        VStack(spacing: 8) {
            if let image = NSApplication.shared.applicationIconImage {
                Button {
                    if let url = URL(string: "https://github.com/steipete/RepoBar") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .cornerRadius(16)
                        .scaleEffect(self.iconHover ? 1.06 : 1.0)
                        .shadow(color: self.iconHover ? .accentColor.opacity(0.25) : .clear, radius: 6)
                        .padding(.bottom, 4)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        self.iconHover = hovering
                    }
                }
            }

            VStack(spacing: 2) {
                Text(self.appName)
                    .font(.title3).bold()
                Text("Version \(self.versionString)")
                    .foregroundStyle(.secondary)
                if let buildTimestamp {
                    let suffix: String = {
                        if let git = self.gitCommit, !git.isEmpty, git != "unknown" {
                            return " (\(git))"
                        }
                        return ""
                    }()
                    Text("Built \(buildTimestamp)\(suffix)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Menubar glance at GitHub repos: CI, issues/PRs, releases, traffic, and activity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 6) {
                AboutLinkRow(icon: "chevron.left.slash.chevron.right", title: "GitHub", url: "https://github.com/steipete/RepoBar")
                AboutLinkRow(icon: "globe", title: "Website", url: "https://repobar.app")
                AboutLinkRow(icon: "ant", title: "Issue Tracker", url: "https://github.com/steipete/RepoBar/issues")
                AboutLinkRow(icon: "envelope", title: "Email", url: "mailto:peter@steipete.me")
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)

            if SparkleController.shared.canCheckForUpdates {
                Divider()
                    .padding(.vertical, 6)
                VStack(spacing: 10) {
                    Toggle("Check for updates automatically", isOn: self.$autoUpdateEnabled)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button("Check for Updates…") {
                        SparkleController.shared.checkForUpdates()
                    }
                }
            } else {
                Text("Updates unavailable in this build.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            Button("Copy Update Diagnostics") {
                self.copyUpdateDiagnostics()
            }

            Text("© 2025 Peter Steinberger. MIT License.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .onAppear {
            guard !self.didSyncUpdater else { return }

            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = self.autoUpdateEnabled
                SparkleController.shared.automaticallyDownloadsUpdates = self.autoUpdateEnabled
            }
            self.didSyncUpdater = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = newValue
                SparkleController.shared.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    private func copyUpdateDiagnostics() {
        let diagnostics = UpdateDiagnostics.current(
            canCheckForUpdates: SparkleController.shared.canCheckForUpdates
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.pasteboardText, forType: .string)
    }
}
