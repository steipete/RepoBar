import Commander
import Darwin
import Foundation
@testable import repobarcli
@testable import RepoBarCore
import Testing

@Suite(.serialized)
struct CLIEndToEndTests {
    @Test
    func `fixture commands capture output larger than pipe capacity`() throws {
        try runProcess(
            "sh",
            ["-c", "i=0; while [ $i -lt 2000 ]; do printf '%0100d\\n' 0; printf '%0100d\\n' 0 >&2; i=$((i + 1)); done"],
            in: FileManager.default.temporaryDirectory
        )
    }

    @Test
    @MainActor
    func `stdout capture handles output larger than a pipe buffer`() async throws {
        let expected = String(repeating: "output line\n", count: 16384)
        let output = try await captureStdout { print(expected, terminator: "") }
        #expect(output == expected)
    }

    @Test
    @MainActor
    func `stdout capture restores output after a thrown error`() async throws {
        await #expect(throws: FixtureError.self) {
            _ = try await captureStdout {
                print("before error")
                throw FixtureError.missing("synthetic")
            }
        }
        let output = try await captureStdout { print("after error") }
        #expect(output == "after error\n")
    }

    @Test
    @MainActor
    func `errors use stderr and leave stdout empty`() async throws {
        var diagnostic = ""
        let output = try await captureStdout {
            diagnostic = try await captureOutput(descriptor: STDERR_FILENO) {
                printError("synthetic failure")
            }
        }
        #expect(output.isEmpty)
        #expect(diagnostic.contains("Error: synthetic failure"))
        #expect(diagnostic.hasSuffix("\n"))
    }

    @Test
    @MainActor
    func `markdown command renders changelog content`() async throws {
        let url = try fixtureURL("ChangelogSample")
        let output = try await runCLI([
            "markdown",
            url.path,
            "--no-wrap",
            "--no-color"
        ])
        #expect(output.contains("Unreleased"))
        #expect(output.contains("- Added first change"))
        #expect(output.contains("- Fixed second change"))
    }

    @Test
    @MainActor
    func `changelog command parses unreleased entries`() async throws {
        let url = try fixtureURL("ChangelogSample")
        let output = try await runCLI([
            "changelog",
            url.path,
            "--release",
            "v1.0.0",
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ChangelogOutput.self, from: data)
        #expect(decoded.sections.count == 2)
        #expect(decoded.presentation?.title == "Changelog • Unreleased")
        #expect(decoded.presentation?.badgeText == "2")
    }

    @Test
    @MainActor
    func `changelog command counts entries since release tag`() async throws {
        // The existing --release test's non-empty Unreleased section never reads the tag,
        // so that test passed while --release was ignored.
        let url = try fixtureURL("ChangelogEmptyUnreleasedSample")
        let output = try await runCLI([
            "changelog",
            url.path,
            "--release",
            "0.8.7",
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ChangelogOutput.self, from: data)
        #expect(decoded.presentation?.title == "Changelog • Since 0.8.7")
        #expect(decoded.presentation?.badgeText == "2")
        #expect(decoded.presentation?.detailText == nil)
    }

    @Test
    @MainActor
    func `changelog command defaults to repo changelog`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let changelogURL = tempDir.appendingPathComponent("CHANGELOG.md")
        let contents = """
        # Changelog

        ## Unreleased
        - One

        ## 1.0.0
        - Initial
        """
        try contents.write(to: changelogURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let output = try await withCurrentDirectory(tempDir) {
            try await runCLI([
                "changelog",
                "--release",
                "v1.0.0",
                "--json"
            ])
        }

        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ChangelogOutput.self, from: data)
        #expect(decoded.presentation?.title == "Changelog • Unreleased")
        #expect(decoded.presentation?.badgeText == "1")
    }

    @Test
    @MainActor
    func `reference translate command parses copied issue shorthand`() async throws {
        let output = try await runCLI([
            "reference-translate",
            "  - scoped issue shorthand: openclaw/ClawSweeper#57",
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ReferenceTranslationOutput.self, from: data)
        #expect(decoded.matched)
        #expect(decoded.query == "repositoryIssueNumber")
        #expect(decoded.repositoryFullName == "openclaw/ClawSweeper")
        #expect(decoded.number == 57)
    }

    @Test
    @MainActor
    func `reference translate command parses copied repo name issue shorthand`() async throws {
        let output = try await runCLI([
            "reference-translate",
            "discrawl#64",
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ReferenceTranslationOutput.self, from: data)
        #expect(decoded.matched)
        #expect(decoded.query == "repositoryNameIssueNumber")
        #expect(decoded.repositoryName == "discrawl")
        #expect(decoded.number == 64)
    }

    @Test
    @MainActor
    func `reference translate command parses copied short sha`() async throws {
        let output = try await runCLI([
            "reference-translate",
            "-",
            "bare",
            "short",
            "SHA:",
            "4992546",
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ReferenceTranslationOutput.self, from: data)
        #expect(decoded.matched)
        #expect(decoded.query == "commitHash")
        #expect(decoded.hash == "4992546")
    }

    @Test
    @MainActor
    func `reference translate command parses copied workflow run url`() async throws {
        let output = try await runCLI([
            "reference-translate",
            "https://github.com/openclaw/songsee/actions/runs/25620622163",
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ReferenceTranslationOutput.self, from: data)
        #expect(decoded.matched)
        #expect(decoded.query == "repositoryWorkflowRun")
        #expect(decoded.repositoryFullName == "openclaw/songsee")
        #expect(decoded.runID == 25_620_622_163)
    }

    @Test
    @MainActor
    func `reference translate command emits multiple scoped issue matches`() async throws {
        let output = try await runCLI([
            "reference-translate",
            "Found",
            "5",
            "more",
            "in",
            "openclaw/gogcli",
            "1.",
            "#569",
            "2.",
            "#568",
            "3.",
            "#567",
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ReferenceTranslationOutput.self, from: data)
        #expect(decoded.matched)
        #expect(decoded.matches.map(\.displayText) == [
            "openclaw/gogcli#569",
            "openclaw/gogcli#568",
            "openclaw/gogcli#567"
        ])
    }

    @Test
    @MainActor
    func `reference translate command infers repo from local git path`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try runProcess("git", ["init"], in: tempDir)
        try runProcess("git", ["remote", "add", "origin", "https://github.com/openclaw/crabbox.git"], in: tempDir)

        let copiedText = """
        issues: none
          - PRs:
              - #61 feat: add checkpoint ledger store
              - #60 docs: sharpen agent workspace positioning

        gpt-5.5 high fast · \(tempDir.path) · -
        """
        let output = try await runCLI([
            "reference-translate",
            copiedText,
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ReferenceTranslationOutput.self, from: data)
        #expect(decoded.matched)
        #expect(decoded.matches.map(\.displayText) == [
            "openclaw/crabbox#61",
            "openclaw/crabbox#60"
        ])
    }

    @Test
    @MainActor
    func `reference translate command prefers local repo over prose slash words`() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try runProcess("git", ["init"], in: tempDir)
        try runProcess("git", ["remote", "add", "origin", "https://github.com/openclaw/clawhub.git"], in: tempDir)

        let copiedText = """
        Findings:
        - #2124 header avatar controls
        - #908 upload page validation errors hidden. Likely fix: surface validationError inline/toast on publish/upload forms.

        gpt-5.5 high fast · \(tempDir.path) · Context 67% left
        """
        let output = try await runCLI([
            "reference-translate",
            copiedText,
            "--json"
        ])
        let data = try #require(output.data(using: .utf8))
        let decoded = try JSONDecoder().decode(ReferenceTranslationOutput.self, from: data)
        #expect(decoded.matches.map(\.displayText) == [
            "openclaw/clawhub#2124",
            "openclaw/clawhub#908"
        ])
    }

    @Test
    @MainActor
    func `local command rejects missing root`() async throws {
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("repobar-missing-\(UUID().uuidString)")

        await #expect(throws: ValidationError.self) {
            _ = try await runCLI([
                "local",
                "--root",
                missingRoot.path,
                "--json"
            ])
        }
    }
}

private func fixtureURL(_ name: String) throws -> URL {
    guard let url = Bundle.module.url(forResource: name, withExtension: "md") else {
        throw FixtureError.missing(name)
    }

    return url
}

private enum FixtureError: Error {
    case missing(String)
}

private func runProcess(_ executable: String, _ arguments: [String], in directory: URL) throws {
    let result = try GitProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/env"),
        arguments: [executable] + arguments,
        in: directory,
        timeout: 30
    )
    guard result.terminationStatus == 0 else {
        throw ProcessError.failed(executable: executable, arguments: arguments)
    }
}

private enum ProcessError: Error {
    case failed(executable: String, arguments: [String])
}

@MainActor
private func withCurrentDirectory<T>(_ url: URL, _ work: () async throws -> T) async throws -> T {
    let previous = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(url.path)
    defer { FileManager.default.changeCurrentDirectoryPath(previous) }
    return try await work()
}

@MainActor
private func runCLI(_ args: [String]) async throws -> String {
    let argv = CLIArgumentNormalizer.normalize(["repobar"] + args)
    let program = Program(descriptors: [RepoBarRoot.descriptor()])
    let invocation = try program.resolve(argv: argv)
    var command = try RepoBarCLI.makeCommand(from: invocation)
    return try await captureStdout {
        try await command.run()
    }
}

@MainActor
private func captureStdout(_ work: () async throws -> Void) async throws -> String {
    try await captureOutput(descriptor: STDOUT_FILENO, work)
}

@MainActor
private func captureOutput(descriptor target: Int32, _ work: () async throws -> Void) async throws -> String {
    // Commands can exceed the pipe buffer before the capture starts reading.
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("repobar-output-\(UUID().uuidString)")
    let descriptor = open(url.path, O_RDWR | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    defer {
        close(descriptor)
        try? FileManager.default.removeItem(at: url)
    }

    fflush(nil)
    let original = dup(target)
    guard original >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    defer {
        fflush(nil)
        dup2(original, target)
        close(original)
    }
    guard dup2(descriptor, target) >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    try await work()
    fflush(nil)
    let data = try Data(contentsOf: url)
    return String(bytes: data, encoding: .utf8) ?? ""
}
