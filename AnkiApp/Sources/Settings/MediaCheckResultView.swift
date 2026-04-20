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
    @State private var currentResult: MediaCheckResult
    @Environment(\.dismiss) private var dismiss

    @Dependency(\.ankiBackend) var backend
    @State private var isTrashingUnused = false
    @State private var isDeletingTrash = false
    @State private var isRestoringTrash = false
    @State private var actionMessage: String?
    @State private var showActionAlert = false

    init(result: MediaCheckResult) {
        _currentResult = State(initialValue: result)
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !currentResult.missing.isEmpty { missingSection }
                if !currentResult.unused.isEmpty { unusedSection }
                if currentResult.haveTrash || !currentResult.unused.isEmpty { trashSection }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(L("media_check_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                        .amgiToolbarTextButton()
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
                L("media_check_missing_count", currentResult.missing.count),
                systemImage: "exclamationmark.triangle"
            )
            .amgiStatusText(currentResult.missing.isEmpty ? .neutral : .danger)
            .listRowBackground(Color.amgiSurfaceElevated)

            Label(
                L("media_check_unused_count", currentResult.unused.count),
                systemImage: "archivebox"
            )
            .amgiStatusText(currentResult.unused.isEmpty ? .neutral : .warning)
            .listRowBackground(Color.amgiSurfaceElevated)

            if !currentResult.report.isEmpty {
                DisclosureGroup(L("media_check_full_report")) {
                    Text(currentResult.report)
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
                .listRowBackground(Color.amgiSurfaceElevated)
            }
        }
    }

    private var missingSection: some View {
        Section(L("media_check_section_missing")) {
            ForEach(currentResult.missing.prefix(200), id: \.self) { file in
                Label(file, systemImage: "questionmark.circle")
                    .amgiStatusText(.danger, font: .caption)
                    .listRowBackground(Color.amgiSurfaceElevated)
            }
            if currentResult.missing.count > 200 {
                Text(L("media_check_and_more", currentResult.missing.count - 200))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .listRowBackground(Color.amgiSurfaceElevated)
            }
        }
    }

    private var unusedSection: some View {
        Section(L("media_check_section_unused")) {
            ForEach(currentResult.unused.prefix(200), id: \.self) { file in
                Label(file, systemImage: "tray")
                    .amgiStatusText(.warning, font: .caption)
                    .listRowBackground(Color.amgiSurfaceElevated)
            }
            if currentResult.unused.count > 200 {
                Text(L("media_check_and_more", currentResult.unused.count - 200))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .listRowBackground(Color.amgiSurfaceElevated)
            }
        }
    }

    private var trashSection: some View {
        Section(L("media_check_section_actions")) {
            if !currentResult.unused.isEmpty {
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
                .listRowBackground(Color.amgiSurfaceElevated)
            }

            if currentResult.haveTrash {
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
                .foregroundStyle(Color.amgiDanger)
                .listRowBackground(Color.amgiSurfaceElevated)

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
                .listRowBackground(Color.amgiSurfaceElevated)
            }
        }
    }

    private static func fetchLatestResult(using backend: AnkiBackend) throws -> MediaCheckResult {
        let response: Anki_Media_CheckMediaResponse = try backend.invoke(
            service: AnkiBackend.Service.media,
            method: AnkiBackend.MediaMethod.checkMedia
        )
        return MediaCheckResult(
            missing: response.missing,
            unused: response.unused,
            missingNoteIds: response.missingMediaNotes,
            report: response.report,
            haveTrash: response.haveTrash
        )
    }

    private func trashUnused() {
        isTrashingUnused = true
        let capturedBackend = backend
        let unusedFiles = currentResult.unused
        Task.detached {
            do {
                var req = Anki_Media_TrashMediaFilesRequest()
                req.fnames = unusedFiles
                try capturedBackend.callVoid(
                    service: AnkiBackend.Service.media,
                    method: AnkiBackend.MediaMethod.trashMediaFiles,
                    request: req
                )
                let latestResult = try Self.fetchLatestResult(using: capturedBackend)
                await MainActor.run {
                    currentResult = latestResult
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
                let latestResult = try Self.fetchLatestResult(using: capturedBackend)
                await MainActor.run {
                    currentResult = latestResult
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
                let latestResult = try Self.fetchLatestResult(using: capturedBackend)
                await MainActor.run {
                    currentResult = latestResult
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
