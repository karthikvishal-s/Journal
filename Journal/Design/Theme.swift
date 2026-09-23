import SwiftUI

/// The look: warm paper, soft ink, generous space.
///
/// Colours are defined as light/dark pairs rather than pulled from the system
/// palette, because the system greys are cool-toned and the point here is
/// paper. Everything adapts automatically via `NSColor` dynamic providers.
enum Theme {

    // MARK: - Colour

    /// The writing surface. A faint cream in light mode rather than pure white,
    /// which is what makes a long page of text comfortable to sit in front of.
    static let paper = dynamic(
        light: NSColor(srgbRed: 0.992, green: 0.980, blue: 0.957, alpha: 1),
        dark:  NSColor(srgbRed: 0.106, green: 0.102, blue: 0.098, alpha: 1)
    )

    /// Sidebar and chrome — a half-step back from the page.
    static let chrome = dynamic(
        light: NSColor(srgbRed: 0.965, green: 0.949, blue: 0.918, alpha: 1),
        dark:  NSColor(srgbRed: 0.145, green: 0.141, blue: 0.133, alpha: 1)
    )

    /// Body text. Never pure black: softer on the eye against cream.
    static let ink = dynamic(
        light: NSColor(srgbRed: 0.145, green: 0.129, blue: 0.106, alpha: 1),
        dark:  NSColor(srgbRed: 0.918, green: 0.902, blue: 0.871, alpha: 1)
    )

    /// Secondary text: dates, counts, hints.
    static let inkSoft = dynamic(
        light: NSColor(srgbRed: 0.404, green: 0.376, blue: 0.333, alpha: 1),
        dark:  NSColor(srgbRed: 0.616, green: 0.596, blue: 0.565, alpha: 1)
    )

    /// Markdown syntax markers, placeholder text — present but receding.
    static let inkFaint = dynamic(
        light: NSColor(srgbRed: 0.627, green: 0.596, blue: 0.545, alpha: 1),
        dark:  NSColor(srgbRed: 0.435, green: 0.420, blue: 0.396, alpha: 1)
    )

    /// A muted terracotta. Used sparingly: today's date, the streak, selection.
    static let accent = dynamic(
        light: NSColor(srgbRed: 0.694, green: 0.396, blue: 0.290, alpha: 1),
        dark:  NSColor(srgbRed: 0.839, green: 0.541, blue: 0.424, alpha: 1)
    )

    static let rule = dynamic(
        light: NSColor(srgbRed: 0.878, green: 0.851, blue: 0.804, alpha: 1),
        dark:  NSColor(srgbRed: 0.231, green: 0.224, blue: 0.212, alpha: 1)
    )

    static let selection = dynamic(
        light: NSColor(srgbRed: 0.929, green: 0.898, blue: 0.847, alpha: 1),
        dark:  NSColor(srgbRed: 0.204, green: 0.196, blue: 0.184, alpha: 1)
    )

    // MARK: - Type
    //
    // A serif for prose — it is what makes the page read like a notebook rather
    // than a text field — and the system sans for chrome, where clarity at
    // small sizes matters more than character.

    static let readingFontSize: CGFloat = 17
    static let readingLineSpacing: CGFloat = 8

    static func reading(_ size: CGFloat = readingFontSize, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func readingNSFont(_ size: CGFloat = readingFontSize, weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func chromeFont(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: - Metrics

    static let pageInset: CGFloat = 56
    static let cornerRadius: CGFloat = 10

    // MARK: - Internals

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    /// Standard page background, used by every full-window view.
    func paperBackground() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }
}
