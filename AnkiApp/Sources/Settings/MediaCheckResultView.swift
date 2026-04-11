import SwiftUI
import AnkiBackend
import AnkiProto
import Dependencies
import SwiftProtobuf

struct MediaCheckResult {
    let missing: [String]
    let unused: [String]
    let missingNoteIds: [Int64]
    let report: String
    let haveTrash: Bool
}

struct MediaCheckResultView: View {
    let result: MediaCheckResult
    @Environment(\.dismiss) private var dismiss

    @Dependency(\.ankiBackend) var backend
    @State private var isTrashingUnused = false
    @State private var isDeletingTrash = false
    @State private var isRestoringTrash = false
    @State private var actionMessage: String?
    @State private var showActionAlert = false

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !result.missing.isEmpty { missingSection }
                if !result.unused.isEmpty { unusedSection }
                if result.haveTrash || !result.unused.isEmpty { trashSection }
            }
            .navigationTitle(L("media_check_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                }
            }
            .alert(L("common_done"), isPresented: $showActionAlert) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(actionMessage ?? "")
            }
        }
    }

    private var summarySection: some View {
        Section(L("media_check_section_summary")) {
            Label(
                L("media_check_missing_count", result.missing.count),
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(result.missing.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))

            Label(
                L("media_check_unused_count", result.unused.count),
                systemImage: "archivebox"
            )
            .foregroundStyle(result.unused.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))

            if !result.report.isEmpty {
                DisclosureGroup(L("media_check_full_report")) {
                    Text(result.report)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var missingSection: some View {
        Section(L("media_check_section_missing")) {
            ForEach(result.missing.prefix(200), id: \.self) { file in
                Label(file, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if result.missing.count > 200 {
                Text(L("media_check_and_more", result.missing.count - 200))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unusedSection: some View {
        Section(L("media_check_section_unused")) {
            ForEach(result.unused.prefix(200), id: \.self) { file in
                Label(file, systemImage: "tray")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if result.unused.count > 200 {
                Text(L("media_check_and_more", result.unused.count - 200))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var trashSection: some View {
        Section(L("media_check_section_actions")) {
            if !result.unused.isEmpty {
                Button {
                    trashUnused()
                } label: {
                    if isTrashingUnused {
                        HStack {
                            Text(L("media_check_trash_unused"))
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Label(L("media_check_trash_unused"), systemImage: "trash")
                    }
                }
                .disabled(isTrashingUnused)
            }

            if result.haveTrash {
                Button {
                    emptyTrash()
                } label: {
                    if isDeletingTrash {
                        HStack {
                            Text(L("media_check_empty_trash"))
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Label(L("media_check_empty_trash"), systemImage: "trash.slash")
                    }
                }
                .disabled(isDeletingTrash)
                .foregroundStyle(.red)

                Button {
                    restoreTrash()
                } label: {
                    if isRestoringTrash {
                        HStack {
                            Text(L("media_check_restore_trash"))
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Label(L("media_check_restore_trash"), systemImage: "arrow.uturn.backward")
                    }
                }
                .disabled(isRestoringTrash)
            }
        }
    }

    private func trashUnused() {
        isTrashingUnused = true
        let capturedBackend = backend
        let unusedFiles = result.unused
        Task.detached {
            do {
                var req = Anki_Media_TrashMediaFilesRequest()
                req.fnames = unusedFiles
                try capturedBackend.callVoid(
                    service: AnkiBackend.Service.media,
                    method: AnkiBackend.MediaMethod.trashMediaFiles,
                    request: req
                )
                await MainActor.run {
                    isTrashingUnused = false
                    actionMessage = L("media_check_trash_done", unusedFiles.count)
                    showActionAlert = true
                }
            } catch {
                await MainActor.run {
                    isTrashingUnused = false
                    actionMessage = error.localizedDescription
                    showActionAlert = true
                }
            }
        }
    }

    private func emptyTrash() {
        isDeletingTrash = true
        let capturedBackend = backend
        Task.detached {
            do {
                try capturedBackend.callVoid(
                    service: AnkiBackend.Service.media,
                    method: AnkiBackend.MediaMethod.emptyTrash
                )
                await MainActor.run {
                    isDeletingTrash = false
                    actionMessage = L("media_check_empty_trash_done")
                    showActionAlert = true
                }
            } catch {
                await MainActor.run {
                    isDeletingTrash = false
                    actionMessage = error.localizedDescription
                    showActionAlert = true
                }
            }
        }
    }

    private func restoreTrash() {
        isRestoringTrash = true
        let capturedBackend = backend
        Task.detached {
            do {
                try capturedBackend.callVoid(
                    service: AnkiBackend.Service.media,
                    method: AnkiBackend.MediaMethod.restoreTrash
                )
                await MainActor.run {
                    isRestoringTrash = false
                    actionMessage = L("media_check_restore_done")
                    showActionAlert = true
                }
            } catch {
                await MainActor.run {
                    isRestoringTrash = false
                    actionMessage = error.localizedDescription
                    showActionAlert = true
                }
            }
        }
    }
}
