import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: self.$selectedTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            RepoSettingsView()
                .tabItem { Label("Repositories", systemImage: "tray.full") }
                .tag(SettingsTab.repositories)
            AccountSettingsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag(SettingsTab.accounts)
            #if DEBUG
                if self.session.settings.debugPaneEnabled {
                    DebugSettingsView()
                        .tabItem { Label("Debug", systemImage: "ant.fill") }
                        .tag(SettingsTab.debug)
                }
            #endif
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 540, height: 420)
        .onChange(of: self.session.settings.debugPaneEnabled) { _, enabled in
            #if DEBUG
                if !enabled, self.selectedTab == .debug {
                    self.selectedTab = .general
                }
            #endif
        }
    }
}

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
            }
            self.didSyncUpdater = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = newValue
            }
        }
    }
}

@MainActor
private struct AboutLinkRow: View {
    let icon: String
    let title: String
    let url: String

    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: self.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: self.icon)
                Text(self.title)
                    .underline(self.hovering, color: .accentColor)
            }
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .onHover { self.hovering = $0 }
    }
}

enum SettingsTab: Hashable {
    case general
    case repositories
    case accounts
    case about
    #if DEBUG
        case debug
    #endif
}

struct GeneralSettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Show contribution header", isOn: self.$session.settings.showContributionHeader)
                .onChange(of: self.session.settings.showContributionHeader) { _, _ in self.appState.persistSettings() }

            Toggle("Show heatmap", isOn: self.$session.settings.showHeatmap)
                .onChange(of: self.session.settings.showHeatmap) { _, _ in self.appState.persistSettings() }

            Picker("Heatmap window", selection: self.$session.settings.heatmapSpan) {
                ForEach(HeatmapSpan.allCases, id: \.self) { span in
                    Text(span.label).tag(span)
                }
            }
            .onChange(of: self.session.settings.heatmapSpan) { _, _ in self.appState.persistSettings() }

            Picker("Repositories shown", selection: self.$session.settings.repoDisplayLimit) {
                ForEach([3, 5, 8, 12], id: \.self) { Text("\($0)").tag($0) }
            }
            .onChange(of: self.session.settings.repoDisplayLimit) { _, _ in self.appState.persistSettings() }

            Picker("Refresh interval", selection: self.$session.settings.refreshInterval) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(self.intervalLabel(interval)).tag(interval)
                }
            }
            .onChange(of: self.session.settings.refreshInterval) { _, newValue in
                LaunchAtLoginHelper.set(enabled: self.session.settings.launchAtLogin)
                self.appState.persistSettings()
                Task { @MainActor in
                    self.appState.refreshScheduler.configure(interval: newValue.seconds) { [weak appState] in
                        Task { await appState?.refresh() }
                    }
                }
            }

            #if DEBUG
                Toggle("Enable debug tools", isOn: self.$session.settings.debugPaneEnabled)
                    .onChange(of: self.session.settings.debugPaneEnabled) { _, _ in
                        self.appState.persistSettings()
                    }
                    .help("Show the Debug tab for diagnostics and developer-only controls.")
            #endif

            Toggle("Launch at login", isOn: self.$session.settings.launchAtLogin)
                .onChange(of: self.session.settings.launchAtLogin) { _, value in
                    LaunchAtLoginHelper.set(enabled: value)
                    self.appState.persistSettings()
                }
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(.horizontal, 48)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func intervalLabel(_ interval: RefreshInterval) -> String {
        switch interval {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var session: Session
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Picker("Card density", selection: self.$session.settings.cardDensity) {
                ForEach(CardDensity.allCases, id: \.self) { density in
                    Text(density.label).tag(density)
                }
            }
            .onChange(of: self.session.settings.cardDensity) { _, _ in self.appState.persistSettings() }

            Picker("Accent tone", selection: self.$session.settings.accentTone) {
                ForEach(AccentTone.allCases, id: \.self) { tone in
                    Text(tone.label).tag(tone)
                }
            }
            .onChange(of: self.session.settings.accentTone) { _, _ in self.appState.persistSettings() }

            Text("GitHub greens keep the classic contribution palette; System accent follows your macOS accent color.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding()
    }
}

struct AccountSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var session: Session
    @State private var clientID = "Iv23liGm2arUyotWSjwJ"
    @State private var clientSecret = ""
    @State private var enterpriseHost = ""
    @State private var validationError: String?

    var body: some View {
        Form {
            Section("GitHub.com") {
                switch self.session.account {
                case let .loggedIn(user):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Signed in as \(user.username) on \(user.host.host ?? "github.com")")
                            .font(.body)
                        Text("Use the button below to sign out.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Log out") {
                            Task {
                                await self.appState.auth.logout()
                                self.session.account = .loggedOut
                            }
                        }
                    }
                default:
                    TextField("Client ID", text: self.$clientID)
                    SecureField("Client Secret", text: self.$clientSecret)
                    Button(self.session.account == .loggingIn ? "Signing in…" : "Sign in") { self.login() }
                        .disabled(self.session.account == .loggingIn)
                }
            }

            Section("Enterprise (optional)") {
                TextField("Base URL (https://host)", text: self.$enterpriseHost)
                Text("Trusted TLS only; leave blank if unused")
                    .font(.caption)
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .onAppear {
            if let enterprise = self.session.settings.enterpriseHost {
                self.enterpriseHost = enterprise.absoluteString
            }
        }
    }

    private func login() {
        Task { @MainActor in
            self.session.account = .loggingIn
            let enterpriseURL = self.normalizedEnterpriseHost()

            if let enterpriseURL {
                self.session.settings.enterpriseHost = enterpriseURL
                await self.appState.github.setAPIHost(enterpriseURL.appending(path: "/api/v3"))
                self.session.settings.githubHost = enterpriseURL
                self.validationError = nil
            } else {
                if !self.enterpriseHost.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.validationError = "Enterprise host must be a valid https:// URL with a trusted certificate."
                    self.session.account = .loggedOut
                    return
                }
                await self.appState.github.setAPIHost(URL(string: "https://api.github.com")!)
                self.session.settings.githubHost = URL(string: "https://github.com")!
                self.session.settings.enterpriseHost = nil
                self.validationError = nil
            }
            do {
                try await self.appState.auth.login(
                    clientID: self.clientID,
                    clientSecret: self.clientSecret,
                    host: self.session.settings.enterpriseHost ?? self.session.settings.githubHost,
                    loopbackPort: self.session.settings.loopbackPort
                )
                if let user = try? await appState.github.currentUser() {
                    self.session.account = .loggedIn(user)
                    self.session.lastError = nil
                }
            } catch {
                self.session.account = .loggedOut
                self.session.lastError = error.userFacingMessage
            }
        }
    }

    private func normalizedEnterpriseHost() -> URL? {
        guard !self.enterpriseHost.isEmpty else { return nil }
        guard var components = URLComponents(string: enterpriseHost) else { return nil }
        if components.scheme == nil { components.scheme = "https" }
        guard components.scheme?.lowercased() == "https", components.host != nil else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct DebugSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var session: Session
    @State private var diagnostics = DiagnosticsSummary.empty

    var body: some View {
        Form {
            Section("Debug") {
                Button("Clear cache") {
                    Task {
                        await self.appState.clearCaches()
                        await self.loadDiagnosticsIfEnabled()
                    }
                }
                Button("Clear contribution heatmap cache") {
                    self.appState.clearContributionCache()
                }
                Button("Force refresh") {
                    self.appState.refreshScheduler.forceRefresh()
                }
                Toggle("Show diagnostics overlay", isOn: self.$session.settings.diagnosticsEnabled)
                    .onChange(of: self.session.settings.diagnosticsEnabled) { _, newValue in
                        self.appState.persistSettings()
                        Task {
                            await DiagnosticsLogger.shared.setEnabled(newValue)
                            await self.loadDiagnosticsIfEnabled()
                        }
                    }
            }

            Section("Diagnostics") {
                LabeledContent("API host") {
                    Text(self.diagnostics.apiHost.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let reset = diagnostics.rateLimitReset {
                    LabeledContent("Rate limit resets") {
                        Text(RelativeFormatter.string(from: reset, relativeTo: Date()))
                    }
                }
                if let error = diagnostics.lastRateLimitError {
                    LabeledContent("Last API notice") { Text(error).foregroundStyle(.red) }
                }
                LabeledContent("Backoff entries") { Text("\(self.diagnostics.backoffEntries)") }
                LabeledContent("ETag entries") { Text("\(self.diagnostics.etagEntries)") }
                Button("Refresh diagnostics") { Task { await self.loadDiagnosticsIfEnabled() } }
            }
            .opacity(self.session.settings.diagnosticsEnabled ? 1 : 0.4)
            .disabled(!self.session.settings.diagnosticsEnabled)
        }
        .padding()
        .task { await self.loadDiagnosticsIfEnabled() }
    }

    private func loadDiagnosticsIfEnabled() async {
        guard self.session.settings.diagnosticsEnabled else {
            self.diagnostics = .empty
            return
        }
        self.diagnostics = await self.appState.diagnostics()
    }
}
