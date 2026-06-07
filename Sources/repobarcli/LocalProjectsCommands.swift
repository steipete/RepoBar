import Commander
import Foundation
import RepoBarCore

@MainActor
struct LocalProjectsCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "local"

    @Option(name: .customLong("root"), help: "Project folder to scan (defaults to settings value, then ~/Projects)")
    var root: String?

    @Option(name: .customLong("depth"), help: "Max scan depth (default: 2)")
    var depth: Int = 2

    @Flag(names: [.customLong("sync")], help: "Fast-forward pull clean repos that are behind")
    var sync: Bool = false

    @Option(name: .customLong("limit"), help: "Limit processed repos (default: all)")
    var limit: Int?

    @OptionGroup
    var output: OutputOptions

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Scan local project folder for Git repositories"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.output.bind(values)
        self.root = try values.decodeOption("root")
        self.depth = try values.decodeOption("depth") ?? 2
        self.sync = values.flag("sync")
        self.limit = try values.decodeOption("limit")
    }

    mutating func run() async throws {
        if self.depth < 0 { throw ValidationError("--depth must be >= 0") }
        if let limit, limit <= 0 { throw ValidationError("--limit must be > 0") }

        let settings = cliSettingsStore().load()
        let rootPath = self.root
            ?? settings.localProjects.rootPath
            ?? "~/Projects"
        let resolvedRoot = PathFormatter.expandTilde(rootPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedRoot, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ValidationError("Local projects root does not exist: \(PathFormatter.displayString(resolvedRoot))")
        }

        let service = LocalProjectsService()
        let snapshot = await service.snapshot(
            rootPath: rootPath,
            maxDepth: self.depth,
            autoSyncEnabled: self.sync,
            maxRepoCount: self.limit
        )

        let displayRoot = PathFormatter.displayString(rootPath)

        let statuses = snapshot.statuses
        let syncedPaths = Set(snapshot.syncedStatuses.map(\.path.path))

        if self.output.jsonOutput {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = LocalProjectsOutput(
                root: displayRoot,
                resolvedRoot: resolvedRoot,
                depth: self.depth,
                syncedCount: snapshot.syncedStatuses.count,
                repositories: statuses.map { LocalRepoOutput($0, didSync: syncedPaths.contains($0.path.path)) }
            )
            let data = try encoder.encode(payload)
            if let json = String(data: data, encoding: .utf8) { print(json) }
            return
        }

        print("Local projects")
        print("Root: \(displayRoot)")
        print("Resolved: \(resolvedRoot)")
        print("Depth: \(self.depth)")
        if self.sync {
            print("Synced: \(snapshot.syncedStatuses.count)")
        }
        print("Discovered: \(snapshot.discoveredRepoCount)")
        if statuses.isEmpty {
            print("No repositories found.")
            return
        }

        for line in localProjectsTableLines(
            statuses,
            useColor: self.output.useColor,
            showSync: self.sync,
            syncedPaths: syncedPaths
        ) {
            print(line)
        }
    }
}

private struct LocalProjectsOutput: Codable {
    let root: String
    let resolvedRoot: String
    let depth: Int
    let syncedCount: Int
    let repositories: [LocalRepoOutput]
}

private struct LocalRepoOutput: Codable {
    let displayName: String
    let fullName: String?
    let branch: String
    let isClean: Bool
    let aheadCount: Int?
    let behindCount: Int?
    let syncState: String
    let synced: Bool
    let path: String

    init(_ status: LocalRepoStatus, didSync: Bool) {
        self.displayName = status.displayName
        self.fullName = status.fullName
        self.branch = status.branch
        self.isClean = status.isClean
        self.aheadCount = status.aheadCount
        self.behindCount = status.behindCount
        self.syncState = status.syncState.rawValue
        self.synced = didSync
        self.path = status.path.path
    }
}

private func localProjectsTableLines(
    _ statuses: [LocalRepoStatus],
    useColor: Bool,
    showSync: Bool,
    syncedPaths: Set<String>
) -> [String] {
    let stateHeader = "STATE"
    let branchHeader = "BRANCH"
    let repoHeader = "REPO"
    let pathHeader = "PATH"
    let syncHeader = "SYNC"

    let stateValues = statuses.map { localStateLabel($0) }
    let branchValues = statuses.map(\.branch)
    let repoValues = statuses.map(\.displayName)
    let pathValues = statuses.map { PathFormatter.displayString($0.path.path) }
    let syncValues = statuses.map { syncedPaths.contains($0.path.path) ? "✓" : "" }

    let stateWidth = max(stateHeader.count, stateValues.map(\.count).max() ?? 1)
    let branchWidth = max(branchHeader.count, branchValues.map(\.count).max() ?? 1)
    let repoWidth = max(repoHeader.count, repoValues.map(\.count).max() ?? 1)
    let pathWidth = max(pathHeader.count, pathValues.map(\.count).max() ?? 1)
    let syncWidth = showSync ? max(syncHeader.count, syncValues.map(\.count).max() ?? 1) : 0

    var headerParts = [
        padRight(stateHeader, to: stateWidth),
        padRight(branchHeader, to: branchWidth),
        padRight(repoHeader, to: repoWidth),
        padRight(pathHeader, to: pathWidth)
    ]
    if showSync {
        headerParts.append(padRight(syncHeader, to: syncWidth))
    }
    let header = headerParts.joined(separator: "  ")

    var lines: [String] = []
    lines.append(useColor ? Ansi.bold.wrap(header) : header)

    for idx in statuses.indices {
        var lineParts = [
            padRight(stateValues[idx], to: stateWidth),
            padRight(branchValues[idx], to: branchWidth),
            padRight(repoValues[idx], to: repoWidth),
            padRight(pathValues[idx], to: pathWidth)
        ]
        if showSync {
            lineParts.append(padRight(syncValues[idx], to: syncWidth))
        }
        let line = lineParts.joined(separator: "  ")
        lines.append(line)
    }

    return lines
}

private func localStateLabel(_ status: LocalRepoStatus) -> String {
    switch status.syncState {
    case .synced:
        status.isClean ? "✓" : "✓?"
    case .behind:
        status.behindCount.map { "↓\($0)" } ?? "↓"
    case .ahead:
        status.aheadCount.map { "↑\($0)" } ?? "↑"
    case .diverged:
        "⇄"
    case .dirty:
        "!"
    case .unknown:
        "?"
    }
}
