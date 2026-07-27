import Foundation
import Markdown

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case listItem(marker: String, text: String, indentLevel: Int)
    case codeBlock(text: String)
    case blockQuote(text: String, indentLevel: Int)
    case blankLine
}

public enum MarkdownBlockParser {
    public static func parse(markdown: String) -> [MarkdownBlock] {
        let document = Document(parsing: markdown)
        var builder = MarkdownBlockBuilder()
        return builder.blocks(from: document)
    }
}

private struct MarkdownBlockBuilder {
    mutating func blocks(from markup: Markup) -> [MarkdownBlock] {
        var output: [MarkdownBlock] = []
        self.appendBlocks(from: markup, into: &output)
        return output
    }

    private mutating func appendBlocks(from markup: Markup, into blocks: inout [MarkdownBlock]) {
        switch markup {
        case let heading as Heading:
            let text = self.inlineMarkdown(from: heading)
            if text.isEmpty == false {
                blocks.append(.heading(level: heading.level, text: text))
            }
        case let paragraph as Paragraph:
            let text = self.inlineMarkdown(from: paragraph)
            if text.isEmpty == false {
                blocks.append(.paragraph(text: text))
            }
        case let list as UnorderedList:
            self.appendUnorderedList(list, into: &blocks)
        case let list as OrderedList:
            self.appendOrderedList(list, into: &blocks)
        case let codeBlock as CodeBlock:
            blocks.append(.codeBlock(text: self.trimTrailingNewlines(codeBlock.code)))
        case let blockQuote as BlockQuote:
            self.appendBlockQuote(blockQuote, into: &blocks)
        case _ as ThematicBreak:
            blocks.append(.blankLine)
        default:
            for child in markup.children {
                self.appendBlocks(from: child, into: &blocks)
            }
        }
    }

    private mutating func appendUnorderedList(_ list: UnorderedList, into blocks: inout [MarkdownBlock]) {
        let depth = list.listDepth
        for listItem in list.listItems {
            self.appendListItem(listItem, marker: "•", indentLevel: depth, into: &blocks)
        }
    }

    private mutating func appendOrderedList(_ list: OrderedList, into blocks: inout [MarkdownBlock]) {
        let depth = list.listDepth
        for (index, listItem) in list.listItems.enumerated() {
            self.appendListItem(listItem, marker: "\(index + 1).", indentLevel: depth, into: &blocks)
        }
    }

    private mutating func appendListItem(
        _ listItem: ListItem,
        marker: String,
        indentLevel: Int,
        into blocks: inout [MarkdownBlock]
    ) {
        let paragraphs = listItem.children.compactMap { child -> String? in
            guard let paragraph = child as? Paragraph else { return nil }

            let text = self.inlineMarkdown(from: paragraph)
            return text.isEmpty ? nil : text
        }
        let text = paragraphs.joined(separator: "\n")
        if text.isEmpty == false {
            blocks.append(.listItem(marker: marker, text: text, indentLevel: indentLevel))
        }

        for child in listItem.children {
            if child is Paragraph {
                continue
            }
            self.appendBlocks(from: child, into: &blocks)
        }
    }

    private mutating func appendBlockQuote(_ blockQuote: BlockQuote, into blocks: inout [MarkdownBlock]) {
        let depth = blockQuote.quoteDepth
        for child in blockQuote.children {
            if let paragraph = child as? Paragraph {
                let text = self.inlineMarkdown(from: paragraph)
                if text.isEmpty == false {
                    blocks.append(.blockQuote(text: text, indentLevel: depth))
                }
                continue
            }
            self.appendBlocks(from: child, into: &blocks)
        }
    }

    private func inlineMarkdown(from markup: Markup) -> String {
        if let text = markup as? Text {
            return text.plainText
        }
        if let softBreak = markup as? SoftBreak {
            return softBreak.renderedText
        }
        if let hardBreak = markup as? LineBreak {
            return hardBreak.renderedText
        }
        if let inlineCode = markup as? InlineCode {
            return "`\(inlineCode.code)`"
        }
        if let strong = markup as? Strong {
            return "**\(self.inlineMarkdown(fromChildrenOf: strong))**"
        }
        if let emphasis = markup as? Emphasis {
            return "*\(self.inlineMarkdown(fromChildrenOf: emphasis))*"
        }
        if let strikethrough = markup as? Strikethrough {
            return "~~\(self.inlineMarkdown(fromChildrenOf: strikethrough))~~"
        }
        if let link = markup as? Link {
            let label = self.inlineMarkdown(fromChildrenOf: link)
            if let destination = link.destination {
                return "[\(label)](\(destination))"
            }
            return label
        }
        if let image = markup as? Image {
            let label = self.inlineMarkdown(fromChildrenOf: image)
            if let source = image.source {
                return "![\(label)](\(source))"
            }
            return "![\(label)]"
        }

        return self.inlineMarkdown(fromChildrenOf: markup)
    }

    private func inlineMarkdown(fromChildrenOf markup: Markup) -> String {
        markup.children.map { self.inlineMarkdown(from: $0) }.joined()
    }

    private func trimTrailingNewlines(_ text: String) -> String {
        var result = text
        while let last = result.last, last == "\n" || last == "\r" {
            result.removeLast()
        }
        return result
    }
}

private extension SoftBreak {
    var renderedText: String {
        "\n"
    }
}

private extension LineBreak {
    var renderedText: String {
        "\n"
    }
}

private extension ListItemContainer {
    var listDepth: Int {
        var depth = 0
        var current = self.parent
        while let element = current {
            if element is ListItemContainer {
                depth += 1
            }
            current = element.parent
        }
        return depth
    }
}

private extension BlockQuote {
    var quoteDepth: Int {
        var depth = 0
        var current = self.parent
        while let element = current {
            if element is BlockQuote {
                depth += 1
            }
            current = element.parent
        }
        return depth
    }
}
