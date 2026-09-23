import SwiftUI

/// Full-text search. Entries are decrypted into memory when this opens and
/// released when it closes — nothing searchable is ever written to disk.
struct SearchView: View {

    @ObservedObject var model: JournalViewModel
    let onOpen: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var entries: [Entry] = []
    @State private var results: [SearchEngine.Result] = []
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.rule)
            resultsList
        }
        .frame(width: 620, height: 460)
        .background(Theme.paper)
        .onAppear {
            entries = model.loadAllEntries()
            fieldFocused = true
        }
        .onDisappear {
            // Drop the decrypted copies as soon as the sheet closes.
            entries = []
            results = []
        }
        .onChange(of: query) { _, newValue in
            results = SearchEngine.search(query: newValue, in: entries, index: model.index)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkFaint)

            TextField("Search your journal", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.reading(16))
                .foregroundStyle(Theme.ink)
                .focused($fieldFocused)

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(Theme.chromeFont(12))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var resultsList: some View {
        if query.isEmpty {
            placeholder("Type to search across every entry.")
        } else if results.isEmpty {
            placeholder("Nothing matches “\(query)”.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { result in
                        resultRow(result)
                        Divider().overlay(Theme.rule.opacity(0.5))
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(Theme.chromeFont(12))
                .foregroundStyle(Theme.inkFaint)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func resultRow(_ result: SearchEngine.Result) -> some View {
        Button {
            onOpen(result.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if let mood = result.record.mood {
                        Text(mood.emoji).font(.system(size: 11))
                    }
                    Text(result.record.title)
                        .font(Theme.reading(14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(result.record.day, format: .dateTime.day().month(.abbreviated).year())
                        .font(Theme.chromeFont(10))
                        .foregroundStyle(Theme.inkFaint)
                }

                Text(result.snippet)
                    .font(Theme.reading(12))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
