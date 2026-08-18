import Foundation
@testable import RepoBarCore
import Testing

struct LocalProjectsServiceTests {
    @Test
    func `path formatter abbreviates home`() {
        let user = NSUserName()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let homeResolved = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path

        #expect(PathFormatter.displayString("/Users/\(user)/Projects").hasPrefix("~"))

        let expanded = PathFormatter.expandTilde("~/Projects")
        #expect(expanded.hasSuffix("/Projects"))
        #expect(expanded.hasPrefix(home) || expanded.hasPrefix(homeResolved))
    }

    @Test
    func `local repo status details and auto sync eligibility`() {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/repo"),
            name: "repo",
            fullName: "owner/repo",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 2,
            syncState: .behind
        )
        #expect(status.displayName == "owner/repo")
        #expect(status.syncDetail.contains("Behind"))
        #expect(status.canAutoSync == true)

        let dirty = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/repo"),
            name: "repo",
            fullName: nil,
            branch: "main",
            isClean: false,
            aheadCount: 0,
            behindCount: 0,
            syncState: .dirty
        )
        #expect(dirty.canAutoSync == false)
        #expect(dirty.syncDetail == "Dirty")
    }

    @Test
    func `snapshot discovers repos and parses remote formats`() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repoA = root.appendingPathComponent("repo-a", isDirectory: true)
        let nested = root.appendingPathComponent("group", isDirectory: true)
        let repoB = nested.appendingPathComponent("repo-b", isDirectory: true)
        try FileManager.default.createDirectory(at: repoA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)

        try initializeRepo(at: repoA, origin: "git@github.com:foo/repo-a.git")
        try initializeRepo(at: repoB, origin: "https://github.com/foo/repo-b.git")

        let snapshot = await LocalProjectsService().snapshot(
            rootPath: root.path,
            maxDepth: 2,
            autoSyncEnabled: false,
            concurrencyLimit: 1
        )

        #expect(snapshot.statuses.count == 2)
        let names = Set(snapshot.statuses.map(\.displayName))
        #expect(names.contains("foo/repo-a"))
        #expect(names.contains("foo/repo-b"))
        let repoAStatus = snapshot.statuses.first(where: { $0.name == "repo-a" })
        #expect(repoAStatus?.branch == "main")
    }

    @Test
    func `snapshot discovered repo count includes all discovered even when filtered`() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repoA = root.appendingPathComponent("repo-a", isDirectory: true)
        let nested = root.appendingPathComponent("group", isDirectory: true)
        let repoB = nested.appendingPathComponent("repo-b", isDirectory: true)
        try FileManager.default.createDirectory(at: repoA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)

        try initializeRepo(at: repoA, origin: "git@github.com:foo/repo-a.git")
        try initializeRepo(at: repoB, origin: "https://github.com/foo/repo-b.git")

        let snapshot = await LocalProjectsService().snapshot(
            rootPath: root.path,
            maxDepth: 2,
            autoSyncEnabled: false,
            includeOnlyRepoNames: ["does-not-exist"],
            concurrencyLimit: 1
        )

        #expect(snapshot.discoveredRepoCount == 2)
        #expect(snapshot.statuses.isEmpty)
    }

    @Test
    func `discover repo roots accepts file reference UR ls`() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo-a", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try initializeRepo(at: repo, origin: "git@github.com:foo/repo-a.git")

        let referenceRoot = (root as NSURL).fileReferenceURL() as URL? ?? root
        let roots = LocalProjectsService().discoverRepoRoots(rootURL: referenceRoot, maxDepth: 1)

        #expect(roots.count == 1)
        #expect(roots.first?.lastPathComponent == "repo-a")
    }

    @Test
    func `discover repo roots follows symlinked directories once`() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let targetRepo = outside.appendingPathComponent("target-repo", isDirectory: true)
        try FileManager.default.createDirectory(at: targetRepo, withIntermediateDirectories: true)
        try initializeRepo(at: targetRepo, origin: "git@github.com:foo/target-repo.git")

        let linkedRepo = root.appendingPathComponent("linked-repo", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedRepo, withDestinationURL: targetRepo)
        let loop = root.appendingPathComponent("loop", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: root)

        let roots = LocalProjectsService().discoverRepoRoots(rootURL: root, maxDepth: 2)

        #expect(roots.map(\.lastPathComponent) == ["linked-repo"])
    }

    @Test
    func `snapshot auto sync fast forward pulls behind repos`() async throws {
        let base = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let scanRoot = base.appendingPathComponent("scan", isDirectory: true)
        let origin = base.appendingPathComponent("origin.git", isDirectory: true)
        try FileManager.default.createDirectory(at: scanRoot, withIntermediateDirectories: true)

        try runGit(["init", "--bare", origin.path], in: base)

        let repoA = scanRoot.appendingPathComponent("repo-a", isDirectory: true)
        let repoB = scanRoot.appendingPathComponent("repo-b", isDirectory: true)
        _ = try runGit(["clone", origin.path, repoA.lastPathComponent], in: scanRoot)

        try runGit(["switch", "-c", "main"], in: repoA)
        try runGit(["config", "user.email", "repobar-tests@example.com"], in: repoA)
        try runGit(["config", "user.name", "RepoBar Tests"], in: repoA)
        try writeFile(repoA.appendingPathComponent("README.md"), contents: "a\n")
        try runGit(["add", "."], in: repoA)
        try runGit(["commit", "-m", "init"], in: repoA)
        try runGit(["push", "-u", "origin", "main"], in: repoA)

        _ = try runGit(["clone", origin.path, repoB.lastPathComponent], in: scanRoot)
        try runGit(["switch", "main"], in: repoB)

        try writeFile(repoA.appendingPathComponent("README.md"), contents: "a\nb\n")
        try runGit(["add", "."], in: repoA)
        try runGit(["commit", "-m", "next"], in: repoA)
        try runGit(["push"], in: repoA)

        let snapshot = await LocalProjectsService().snapshot(
            rootPath: scanRoot.path,
            maxDepth: 1,
            autoSyncEnabled: true,
            concurrencyLimit: 1
        )

        #expect(snapshot.statuses.count == 2)
        #expect(snapshot.syncedStatuses.count == 1)

        let repoBStatus = snapshot.statuses.first(where: { $0.name == "repo-b" })
        #expect(repoBStatus != nil)
        #expect(repoBStatus?.syncState == .synced)
    }

    @Test
    func `local repo index matches case insensitive names and full names`() {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/CodexBar"),
            name: "CodexBar",
            fullName: "steipete/CodexBar",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let index = LocalRepoIndex(statuses: [status])
        let repo = makeRepository(name: "codexbar", owner: "steipete")

        #expect(index.status(for: repo) != nil)
        #expect(index.status(forFullName: "STEIPETE/CODEXBAR") != nil)
    }

    @Test
    func `local repo index rejects same owner and name on a different host`() throws {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/RepoBar"),
            name: "RepoBar",
            fullName: "steipete/RepoBar",
            remoteHost: "github.com",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let index = LocalRepoIndex(statuses: [status])
        let repo = makeRepository(name: "RepoBar", owner: "steipete")
        let github = try #require(URL(string: "https://github.com"))
        let enterprise = try #require(URL(string: "https://ghe.example.com"))

        #expect(index.status(for: repo, host: github)?.path == status.path)
        #expect(index.status(for: repo, host: enterprise) == nil)
    }

    @Test
    func `same host account rows may share a local checkout`() throws {
        let status = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/RepoBar"),
            name: "RepoBar",
            fullName: "steipete/RepoBar",
            remoteHost: "github.com",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let index = LocalRepoIndex(statuses: [status])
        let host = try #require(URL(string: "https://github.com"))

        let firstAccountMatch = index.status(forFullName: "steipete/RepoBar", host: host)
        let secondAccountMatch = index.status(forFullName: "steipete/RepoBar", host: host)

        #expect(firstAccountMatch?.path == status.path)
        #expect(secondAccountMatch?.path == status.path)
    }

    @Test
    func `local repo index prefers higher hierarchy for duplicate full names`() {
        let worktree = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/Repo/.work/feature"),
            name: "Repo",
            fullName: "owner/Repo",
            branch: "feature",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced,
            worktreeName: "feature"
        )
        let root = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/Repo"),
            name: "Repo",
            fullName: "owner/Repo",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let index = LocalRepoIndex(statuses: [worktree, root])

        let selected = index.status(forFullName: "OWNER/REPO")
        #expect(selected?.path.path == root.path.path)
    }

    @Test
    func `local repo index prefers preferred path`() {
        let primary = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/repo-a"),
            name: "Repo",
            fullName: nil,
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let secondary = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/repo-b"),
            name: "Repo",
            fullName: nil,
            branch: "feature",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let index = LocalRepoIndex(
            statuses: [primary, secondary],
            preferredPathsByFullName: ["owner/repo": secondary.path.path]
        )

        let selected = index.status(forFullName: "owner/repo")
        #expect(selected?.path.path == secondary.path.path)
    }

    @Test
    func `local repo index matches containing paths`() {
        let root = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/repo"),
            name: "repo",
            fullName: "owner/repo",
            branch: "main",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced
        )
        let worktree = LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/repo/.work/feature"),
            name: "repo",
            fullName: "owner/repo",
            branch: "feature",
            isClean: true,
            aheadCount: 0,
            behindCount: 0,
            syncState: .synced,
            worktreeName: "feature"
        )
        let index = LocalRepoIndex(statuses: [root, worktree])

        #expect(index.status(containingPath: "/tmp/repo/Sources/File.swift")?.path.path == root.path.path)
        #expect(index.status(containingPath: "/tmp/repo/.work/feature/Sources/File.swift")?.path.path == worktree.path.path)
    }

    @Test
    func `snapshot includes worktree name for worktrees`() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try initializeRepo(at: repo, origin: "git@github.com:foo/repo.git")

        let worktree = root.appendingPathComponent("repo-worktree", isDirectory: true)
        _ = try runGit(["worktree", "add", worktree.path, "-b", "feature"], in: repo)

        let snapshot = await LocalProjectsService().snapshot(
            rootPath: root.path,
            maxDepth: 1,
            autoSyncEnabled: false,
            concurrencyLimit: 1
        )

        let worktreeStatus = snapshot.statuses.first(where: { $0.path.lastPathComponent == "repo-worktree" })
        #expect(worktreeStatus != nil)
        #expect(worktreeStatus?.worktreeName != nil)
        #expect(worktreeStatus?.branch == "feature")
    }

    @Test
    func `snapshot limits dirty files`() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try initializeRepo(at: repo, origin: "git@github.com:foo/repo.git")

        for index in 0 ..< 12 {
            try writeFile(repo.appendingPathComponent("file-\(index).txt"), contents: "\(index)\n")
        }

        let snapshot = await LocalProjectsService().snapshot(
            rootPath: root.path,
            maxDepth: 1,
            autoSyncEnabled: false,
            concurrencyLimit: 1
        )

        let status = snapshot.statuses.first(where: { $0.name == "repo" })
        #expect(status != nil)
        #expect(status?.dirtyFiles.count == LocalProjectsConstants.dirtyFileLimit)
        let dirtySet = Set(status?.dirtyFiles ?? [])
        let created = Set((0 ..< 12).map { "file-\($0).txt" })
        #expect(dirtySet.isSubset(of: created))
    }
}

private func makeTempDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("repobar-localprojects-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeFile(_ url: URL, contents: String) throws {
    try Data(contents.utf8).write(to: url, options: .atomic)
}

@discardableResult
private func runGit(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.currentDirectoryURL = directory
    process.arguments = arguments

    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err

    try process.run()
    process.waitUntilExit()

    let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if process.terminationStatus != 0 {
        throw GitTestError.commandFailed(arguments: arguments, output: output, error: error)
    }
    return output
}

private func initializeRepo(at url: URL, origin: String) throws {
    try runGit(["init"], in: url)
    try runGit(["switch", "-c", "main"], in: url)
    try runGit(["config", "user.email", "repobar-tests@example.com"], in: url)
    try runGit(["config", "user.name", "RepoBar Tests"], in: url)
    try runGit(["remote", "add", "origin", origin], in: url)
    try writeFile(url.appendingPathComponent("README.md"), contents: "test\n")
    try runGit(["add", "."], in: url)
    try runGit(["commit", "-m", "init"], in: url)
}

private func makeRepository(name: String, owner: String) -> Repository {
    Repository(
        id: UUID().uuidString,
        name: name,
        owner: owner,
        isFork: false,
        isArchived: false,
        sortOrder: nil,
        error: nil,
        rateLimitedUntil: nil,
        ciStatus: .unknown,
        ciRunCount: nil,
        openIssues: 0,
        openPulls: 0,
        stars: 0,
        forks: 0,
        pushedAt: nil,
        latestRelease: nil,
        latestActivity: nil,
        activityEvents: [],
        traffic: nil,
        heatmap: [],
        detailCacheState: nil
    )
}

private enum GitTestError: Error {
    case commandFailed(arguments: [String], output: String, error: String)
}
