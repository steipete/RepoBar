import Commander
import Foundation

@MainActor
struct MarkdownCommand: CommanderRunnableCommand {
    nonisolated static let commandName = "markdown"

    @Option(name: .customLong("width"), help: "Wrap at N columns (defaults to terminal width)")
    var width: Int?

    @Flag(names: [.customLong("no-wrap")], help: "Disable line wrapping")
    var noWrap: Bool = false

    @Flag(names: [.customLong("plain")], help: "Plain output (strip ANSI styles)")
    var plain: Bool = false

    @Flag(names: [.customLong("no-color")], help: "Disable color output")
    var noColor: Bool = false

    @Argument
    private var path: String?

    static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: commandName,
            abstract: "Render markdown to ANSI text"
        )
    }

    mutating func bind(_ values: ParsedValues) throws {
        self.width = try values.decodeOption("width")
        self.noWrap = values.flag("noWrap")
        self.plain = values.flag("plain")
        self.noColor = values.flag("noColor")

        if values.positional.count > 1 {
            throw ValidationError(cliText("Only one markdown file can be specified"))
        }
        self.path = values.positional.first
    }

    mutating func run() async throws {
        guard let path, path.isEmpty == false else {
            throw ValidationError(cliText("Missing markdown file path"))
        }

        if let width, width <= 0 {
            throw ValidationError(cliText("--width must be greater than 0"))
        }

        let markdown = try String(contentsOfFile: path, encoding: .utf8)
        let color = (self.plain || self.noColor) ? false : Ansi.supportsColor
        let wrap: Bool? = self.noWrap ? false : nil

        let request = MarkdownRenderRequest(
            width: self.width,
            wrap: wrap,
            color: color,
            plain: self.plain
        )
        let output = renderMarkdown(markdown, request: request)
        // Rendered Markdown is user content; never run it through CLI prose localization.
        Swift.print(output)
    }
}
