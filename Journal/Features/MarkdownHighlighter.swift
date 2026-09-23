import AppKit
import Foundation

/// Styles Markdown in place as the user types.
///
/// This is not a renderer: the text stays exactly as written, character for
/// character. What changes is how it looks — a heading grows, `**bold**` turns
/// bold, and the `#` and `*` markers fade back so they stop competing with the
/// prose. The markers stay visible and editable, which is what makes this
/// workable without a preview mode: nothing is hidden, so the cursor never
/// lands somewhere the user can't see.
enum MarkdownHighlighter {

    private static let patterns: [(regex: NSRegularExpression, style: Style)] = {
        func re(_ pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression {
            // Patterns are literals written here; a failure is a programming
            // error, not a runtime condition.
            try! NSRegularExpression(pattern: pattern, options: options)
        }

        return [
            // Headings: #, ##, ### at the start of a line. Group 1 is the
            // marker, group 2 the text.
            (re(#"^(#{1,6}\s)(.*)$"#, options: [.anchorsMatchLines]), .heading),
            // Blockquote.
            (re(#"^(>\s)(.*)$"#, options: [.anchorsMatchLines]), .quote),
            // Bullet and numbered list markers.
            (re(#"^(\s*[-*+]\s)"#, options: [.anchorsMatchLines]), .listMarker),
            (re(#"^(\s*\d+\.\s)"#, options: [.anchorsMatchLines]), .listMarker),
            // Bold before italic, so ** isn't mistaken for a pair of *.
            (re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\*\*|__)"#), .bold),
            (re(#"(?<![\*_])(\*|_)(?=\S)([^\*_]+?)(?<=\S)(\*|_)(?![\*_])"#), .italic),
            (re(#"(`)([^`\n]+)(`)"#), .code),
        ]
    }()

    private enum Style {
        case heading, quote, listMarker, bold, italic, code
    }

    /// Applies styling to the whole storage. Called on every edit; for the
    /// length of a journal entry this is far too fast to notice.
    static func apply(to storage: NSTextStorage, baseSize: CGFloat = Theme.readingFontSize) {
        let full = NSRange(location: 0, length: storage.length)
        let text = storage.string

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Theme.readingLineSpacing
        paragraph.paragraphSpacing = Theme.readingLineSpacing * 1.4

        storage.beginEditing()

        // Reset first, so deleting a marker removes its styling.
        storage.setAttributes([
            .font: Theme.readingNSFont(baseSize),
            .foregroundColor: NSColor(Theme.ink),
            .paragraphStyle: paragraph,
        ], range: full)

        for (regex, style) in patterns {
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match else { return }
                apply(style: style, match: match, storage: storage, baseSize: baseSize, paragraph: paragraph)
            }
        }

        storage.endEditing()
    }

    private static func apply(
        style: Style,
        match: NSTextCheckingResult,
        storage: NSTextStorage,
        baseSize: CGFloat,
        paragraph: NSParagraphStyle
    ) {
        let faint = NSColor(Theme.inkFaint)

        switch style {
        case .heading:
            guard match.numberOfRanges >= 3 else { return }
            let markerRange = match.range(at: 1)
            let textRange = match.range(at: 2)

            // Depth from the number of #s: h1 biggest, tapering to body size.
            let hashes = max(1, markerRange.length - 1)
            let size = baseSize + max(0, CGFloat(7 - hashes)) * 1.8

            storage.addAttributes([
                .font: Theme.readingNSFont(size, weight: .semibold),
                .paragraphStyle: paragraph,
            ], range: match.range)
            storage.addAttribute(.foregroundColor, value: faint, range: markerRange)
            storage.addAttribute(.foregroundColor, value: NSColor(Theme.ink), range: textRange)

        case .quote:
            guard match.numberOfRanges >= 3 else { return }
            storage.addAttributes([
                .font: Theme.readingNSFont(baseSize).italic(),
                .foregroundColor: NSColor(Theme.inkSoft),
            ], range: match.range)
            storage.addAttribute(.foregroundColor, value: faint, range: match.range(at: 1))

        case .listMarker:
            storage.addAttribute(.foregroundColor, value: NSColor(Theme.accent), range: match.range(at: 1))

        case .bold:
            guard match.numberOfRanges >= 4 else { return }
            storage.addAttribute(.font, value: Theme.readingNSFont(baseSize, weight: .bold), range: match.range)
            storage.addAttribute(.foregroundColor, value: faint, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: faint, range: match.range(at: 3))

        case .italic:
            guard match.numberOfRanges >= 4 else { return }
            storage.addAttribute(.font, value: Theme.readingNSFont(baseSize).italic(), range: match.range)
            storage.addAttribute(.foregroundColor, value: faint, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: faint, range: match.range(at: 3))

        case .code:
            guard match.numberOfRanges >= 4 else { return }
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular),
                .foregroundColor: NSColor(Theme.accent),
            ], range: match.range)
            storage.addAttribute(.foregroundColor, value: faint, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: faint, range: match.range(at: 3))
        }
    }
}

private extension NSFont {
    func italic() -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
