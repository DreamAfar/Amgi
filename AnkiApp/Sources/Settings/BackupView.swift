import SwiftUI
import AnkiBackend
import Dependencies

struct BackupView: View {
    let username: String

    @Dependency(\.ankiBackend) var backend

    @State private var backups: [BackupFileEntry] = []
    @State private var isCreating = false
    @State private var isRestoring = false
    @State private var isLoadingSettings = true
    @State private var isSavingSettings = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var successMessage: String?
    @State private var showSuccess = false
    @State private var backupToDelete: BackupFileEntry?
    @State private var backupToRestore: BackupFileEntry?
    @State private var showDeleteConfirm = false
    @State private var showRestoreConfirm = false
    @State private var minimumIntervalMins = CollectionBackupManager.defaultMinimumIntervalMins
    @State private var dailyBackups = CollectionBackupManager.defaultDailyBackups
    @State private var weeklyBackups = CollectionBackupManager.defaultWeeklyBackups
    @State private var monthlyBackups = CollectionBackupManager.defaultMonthlyBackups
    @State private var legacyBackupCount = 0

    var body: some View {
        List {
            Section(L("backup_section_settings")) {
                Stepper(value: $minimumIntervalMins, in: 0...1440, step: 5) {
                    backupSettingRow(
                        title: L("backup_auto_interval"),
                        value: "\(minimumIntervalMins)"
                    )
                }
                .disabled(isLoadingSettings || isSavingSettings)

                Stepper(value: $dailyBackups, in: 0...365) {
                    backupSettingRow(
                        title: L("backup_daily_keep"),
                        value: "\(dailyBackups)"
                    )
                }
                .disabled(isLoadingSettings || isSavingSettings)

                Stepper(value: $weeklyBackups, in: 0...104) {
                    backupSettingRow(
                        title: L("backup_weekly_keep"),
                        value: "\(weeklyBackups)"
                    )
                }
                .disabled(isLoadingSettings || isSavingSettings)

                Stepper(value: $monthlyBackups, in: 0...60) {
                    backupSettingRow(
                        title: L("backup_monthly_keep"),
                        value: "\(monthlyBackups)"
                    )
                }
                .disabled(isLoadingSettings || isSavingSettings)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("backup_explanation"))
                    Text(L("backup_media_notice"))
                }
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
            }

            Section {
                Button {
                    Task { await createBackup() }
                } label: {
                    if isCreating {
                        HStack {
                            Label(L("backup_creating"), systemImage: "externaldrive.badge.plus")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Label(L("backup_create_now"), systemImage: "externaldrive.badge.plus")
                    }
                }
                .disabled(isCreating || isRestoring)
                .listRowBackground(Color.amgiSurfaceElevated)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("backup_storage_hint"))
                    if legacyBackupCount > 0 {
                        Text(L("backup_legacy_hidden_notice", legacyBackupCount))
                    }
                }
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
            }

            if backups.isEmpty {
                Section {
                    Text(L("backup_empty"))
                        .amgiFont(.body)
                        .foregroundStyle(Color.amgiTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.amgiSurfaceElevated)
                }
            } else {
                Section(L("backup_section_list")) {
                    ForEach(backups) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                                Text(entry.formattedDate)
                                    .amgiFont(.body)
                                    .foregroundStyle(Color.amgiTextPrimary)
                                Text(entry.fileSize)
                                    .amgiFont(.caption)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                            Spacer()
                            ShareLink(item: entry.url) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(Color.amgiAccent)
                            }
                            .buttonStyle(.plain)

                            if entry.url.pathExtension.lowercased() == "colpkg" {
                                Button {
                                    backupToRestore = entry
                                    showRestoreConfirm = true
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .foregroundStyle(Color.amgiAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                backupToDelete = entry
                                showDeleteConfirm = true
                            } label: {
                                Label(L("common_delete"), systemImage: "trash")
                            }

                            if entry.url.pathExtension.lowercased() == "colpkg" {
                                Button {
                                    backupToRestore = entry
                                    showRestoreConfirm = true
                                } label: {
                                    Label(L("backup_restore_action"), systemImage: "arrow.counterclockwise")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("backup_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("backup_delete_title"), isPresented: $showDeleteConfirm) {
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_delete"), role: .destructive) {
                if let entry = backupToDelete {
                    deleteBackup(entry)
                }
            }
        } message: {
            Text(L("backup_delete_confirm", backupToDelete?.formattedDate ?? ""))
        }
        .alert(L("backup_restore_title"), isPresented: $showRestoreConfirm) {
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("backup_restore_action"), role: .destructive) {
                if let entry = backupToRestore {
                    Task { await restoreBackup(entry) }
                }
            }
        } message: {
            Text(L("backup_restore_confirm", backupToRestore?.url.lastPathComponent ?? ""))
        }
        .alert(L("common_done"), isPresented: $showSuccess) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            loadBackups()
            await loadBackupPreferences()
        }
        .onChange(of: minimumIntervalMins) { oldValue, newValue in
            guard oldValue != newValue else { return }
            persistBackupPreferencesIfNeeded()
        }
        .onChange(of: dailyBackups) { oldValue, newValue in
            guard oldValue != newValue else { return }
            persistBackupPreferencesIfNeeded()
        }
        .onChange(of: weeklyBackups) { oldValue, newValue in
            guard oldValue != newValue else { return }
            persistBackupPreferencesIfNeeded()
        }
        .onChange(of: monthlyBackups) { oldValue, newValue in
            guard oldValue != newValue else { return }
            persistBackupPreferencesIfNeeded()
        }
    }

    private func backupSettingRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AmgiSpacing.md) {
            Text(title)
                .foregroundStyle(Color.amgiTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .foregroundStyle(Color.amgiAccent)
                .monospacedDigit()
        }
    }

    private func loadBackups() {
        backups = CollectionBackupManager.loadBackups(for: username)
        legacyBackupCount = CollectionBackupManager.legacyBackupCount(for: username)
    }

    private func createBackup() async {
        isCreating = true
        defer { isCreating = false }

        do {
            let result = try await CollectionBackupManager.createBackup(
                backend: backend,
                username: username,
                force: true
            )
            loadBackups()
            switch result {
            case .created(let entry):
                successMessage = L("backup_created_ok", entry?.url.lastPathComponent ?? "")
            case .unchanged:
                successMessage = L("backup_unchanged")
            }
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func restoreBackup(_ entry: BackupFileEntry) async {
        guard entry.url.pathExtension.lowercased() == "colpkg" else {
            errorMessage = L("backup_restore_unsupported")
            showError = true
            return
        }

        isRestoring = true
        let capturedBackend = backend
        let backupURL = entry.url
        await MainActor.run {
            AppCollectionState.shared.markOpening()
        }
        defer { isRestoring = false }

        do {
            let message = try await Task.detached(priority: .userInitiated) {
                try ImportHelper.importPackage(
                    from: backupURL,
                    backend: capturedBackend,
                    configuration: .collection
                )
            }.value

            await MainActor.run {
                AppCollectionState.shared.markReady()
                NotificationCenter.default.post(name: AppCollectionEvents.didOpenNotification, object: nil)
                successMessage = message
                showSuccess = true
            }
        } catch {
            await MainActor.run {
                AppCollectionState.shared.markFailed(error.localizedDescription)
                errorMessage = L("backup_restore_failed", error.localizedDescription)
                showError = true
            }
        }
    }

    @MainActor
    private func loadBackupPreferences() async {
        isLoadingSettings = true
        defer { isLoadingSettings = false }

        do {
            let preferences = try backend.getPreferences()
            let limits = preferences.backups
            minimumIntervalMins = Int(limits.minimumIntervalMins)
            dailyBackups = Int(limits.daily)
            weeklyBackups = Int(limits.weekly)
            monthlyBackups = Int(limits.monthly)
        } catch {
            errorMessage = L("backup_settings_load_failed", error.localizedDescription)
            showError = true
        }
    }

    private func persistBackupPreferencesIfNeeded() {
        guard !isLoadingSettings, !isSavingSettings else { return }
        isSavingSettings = true

        let interval = minimumIntervalMins
        let daily = dailyBackups
        let weekly = weeklyBackups
        let monthly = monthlyBackups
        let capturedBackend = backend

        Task {
            do {
                var preferences = try capturedBackend.getPreferences()
                preferences.backups.daily = UInt32(max(0, daily))
                preferences.backups.weekly = UInt32(max(0, weekly))
                preferences.backups.monthly = UInt32(max(0, monthly))
                preferences.backups.minimumIntervalMins = UInt32(max(0, interval))
                try capturedBackend.setPreferences(preferences)
            } catch {
                await MainActor.run {
                    errorMessage = L("backup_settings_save_failed", error.localizedDescription)
                    showError = true
                }
                await loadBackupPreferences()
            }

            await MainActor.run {
                isSavingSettings = false
            }
        }
    }

    private func deleteBackup(_ entry: BackupFileEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        loadBackups()
    }
}
