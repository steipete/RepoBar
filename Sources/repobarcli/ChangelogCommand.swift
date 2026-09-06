import Commander
import Foundation
import RepoBarCore

struct ChangelogPresentationOutput: Codable {
    let title: String
    let badgeText: String?
    let detailText: String?
}

struct ChangelogSectionOutput: Codable {
    let title: String
    let entryCount: Int
}

struct ChangelogOutput: Codable {
    let sections: [ChangelogSectionOutput]
    let presentation: ChangelogPresentationOutput?
}

@MainActor
struct ChangelogCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "changelog"

    @Option(name: .customLong("release"), help: "Release tag to compare against (ex: v1.0.0)")
    var releaseTag: String?

    @OptionGroup
    var output: OutputOptions

    @Argument
    private var path: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Parse a changelog and summarize entries"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.releaseTag = try values.decodeOption("releaseTag")
        self.output.bind(values)

        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one changelog file can be specified"))
        }
        self.path = values.positional.first
    }

    mutating func run() async throws {
        let changelogURL = try resolveChangelogURL(explicitPath: path)
        let markdown = try String(contentsOf: changelogURL, encoding: .utf8)
        let parsed = ChangelogParser.parse(markdown: markdown)
        let presentation = ChangelogParser.presentation(parsed: parsed, releaseTag: self.releaseTag)

        let outputSections = parsed.sections.map { section in
            ChangelogSectionOutput(title: section.title, entryCount: section.entryCount)
        }
        let outputPresentation = presentation.map { presentation in
            ChangelogPresentationOutput(
                title: presentation.title,
                badgeText: presentation.badgeText,
                detailText: presentation.detailText
            )
        }

        if self.output.jsonOutput {
            try printJSON(ChangelogOutput(sections: outputSections, presentation: outputPresentation))
            return
        }

        cliPrint("Sections: \(outputSections.count)")
        for section in outputSections {
            cliPrint("- \(section.title) (\(section.entryCount))")
        }
        if let outputPresentation {
            cliPrint("Presentation: \(outputPresentation.title)")
            if let badge = outputPresentation.badgeText {
                cliPrint("Badge: \(badge)")
            }
            if let detail = outputPresentation.detailText {
                cliPrint("Detail: \(detail)")
            }
        } else {
            cliPrint("Presentation: -")
        }
    }
}

private func resolveChangelogURL(explicitPath: String?) throws -> URL {
    if let path = explicitPath, path.isEmpty == false {
        return URL(fileURLWithPath: path)
    }

    let roots = [gitRootURL(), URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)]
        .compactMap(\.self)
    let candidates = ["CHANGELOG.md", "CHANGELOG"]
    let manager = FileManager.default

    for root in roots {
        for name in candidates {
            let url = root.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return url
            }
        }
    }

    throw ValidationError(cliText("Missing changelog file. Provide a path or add CHANGELOG.md/CHANGELOG."))
}

private func gitRootURL() -> URL? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-parse", "--show-toplevel"]
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
    guard let path = String(bytes: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        path.isEmpty == false
    else {
        return nil
    }

    return URL(fileURLWithPath: path, isDirectory: true)
}
