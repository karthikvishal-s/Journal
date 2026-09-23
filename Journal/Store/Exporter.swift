import AppKit
import CoreText
import Foundation

/// Writes decrypted copies of entries out to a folder the user picks.
///
/// Everything here produces **unencrypted** files. That is the entire purpose —
/// an export you can't read isn't an export — but it means the moment these
/// land on disk they are outside every protection the rest of the app provides.
/// The UI says so, in those words, before calling any of this.
enum Exporter {

    struct Range {
        var start: Date?
        var end: Date?

        static let all = Range(start: nil, end: nil)

        func contains(_ day: Date) -> Bool {
            let target = Calendar.current.startOfDay(for: day)
            if let start, target < Calendar.current.startOfDay(for: start) { return false }
            if let end, target > Calendar.current.startOfDay(for: end) { return false }
            return true
        }
    }

    // MARK: - Markdown

    /// One `.md` file per entry, with YAML front matter so the metadata
    /// survives the trip into other tools.
    @discardableResult
    static func exportMarkdown(entries: [Entry], range: Range = .all, to directory: URL) throws -> Int {
        let selected = entries.filter { range.contains($0.day) }
        var written = 0
        var usedNames: Set<String> = []

        for entry in selected {
            var name = filename(for: entry)
            // Several entries can share a day; disambiguate rather than
            // silently overwriting one with another.
            var suffix = 2
            while usedNames.contains(name) {
                name = filename(for: entry, suffix: suffix)
                suffix += 1
            }
            usedNames.insert(name)

            let url = directory.appendingPathComponent(name)
            try markdown(for: entry).data(using: .utf8)?.write(to: url, options: [.atomic])
            written += 1
        }
        return written
    }

    private static func filename(for entry: Entry, suffix: Int? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: entry.day)

        let slug = entry.displayTitle
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(50)

        let base = slug.isEmpty ? date : "\(date)-\(slug)"
        return suffix.map { "\(base)-\($0).md" } ?? "\(base).md"
    }

    static func markdown(for entry: Entry) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var lines = ["---"]
        lines.append("date: \(formatter.string(from: entry.day))")
        if !entry.title.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("title: \(entry.title)")
        }
        if let mood = entry.mood {
            lines.append("mood: \(mood.rawValue)")
        }
        if !entry.tags.isEmpty {
            lines.append("tags: [\(entry.tags.joined(separator: ", "))]")
        }
        lines.append("words: \(entry.wordCount)")
        lines.append("---")
        lines.append("")
        lines.append(entry.body)

        return lines.joined(separator: "\n")
    }

    // MARK: - PDF

    /// A single paginated PDF of every selected entry.
    ///
    /// Built with CoreText rather than an `NSPrintOperation`, so it writes the
    /// file directly instead of putting a print dialog in the user's way.
    static func exportPDF(entries: [Entry], range: Range = .all, to url: URL) throws {
        let selected = entries.filter { range.contains($0.day) }
        let document = attributedDocument(for: selected)

        // US Letter at 72dpi, with a wide margin so the text column stays a
        // comfortable width to read.
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 72
        let textRect = CGRect(
            x: margin,
            y: margin,
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2
        )

        guard let consumer = CGDataConsumer(url: url as CFURL),
              var mediaBox = Optional(CGRect(origin: .zero, size: pageSize)),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ExportError.pdfCreationFailed
        }

        let framesetter = CTFramesetterCreateWithAttributedString(document)
        let path = CGPath(rect: textRect, transform: nil)

        var position = 0
        let length = document.length

        repeat {
            context.beginPDFPage(nil)

            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRangeMake(position, 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)

            let visible = CTFrameGetVisibleStringRange(frame)
            // A page that fits nothing would loop forever; bail instead.
            guard visible.length > 0 else {
                context.endPDFPage()
                break
            }
            position += visible.length

            context.endPDFPage()
        } while position < length

        context.closePDF()
    }

    private static func attributedDocument(for entries: [Entry]) -> NSAttributedString {
        let output = NSMutableAttributedString()

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full

        let body = NSMutableParagraphStyle()
        body.lineSpacing = 4
        body.paragraphSpacing = 12

        let heading = NSMutableParagraphStyle()
        heading.paragraphSpacing = 8
        heading.paragraphSpacingBefore = 24

        for entry in entries {
            output.append(NSAttributedString(
                string: dateFormatter.string(from: entry.day) + "\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.gray,
                    .paragraphStyle: heading,
                ]
            ))

            let title = entry.displayTitle
            if !title.isEmpty && title != "Untitled" {
                output.append(NSAttributedString(
                    string: title + "\n",
                    attributes: [
                        .font: Theme.readingNSFont(18, weight: .semibold),
                        .foregroundColor: NSColor.black,
                        .paragraphStyle: body,
                    ]
                ))
            }

            var meta: [String] = []
            if let mood = entry.mood { meta.append("\(mood.emoji) \(mood.label)") }
            if !entry.tags.isEmpty { meta.append(entry.tags.map { "#\($0)" }.joined(separator: " ")) }
            if !meta.isEmpty {
                output.append(NSAttributedString(
                    string: meta.joined(separator: "   ") + "\n",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 9),
                        .foregroundColor: NSColor.darkGray,
                        .paragraphStyle: body,
                    ]
                ))
            }

            output.append(NSAttributedString(
                string: entry.body + "\n",
                attributes: [
                    .font: Theme.readingNSFont(11),
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: body,
                ]
            ))
        }

        return output
    }
}

enum ExportError: LocalizedError {
    case pdfCreationFailed
    case noEntries

    var errorDescription: String? {
        switch self {
        case .pdfCreationFailed: return "Couldn't create the PDF file."
        case .noEntries:         return "There are no entries in that range."
        }
    }
}
