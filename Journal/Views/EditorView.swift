import SwiftUI

/// The writing page. Chrome is kept to the edges so the text has the middle.
struct EditorView: View {

    @ObservedObject var model: JournalViewModel
    @State private var tagDraft = ""
    @State private var isAddingTag = false
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    dateLine
                    titleField
                    moodRow
                    tagRow

                    MarkdownTextView(text: $model.draftBody)
                        .frame(minHeight: 420)
                        .padding(.top, 14)
                }
                .padding(.horizontal, Theme.pageInset)
                .padding(.top, 28)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            footer
        }
        .paperBackground()
    }

    // MARK: - Header

    private var dateLine: some View {
        Text(model.selectedDay, format: .dateTime.weekday(.wide).day().month(.wide).year())
            .font(Theme.chromeFont(11, weight: .medium))
            .foregroundStyle(Theme.inkFaint)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private var titleField: some View {
        TextField("Title", text: $model.draftTitle)
            .textFieldStyle(.plain)
            .font(Theme.reading(26, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.top, 8)
    }

    // MARK: - Mood

    private var moodRow: some View {
        HStack(spacing: 6) {
            ForEach(Mood.allCases) { mood in
                let isSelected = model.openEntry?.mood == mood

                Button {
                    model.setMood(mood)
                } label: {
                    Text(mood.emoji)
                        .font(.system(size: 16))
                        .saturation(isSelected ? 1 : 0)
                        .opacity(isSelected ? 1 : 0.45)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isSelected ? Theme.selection : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mood.label)
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    // MARK: - Tags

    private var tagRow: some View {
        HStack(spacing: 6) {
            ForEach(model.openEntry?.tags ?? [], id: \.self) { tag in
                HStack(spacing: 4) {
                    Text(tag)
                        .font(Theme.chromeFont(11))
                    Button {
                        model.removeTag(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.chrome))
            }

            if isAddingTag {
                TextField("tag", text: $tagDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.chromeFont(11))
                    .frame(width: 80)
                    .focused($tagFieldFocused)
                    .onSubmit(commitTag)
                    .onChange(of: tagFieldFocused) { _, focused in
                        if !focused { commitTag() }
                    }
            } else {
                Button {
                    isAddingTag = true
                    tagFieldFocused = true
                } label: {
                    Label("Tag", systemImage: "plus")
                        .font(Theme.chromeFont(11))
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.top, 10)
    }

    private func commitTag() {
        model.addTag(tagDraft)
        tagDraft = ""
        isAddingTag = false
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(model.wordCount) word\(model.wordCount == 1 ? "" : "s")")
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.inkFaint)

            Spacer()

            saveIndicator
        }
        .padding(.horizontal, Theme.pageInset)
        .padding(.vertical, 10)
        .background(Theme.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
    }

    @ViewBuilder
    private var saveIndicator: some View {
        switch model.saveState {
        case .idle:
            // Reserve the space so the footer doesn't twitch as state changes.
            Text(" ").font(Theme.chromeFont(11))
        case .editing:
            Text("Saving…")
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.inkFaint)
        case .saved:
            Label("Saved", systemImage: "checkmark")
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.inkFaint)
                .transition(.opacity)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
        }
    }
}
