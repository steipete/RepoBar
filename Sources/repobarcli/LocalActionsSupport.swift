import Commander
import Darwin
import Foundation
import RepoBarCore

struct LocalActionOutput: Encodable {
    let action: String
    let path: String
    let fullName: String?
    let success: Bool
    let didFetch: Bool?
    let didPull: Bool?
    let didPush: Bool?
}

struct LocalBranchesOutput: Encodable {
    let path: String
    let fullName: String?
    let detached: Bool
    let branches: [LocalBranchOutput]
}

struct LocalWorktreesOutput: Encodable {
    let path: String
    let fullName: String?
    let worktrees: [LocalWorktreeOutput]
}

struct CheckoutOutput: Encodable {
    let repo: String
    let destination: String
    let opened: Bool
}

struct LocalBranchOutput: Encodable {
    let name: String
    let isCurrent: Bool
    let upstream: String?
    let aheadCount: Int?
    let behindCount: Int?
    let lastCommitDate: Date?
    let lastCommitAuthor: String?

    init(_ branch: LocalGitBranchDetails) {
        self.name = branch.name
        self.isCurrent = branch.isCurrent
        self.upstream = branch.upstream
        self.aheadCount = branch.aheadCount
        self.behindCount = branch.behindCount
        self.lastCommitDate = branch.lastCommitDate
        self.lastCommitAuthor = branch.lastCommitAuthor
    }
}

struct LocalWorktreeOutput: Encodable {
    let path: String
    let branch: String?
    let isCurrent: Bool
    let upstream: String?
    let aheadCount: Int?
    let behindCount: Int?
    let lastCommitDate: Date?
    let lastCommitAuthor: String?
    let dirty: LocalDirtyOutput?

    init(_ worktree: LocalGitWorktree) {
        self.path = worktree.path.path
        self.branch = worktree.branch
        self.isCurrent = worktree.isCurrent
        self.upstream = worktree.upstream
        self.aheadCount = worktree.aheadCount
        self.behindCount = worktree.behindCount
        self.lastCommitDate = worktree.lastCommitDate
        self.lastCommitAuthor = worktree.lastCommitAuthor
        self.dirty = worktree.dirtyCounts.map(LocalDirtyOutput.init)
    }
}

struct LocalDirtyOutput: Encodable {
    let added: Int
    let modified: Int
    let deleted: Int
    let summary: String

    init(_ counts: LocalDirtyCounts) {
        self.added = counts.added
        self.modified = counts.modified
        self.deleted = counts.deleted
        self.summary = counts.summary
    }
}

struct LocalRepoResolution {
    let path: URL
    let status: LocalRepoStatus?

    var displayName: String {
        self.status?.displayName ?? PathFormatter.displayString(self.path.path)
    }
}

func requireLocalTarget(_ target: String?) throws -> String {
    guard let target, target.isEmpty == false else {
        throw ValidationError(cliText("Missing repository name or path"))
    }

    return target
}

func resolveLocalRepoTarget(_ target: String, settings: UserSettings) async throws -> LocalRepoResolution {
    let expanded = PathFormatter.expandTilde(target)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
        let url = URL(fileURLWithPath: expanded, isDirectory: isDirectory.boolValue)
        let snapshot = await LocalProjectsService().snapshot(repoRoots: [url], autoSyncEnabled: false)
        guard let status = snapshot.statuses.first else {
            throw ValidationError(cliText("No git repository found at \(PathFormatter.displayString(expanded))"))
        }

        return LocalRepoResolution(path: status.path, status: status)
    }

    guard let rootPath = settings.localProjects.rootPath, rootPath.isEmpty == false else {
        throw ValidationError(cliText("Local Projects root not set. Provide a path or set it in Settings."))
    }

    let snapshot = await LocalProjectsService().snapshot(
        rootPath: rootPath,
        maxDepth: LocalProjectsConstants.defaultMaxDepth,
        autoSyncEnabled: false
    )
    let index = LocalRepoIndex(
        statuses: snapshot.statuses,
        preferredPathsByFullName: settings.localProjects.preferredLocalPathsByFullName
    )

    if target.contains("/") {
        if let status = index.status(forFullName: target) {
            return LocalRepoResolution(path: status.path, status: status)
        }
        let name = target.split(separator: "/").last.map(String.init)
        let matches = name.flatMap { index.byNameLowercased[$0.lowercased()] } ?? []
        if matches.count == 1, let status = matches.first {
            return LocalRepoResolution(path: status.path, status: status)
        }
        if matches.count > 1 {
            let options = matches.compactMap { $0.fullName ?? $0.displayName }
                .sorted()
                .joined(separator: ", ")
            throw ValidationError(cliText("Multiple local repositories matched \(target): \(options). Use full owner/name or a path."))
        }
        throw ValidationError(cliText("No local repository matched \(target)"))
    }

    let matches = index.byNameLowercased[target.lowercased()] ?? []
    if matches.count == 1, let status = matches.first {
        return LocalRepoResolution(path: status.path, status: status)
    }
    if matches.count > 1 {
        let options = matches.compactMap { $0.fullName ?? $0.displayName }
            .sorted()
            .joined(separator: ", ")
        throw ValidationError(cliText("Multiple local repositories matched \(target): \(options). Use full owner/name or a path."))
    }
    throw ValidationError(cliText("No local repository matched \(target)"))
}

func confirmHardReset(path: String) throws {
    guard isatty(fileno(stdin)) != 0 else {
        throw ValidationError(cliText("Refusing to hard reset in non-interactive mode without --yes"))
    }

    cliPrint("Hard reset \(path) to upstream. This is destructive.")
    cliPrint("Type 'reset' to continue: ", terminator: "")
    guard let response = readLine(), response.lowercased() == "reset" else {
        throw ValidationError(cliText("Reset cancelled"))
    }
}

func openTerminal(at url: URL, settings: UserSettings) throws {
    let preferred = settings.localProjects.preferredTerminal
    let openMode = settings.localProjects.ghosttyOpenMode
    if preferred == GhosttyTerminalConfig.name, openMode == .newWindow {
        if openGhosttyNewWindow(at: url) {
            return
        }
    }

    if let preferred, preferred.isEmpty == false {
        do {
            try openPath(url.path, application: preferred)
            return
        } catch {
            // Fall back to Terminal.
        }
    }

    try openPath(url.path, application: "Terminal")
}

enum GhosttyTerminalConfig {
    static let name = "Ghostty"
}

func openGhosttyNewWindow(at url: URL) -> Bool {
    let filePath = (url as NSURL).filePathURL?.path ?? url.path
    let script = ghosttyNewWindowScript(for: filePath)
    return runAppleScript(script)
}

func ghosttyNewWindowScript(for path: String) -> String {
    let escapedPath = escapeAppleScriptString(path)
    return """
    on run
        set targetPath to \"\(escapedPath)\"
        tell application \"Ghostty\" to activate
        tell application \"System Events\"
            repeat until exists process \"Ghostty\"
                delay 0.05
            end repeat
            tell process \"Ghostty\"
                set frontmost to true
                click menu item \"New Window\" of menu \"File\" of menu bar 1
            end tell
        end tell
        delay 0.2
        tell application \"System Events\"
            set cmd to \"cd \" & quoted form of targetPath
            keystroke cmd
            key code 36
        end tell
    end run
    """
}

func escapeAppleScriptString(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

func runAppleScript(_ script: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    do {
        try process.run()
    } catch {
        return false
    }
    process.waitUntilExit()
    return process.terminationStatus == 0
}
