import Foundation
import RepoBarCore
import SwiftUI

struct AccountSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var clientID = "Iv23liGm2arUyotWSjwJ"
    @State private var clientSecret = ""
    @State private var enterpriseHost = ""
    @State private var hostMode: HostMode = .githubCom
    @State private var authMethod: AuthMethod = .oauth
    @State private var patInput = ""
    @State private var monitoredOwnersDraft = ""
    @State private var isValidatingPAT = false
    @State private var validationError: String?
    @State private var tokenValidation: TokenValidationState = .unknown
    private let enterpriseFieldMinWidth: CGFloat = 260
    private let spinnerSize: CGFloat = 14
    private let tokenCheckTimeout: TimeInterval = 8
    private let tokenRefreshTimeout: TimeInterval = 12

    var body: some View {
        Form {
            AccountsListSection(session: self.session, appState: self.appState)
            GitHubAPIUsageSection(session: self.session, appState: self.appState)

            Section("Add Account") {
                Picker("Host", selection: self.$hostMode) {
                    ForEach(HostMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                switch self.session.account {
                case let .loggedIn(user) where self.session.settings.accounts.isEmpty:
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Signed in")
                                        .font(.headline)
                                    Text("\(user.username) · \(user.host.host ?? "github.com")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Log out") {
                                Task {
                                    await self.appState.logoutCurrentMethod()
                                    self.authMethod = .oauth
                                    self.patInput = ""
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        if let status = self.tokenStatusText {
                            HStack(spacing: 8) {
                                if self.tokenValidation == .checking {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: self.spinnerSize, height: self.spinnerSize)
                                }
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(self.tokenStatusColor)
                            }
                        }
                        HStack(spacing: 8) {
                            Button("Check token") {
                                Task { await self.validateToken() }
                            }
                            .disabled(self.tokenValidation == .checking)
                            if self.session.settings.authMethod == .oauth {
                                Button("Refresh token") {
                                    Task { await self.refreshToken() }
                                }
                                .disabled(self.tokenValidation == .checking)
                            }
                        }
                        .buttonStyle(.bordered)
                        if self.session.settings.authMethod == .oauth, self.session.settings.enterpriseHost == nil {
                            Text("Private organization repositories are visible only after the RepoBar GitHub App is installed on that organization or selected repository.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("Manage GitHub App installation", destination: RepoBarAuthDefaults.appInstallURL)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                default:
                    Picker("Authentication", selection: self.$authMethod) {
                        ForEach(AuthMethod.allCases, id: \.self) { method in
                            Text(method.label).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    if self.authMethod == .pat {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Token")
                            SecureField("ghp_… or github_pat_…", text: self.$patInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: self.enterpriseFieldMinWidth)
                        }
                        Text("Recommended for SAML SSO organizations. Required scopes: repo, read:org")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("Create a token on GitHub", destination: self.createTokenURL())
                            .font(.caption)
                        if self.hostMode == .enterprise {
                            LabeledContent("Enterprise Base URL") {
                                TextField("https://ghe.example.com", text: self.$enterpriseHost)
                                    .frame(minWidth: self.enterpriseFieldMinWidth)
                                    .layoutPriority(1)
                            }
                        }
                        HStack(spacing: 8) {
                            if self.isValidatingPAT {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: self.spinnerSize, height: self.spinnerSize)
                            }
                            Button(self.isValidatingPAT ? "Signing in…" : "Sign in with Token") {
                                self.loginWithPAT()
                            }
                            .disabled(self.patInput.isEmpty || self.isValidatingPAT)
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        if self.hostMode == .enterprise {
                            LabeledContent("Enterprise Base URL") {
                                TextField("https://ghe.example.com", text: self.$enterpriseHost)
                                    .frame(minWidth: self.enterpriseFieldMinWidth)
                                    .layoutPriority(1)
                            }
                            LabeledContent("Client ID") {
                                TextField("", text: self.$clientID)
                                    .frame(minWidth: self.enterpriseFieldMinWidth)
                                    .layoutPriority(1)
                            }
                            LabeledContent("Client Secret") {
                                SecureField("", text: self.$clientSecret)
                                    .frame(minWidth: self.enterpriseFieldMinWidth)
                                    .layoutPriority(1)
                            }
                            Text("Create an OAuth App in your enterprise server. Callback URL: http://127.0.0.1:53682/callback")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Uses the built-in GitHub.com OAuth app.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Private organization repositories require the RepoBar GitHub App installation to include that organization or repository.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("Install RepoBar GitHub App", destination: RepoBarAuthDefaults.appInstallURL)
                                .font(.caption)
                        }
                        HStack(spacing: 8) {
                            if self.session.account == .loggingIn {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: self.spinnerSize, height: self.spinnerSize)
                            }
                            Button(self.session.account == .loggingIn ? "Signing in…" : self.hostMode == .enterprise ? "Sign in to Enterprise" : "Sign in to GitHub.com") {
                                self.login()
                            }
                            .disabled(self.session.account == .loggingIn)
                            .buttonStyle(.borderedProminent)
                        }
                        Text("Uses browser-based OAuth. Tokens are stored by RepoBar's configured auth store.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Add owner", text: self.$monitoredOwnersDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { self.addMonitoredOwners() }
                        Button("Add") { self.addMonitoredOwners() }
                            .disabled(Self.parseOwners(self.monitoredOwnersDraft).isEmpty)
                        Button("Use Visible") { self.useVisibleOwners() }
                            .disabled(self.visibleOwnerCandidates.isEmpty)
                        Button("Auto") { self.clearMonitoredOwners() }
                            .disabled(self.selectedMonitoredOwners.isEmpty)
                    }

                    VStack(spacing: 0) {
                        if self.selectedMonitoredOwners.isEmpty {
                            self.monitoredOwnerRow(
                                title: "Auto",
                                subtitle: "Personal account plus visible repository owners",
                                systemImage: "wand.and.stars",
                                removeAction: nil
                            )
                        } else {
                            ForEach(Array(self.selectedMonitoredOwners.enumerated()), id: \.element) { index, owner in
                                if index > 0 {
                                    Divider()
                                }
                                self.monitoredOwnerRow(
                                    title: owner,
                                    subtitle: self.monitoredOwnerSubtitle(owner),
                                    systemImage: self.monitoredOwnerIcon(owner),
                                    removeAction: { self.removeMonitoredOwner(owner) }
                                )
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
            } header: {
                Text("Monitored Owners")
            } footer: {
                Text("Owners control which accounts RepoBar uses for Actions & Runners. Auto follows your personal account and visible repository owners.")
            }

            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let lastError = self.session.lastError, validationError == nil {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            if let enterprise = self.session.settings.enterpriseHost {
                self.enterpriseHost = enterprise.absoluteString
                self.hostMode = .enterprise
            }
            if self.session.settings.enterpriseHost == nil {
                self.hostMode = .githubCom
                if self.clientID.isEmpty {
                    self.clientID = RepoBarAuthDefaults.clientID
                }
                if self.clientSecret.isEmpty {
                    self.clientSecret = RepoBarAuthDefaults.clientSecret
                }
            }
            self.authMethod = self.session.settings.authMethod
            self.monitoredOwnersDraft = ""
        }
        .task(id: self.session.account) {
            guard case .loggedIn = self.session.account else {
                self.tokenValidation = .unknown
                return
            }

            await self.validateToken()
        }
    }

    private var visibleOwnerCandidates: [String] {
        var owners = self.session.repositories.map(\.owner)
        if case let .loggedIn(user) = self.session.account {
            owners.append(user.username)
        }
        return OwnerFilter.normalize(owners)
    }

    private var selectedMonitoredOwners: [String] {
        OwnerFilter.normalize(self.session.settings.monitoredOwners)
    }

    private func addMonitoredOwners() {
        let owners = Self.parseOwners(self.monitoredOwnersDraft)
        guard !owners.isEmpty else { return }

        self.session.settings.monitoredOwners = OwnerFilter.normalize(self.selectedMonitoredOwners + owners)
        self.monitoredOwnersDraft = ""
        self.monitoredOwnersChanged()
    }

    private func useVisibleOwners() {
        self.session.settings.monitoredOwners = self.visibleOwnerCandidates
        self.monitoredOwnersDraft = ""
        self.monitoredOwnersChanged()
    }

    private func clearMonitoredOwners() {
        self.session.settings.monitoredOwners = []
        self.monitoredOwnersDraft = ""
        self.monitoredOwnersChanged()
    }

    private func removeMonitoredOwner(_ owner: String) {
        let normalized = owner.lowercased()
        self.session.settings.monitoredOwners = self.selectedMonitoredOwners.filter { $0 != normalized }
        self.monitoredOwnersChanged()
    }

    private func monitoredOwnersChanged() {
        self.appState.persistSettings()
        if !self.session.settings.menuCustomization.hiddenMainMenuItems.contains(.actionsLimits) {
            self.session.actionsOrgSnapshots = []
            NotificationCenter.default.post(name: .menuRepositoriesDidChange, object: nil)
            self.appState.requestRefresh(cancelInFlight: true)
        }
    }

    private static func parseOwners(_ rawValue: String) -> [String] {
        OwnerFilter.normalize(rawValue.split { separator in
            separator == "," || separator == " " || separator == "\n" || separator == "\t"
        }.map(String.init))
    }

    private func monitoredOwnerIcon(_ owner: String) -> String {
        guard case let .loggedIn(user) = self.session.account,
              owner == user.username.lowercased()
        else { return "building.2" }

        return "person.crop.circle"
    }

    private func monitoredOwnerSubtitle(_ owner: String) -> String {
        guard case let .loggedIn(user) = self.session.account,
              owner == user.username.lowercased()
        else { return "Pinned owner" }

        return "Personal account"
    }

    private func monitoredOwnerRow(
        title: String,
        subtitle: String,
        systemImage: String,
        removeAction: (() -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let removeAction {
                Button(action: removeAction) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Remove owner")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func login() {
        Task { @MainActor in
            self.session.account = .loggingIn
            self.session.lastError = nil
            let enterpriseURL = self.hostMode == .enterprise ? self.normalizedEnterpriseHost() : nil

            if self.hostMode == .enterprise, let enterpriseURL {
                self.session.settings.enterpriseHost = enterpriseURL
                self.session.settings.githubHost = enterpriseURL
                self.validationError = nil
            } else {
                if self.hostMode == .enterprise {
                    self.validationError = "Enterprise Base URL must be a valid https:// URL with a trusted certificate."
                    self.session.account = .loggedOut
                    return
                }
                self.session.settings.githubHost = URL(string: "https://github.com")!
                self.session.settings.enterpriseHost = nil
                self.validationError = nil
            }
            let usingEnterprise = self.session.settings.enterpriseHost != nil
            let effectiveClientID = self.clientID.isEmpty && !usingEnterprise
                ? RepoBarAuthDefaults.clientID
                : self.clientID
            let effectiveClientSecret = self.clientSecret.isEmpty && !usingEnterprise
                ? RepoBarAuthDefaults.clientSecret
                : self.clientSecret
            if usingEnterprise, effectiveClientID.isEmpty || effectiveClientSecret.isEmpty {
                self.validationError = "Client ID and Client Secret are required for enterprise login."
                self.session.account = .loggedOut
                return
            }
            do {
                try await self.appState.auth.login(
                    clientID: effectiveClientID,
                    clientSecret: effectiveClientSecret,
                    host: self.session.settings.enterpriseHost ?? self.session.settings.githubHost,
                    loopbackPort: self.session.settings.loopbackPort,
                    scope: usingEnterprise ? "repo read:org" : nil
                )
                self.session.settings.authMethod = .oauth
                self.appState.persistSettings()
                self.session.hasStoredTokens = true
                let loginHost = self.session.settings.enterpriseHost ?? self.session.settings.githubHost
                if let user = await self.appState.currentUserFromLegacyCredentials(host: loginHost) {
                    self.session.account = .loggedIn(user)
                    self.session.lastError = nil
                    await self.appState.recordAccountForLogin(
                        user: user,
                        host: loginHost,
                        method: .oauth
                    )
                } else {
                    self.session.account = .loggedIn(UserIdentity(username: "", host: self.session.settings.githubHost))
                }
                await self.appState.refresh()
            } catch {
                self.session.account = .loggedOut
                self.session.lastError = error.userFacingMessage
            }
        }
    }

    private func loginWithPAT() {
        Task { @MainActor in
            self.isValidatingPAT = true
            self.validationError = nil

            let host: URL
            if self.hostMode == .enterprise {
                guard let enterpriseURL = self.normalizedEnterpriseHost() else {
                    self.validationError = "Enterprise Base URL must be a valid https:// URL with a trusted certificate."
                    self.isValidatingPAT = false
                    return
                }

                self.session.settings.enterpriseHost = enterpriseURL
                host = enterpriseURL
            } else {
                self.session.settings.enterpriseHost = nil
                host = URL(string: "https://github.com")!
            }

            await self.appState.loginWithPAT(self.patInput, host: host)
            self.isValidatingPAT = false

            if case .loggedIn = self.session.account {
                self.patInput = ""
            }
        }
    }

    private func createTokenURL() -> URL {
        let baseHost = self.hostMode == .enterprise
            ? (self.normalizedEnterpriseHost()?.absoluteString ?? "https://github.com")
            : "https://github.com"
        return URL(string: "\(baseHost)/settings/tokens/new?scopes=repo,read:org&description=RepoBar")!
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

    private func validateToken() async {
        guard case .loggedIn = self.session.account else { return }

        if self.tokenValidation == .checking { return }
        self.tokenValidation = .checking
        let started = Date()
        await self.logAuth("Auth: token check started")
        do {
            let user = try await self.withTimeout(seconds: self.tokenCheckTimeout) {
                try await self.appState.github.currentUser()
            }
            self.session.account = .loggedIn(user)
            self.session.lastError = nil
            self.tokenValidation = .valid
            await self.logAuth("Auth: token check ok in \(Self.formatElapsed(since: started))")
        } catch {
            if error.isAuthenticationFailure {
                self.tokenValidation = .invalid("Authentication required.")
                await self.logAuth("Auth: token check auth failure in \(Self.formatElapsed(since: started))")
                await self.appState.handleAuthenticationFailure(error)
                return
            }
            self.tokenValidation = .invalid(error.userFacingMessage)
            await self.logAuth("Auth: token check failed in \(Self.formatElapsed(since: started)): \(error.userFacingMessage)")
        }
    }

    private func refreshToken() async {
        guard case .loggedIn = self.session.account else { return }

        if self.tokenValidation == .checking { return }
        self.tokenValidation = .checking
        let started = Date()
        await self.logAuth("Auth: token refresh started")
        do {
            let refreshed = try await self.withTimeout(seconds: self.tokenRefreshTimeout) {
                try await self.appState.auth.refreshIfNeeded(force: true)
            }
            guard refreshed != nil else {
                throw URLError(.userAuthenticationRequired)
            }

            await self.logAuth("Auth: token refresh ok in \(Self.formatElapsed(since: started))")
            await self.validateToken()
        } catch {
            if error.isAuthenticationFailure {
                self.tokenValidation = .invalid("Authentication required.")
                await self.logAuth("Auth: token refresh auth failure in \(Self.formatElapsed(since: started))")
                await self.appState.handleAuthenticationFailure(error)
                return
            }
            self.tokenValidation = .invalid(error.userFacingMessage)
            await self.logAuth("Auth: token refresh failed in \(Self.formatElapsed(since: started)): \(error.userFacingMessage)")
        }
    }

    private var tokenStatusText: String? {
        switch self.tokenValidation {
        case .unknown:
            "Token status not checked yet."
        case .checking:
            "Checking token…"
        case .valid:
            "Token is valid."
        case let .invalid(message):
            "Token invalid: \(message)"
        }
    }

    private var tokenStatusColor: Color {
        switch self.tokenValidation {
        case .valid:
            .green
        case .invalid:
            .red
        default:
            .secondary
        }
    }

    private func logAuth(_ message: String) async {
        await DiagnosticsLogger.shared.message(message)
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func formatElapsed(since start: Date) -> String {
        let elapsed = Date().timeIntervalSince(start)
        return String(format: "%.2fs", elapsed)
    }
}

private enum TokenValidationState: Equatable {
    case unknown
    case checking
    case valid
    case invalid(String)
}

private enum HostMode: String, CaseIterable {
    case githubCom
    case enterprise

    var label: String {
        switch self {
        case .githubCom:
            "GitHub.com"
        case .enterprise:
            "Enterprise"
        }
    }
}
