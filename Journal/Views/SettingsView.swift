import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {

    @EnvironmentObject private var lock: LockController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            SecuritySettings().tabItem { Label("Security", systemImage: "lock") }
            ReminderSettings().tabItem { Label("Reminder", systemImage: "bell") }
            DataSettings().tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .environmentObject(lock)
        .environmentObject(settings)
        .frame(width: 520, height: 400)
    }
}

// MARK: - General

private struct GeneralSettings: View {

    @EnvironmentObject private var lock: LockController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Lock after inactivity:", selection: $settings.autoLockMinutes) {
                    ForEach(AppSettings.autoLockChoices, id: \.self) { minutes in
                        Text(AppSettings.autoLockLabel(minutes)).tag(minutes)
                    }
                }
                .onChange(of: settings.autoLockMinutes) { _, _ in
                    lock.restartIdleTimer()
                }

                Text("The journal also locks when your Mac sleeps, when the screen locks, and when you press ⌘L. Those can't be turned off.")
                    .font(Theme.chromeFont(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if BiometricAuth.isAvailable {
                Section {
                    Toggle("Unlock with Touch ID", isOn: touchIDBinding)

                    if let mode = lock.keychainMode, settings.touchIDEnabled {
                        Text(mode.explanation)
                            .font(Theme.chromeFont(11))
                            .foregroundStyle(mode == .dataProtection ? Theme.inkSoft : Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { lock.refreshKeychainMode() }
    }

    private var touchIDBinding: Binding<Bool> {
        Binding(
            get: { settings.touchIDEnabled },
            set: { enabled in
                settings.touchIDEnabled = enabled
                if enabled {
                    // Needs the live key, which only exists while unlocked.
                    if let session = lock.session {
                        try? lock.enableTouchID(dataKey: session.dataKey)
                    }
                } else {
                    lock.disableTouchID()
                }
            }
        )
    }
}

// MARK: - Security

private struct SecuritySettings: View {

    @EnvironmentObject private var lock: LockController

    @State private var current = ""
    @State private var updated = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var messageIsError = false
    @State private var newRecoveryKey: String?

    var body: some View {
        Form {
            Section("Change passcode") {
                SecureField("Current passcode", text: $current)
                SecureField("New passcode", text: $updated)
                SecureField("Confirm new passcode", text: $confirmation)

                HStack {
                    Button("Change Passcode", action: changePasscode)
                        .disabled(!isValid)
                    Spacer()
                    if let message {
                        Text(message)
                            .font(Theme.chromeFont(11))
                            .foregroundStyle(messageIsError ? Theme.accent : Theme.inkSoft)
                    }
                }
            }

            Section("Recovery key") {
                Text("Issuing a new recovery key immediately invalidates the old one. Your entries are unaffected.")
                    .font(Theme.chromeFont(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Generate New Recovery Key…") { generateRecoveryKey() }
                    .disabled(current.isEmpty)

                if current.isEmpty {
                    Text("Enter your current passcode above first.")
                        .font(Theme.chromeFont(10))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: Binding(
            get: { newRecoveryKey.map(IdentifiableString.init) },
            set: { newRecoveryKey = $0?.value }
        )) { wrapped in
            RecoveryKeySheet(key: wrapped.value)
        }
    }

    private var isValid: Bool {
        !current.isEmpty && updated.count >= 6 && updated == confirmation
    }

    private func changePasscode() {
        do {
            try lock.vault.changePasscode(current: current, new: updated)
            message = "Passcode changed."
            messageIsError = false
            current = ""; updated = ""; confirmation = ""
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }

    private func generateRecoveryKey() {
        do {
            newRecoveryKey = try lock.vault.regenerateRecoveryKey(passcode: current)
        } catch {
            message = error.localizedDescription
            messageIsError = true
        }
    }
}

private struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

private struct RecoveryKeySheet: View {
    let key: String
    @Environment(\.dismiss) private var dismiss
    @State private var acknowledged = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Your new recovery key")
                .font(Theme.reading(18, weight: .medium))

            Text(key)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chrome))

            Text("Write this down. Your previous recovery key no longer works.")
                .font(Theme.chromeFont(11))
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)

            Toggle("I've written it down", isOn: $acknowledged)
                .toggleStyle(.checkbox)
                .font(Theme.chromeFont(12))

            Button("Done") { dismiss() }
                .disabled(!acknowledged)
        }
        .padding(28)
        .frame(width: 420)
    }
}

// MARK: - Reminder

private struct ReminderSettings: View {

    @EnvironmentObject private var settings: AppSettings
    @State private var denied = false

    var body: some View {
        Form {
            Section {
                Toggle("Daily reminder", isOn: reminderBinding)

                DatePicker(
                    "Remind me at:",
                    selection: Binding(get: { settings.reminderTime }, set: { settings.reminderTime = $0 }),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!settings.reminderEnabled)
                .onChange(of: settings.reminderHour) { _, _ in resync() }
                .onChange(of: settings.reminderMinute) { _, _ in resync() }

                if denied {
                    Text("Notifications are turned off for Journal in System Settings → Notifications.")
                        .font(Theme.chromeFont(11))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("A local notification on this Mac. It says only “A few minutes to write?” — never anything from your entries, since notifications can appear on a locked screen.")
                    .font(Theme.chromeFont(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { settings.reminderEnabled },
            set: { enabled in
                settings.reminderEnabled = enabled
                Task {
                    if enabled {
                        let granted = await Reminders.requestAuthorization()
                        denied = !granted
                        if !granted { settings.reminderEnabled = false }
                    }
                    await Reminders.sync(with: settings)
                }
            }
        )
    }

    private func resync() {
        Task { await Reminders.sync(with: settings) }
    }
}

// MARK: - Data

private struct DataSettings: View {

    @EnvironmentObject private var lock: LockController
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isConfirmingExport = false
    @State private var isConfirmingRestore = false
    @State private var pendingRestore: (url: URL, envelope: BackupArchive.Envelope)?
    @State private var exportFormat: ExportFormat = .markdown

    private enum ExportFormat: String, CaseIterable, Identifiable {
        case markdown = "Markdown files"
        case pdf = "Single PDF"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Export") {
                Picker("Format:", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) }
                }

                Button("Export All Entries…") { isConfirmingExport = true }
                    .disabled(!lock.isUnlocked)

                Text("Exported files are **not encrypted**. Anyone who can open the folder can read them.")
                    .font(Theme.chromeFont(11))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Backup") {
                HStack {
                    Button("Save Encrypted Backup…", action: saveBackup)
                        .disabled(!lock.isUnlocked)
                    Button("Restore from Backup…", action: chooseRestore)
                }

                Text("A backup stays encrypted and opens with the same passcode or recovery key as this journal.")
                    .font(Theme.chromeFont(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Data folder") {
                Button("Reveal in Finder", action: revealDataFolder)

                Text(lock.vault.paths.root.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status {
                Text(status)
                    .font(Theme.chromeFont(11))
                    .foregroundStyle(statusIsError ? Theme.accent : Theme.inkSoft)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Export unencrypted copies?",
            isPresented: $isConfirmingExport,
            titleVisibility: .visible
        ) {
            Button("Export Anyway", role: .destructive) { runExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The exported files will be readable by anyone with access to the folder you choose. They are not protected by your passcode.")
        }
        .confirmationDialog(
            "Replace this journal?",
            isPresented: $isConfirmingRestore,
            titleVisibility: .visible
        ) {
            Button("Replace Everything", role: .destructive) { runRestore() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let pendingRestore {
                Text("This backup holds \(pendingRestore.envelope.entryCount) entries from \(pendingRestore.envelope.createdAt.formatted(date: .abbreviated, time: .shortened)). Restoring replaces every entry currently on this Mac, and the app will lock so you can unlock with that backup's passcode.")
            }
        }
    }

    // MARK: Export

    private func runExport() {
        guard let session = lock.session else { return }
        let entries = (try? session.store.loadAllEntries()) ?? []
        guard !entries.isEmpty else { return report(ExportError.noEntries.localizedDescription, error: true) }

        switch exportFormat {
        case .markdown:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.prompt = "Export Here"
            panel.message = "Choose a folder for the exported Markdown files."
            guard panel.runModal() == .OK, let directory = panel.url else { return }

            do {
                let count = try Exporter.exportMarkdown(entries: entries, to: directory)
                report("Exported \(count) entries.")
            } catch {
                report(error.localizedDescription, error: true)
            }

        case .pdf:
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Journal.pdf"
            panel.allowedContentTypes = [.pdf]
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try Exporter.exportPDF(entries: entries, to: url)
                report("Exported \(entries.count) entries to PDF.")
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    // MARK: Backup

    private func saveBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = BackupArchive.suggestedFilename()
        panel.message = "Choose where to keep the encrypted backup."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try BackupArchive.create(from: lock.vault.paths)
            try data.write(to: url, options: [.atomic])
            report("Backup saved.")
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    private func chooseRestore() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.data]
        panel.message = "Choose a Journal backup file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let envelope = try BackupArchive.inspect(try Data(contentsOf: url))
            pendingRestore = (url, envelope)
            isConfirmingRestore = true
        } catch {
            report("That file isn't a Journal backup.", error: true)
        }
    }

    private func runRestore() {
        guard let pending = pendingRestore else { return }
        defer { pendingRestore = nil }

        do {
            let data = try Data(contentsOf: pending.url)
            try BackupArchive.restore(data, to: lock.vault.paths)
            report("Restored \(pending.envelope.entryCount) entries.")
            // The restored vault may use a different passcode, and the
            // in-memory key certainly no longer matches — lock so the user
            // comes back in through the front door.
            lock.lock(reason: .manual)
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    // MARK: Misc

    private func revealDataFolder() {
        let root = lock.vault.paths.root
        try? lock.vault.paths.createDirectoriesIfNeeded()
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    private func report(_ message: String, error: Bool = false) {
        status = message
        statusIsError = error
    }
}
