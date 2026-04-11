import SwiftUI

struct BackupView: View {
    let username: String

    @State private var backups: [BackupEntry] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var successMessage: String?
    @State private var showSuccess = false
    @State private var backupToDelete: BackupEntry?
    @State private var showDeleteConfirm = false

    struct BackupEntry: Identifiable {
        let id = UUID()
        let url: URL
        let date: Date
        var formattedDate: String {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            return fmt.string(from: date)
        }
        var fileSize: String {
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    var body: some View {
        List {
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
                .disabled(isCreating)
            } footer: {
                Text(L("backup_storage_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if backups.isEmpty {
                Section {
                    Text(L("backup_empty"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                Section(L("backup_section_list")) {
                    ForEach(backups) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.formattedDate)
                                    .font(.subheadline)
                                Text(entry.fileSize)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            ShareLink(item: entry.url) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                backupToDelete = entry
                                showDeleteConfirm = true
                            } label: {
                                Label(L("common_delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("backup_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("backup_delete_title"), isPresented: $showDeleteConfirm) {
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_delete"), role: .destructive) {
                if let entry = backupToDelete { deleteBackup(entry) }
            }
        } message: {
            Text(L("backup_delete_confirm", backupToDelete?.formattedDate ?? ""))
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
        .task { loadBackups() }
    }

    // MARK: - Helpers

    private func backupsDirectory() -> URL? {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return nil }
        let folderName = "Backups for \(username)"
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadBackups() {
        guard let dir = backupsDirectory() else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )) ?? []
        backups = files
            .filter { $0.pathExtension == "anki2" }
            .compactMap { url -> BackupEntry? in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date.distantPast
                return BackupEntry(url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    private func createBackup() async {
        isCreating = true
        let user = username
        do {
            guard let dir = backupsDirectory() else {
                throw NSError(domain: "BackupView", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot access backup directory"])
            }
            let sourceURL = AppUserStore.collectionURLs(for: user).collection
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let destURL = dir.appendingPathComponent("\(timestamp).anki2")
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }.value
            loadBackups()
            successMessage = L("backup_created_ok", destURL.lastPathComponent)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isCreating = false
    }

    private func deleteBackup(_ entry: BackupEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        loadBackups()
    }
}
