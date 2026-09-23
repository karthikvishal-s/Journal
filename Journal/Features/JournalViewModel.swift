import Combine
import Foundation
import SwiftUI

/// Drives the unlocked journal: which day is selected, which entry is open,
/// and getting edits saved without the user ever thinking about it.
@MainActor
final class JournalViewModel: ObservableObject {

    enum SaveState: Equatable {
        case idle
        case editing
        case saved
        case failed(String)
    }

    private let store: EntryStore

    @Published private(set) var index: EntryIndex
    @Published var selectedDay: Date
    @Published private(set) var openEntry: Entry?
    @Published private(set) var saveState: SaveState = .idle

    /// Bound directly to the editor. Every keystroke lands here and schedules a
    /// save; the entry itself is only touched when that save fires.
    @Published var draftBody: String = ""
    @Published var draftTitle: String = ""

    private var saveTask: Task<Void, Never>?
    private var savedIndicatorTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    /// How long to wait after the last keystroke. Long enough not to churn the
    /// disk mid-sentence, short enough that closing the lid never loses a line.
    private let autosaveDelay: Duration = .milliseconds(800)

    init(store: EntryStore, today: Date = Date()) {
        self.store = store
        self.index = store.index
        self.selectedDay = Calendar.current.startOfDay(for: today)

        // Any edit to either field schedules a save.
        Publishers.Merge(
            $draftBody.dropFirst().map { _ in () },
            $draftTitle.dropFirst().map { _ in () }
        )
        .sink { [weak self] in self?.scheduleSave() }
        .store(in: &cancellables)

        openOrCreateEntry(for: selectedDay, createIfMissing: false)
    }

    // MARK: - Selection

    func select(day: Date) {
        flushPendingSave()
        selectedDay = Calendar.current.startOfDay(for: day)
        openOrCreateEntry(for: selectedDay, createIfMissing: false)
    }

    func open(entryID: UUID) {
        flushPendingSave()
        guard let entry = try? store.loadEntry(id: entryID) else { return }
        selectedDay = entry.day
        load(entry)
    }

    /// ⌘T
    func jumpToToday() {
        select(day: Date())
    }

    /// ⌘N — a new entry on the selected day. Days can hold several.
    func newEntry(on day: Date? = nil) {
        flushPendingSave()
        let target = Calendar.current.startOfDay(for: day ?? selectedDay)
        selectedDay = target
        load(Entry(day: target))
    }

    private func openOrCreateEntry(for day: Date, createIfMissing: Bool) {
        let existing = index.records(on: day)
        if let first = existing.first, let entry = try? store.loadEntry(id: first.id) {
            load(entry)
        } else if createIfMissing {
            load(Entry(day: day))
        } else {
            load(Entry(day: day))
        }
    }

    private func load(_ entry: Entry) {
        openEntry = entry
        // Assigning these fires the publishers, so suppress the save they'd
        // otherwise schedule — loading an entry is not an edit.
        suppressNextSave = true
        draftTitle = entry.title
        draftBody = entry.body
        suppressNextSave = false
        saveState = .idle
    }

    private var suppressNextSave = false

    // MARK: - Metadata edits
    //
    // Mood and tags save immediately: they're single deliberate actions, and
    // waiting 800ms to confirm a tap would feel broken.

    func setMood(_ mood: Mood?) {
        guard var entry = openEntry else { return }
        entry.mood = entry.mood == mood ? nil : mood   // tapping the same mood clears it
        openEntry = entry
        save(entry)
    }

    func addTag(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !tag.isEmpty, var entry = openEntry else { return }
        guard !entry.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }

        entry.tags.append(tag)
        openEntry = entry
        save(entry)
    }

    func removeTag(_ tag: String) {
        guard var entry = openEntry else { return }
        entry.tags.removeAll { $0 == tag }
        openEntry = entry
        save(entry)
    }

    func deleteOpenEntry() {
        guard let entry = openEntry else { return }
        saveTask?.cancel()
        try? store.delete(id: entry.id)
        index = store.index
        load(Entry(day: selectedDay))
    }

    // MARK: - Saving

    private func scheduleSave() {
        guard !suppressNextSave else { return }
        saveState = .editing
        saveTask?.cancel()

        saveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self.commitDraft()
        }
    }

    /// Writes immediately, cancelling any pending debounce. Called before the
    /// open entry changes and when the app locks — the two moments where a
    /// pending save would otherwise be lost.
    func flushPendingSave() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        commitDraft()
    }

    private func commitDraft() {
        guard var entry = openEntry else { return }

        let titleChanged = entry.title != draftTitle
        let bodyChanged = entry.body != draftBody
        guard titleChanged || bodyChanged else { return }

        entry.title = draftTitle
        entry.body = draftBody

        // Never persist a blank entry. Opening a day creates one in memory, and
        // clicking through the calendar shouldn't litter the journal with
        // empty files — or light up the calendar with dots for days you only
        // looked at.
        if entry.isEmpty {
            if index[entry.id] != nil {
                try? store.delete(id: entry.id)
                index = store.index
            }
            openEntry = entry
            saveState = .idle
            return
        }

        openEntry = entry
        save(entry)
    }

    private func save(_ entry: Entry) {
        guard !entry.isEmpty else { return }
        do {
            try store.save(entry)
            index = store.index
            openEntry = store.index[entry.id].flatMap { _ in entry }
            showSavedIndicator()
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    private func showSavedIndicator() {
        saveState = .saved
        savedIndicatorTask?.cancel()
        savedIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if self?.saveState == .saved { self?.saveState = .idle }
        }
    }

    // MARK: - Derived

    var openEntryID: UUID? { openEntry?.id }

    var wordCount: Int {
        draftBody.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    var streak: Int {
        Streak.current(days: index.daysWithEntries)
    }

    var entriesOnSelectedDay: [EntryIndexRecord] {
        index.records(on: selectedDay)
    }

    var allTags: [String] { index.allTags }

    func loadAllEntries() -> [Entry] {
        (try? store.loadAllEntries()) ?? []
    }

    func entry(id: UUID) -> Entry? {
        try? store.loadEntry(id: id)
    }
}
