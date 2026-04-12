import SwiftUI
import AVKit
import UIKit

struct UserFileManagerView: View {
    let username: String
    private let pageSize = 200

    private static let summarySizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    @State private var mediaFiles: [MediaFileEntry] = []
    @State private var totalMediaSizeBytes: Int64 = 0
    @State private var searchText = ""
    @State private var displayLimit = 200
    @State private var isLoading = false

    @State private var renameTarget: MediaFileEntry?
    @State private var renameText = ""
    @State private var showRenamePrompt = false
    @State private var previewTarget: MediaFileEntry?

    @State private var errorMessage: String?
    @State private var showError = false
    @State private var successMessage: String?
    @State private var showSuccess = false

    private var urls: (directory: URL, collection: URL, mediaDirectory: URL, mediaDB: URL) {
        AppUserStore.collectionURLs(for: username)
    }

    private var filteredFiles: [MediaFileEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return mediaFiles }
        return mediaFiles.filter { $0.fileName.localizedCaseInsensitiveContains(keyword) }
    }

    private var visibleFiles: [MediaFileEntry] {
        Array(filteredFiles.prefix(displayLimit))
    }

    private var remainingFileCount: Int {
        max(0, filteredFiles.count - visibleFiles.count)
    }

    private var totalMediaSizeText: String {
        Self.summarySizeFormatter.string(fromByteCount: totalMediaSizeBytes)
    }

    private var mediaDBSizeText: String {
        let bytes = fileSize(for: urls.mediaDB)
        return Self.summarySizeFormatter.string(fromByteCount: bytes)
    }

    private var collectionDBSizeText: String {
        let bytes = fileSize(for: urls.collection)
        return Self.summarySizeFormatter.string(fromByteCount: bytes)
    }

    var body: some View {
        contentList
    }

    private var contentList: some View {
        List {
            summarySection
            mediaSection
        }
        .navigationTitle(L("settings_row_file_manager"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: Text(L("file_mgmt_search_placeholder")))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    loadMediaFiles()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .alert(L("file_mgmt_rename_title"), isPresented: $showRenamePrompt) {
            TextField(L("file_mgmt_rename_placeholder"), text: $renameText)
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_save")) {
                performRename()
            }
        } message: {
            Text(renameTarget?.fileName ?? "")
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(L("common_done"), isPresented: $showSuccess) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
        .sheet(item: $previewTarget) { entry in
            MediaFilePreviewView(entry: entry)
        }
        .onChange(of: searchText) {
            displayLimit = pageSize
        }
        .task {
            loadMediaFiles()
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section(L("file_mgmt_section_summary")) {
            LabeledContent(L("file_mgmt_user"), value: username)
            LabeledContent(L("file_mgmt_media_count"), value: "\(mediaFiles.count)")
            LabeledContent(L("file_mgmt_media_size"), value: totalMediaSizeText)
            LabeledContent(L("file_mgmt_collection_size"), value: collectionDBSizeText)
            LabeledContent(L("file_mgmt_media_db_size"), value: mediaDBSizeText)
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        Section(L("file_mgmt_section_media")) {
            mediaSectionContent
        } footer: {
            Text(L("file_mgmt_footer_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var mediaSectionContent: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if filteredFiles.isEmpty {
            Text(L(searchText.isEmpty ? "file_mgmt_empty" : "file_mgmt_no_search_result"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            ForEach(visibleFiles) { entry in
                mediaRow(for: entry)
            }

            if remainingFileCount > 0 {
                Button {
                    displayLimit += pageSize
                } label: {
                    Text(L("file_mgmt_load_more", min(pageSize, remainingFileCount)))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 6)
            }
        }
    }

    private func mediaRow(for entry: MediaFileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbolName)
                .foregroundStyle(entry.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fileName)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            previewTarget = entry
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                renameTarget = entry
                renameText = entry.fileName
                showRenamePrompt = true
            } label: {
                Label(L("user_mgmt_rename"), systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    private func loadMediaFiles() {
        isLoading = true
        defer { isLoading = false }

        do {
            let dir = urls.mediaDirectory
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            var entries: [MediaFileEntry] = []
            var totalBytes: Int64 = 0
            for url in files {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }
                let size = Int64(values?.fileSize ?? 0)
                let modifiedAt = values?.contentModificationDate ?? Date.distantPast
                entries.append(MediaFileEntry(url: url, sizeBytes: size, modifiedAt: modifiedAt))
                totalBytes += size
            }

            mediaFiles = entries.sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
                }
                return lhs.modifiedAt > rhs.modifiedAt
            }
            displayLimit = pageSize
            totalMediaSizeBytes = totalBytes
        } catch {
            errorMessage = L("file_mgmt_load_error", error.localizedDescription)
            showError = true
        }
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !newName.isEmpty else {
            errorMessage = L("file_mgmt_rename_empty")
            showError = true
            return
        }

        guard !newName.contains("/"), !newName.contains("\\") else {
            errorMessage = L("file_mgmt_rename_invalid")
            showError = true
            return
        }

        guard newName != target.fileName else { return }

        let destination = target.url.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: destination.path) {
            errorMessage = L("file_mgmt_rename_exists")
            showError = true
            return
        }

        do {
            try FileManager.default.moveItem(at: target.url, to: destination)
            successMessage = L("file_mgmt_rename_success", target.fileName, newName)
            showSuccess = true
            loadMediaFiles()
        } catch {
            errorMessage = L("file_mgmt_rename_failed", error.localizedDescription)
            showError = true
        }
    }

    private func fileSize(for url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

private struct MediaFileEntry: Identifiable {
    enum PreviewKind {
        case image
        case audio
        case video
        case other
    }

    var id: String { url.lastPathComponent }
    let url: URL
    let sizeBytes: Int64
    let modifiedAt: Date

    var fileName: String {
        url.lastPathComponent
    }

    var subtitle: String {
        "\(formattedSize)  ·  \(formattedDate)"
    }

    var formattedSize: String {
        sizeBytes.formatted(.byteCount(style: .file))
    }

    var formattedDate: String {
        modifiedAt.formatted(date: .numeric, time: .shortened)
    }

    var symbolName: String {
        switch fileType {
        case .image: return "photo"
        case .audio: return "waveform"
        case .video: return "film"
        case .other: return "doc"
        }
    }

    var tintColor: Color {
        switch fileType {
        case .image: return .blue
        case .audio: return .orange
        case .video: return .purple
        case .other: return .secondary
        }
    }

    var previewKind: PreviewKind {
        switch fileType {
        case .image: return .image
        case .audio: return .audio
        case .video: return .video
        case .other: return .other
        }
    }

    private var fileType: FileType {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"].contains(ext) {
            return .image
        }
        if ["mp3", "wav", "ogg", "m4a", "aac", "flac"].contains(ext) {
            return .audio
        }
        if ["mp4", "mov", "webm", "mkv"].contains(ext) {
            return .video
        }
        return .other
    }

    private enum FileType {
        case image
        case audio
        case video
        case other
    }
}

private struct MediaFilePreviewView: View {
    let entry: MediaFileEntry
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                switch entry.previewKind {
                case .image:
                    if let image = UIImage(contentsOfFile: entry.url.path) {
                        ScrollView([.vertical, .horizontal]) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    } else {
                        ContentUnavailableView(
                            L("file_mgmt_preview_unavailable"),
                            systemImage: "photo",
                            description: Text(L("file_mgmt_preview_load_failed"))
                        )
                    }
                case .audio, .video:
                    if let player {
                        VideoPlayer(player: player)
                            .onAppear { player.play() }
                            .onDisappear {
                                player.pause()
                                player.seek(to: .zero)
                            }
                    } else {
                        ContentUnavailableView(
                            L("file_mgmt_preview_unavailable"),
                            systemImage: "play.circle",
                            description: Text(L("file_mgmt_preview_load_failed"))
                        )
                    }
                case .other:
                    ContentUnavailableView(
                        L("file_mgmt_preview_unavailable"),
                        systemImage: "doc",
                        description: Text(L("file_mgmt_preview_not_supported"))
                    )
                }
            }
            .navigationTitle(entry.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_done")) { dismiss() }
                }
            }
        }
        .onAppear {
            if entry.previewKind == .audio || entry.previewKind == .video {
                player = AVPlayer(url: entry.url)
            }
        }
    }
}