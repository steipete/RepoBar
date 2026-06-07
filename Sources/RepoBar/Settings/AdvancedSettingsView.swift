import AppKit
import RepoBarCore
import SwiftUI

struct AdvancedSettingsView: View {
    @Bindable var session: Session
    let appState: AppState
    @State private var isInstallingCLI = false
    @State private var cliStatus: String?
    @State private var openAIAPIKey = ""
    @State private var openAIKeyStatus = OpenAIAPIKeySource.missing.label

    var body: some View {
        Form {
            Section {
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
                            appState?.requestRefresh()
                        }
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Controls how often RepoBar refreshes GitHub data.")
            }

            Section {
                LabeledContent("Project folder") {
                    HStack(spacing: 8) {
                        Text(self.projectFolderLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(self.projectFolderLabelColor)
                        Button("Choose…") { self.pickProjectFolder() }
                        if self.session.settings.localProjects.rootPath != nil {
                            Button {
                                self.appState.refreshLocalProjects(forceRescan: true)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Rescan local projects")
                            Button {
                                self.clearProjectFolder()
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Clear project folder")
                        }
                    }
                }

                if let summary = self.localRepoSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Auto-sync clean repos", isOn: self.$session.settings.localProjects.autoSyncEnabled)
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.autoSyncEnabled) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects()
                        self.appState.requestRefresh(cancelInFlight: true)
                    }

                Toggle("Show dirty files in menu", isOn: self.$session.settings.localProjects.showDirtyFilesInMenu)
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.showDirtyFilesInMenu) { _, _ in
                        self.appState.persistSettings()
                        NotificationCenter.default.post(name: .menuFiltersDidChange, object: nil)
                    }

                HStack {
                    Text("Worktree folder")
                    Spacer()
                    TextField("", text: self.worktreeFolderBinding)
                        .frame(width: 120)
                        .multilineTextAlignment(.trailing)
                        .disabled(self.session.settings.localProjects.rootPath == nil)
                }

                HStack {
                    Text("Fetch interval")
                    Spacer()
                    Picker("", selection: self.$session.settings.localProjects.fetchInterval) {
                        ForEach(LocalProjectsRefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.fetchInterval) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects()
                    }
                }

                HStack {
                    Text("Scan depth")
                    Spacer()
                    Picker("", selection: self.$session.settings.localProjects.maxDepth) {
                        ForEach(1 ... 6, id: \.self) { depth in
                            Text("\(depth) level\(depth == 1 ? "" : "s")")
                                .tag(depth)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                    .onChange(of: self.session.settings.localProjects.maxDepth) { _, _ in
                        self.appState.persistSettings()
                        self.appState.refreshLocalProjects(forceRescan: true)
                    }
                }

                HStack {
                    Text("Preferred Terminal")
                    Spacer()
                    Picker("", selection: self.preferredTerminalBinding) {
                        ForEach(TerminalApp.installed, id: \.rawValue) { terminal in
                            HStack {
                                if let icon = terminal.appIcon {
                                    Image(nsImage: icon.resized(to: NSSize(width: 16, height: 16)))
                                }
                                Text(terminal.displayName)
                            }
                            .tag(terminal.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(self.session.settings.localProjects.rootPath == nil)
                }

                if self.isGhosttySelected {
                    HStack {
                        Text("Ghostty opens in")
                        Spacer()
                        Picker("", selection: self.ghosttyOpenModeBinding) {
                            ForEach(GhosttyOpenMode.allCases, id: \.self) { mode in
                                Text(mode.label)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(self.session.settings.localProjects.rootPath == nil)
                    }
                }
            } header: {
                Text("Local Projects")
            } footer: {
                Text("Scans up to the configured depth under the folder, fetches periodically, and can fast-forward pull clean repos.")
            }

            GitHubArchiveSettingsSection(settings: self.$session.settings.githubArchives) {
                self.appState.persistSettings()
            }

            Section {
                Toggle("Watch copied GitHub references", isOn: self.$session.settings.gitHubReferenceMonitor.enabled)
                    .onChange(of: self.session.settings.gitHubReferenceMonitor.enabled) { _, _ in
                        self.appState.persistSettings()
                        self.appState.updateGitHubReferenceMonitor()
                    }

                if self.session.settings.gitHubReferenceMonitor.enabled {
                    LabeledContent("Matches") {
                        Text("GitHub URLs, issue numbers, commit hashes")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("GitHub References")
            } footer: {
                Text(
                    "Shows the best cached or live match in a separate menu bar item when a copied reference resolves."
                )
            }

            Section {
                Toggle("Summarize Issue Navigator PRs", isOn: self.$session.settings.aiSummaries.enabled)
                    .onChange(of: self.session.settings.aiSummaries.enabled) { _, _ in
                        self.appState.persistSettings()
                    }

                LabeledContent("Model") {
                    TextField("", text: self.aiSummaryModelBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 170)
                }

                LabeledContent("OpenAI API key") {
                    HStack(spacing: 8) {
                        SecureField("OPENAI_API_KEY", text: self.$openAIAPIKey)
                            .frame(width: 190)
                        Button("Save") {
                            self.saveOpenAIAPIKey()
                        }
                        .disabled(self.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Clear") {
                            self.clearOpenAIAPIKey()
                        }
                    }
                }

                Text(self.openAIKeyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI Summaries")
            } footer: {
                Text("Uses the stored key first, then OPENAI_API_KEY or REPOBAR_OPENAI_API_KEY from the app environment.")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        Task { await self.installCLI() }
                    } label: {
                        if self.isInstallingCLI {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Install CLI")
                        }
                    }
                    .disabled(self.isInstallingCLI)

                    if let status = self.cliStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Text("Install `repobar` into /usr/local/bin and /opt/homebrew/bin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("CLI")
            }

            #if DEBUG
                Section {
                    Toggle("Enable debug tools", isOn: self.$session.settings.debugPaneEnabled)
                        .onChange(of: self.session.settings.debugPaneEnabled) { _, _ in
                            self.appState.persistSettings()
                        }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("Developer-only diagnostics and experimental tools.")
                }
            #endif
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            self.ensurePreferredTerminal()
            self.appState.updateGitHubReferenceMonitor()
            self.appState.refreshLocalProjects()
            self.cliStatus = self.currentCLIStatus()
            self.refreshOpenAIKeyStatus()
        }
    }

    private func intervalLabel(_ interval: RefreshInterval) -> String {
        switch interval {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }

    private var projectFolderLabel: String {
        guard let path = self.session.settings.localProjects.rootPath,
              path.isEmpty == false
        else { return "Not set" }

        return PathFormatter.displayString(path)
    }

    private var projectFolderLabelColor: Color {
        self.session.settings.localProjects.rootPath == nil ? .secondary : .primary
    }

    private var localRepoSummary: String? {
        guard self.session.settings.localProjects.rootPath != nil else { return nil }

        if self.session.localProjectsScanInProgress { return "Scanning…" }
        let total = self.session.localDiscoveredRepoCount
        let matched = self.localMatchedRepoCount
        if total == 0 {
            if self.session.localProjectsAccessDenied || self.session.settings.localProjects.rootBookmarkData == nil {
                return "No repositories found yet. Re-choose the folder to grant access."
            }
            return "No repositories found yet."
        }
        if matched > 0 { return "Found \(total) local repos · \(matched) match GitHub data." }
        return "Found \(total) local repos."
    }

    private var localMatchedRepoCount: Int {
        let repos = self.session.repositories.isEmpty
            ? (self.session.menuSnapshot?.repositories ?? [])
            : self.session.repositories
        guard repos.isEmpty == false else { return 0 }

        let fullNames = Set(repos.map(\.fullName))
        let repoByName = Dictionary(grouping: repos, by: \.name)
        var matched = 0
        for status in self.session.localRepoIndex.all {
            if let fullName = status.fullName, fullNames.contains(fullName) {
                matched += 1
            } else if let candidates = repoByName[status.name], candidates.count == 1 {
                matched += 1
            }
        }
        return matched
    }

    // MARK: - CLI installer

    private func currentCLIStatus() -> String? {
        let installed = Self.cliTargets.filter { FileManager.default.fileExists(atPath: $0) }
        guard installed.isEmpty == false else { return "Not installed yet." }

        if installed.count == Self.cliTargets.count {
            return "Installed in /usr/local/bin and /opt/homebrew/bin."
        }
        return "Installed in \(installed.joined(separator: ", "))."
    }

    private func installCLI() async {
        guard !self.isInstallingCLI else { return }

        self.isInstallingCLI = true
        defer { self.isInstallingCLI = false }

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent("repobarcli")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            await MainActor.run { self.cliStatus = "Helper missing; reinstall RepoBar." }
            return
        }

        let installScript = """
        #!/usr/bin/env bash
        set -euo pipefail
        HELPER="\(helperURL.path)"
        TARGETS=("/usr/local/bin/repobar" "/opt/homebrew/bin/repobar")

        for t in "${TARGETS[@]}"; do
          mkdir -p "$(dirname "$t")"
          ln -sf "$HELPER" "$t"
          echo "Linked $t -> $HELPER"
        done
        """

        do {
            let scriptURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("install_repobar_cli.sh")
            defer { try? FileManager.default.removeItem(at: scriptURL) }
            try installScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let escapedPath = scriptURL.path.replacingOccurrences(of: "\"", with: "\\\"")
            let appleScript = "do shell script \"bash \\\"\(escapedPath)\\\"\" with administrator privileges"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript]
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()
            let status: String
            if process.terminationStatus == 0 {
                status = "Installed. Try: repobar --help"
            } else {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                status = "Failed: \(msg ?? "error")"
            }
            await MainActor.run { self.cliStatus = status }
        } catch {
            await MainActor.run { self.cliStatus = "Failed: \(error.localizedDescription)" }
        }
    }

    private static let cliTargets = [
        "/usr/local/bin/repobar",
        "/opt/homebrew/bin/repobar"
    ]

    private var preferredTerminalBinding: Binding<String> {
        Binding(
            get: {
                self.session.settings.localProjects.preferredTerminal ?? TerminalApp.defaultPreferred.rawValue
            },
            set: { newValue in
                self.session.settings.localProjects.preferredTerminal = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var ghosttyOpenModeBinding: Binding<GhosttyOpenMode> {
        Binding(
            get: { self.session.settings.localProjects.ghosttyOpenMode },
            set: { newValue in
                self.session.settings.localProjects.ghosttyOpenMode = newValue
                self.appState.persistSettings()
            }
        )
    }

    private var isGhosttySelected: Bool {
        TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal) == .ghostty
    }

    private var worktreeFolderBinding: Binding<String> {
        Binding(
            get: {
                self.session.settings.localProjects.worktreeFolderName
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                self.session.settings.localProjects.worktreeFolderName = trimmed.isEmpty ? ".work" : trimmed
                self.appState.persistSettings()
            }
        )
    }

    private var aiSummaryModelBinding: Binding<String> {
        Binding(
            get: { self.session.settings.aiSummaries.model },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.session.settings.aiSummaries.model = trimmed.isEmpty ? AISummarySettings.defaultModel : trimmed
                self.appState.persistSettings()
            }
        )
    }

    private func refreshOpenAIKeyStatus() {
        self.openAIKeyStatus = self.appState.openAIAPIKeySource().label
    }

    private func saveOpenAIAPIKey() {
        do {
            try self.appState.saveOpenAIAPIKey(self.openAIAPIKey)
            self.openAIAPIKey = ""
            self.refreshOpenAIKeyStatus()
        } catch {
            self.openAIKeyStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func clearOpenAIAPIKey() {
        self.appState.clearOpenAIAPIKey()
        self.openAIAPIKey = ""
        self.refreshOpenAIKeyStatus()
    }

    private func pickProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let existing = self.session.settings.localProjects.rootPath {
            panel.directoryURL = URL(fileURLWithPath: PathFormatter.expandTilde(existing), isDirectory: true)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            panel.directoryURL = home.appendingPathComponent("Projects", isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            let filePathURL = (url as NSURL).filePathURL ?? url
            let resolvedPath = filePathURL.resolvingSymlinksInPath().path
            self.session.settings.localProjects.rootPath = PathFormatter.abbreviateHome(resolvedPath)
            self.session.settings.localProjects.rootBookmarkData = SecurityScopedBookmark.create(for: url)
            self.appState.persistSettings()
            self.appState.refreshLocalProjects(forceRescan: true)
            self.appState.requestRefresh(cancelInFlight: true)
        }
    }

    private func clearProjectFolder() {
        self.session.settings.localProjects.rootPath = nil
        self.session.settings.localProjects.rootBookmarkData = nil
        self.appState.persistSettings()
        self.appState.refreshLocalProjects(forceRescan: true)
        self.appState.requestRefresh(cancelInFlight: true)
    }

    private func ensurePreferredTerminal() {
        let resolved = TerminalApp.resolve(self.session.settings.localProjects.preferredTerminal).rawValue
        if self.session.settings.localProjects.preferredTerminal != resolved {
            self.session.settings.localProjects.preferredTerminal = resolved
            self.appState.persistSettings()
        }
    }
}
