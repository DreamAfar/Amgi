import SwiftUI
import AnkiBackend
import AnkiProto
import Dependencies
import SwiftProtobuf

struct MediaCheckResult: Sendable {
    let missing: [String]
    let unused: [String]
    let missingNoteIds: [Int64]
    let report: String
    let haveTrash: Bool
}

private func fetchLatestMediaCheckResult(using backend: AnkiBackend) throws -> MediaCheckResult {
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

struct MediaCheckResultView: View {
    @State private var currentResult: MediaCheckResult?
    @Environment(\.dismiss) private var dismiss

    @Dependency(\.ankiBackend) var backend
    @State private var isLoading = true
    @State private var isTrashingUnused = false
    @State private var isDeletingTrash = false
    @State private var isRestoringTrash = false
    @State private var actionMessage: String?
    @State private var showActionAlert = false
    @State private var errorMessage: String?
    @State private var showError = false

    init(result: MediaCheckResult? = nil) {
        _currentResult = State(initialValue: result)
        _isLoading = State(initialValue: result == nil)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: AmgiSpacing.md) {
                        ProgressView()
                        Text(L("media_check_running"))
                            .amgiFont(.body)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.amgiBackground)
                } else if let currentResult {
                    List {
                        summarySection(currentResult)
                        if !currentResult.missing.isEmpty { missingSection(currentResult) }
                        if !currentResult.unused.isEmpty { unusedSection(currentResult) }
                        if currentResult.haveTrash || !currentResult.unused.isEmpty { trashSection(currentResult) }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.amgiBackground)
                } else {
                    Color.amgiBackground
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
            .alert(L("common_error"), isPresented: $showError) {
                Button(L("common_ok"), role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(errorMessage ?? L("common_unknown_error"))
            }
            .task {
                await loadIfNeeded()
            }
        }
    }

    private func summarySection(_ currentResult: MediaCheckResult) -> some View {
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

    private func missingSection(_ currentResult: MediaCheckResult) -> some View {
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

    private func unusedSection(_ currentResult: MediaCheckResult) -> some View {
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

    private func trashSection(_ currentResult: MediaCheckResult) -> some View {
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

    @MainActor
    private func loadIfNeeded() async {
        guard isLoading else { return }
        let capturedBackend = backend
        do {
            let result = try await Task.detached {
                try fetchLatestMediaCheckResult(using: capturedBackend)
            }.value
            currentResult = result
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = L("media_check_error", error.localizedDescription)
            showError = true
        }
    }

    private func trashUnused() {
        guard let currentResult else { return }
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
                let latestResult = try fetchLatestMediaCheckResult(using: capturedBackend)
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
                let latestResult = try fetchLatestMediaCheckResult(using: capturedBackend)
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
                let latestResult = try fetchLatestMediaCheckResult(using: capturedBackend)
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
