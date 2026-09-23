import AppKit
import SwiftUI

/// The writing surface: an `NSTextView` with live Markdown styling.
///
/// SwiftUI's `TextEditor` can't do per-range attributes, which is the whole
/// point of the live-styling editor, so this drops to AppKit. The binding is
/// one-way-at-a-time: typing pushes text out through `onChange`, and the view
/// only pulls text back in when it differs from what's on screen — otherwise
/// every keystroke would reset the cursor to the end of the document.
struct MarkdownTextView: NSViewRepresentable {

    @Binding var text: String
    var isEditable: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false          // typing must not carry pasted styling
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isEditable = isEditable
        textView.font = Theme.readingNSFont()
        textView.textColor = NSColor(Theme.ink)
        textView.insertionPointColor = NSColor(Theme.accent)

        // Generous margins: the text should sit in the page, not against it.
        textView.textContainerInset = NSSize(width: 4, height: 18)
        textView.textContainer?.lineFragmentPadding = 0

        // Typing niceties that suit prose. Smart quotes on, but no automatic
        // spelling *correction* — a journal is full of names and shorthand and
        // silently rewriting them would be maddening.
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false

        textView.string = text
        if let storage = textView.textStorage {
            MarkdownHighlighter.apply(to: storage)
        }

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable

        // Only replace the contents when the model genuinely diverged — i.e.
        // the user switched entries — never on the echo of their own typing.
        if textView.string != text {
            let selected = textView.selectedRange()
            textView.string = text
            if let storage = textView.textStorage {
                MarkdownHighlighter.apply(to: storage)
            }
            let safeLocation = min(selected.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MarkdownTextView
        weak var textView: NSTextView?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            // Re-style after the edit, preserving the cursor. Re-applying
            // attributes moves the selection unless it's restored explicitly.
            if let storage = textView.textStorage {
                let selected = textView.selectedRange()
                MarkdownHighlighter.apply(to: storage)
                textView.setSelectedRange(selected)
            }
        }

        /// Continues a list when the user presses Return on a list line — the
        /// one bit of automation that genuinely helps while writing.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn range: NSRange,
            replacementString: String?
        ) -> Bool {
            guard replacementString == "\n" else { return true }

            let text = textView.string as NSString
            let lineRange = text.lineRange(for: NSRange(location: range.location, length: 0))
            let line = text.substring(with: lineRange).trimmingCharacters(in: .newlines)

            guard let marker = listMarker(for: line) else { return true }

            // Return on an empty list item ends the list instead of adding
            // another empty bullet.
            if line.trimmingCharacters(in: .whitespaces) == marker.trimmingCharacters(in: .whitespaces) {
                textView.insertText("\n", replacementRange: lineRange)
                return false
            }

            textView.insertText("\n" + marker, replacementRange: range)
            return false
        }

        /// Returns the marker to repeat on the next line, incrementing numbers.
        private func listMarker(for line: String) -> String? {
            let leadingSpaces = String(line.prefix { $0 == " " || $0 == "\t" })
            let trimmed = line.drop { $0 == " " || $0 == "\t" }

            for bullet in ["- ", "* ", "+ "] where trimmed.hasPrefix(bullet) {
                return leadingSpaces + bullet
            }

            // "3. " becomes "4. "
            let scanner = Scanner(string: String(trimmed))
            if let number = scanner.scanInt(),
               scanner.scanString(".") != nil,
               scanner.scanString(" ") != nil || trimmed.hasPrefix("\(number). ") {
                return leadingSpaces + "\(number + 1). "
            }
            return nil
        }
    }
}
