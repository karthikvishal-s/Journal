import SwiftUI

@main
struct JournalApp: App {

    @StateObject private var settings: AppSettings
    @StateObject private var lock: LockController

    init() {
        let settings = AppSettings()
        // A vault path that can't be created is unrecoverable and happens
        // before any user data exists, so failing loudly here is better than
        // limping on and silently not saving anything.
        let paths = try! VaultPaths.standard()
        _settings = StateObject(wrappedValue: settings)
        _lock = StateObject(wrappedValue: LockController(vault: VaultManager(paths: paths), settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(lock)
                .environmentObject(settings)
                .frame(minWidth: 880, minHeight: 620)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { menuCommands }

        Settings {
            SettingsView()
                .environmentObject(lock)
                .environmentObject(settings)
        }
    }

    @CommandsBuilder
    private var menuCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") {
                NotificationCenter.default.post(name: .journalNewEntry, object: nil)
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!lock.isUnlocked)
        }

        CommandGroup(after: .toolbar) {
            Button("Jump to Today") {
                NotificationCenter.default.post(name: .journalJumpToToday, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(!lock.isUnlocked)

            Button("Browse Entries") {
                NotificationCenter.default.post(name: .journalBrowse, object: nil)
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!lock.isUnlocked)
        }

        CommandGroup(replacing: .textEditing) {
            Button("Search") {
                NotificationCenter.default.post(name: .journalSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!lock.isUnlocked)
        }

        CommandMenu("Journal") {
            Button("Lock Now") {
                NotificationCenter.default.post(name: .journalLock, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!lock.isUnlocked)
        }
    }
}
