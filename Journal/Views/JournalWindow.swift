import SwiftUI

/// The unlocked journal. Built with a `Session`, so this view cannot exist
/// without a decrypted store.
struct JournalWindow: View {

    let session: LockController.Session

    @EnvironmentObject private var lock: LockController
    @StateObject private var model: JournalViewModel

    @State private var isShowingSearch = false
    @State private var isShowingBrowse = false

    init(session: LockController.Session) {
        self.session = session
        _model = StateObject(wrappedValue: JournalViewModel(store: session.store))
    }

    var body: some View {
        NavigationSplitView {
            CalendarSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } detail: {
            EditorView(model: model)
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $isShowingSearch) {
            SearchView(model: model) { entryID in
                model.open(entryID: entryID)
                isShowingSearch = false
            }
        }
        .sheet(isPresented: $isShowingBrowse) {
            BrowseView(model: model) { entryID in
                model.open(entryID: entryID)
                isShowingBrowse = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalNewEntry)) { _ in
            model.newEntry()
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalJumpToToday)) { _ in
            model.jumpToToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalSearch)) { _ in
            isShowingSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalBrowse)) { _ in
            isShowingBrowse = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalLock)) { _ in
            lockNow()
        }
        .onChange(of: lock.settings.autoLockMinutes) { _, _ in
            lock.restartIdleTimer()
        }
        .onDisappear {
            // Last chance to persist an in-flight edit.
            model.flushPendingSave()
        }
    }

    /// Anything typed in the last fraction of a second must reach the disk
    /// before the key is dropped, or locking would quietly lose it.
    private func lockNow() {
        model.flushPendingSave()
        lock.lock(reason: .manual)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                model.newEntry()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New entry (⌘N)")

            Button {
                isShowingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search (⌘F)")

            Button {
                isShowingBrowse = true
            } label: {
                Image(systemName: "list.bullet")
            }
            .help("Browse all entries (⌘B)")

            Button(action: lockNow) {
                Image(systemName: "lock")
            }
            .help("Lock now (⌘L)")
        }
    }
}

// MARK: - Menu commands
//
// Menu items post these; the window listens. Routing through notifications
// keeps the commands working regardless of which control currently has focus.

extension Notification.Name {
    static let journalNewEntry = Notification.Name("journal.command.newEntry")
    static let journalSearch = Notification.Name("journal.command.search")
    static let journalBrowse = Notification.Name("journal.command.browse")
    static let journalLock = Notification.Name("journal.command.lock")
    static let journalJumpToToday = Notification.Name("journal.command.today")
}
