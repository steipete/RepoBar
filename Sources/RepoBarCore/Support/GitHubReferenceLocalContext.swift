import Foundation

public enum GitHubReferenceLocalContext {
    private static let repositoryFullNameCache = LocalRepositoryFullNameCache()

    public static func queries(
        _ queries: [GitHubReferenceQuery],
        applyingRepositoryFullName repositoryFullName: String?
    ) -> [GitHubReferenceQuery] {
        guard let repositoryFullName else { return queries }

        return queries.map { query in
            switch query {
            case let .issueNumber(number):
                .repositoryIssueNumber(repositoryFullName: repositoryFullName, number: number)
            case let .commitHash(hash):
                .repositoryCommitHash(repositoryFullName: repositoryFullName, hash: hash)
            case .repositoryIssueNumber, .repositoryCommitHash:
                query
            }
        }
    }

    public static func repositoryFullName(in text: String, localRepoIndex: LocalRepoIndex = .empty) async -> String? {
        let paths = self.localPathCandidates(in: text)
        guard paths.isEmpty == false else { return nil }

        var fullNames: [String] = []
        var seen: Set<String> = []
        func append(_ fullName: String) {
            guard seen.insert(fullName.lowercased()).inserted else { return }

            fullNames.append(fullName)
        }

        for path in paths {
            if let fullName = localRepoIndex.status(containingPath: path)?.fullName {
                append(fullName)
                continue
            }

            let expandedPath = PathFormatter.expandTilde(path)
            if let cached = await self.repositoryFullNameCache.value(for: expandedPath) {
                append(cached)
                continue
            }

            let task = Task.detached(priority: .utility) {
                self.gitHubRepositoryFullName(at: expandedPath)
            }
            if let fullName = await task.value {
                await self.repositoryFullNameCache.set(fullName, for: expandedPath)
                append(fullName)
            }
        }

        return fullNames.count == 1 ? fullNames[0] : nil
    }

    public static func localPathCandidates(in text: String) -> [String] {
        var paths: [String] = []
        var seen: Set<String> = []
        let trimCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ".,;:()[]{}<>\"'`“”‘’·•"))
        for rawToken in text.split(whereSeparator: \.isWhitespace) {
            let token = String(rawToken).trimmingCharacters(in: trimCharacters)
            guard token.hasPrefix("~/") || token.hasPrefix("/") else { continue }
            guard seen.insert(token).inserted else { continue }

            paths.append(token)
        }
        return paths
    }

    public nonisolated static func gitHubRepositoryFullName(at path: String) -> String? {
        #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "-C", path, "remote", "get-url", "origin"]
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_TERMINAL_PROMPT"] = "0"
            environment["GIT_OPTIONAL_LOCKS"] = "0"
            process.environment = environment

            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                return nil
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let remote = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return self.gitHubRepositoryFullName(fromRemoteURL: remote)
        #else
            nil
        #endif
    }

    public nonisolated static func gitHubRepositoryFullName(fromRemoteURL remote: String) -> String? {
        if remote.contains("://") {
            guard let url = URL(string: remote),
                  let host = url.host?.lowercased(),
                  host == "github.com" || host.hasSuffix(".github.com")
            else { return nil }

            let parts = url.path.split(separator: "/").map(String.init)
            guard parts.count >= 2 else { return nil }

            return "\(parts[parts.count - 2])/\(self.stripGitSuffix(parts.last ?? ""))"
        }

        let parts = remote.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let host = parts[0].split(separator: "@").last.map { String($0).lowercased() } ?? parts[0].lowercased()
        guard host == "github.com" || host.hasSuffix(".github.com") else { return nil }

        let pathParts = parts[1].split(separator: "/").map(String.init)
        guard pathParts.count >= 2 else { return nil }

        return "\(pathParts[pathParts.count - 2])/\(self.stripGitSuffix(pathParts.last ?? ""))"
    }

    private nonisolated static func stripGitSuffix(_ value: String) -> String {
        value.hasSuffix(".git") ? String(value.dropLast(4)) : value
    }
}

private actor LocalRepositoryFullNameCache {
    private var values: [String: String] = [:]

    func value(for path: String) -> String? {
        self.values[path]
    }

    func set(_ fullName: String, for path: String) {
        self.values[path] = fullName
    }
}
