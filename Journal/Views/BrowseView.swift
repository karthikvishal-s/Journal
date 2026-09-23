import SwiftUI

/// Timeline of every entry, filterable by month, mood and tag.
///
/// Reads from the encrypted index rather than opening entries, so scrolling
/// years of journal never decrypts a single body.
struct BrowseView: View {

    @ObservedObject var model: JournalViewModel
    let onOpen: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var monthFilter: Date?
    @State private var moodFilter: Mood?
    @State private var tagFilter: String?

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.rule)
            filters
            Divider().overlay(Theme.rule)
            timeline
        }
        .frame(width: 680, height: 560)
        .background(Theme.paper)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Browse")
                .font(Theme.reading(18, weight: .medium))
                .foregroundStyle(Theme.ink)

            Text("\(filtered.count) of \(model.index.records.count)")
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.inkFaint)

            Spacer()

            if hasActiveFilter {
                Button("Clear filters") {
                    monthFilter = nil; moodFilter = nil; tagFilter = nil
                }
                .buttonStyle(.plain)
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.accent)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.plain)
                .font(Theme.chromeFont(12))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var hasActiveFilter: Bool {
        monthFilter != nil || moodFilter != nil || tagFilter != nil
    }

    // MARK: - Filters

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("", selection: $monthFilter) {
                Text("All months").tag(Date?.none)
                ForEach(availableMonths, id: \.self) { month in
                    Text(month, format: .dateTime.month(.abbreviated).year()).tag(Date?.some(month))
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("", selection: $moodFilter) {
                Text("Any mood").tag(Mood?.none)
                ForEach(Mood.allCases) { mood in
                    Text("\(mood.emoji)  \(mood.label)").tag(Mood?.some(mood))
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("", selection: $tagFilter) {
                Text("Any tag").tag(String?.none)
                ForEach(model.allTags, id: \.self) { tag in
                    Text(tag).tag(String?.some(tag))
                }
            }
            .labelsHidden()
            .frame(width: 130)
            .disabled(model.allTags.isEmpty)

            Spacer()
        }
        .font(Theme.chromeFont(11))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var availableMonths: [Date] {
        let months = model.index.records.compactMap { record -> Date? in
            calendar.date(from: calendar.dateComponents([.year, .month], from: record.day))
        }
        return Array(Set(months)).sorted(by: >)
    }

    private var filtered: [EntryIndexRecord] {
        model.index.newestFirst.filter { record in
            if let monthFilter,
               !calendar.isDate(record.day, equalTo: monthFilter, toGranularity: .month) {
                return false
            }
            if let moodFilter, record.mood != moodFilter { return false }
            if let tagFilter,
               !record.tags.contains(where: { $0.caseInsensitiveCompare(tagFilter) == .orderedSame }) {
                return false
            }
            return true
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        if filtered.isEmpty {
            VStack {
                Spacer()
                Text(model.index.records.isEmpty ? "No entries yet." : "Nothing matches these filters.")
                    .font(Theme.chromeFont(12))
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedByMonth, id: \.month) { group in
                        Section {
                            ForEach(group.records) { record in
                                row(record)
                                Divider().overlay(Theme.rule.opacity(0.4))
                            }
                        } header: {
                            Text(group.month, format: .dateTime.month(.wide).year())
                                .font(Theme.chromeFont(10, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 7)
                                .background(Theme.chrome)
                        }
                    }
                }
            }
        }
    }

    private var groupedByMonth: [(month: Date, records: [EntryIndexRecord])] {
        let groups = Dictionary(grouping: filtered) { record in
            calendar.date(from: calendar.dateComponents([.year, .month], from: record.day)) ?? record.day
        }
        return groups
            .map { (month: $0.key, records: $0.value) }
            .sorted { $0.month > $1.month }
    }

    private func row(_ record: EntryIndexRecord) -> some View {
        Button {
            onOpen(record.id)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 1) {
                    Text(record.day, format: .dateTime.day())
                        .font(Theme.reading(17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text(record.day, format: .dateTime.weekday(.abbreviated))
                        .font(Theme.chromeFont(9))
                        .foregroundStyle(Theme.inkFaint)
                }
                .frame(width: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        if let mood = record.mood {
                            Text(mood.emoji).font(.system(size: 11))
                        }
                        Text(record.title)
                            .font(Theme.reading(14, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text("\(record.wordCount) word\(record.wordCount == 1 ? "" : "s")")
                            .font(Theme.chromeFont(10))
                            .foregroundStyle(Theme.inkFaint)

                        ForEach(record.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(Theme.chromeFont(9))
                                .foregroundStyle(Theme.inkSoft)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Theme.chrome))
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
