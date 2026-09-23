import SwiftUI

/// Month calendar plus the entries for the selected day.
///
/// The dots are the point: at a glance you can see which days you wrote on,
/// which is most of what anyone wants from a journal's navigation.
struct CalendarSidebar: View {

    @ObservedObject var model: JournalViewModel
    @State private var visibleMonth: Date = Date()

    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            monthHeader
            weekdayHeader
            monthGrid
            Divider().overlay(Theme.rule).padding(.vertical, 14)
            dayEntries
            Spacer(minLength: 0)
            streakFooter
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .frame(minWidth: 240)
        .background(Theme.chrome.ignoresSafeArea())
        .onChange(of: model.selectedDay) { _, day in
            // Follow the selection if it moves outside the visible month, e.g.
            // via ⌘T or a search result.
            if !calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month) {
                withAnimation(.easeInOut(duration: 0.18)) { visibleMonth = day }
            }
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack(spacing: 4) {
            Text(visibleMonth, format: .dateTime.month(.wide).year())
                .font(Theme.chromeFont(13, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Spacer()

            stepButton("chevron.left") { step(-1) }
            stepButton("chevron.right") { step(1) }
        }
        .padding(.bottom, 12)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { visibleMonth = next }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(Theme.chromeFont(10, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 6)
    }

    /// Weekday initials rotated to match the user's locale, so a calendar that
    /// starts on Monday shows M T W ... rather than S M T.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Grid

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
            ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 30)
                }
            }
        }
    }

    /// Days of the visible month, padded with nils so the first lands under the
    /// right weekday column.
    private var gridDays: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let range = calendar.range(of: .day, in: .month, for: visibleMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        let days: [Date?] = range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leadingBlanks) + days
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: model.selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasEntry = model.index.daysWithEntries.contains(calendar.startOfDay(for: day))
        let isFuture = day > Date()

        return Button {
            model.select(day: day)
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(Theme.chromeFont(12, weight: isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? Color.white
                        : isFuture ? Theme.inkFaint
                        : isToday ? Theme.accent
                        : Theme.ink
                    )

                Circle()
                    .fill(isSelected ? Color.white.opacity(0.9) : Theme.accent)
                    .frame(width: 3.5, height: 3.5)
                    .opacity(hasEntry ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Theme.accent : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isToday && !isSelected ? Theme.accent.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Entries on the selected day

    private var dayEntries: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.selectedDay, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(Theme.chromeFont(11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                Button {
                    model.newEntry()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .help("New entry on this day (⌘N)")
            }

            let records = model.entriesOnSelectedDay
            if records.isEmpty {
                Text("Nothing written yet.")
                    .font(Theme.chromeFont(11))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 2)
            } else {
                ForEach(records) { record in
                    entryRow(record)
                }
            }
        }
    }

    private func entryRow(_ record: EntryIndexRecord) -> some View {
        let isOpen = model.openEntryID == record.id

        return Button {
            model.open(entryID: record.id)
        } label: {
            HStack(spacing: 7) {
                if let mood = record.mood {
                    Text(mood.emoji).font(.system(size: 10))
                }
                Text(record.title)
                    .font(Theme.chromeFont(12))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isOpen ? Theme.selection : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streak

    private var streakFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10))
                .foregroundStyle(model.streak > 0 ? Theme.accent : Theme.inkFaint)
            Text(Streak.label(model.streak))
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
        .padding(.vertical, 12)
    }
}
