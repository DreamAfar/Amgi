import SwiftUI
import WebKit
import AVFAudio
import AnkiKit
import AnkiReader
import AnkiClients
import Dependencies
import UIKit

private enum ReaderBookSortOption: String, CaseIterable, Identifiable {
    case recent
    case title
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent:
            return L("reader_library_sort_recent")
        case .title:
            return L("reader_library_sort_title")
        case .progress:
            return L("reader_library_sort_progress")
        }
    }
}

private enum ReaderLibrarySettingsRoute: String, Identifiable {
    case source
    case dictionaries
    case display
    case advanced

    var id: String { rawValue }
}

private enum ReaderChapterSheetRoute: String, Identifiable {
    case chapters
    case display
    case settings

    var id: String { rawValue }
}

struct ReaderLibraryView: View {
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.readerBookClient) var readerBookClient

    fileprivate static let bookCoverAspectRatio: CGFloat = 100 / 136
    fileprivate static let bookGridSpacing: CGFloat = 12

    @AppStorage(ReaderPreferences.Keys.deckID) private var selectedDeckID = 0
    @AppStorage(ReaderPreferences.Keys.notetypeID) private var selectedNotetypeID = 0
    @AppStorage(ReaderPreferences.Keys.bookIDField) private var bookIDField = ""
    @AppStorage(ReaderPreferences.Keys.bookTitleField) private var bookTitleField = ""
    @AppStorage(ReaderPreferences.Keys.bookCoverField) private var bookCoverField = ""
    @AppStorage(ReaderPreferences.Keys.chapterTitleField) private var chapterTitleField = ""
    @AppStorage(ReaderPreferences.Keys.chapterOrderField) private var chapterOrderField = ""
    @AppStorage(ReaderPreferences.Keys.contentField) private var contentField = ""
    @AppStorage(ReaderPreferences.Keys.languageField) private var languageField = ""
    @AppStorage(ReaderPreferences.Keys.bookshelfColumns) private var bookshelfColumns = 3
    @AppStorage(ReaderPreferences.Keys.verticalLayout) private var verticalLayout = false
    @AppStorage(ReaderPreferences.Keys.fontSize) private var readerFontSize = 24

    @State private var decks: [DeckInfo] = []
    @State private var books: [ReaderBook] = []
    @State private var isLoading = false
    @State private var configurationProblem: String?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var sortOption: ReaderBookSortOption = .recent
    @State private var isSelecting = false
    @State private var selectedBookIDs: Set<String> = []
    @State private var settingsRoute: ReaderLibrarySettingsRoute?

    private var resolvedBookshelfColumns: Int {
        bookshelfColumns == 2 ? 2 : 3
    }

    private var configurationSignature: String {
        [
            String(selectedDeckID),
            String(selectedNotetypeID),
            bookIDField,
            bookTitleField,
            bookCoverField,
            chapterTitleField,
            chapterOrderField,
            contentField,
            languageField,
            String(verticalLayout),
            String(readerFontSize)
        ].joined(separator: "|")
    }

    private var sortedBooks: [ReaderBook] {
        books.sorted { lhs, rhs in
            switch sortOption {
            case .recent:
                let lhsDate = ReaderProgressStore.load(bookID: lhs.id)?.updatedAt ?? .distantPast
                let rhsDate = ReaderProgressStore.load(bookID: rhs.id)?.updatedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
            case .progress:
                let lhsProgress = progressValue(for: lhs)
                let rhsProgress = progressValue(for: rhs)
                if lhsProgress != rhsProgress {
                    return lhsProgress > rhsProgress
                }
            case .title:
                break
            }

            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private var bookGridColumns: [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: 0, maximum: .infinity),
                spacing: Self.bookGridSpacing,
                alignment: .top
            ),
            count: resolvedBookshelfColumns
        )
    }

    var body: some View {
        Group {
            if let configurationProblem {
                ContentUnavailableView(
                    L("reader_library_missing_config_title"),
                    systemImage: "books.vertical",
                    description: Text(configurationProblem)
                )
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if books.isEmpty {
                ContentUnavailableView(
                    L("reader_library_empty_title"),
                    systemImage: "book.closed",
                    description: Text(L("reader_library_empty_description"))
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if isSelecting {
                            Text(L("reader_library_selected_count", selectedBookIDs.count))
                                .font(.footnote)
                                .foregroundStyle(Color.amgiTextSecondary)
                                .padding(.horizontal, 2)
                        }

                        LazyVGrid(columns: bookGridColumns, alignment: .leading, spacing: Self.bookGridSpacing) {
                            ForEach(sortedBooks) { book in
                                if isSelecting {
                                    Button {
                                        toggleSelection(for: book)
                                    } label: {
                                        ReaderBookCard(
                                            book: book,
                                            isSelecting: true,
                                            isSelected: selectedBookIDs.contains(book.id)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        ReaderBookDetailView(book: book)
                                    } label: {
                                        ReaderBookCard(book: book)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.amgiBackground)
        .navigationTitle(L("reader_library_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Menu {
                    Picker(L("reader_library_sort_menu"), selection: $sortOption) {
                        ForEach(ReaderBookSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel(Text(L("reader_library_sort_menu")))

                Button {
                    if isSelecting {
                        clearSelection()
                    } else {
                        isSelecting = true
                    }
                } label: {
                    Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .accessibilityLabel(Text(isSelecting ? L("common_done") : L("reader_library_multi_select")))
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker(
                        L("reader_library_layout_menu"),
                        selection: Binding(
                            get: { resolvedBookshelfColumns },
                            set: { bookshelfColumns = $0 == 2 ? 2 : 3 }
                        )
                    ) {
                        Text(L("reader_library_layout_two_columns")).tag(2)
                        Text(L("reader_library_layout_three_columns")).tag(3)
                    }
                } label: {
                    Image(systemName: resolvedBookshelfColumns == 2 ? "square.grid.2x2" : "square.grid.3x2")
                }
                .accessibilityLabel(Text(L("reader_library_layout_menu")))

                Menu {
                    Button {
                        settingsRoute = .source
                    } label: {
                        Label(L("settings_reader_section_source"), systemImage: "tray.full")
                    }

                    Button {
                        settingsRoute = .dictionaries
                    } label: {
                        Label(L("settings_reader_manage_dictionaries"), systemImage: "character.book.closed")
                    }

                    Button {
                        settingsRoute = .display
                    } label: {
                        Label(L("settings_reader_display_settings"), systemImage: "paintbrush")
                    }

                    Button {
                        settingsRoute = .advanced
                    } label: {
                        Label(L("settings_reader_advanced_settings"), systemImage: "gearshape.2")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: configurationSignature) {
            await loadBooks()
        }
        .sheet(item: $settingsRoute) { route in
            NavigationStack {
                switch route {
                case .source:
                    ReaderSourceSettingsView()
                case .dictionaries:
                    ReaderDictionarySettingsView()
                case .display:
                    ReaderDisplaySettingsView()
                case .advanced:
                    ReaderAdvancedSettingsView()
                }
            }
        }
        .alert(L("common_error"), isPresented: $showError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? L("common_unknown_error"))
        }
    }

    private func loadBooks() async {
        isLoading = true
        configurationProblem = nil
        books = []

        decks = (try? deckClient.fetchNamesOnly()) ?? []

        guard selectedDeckID != 0,
              let selectedDeck = decks.first(where: { Int($0.id) == selectedDeckID }) else {
            configurationProblem = L("reader_library_missing_config_description")
            isLoading = false
            return
        }

        guard !bookIDField.isEmpty,
              !bookTitleField.isEmpty,
              !chapterTitleField.isEmpty,
              !chapterOrderField.isEmpty,
              !contentField.isEmpty else {
            configurationProblem = L("reader_library_missing_config_description")
            isLoading = false
            return
        }

        do {
            let configuration = ReaderLibraryConfiguration(
                deckName: selectedDeck.name,
                notetypeID: selectedNotetypeID == 0 ? nil : Int64(selectedNotetypeID),
                fieldMapping: ReaderFieldMapping(
                    bookIDField: bookIDField,
                    bookTitleField: bookTitleField,
                    bookCoverField: bookCoverField.isEmpty ? nil : bookCoverField,
                    chapterTitleField: chapterTitleField,
                    chapterOrderField: chapterOrderField,
                    contentField: contentField,
                    languageField: languageField.isEmpty ? nil : languageField
                )
            )
            books = try readerBookClient.loadBooks(configuration)
            selectedBookIDs.formIntersection(Set(books.map(\.id)))
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    private func progressValue(for book: ReaderBook) -> Double {
        guard let savedProgress = ReaderProgressStore.load(bookID: book.id),
              let chapterIndex = book.chapters.firstIndex(where: { $0.id == savedProgress.chapterID }),
              !book.chapters.isEmpty else {
            return 0
        }

        let base = Double(chapterIndex) / Double(book.chapters.count)
        let chapterSlice = savedProgress.progress / Double(book.chapters.count)
        return min(base + chapterSlice, 1)
    }

    private func toggleSelection(for book: ReaderBook) {
        if selectedBookIDs.contains(book.id) {
            selectedBookIDs.remove(book.id)
        } else {
            selectedBookIDs.insert(book.id)
        }
    }

    private func clearSelection() {
        selectedBookIDs.removeAll()
        isSelecting = false
    }
}

private struct ReaderBookCard: View {
    let book: ReaderBook
    var isSelecting = false
    var isSelected = false

    private var savedProgress: ReaderSavedProgress? {
        ReaderProgressStore.load(bookID: book.id)
    }

    private var progressValue: Double {
        guard let savedProgress,
              let chapterIndex = book.chapters.firstIndex(where: { $0.id == savedProgress.chapterID }),
              !book.chapters.isEmpty else {
            return 0
        }

        let base = Double(chapterIndex) / Double(book.chapters.count)
        let chapterSlice = savedProgress.progress / Double(book.chapters.count)
        return min(base + chapterSlice, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ReaderBookCoverView(coverImagePath: book.coverImagePath)
                .aspectRatio(ReaderLibraryView.bookCoverAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.amgiAccent : Color.amgiTextSecondary)
                            .padding(10)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.amgiBorder.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amgiTextPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34, alignment: .topLeading)

                ProgressView(value: progressValue)
                    .tint(Color.amgiAccent)
            }
            .frame(height: 46, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderBookCoverView: View {
    let coverImagePath: String?

    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.amgiAccent.opacity(0.18), Color.amgiSurfaceElevated],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Color.amgiAccent)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.amgiBorder.opacity(0.18), lineWidth: 1)
            }
            .task(id: coverImagePath) {
                if let data = await ReaderBookCoverLoader.loadImageData(from: coverImagePath) {
                    image = UIImage(data: data)
                } else {
                    image = nil
                }
            }
    }
}

private enum ReaderBookCoverLoader {
    static func loadImageData(from rawValue: String?) async -> Data? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            loadImageDataSynchronously(from: rawValue)
        }.value
    }

    private static func loadImageDataSynchronously(from rawValue: String) -> Data? {
        guard let url = resolvedURL(from: rawValue) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func resolvedURL(from rawValue: String) -> URL? {
        let decodedValue = rawValue.removingPercentEncoding ?? rawValue

        if let directURL = URL(string: decodedValue),
           let scheme = directURL.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return directURL
        }

        guard let mediaDirectoryURL = CardMediaDirectory.currentMediaDirectoryURL() else {
            return nil
        }

        return mediaDirectoryURL.appendingPathComponent(decodedValue)
    }
}

private struct ReaderBookDetailView: View {
    let book: ReaderBook

    @AppStorage(ReaderPreferences.Keys.themeMode) private var themeModeRawValue = ReaderThemeMode.system.rawValue
    @AppStorage(ReaderPreferences.Keys.customContentColor) private var customContentColorHex = "#FFFDF8"
    @AppStorage(ReaderPreferences.Keys.customBackgroundColor) private var customBackgroundColorHex = "#FFFDF8"
    @AppStorage(ReaderPreferences.Keys.customTextColor) private var customTextColorHex = "#17212F"
    @AppStorage(ReaderPreferences.Keys.customHintColor) private var customHintColorHex = "#7F7F7F"
    @Environment(\.colorScheme) private var colorScheme

    private var themeMode: ReaderThemeMode {
        ReaderThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    private var systemListBackground: Color {
        .amgiBackground
    }

    private var resolvedListBackground: Color {
        switch themeMode {
        case .system:
            return systemListBackground
        case .eyeCare:
            return Color(red: 0.95, green: 0.98, blue: 0.95)
        case .sepia:
            return Color(red: 0.98, green: 0.95, blue: 0.88)
        case .custom:
            return Color(readerHex: customBackgroundColorHex, fallback: Color(red: 1.0, green: 0.99, blue: 0.97))
        }
    }

    private var savedProgress: ReaderSavedProgress? {
        ReaderProgressStore.load(bookID: book.id)
    }

    private var resumeChapter: ReaderChapter? {
        guard let savedProgress else {
            return nil
        }
        return book.chapters.first(where: { $0.id == savedProgress.chapterID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
            if let resumeChapter {
                NavigationLink {
                    ReaderChapterView(book: book, chapter: resumeChapter)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "book.fill")
                            .font(.title2.weight(.semibold))
                        Text(L("reader_book_continue"))
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color.amgiTextSecondary.opacity(0.62))
                    }
                    .foregroundStyle(Color.amgiTextPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.amgiSurfaceElevated.opacity(0.72), in: Capsule())
                }
                .buttonStyle(.plain)
            }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L("reader_book_chapters", book.chapters.count))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.amgiTextSecondary)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                            NavigationLink {
                                ReaderChapterView(book: book, chapter: chapter)
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.amgiAccent)
                                        .frame(width: 24, height: 24)
                                        .background(Color.amgiAccent.opacity(0.12), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.amgiTextPrimary)
                                            .lineLimit(1)
                                        if let order = chapter.order {
                                            Text(order)
                                                .font(.caption2)
                                                .foregroundStyle(Color.amgiTextSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.amgiTextSecondary.opacity(0.62))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if index < book.chapters.count - 1 {
                                Divider()
                                    .padding(.leading, 60)
                                    .padding(.trailing, 24)
                                    .overlay(Color.amgiBorder.opacity(0.24))
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.amgiSurfaceElevated.opacity(0.72))
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 140)
        }
        .background(resolvedListBackground)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReaderChapterView: View {
    enum SelectionAction {
        case addNote
        case lookup
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient

    @AppStorage(ReaderPreferences.Keys.deckID) private var selectedDeckID = 0
    @AppStorage(ReaderPreferences.Keys.verticalLayout) private var verticalLayout = false
    @AppStorage(ReaderPreferences.Keys.selectedFont) private var selectedFont = ReaderFontOption.defaultValue
    @AppStorage(ReaderPreferences.Keys.fontSize) private var readerFontSize = 24
    @AppStorage(ReaderPreferences.Keys.hideFurigana) private var hideFurigana = false
    @AppStorage(ReaderPreferences.Keys.horizontalPadding) private var horizontalPadding = 2
    @AppStorage(ReaderPreferences.Keys.verticalPadding) private var verticalPadding = 0
    @AppStorage(ReaderPreferences.Keys.avoidPageBreak) private var avoidPageBreak = false
    @AppStorage(ReaderPreferences.Keys.justifyText) private var justifyText = false
    @AppStorage(ReaderPreferences.Keys.lineHeight) private var lineHeight = 1.65
    @AppStorage(ReaderPreferences.Keys.characterSpacing) private var characterSpacing = 0.0
    @AppStorage(ReaderPreferences.Keys.showTitle) private var showTitle = true
    @AppStorage(ReaderPreferences.Keys.showPercentage) private var showPercentage = true
    @AppStorage(ReaderPreferences.Keys.showProgressTop) private var showProgressTop = true
    @AppStorage(ReaderPreferences.Keys.themeMode) private var themeModeRawValue = ReaderThemeMode.system.rawValue
    @AppStorage(ReaderPreferences.Keys.customContentColor) private var customContentColorHex = "#FFFDF8"
    @AppStorage(ReaderPreferences.Keys.customBackgroundColor) private var customBackgroundColorHex = "#FFFDF8"
    @AppStorage(ReaderPreferences.Keys.customTextColor) private var customTextColorHex = "#17212F"
    @AppStorage(ReaderPreferences.Keys.customHintColor) private var customHintColorHex = "#7F7F7F"
    @AppStorage(ReaderPreferences.Keys.popupWidth) private var popupWidth = 320
    @AppStorage(ReaderPreferences.Keys.popupHeight) private var popupHeight = 250
    @AppStorage(ReaderPreferences.Keys.popupFontSize) private var popupFontSize = 14
    @AppStorage(ReaderPreferences.Keys.popupFrequencyFontSize) private var popupFrequencyFontSize = 13
    @AppStorage(ReaderPreferences.Keys.popupContentFontSize) private var popupContentFontSize = 14
    @AppStorage(ReaderPreferences.Keys.popupDictionaryNameFontSize) private var popupDictionaryNameFontSize = 13
    @AppStorage(ReaderPreferences.Keys.popupKanaFontSize) private var popupKanaFontSize = 14
    @AppStorage(ReaderPreferences.Keys.popupFullWidth) private var popupFullWidth = false
    @AppStorage(ReaderPreferences.Keys.popupSwipeToDismiss) private var popupSwipeToDismiss = false
    @AppStorage(ReaderPreferences.Keys.popupCollapseDictionaries) private var popupCollapseDictionaries = false
    @AppStorage(ReaderPreferences.Keys.popupCompactGlossaries) private var popupCompactGlossaries = true
    @AppStorage(ReaderPreferences.Keys.popupAudioSourceTemplate) private var popupAudioSourceTemplate = ReaderLookupAudioDefaults.defaultTemplate
    @AppStorage(ReaderPreferences.Keys.popupLocalAudioEnabled) private var popupLocalAudioEnabled = false
    @AppStorage(ReaderPreferences.Keys.popupAudioAutoplay) private var popupAudioAutoplay = false
    @AppStorage(ReaderPreferences.Keys.popupAudioPlaybackMode) private var popupAudioPlaybackModeRawValue = ReaderLookupAudioPlaybackMode.interrupt.rawValue
    @AppStorage(ReaderPreferences.Keys.dictionaryMaxResults) private var dictionaryMaxResults = 16
    @AppStorage(ReaderPreferences.Keys.dictionaryScanLength) private var dictionaryScanLength = 16
    @AppStorage(ReaderPreferences.Keys.tapLookup) private var tapLookupEnabled = true
    @AppStorage(ReaderPreferences.Keys.lookupNoteTemplate) private var lookupNoteTemplateData = ""

    let book: ReaderBook
    let chapter: ReaderChapter

    @State private var progress: Double = 0
    @State private var selectionRequestID = 0
    @State private var pendingDraft: AddNoteDraft?
    @State private var showAddNoteSheet = false
    @State private var showSelectionError = false
    @State private var pendingSelectionAction: SelectionAction?
    @State private var lookupErrorMessage: String?
    @State private var lookupStack: [ReaderLookupPopupState] = []
    @State private var lookupHighlightClearRequestID = 0
    @State private var lookupHighlightLengthRequestID = 0
    @State private var lookupHighlightLength = 0
    @State private var activeSheet: ReaderChapterSheetRoute?
    @State private var chapterNavigationTarget: ReaderChapter?

    private var currentChapterIndex: Int {
        book.chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0
    }

    private var savedProgress: Double {
        guard let savedProgress = ReaderProgressStore.load(bookID: book.id),
              savedProgress.chapterID == chapter.id else {
            return 0
        }
        return savedProgress.progress
    }

    private var previousChapter: ReaderChapter? {
        guard currentChapterIndex > 0 else {
            return nil
        }
        return book.chapters[currentChapterIndex - 1]
    }

    private var nextChapter: ReaderChapter? {
        guard currentChapterIndex < book.chapters.count - 1 else {
            return nil
        }
        return book.chapters[currentChapterIndex + 1]
    }

    private var progressLabel: String {
        if showPercentage {
            return L("reader_reader_position", currentChapterIndex + 1, book.chapters.count, progress * 100)
        }
        return L("reader_reader_position_chapter_only", currentChapterIndex + 1, book.chapters.count)
    }

    private var lookupLanguageHint: String? {
        chapter.language?.nilIfBlank ?? book.language?.nilIfBlank
    }

    private var themeMode: ReaderThemeMode {
        ReaderThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    private var lookupNoteTemplate: ReaderLookupNoteTemplate {
        ReaderLookupNoteTemplate.decode(from: lookupNoteTemplateData)
    }

    private var popupAudioPlaybackMode: ReaderLookupAudioPlaybackMode {
        ReaderLookupAudioDefaults.resolvedPlaybackMode(popupAudioPlaybackModeRawValue)
    }

    private var systemPageBackgroundHex: String {
        colorScheme == .dark ? "#000000" : "#F2F2F7"
    }

    private var systemContentBackgroundHex: String {
        colorScheme == .dark ? "#24262E" : "#FFFFFF"
    }

    private var systemTextColorHex: String {
        colorScheme == .dark ? "#FFFFFF" : "#000000"
    }

    private var systemHintColorHex: String {
        colorScheme == .dark ? "#D1D1D1" : "#8E8E93"
    }

    private var systemLinkColorHex: String {
        colorScheme == .dark ? "#7AC7FF" : "#055FD6"
    }

    private var resolvedPageBackgroundHex: String {
        switch themeMode {
        case .system:
            return systemPageBackgroundHex
        case .eyeCare:
            return "#EAF4E4"
        case .sepia:
            return "#F4ECD8"
        case .custom:
            return Self.normalizedHexColor(customBackgroundColorHex, fallback: "#FFFDF8")
        }
    }

    private var resolvedContentBackgroundHex: String {
        switch themeMode {
        case .system:
            return systemContentBackgroundHex
        case .eyeCare:
            return "#F3F9EF"
        case .sepia:
            return "#FAF1DE"
        case .custom:
            return Self.normalizedHexColor(customContentColorHex, fallback: "#FFFDF8")
        }
    }

    private var resolvedTextColorHex: String {
        switch themeMode {
        case .system:
            return systemTextColorHex
        case .eyeCare:
            return "#253224"
        case .sepia:
            return "#5A4632"
        case .custom:
            return Self.normalizedHexColor(customTextColorHex, fallback: "#17212F")
        }
    }

    private var resolvedHintColorHex: String {
        switch themeMode {
        case .system:
            return systemHintColorHex
        case .eyeCare:
            return "#64715D"
        case .sepia:
            return "#7A6852"
        case .custom:
            return Self.normalizedHexColor(customHintColorHex, fallback: "#7F7F7F")
        }
    }

    private var resolvedLinkColorHex: String {
        themeMode == .system
            ? systemLinkColorHex
            : (colorScheme == .dark ? "#8FB8FF" : "#1E5BB8")
    }

    private var chapterContentBackground: Color {
        Color(readerHex: resolvedContentBackgroundHex, fallback: .amgiSurfaceElevated)
    }

    private static func normalizedHexColor(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return fallback
        }
        let normalized = trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
        let hex = normalized.dropFirst()
        guard hex.count == 6, Int(hex, radix: 16) != nil else {
            return fallback
        }
        return normalized.uppercased()
    }

    var body: some View {
        GeometryReader { geometry in
            let topSafeArea = max(UIApplication.readerTopSafeArea, geometry.safeAreaInsets.top)
            let bottomSafeArea = max(UIApplication.readerBottomSafeArea, geometry.safeAreaInsets.bottom)
            let showsTopInfo = showTitle || showProgressTop
            let topOverlayTopPadding = max(topSafeArea, 25)
            let topOverlayHeight = topOverlayTopPadding + (showsTopInfo ? 34 : 10)
            let bottomInset = max(bottomSafeArea - 8, 14)
            let bottomChromePadding = max(bottomSafeArea - 18, 6)

            VStack(spacing: 0) {
                chapterContentBackground
                    .frame(height: topOverlayHeight)

                ZStack(alignment: .bottom) {
                    ReaderChapterWebView(
                        html: chapter.content,
                        languageHint: lookupLanguageHint,
                        isVertical: verticalLayout,
                        fontFamily: ReaderFontOption.resolved(selectedFont).cssFontFamily,
                        fontSize: Double(readerFontSize),
                        pageBackgroundHex: resolvedPageBackgroundHex,
                        contentBackgroundHex: resolvedContentBackgroundHex,
                        textColorHex: resolvedTextColorHex,
                        hintColorHex: resolvedHintColorHex,
                        linkColorHex: resolvedLinkColorHex,
                        hideFurigana: hideFurigana,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        avoidPageBreak: avoidPageBreak,
                        justifyText: justifyText,
                        lineHeight: lineHeight,
                        characterSpacing: characterSpacing,
                        scanLength: dictionaryScanLength,
                        savedProgress: savedProgress,
                        selectionRequestID: selectionRequestID,
                        clearLookupHighlightRequestID: lookupHighlightClearRequestID,
                        lookupHighlightLengthRequestID: lookupHighlightLengthRequestID,
                        lookupHighlightLength: lookupHighlightLength,
                        tapLookupEnabled: tapLookupEnabled,
                        onProgressChange: { newProgress in
                            progress = newProgress
                            ReaderProgressStore.save(bookID: book.id, chapterID: chapter.id, progress: newProgress)
                        },
                        onSelectionResolved: { selection in
                            handleResolvedSelection(selection)
                        },
                        onLookupRequested: { selection, sentence, point, rect in
                            let offsetPoint = CGPoint(x: point.x, y: point.y + topOverlayHeight)
                            let offsetRect = rect.map { $0.offsetBy(dx: 0, dy: topOverlayHeight) }
                            handleTapLookup(selection, sentence: sentence, at: offsetPoint, rect: offsetRect)
                        }
                    )
                    .background(chapterContentBackground)
                    .ignoresSafeArea(edges: .bottom)

                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            ReaderChromeIconLabel(systemName: "chevron.left")
                        }
                        .readerChromeButtonStyle()
                        .accessibilityLabel(Text(L("common_back")))

                        Spacer()

                        Menu {
                            Button {
                                activeSheet = .chapters
                            } label: {
                                Label(L("reader_reader_menu_chapters"), systemImage: "list.bullet")
                            }

                            Button {
                                activeSheet = .display
                            } label: {
                                Label(L("settings_reader_display_settings"), systemImage: "paintbrush.pointed")
                            }

                            Button {
                                activeSheet = .settings
                            } label: {
                                Label(L("settings_row_reader"), systemImage: "slider.horizontal.3")
                            }
                        } label: {
                            ReaderChromeIconLabel(systemName: "ellipsis")
                        }
                        .readerChromeButtonStyle()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, bottomChromePadding)
                }
            }
            .background(chapterContentBackground)
            .overlay(alignment: .top) {
                ReaderChapterInfoOverlay(
                    title: showTitle ? book.title : nil,
                    progressLabel: showProgressTop ? progressLabel : nil,
                    background: chapterContentBackground
                )
                    .padding(.top, topOverlayTopPadding)
            }
            .overlay(alignment: .bottom) {
                if showProgressTop == false {
                    ReaderChapterBottomProgressOverlay(progressLabel: progressLabel)
                        .padding(.bottom, bottomInset + 60)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    Button {
                        pendingSelectionAction = .addNote
                        selectionRequestID += 1
                    } label: {
                        ReaderChromeIconLabel(systemName: "plus")
                    }
                    .readerChromeButtonStyle()
                }
                .padding(.top, topOverlayTopPadding)
                .padding(.trailing, 20)
            }
            .overlay {
                if lookupStack.isEmpty == false {
                    GeometryReader { popupGeometry in
                        ZStack {
                            Color.black.opacity(0.001)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    lookupStack.removeAll()
                                    lookupHighlightClearRequestID += 1
                                }

                            ForEach(Array(lookupStack.enumerated()), id: \.element.id) { index, popup in
                                ReaderLookupPopup(
                                    query: popup.query,
                                    result: popup.result,
                                    isLoading: popup.isLoading,
                                    sentence: popup.sentence,
                                    languageHint: lookupLanguageHint,
                                    popupWidth: CGFloat(popupWidth),
                                    popupHeight: CGFloat(popupHeight),
                                    popupFontSize: CGFloat(popupFontSize),
                                    popupFrequencyFontSize: CGFloat(popupFrequencyFontSize),
                                    popupContentFontSize: CGFloat(popupContentFontSize),
                                    popupDictionaryNameFontSize: CGFloat(popupDictionaryNameFontSize),
                                    popupKanaFontSize: CGFloat(popupKanaFontSize),
                                    isFullWidth: popupFullWidth,
                                    swipeToDismiss: popupSwipeToDismiss,
                                    collapseDictionaries: popupCollapseDictionaries,
                                    compactGlossaries: popupCompactGlossaries,
                                    audioSourceTemplate: popupAudioSourceTemplate,
                                    localAudioEnabled: popupLocalAudioEnabled,
                                    audioAutoplay: popupAudioAutoplay && index == lookupStack.count - 1,
                                    audioPlaybackMode: popupAudioPlaybackMode,
                                    onAddNote: { payload in
                                        pendingDraft = makeLookupDraft(from: payload, sentence: popup.sentence)
                                        lookupStack.removeAll()
                                        lookupHighlightClearRequestID += 1
                                        showAddNoteSheet = true
                                    },
                                    onLookupRequested: { query, sentence in
                                        startLookup(for: query, sentence: sentence, anchor: nil, stacksOnTop: true)
                                    },
                                    onClose: {
                                        closeLookupPopup(id: popup.id)
                                    }
                                )
                                .frame(maxWidth: popupFullWidth ? .infinity : CGFloat(popupWidth))
                                .padding(.horizontal, 14)
                                .position(
                                    lookupPopupPosition(
                                        in: popupGeometry.size,
                                        bottomInset: bottomInset,
                                        anchor: popup.anchor,
                                        anchorRect: popup.anchorRect,
                                        stackDepth: index
                                    )
                                )
                                .zIndex(Double(index))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
        }
        .background(chapterContentBackground)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showAddNoteSheet, onDismiss: {
            pendingDraft = nil
        }) {
            AddNoteView(
                onSave: {
                    pendingDraft = nil
                },
                draft: pendingDraft
            )
        }
        .sheet(item: $activeSheet) { route in
            NavigationStack {
                switch route {
                case .chapters:
                    ReaderChapterListSheet(book: book, currentChapterID: chapter.id) { selectedChapter in
                        activeSheet = nil
                        if selectedChapter.id != chapter.id {
                            chapterNavigationTarget = selectedChapter
                        }
                    }
                case .display:
                    ReaderDisplaySettingsView()
                case .settings:
                    ReaderSettingsHomeView()
                }
            }
            .presentationDetents([.fraction(0.52), .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $chapterNavigationTarget) { target in
            ReaderChapterView(book: book, chapter: target)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: lookupStack)
        .ignoresSafeArea(edges: .top)
        .alert(L("common_error"), isPresented: $showSelectionError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(lookupErrorMessage ?? L("reader_reader_empty_selection"))
        }
    }

    private func handleResolvedSelection(_ selection: String?) {
        guard let trimmedSelection = normalizedSelection(selection) else {
            lookupErrorMessage = L("reader_reader_empty_selection")
            showSelectionError = true
            return
        }

        let action = pendingSelectionAction
        pendingSelectionAction = nil

        switch action {
        case .lookup:
            startLookup(for: trimmedSelection)
        case .addNote, .none:
            pendingDraft = makeDraft(for: trimmedSelection)
            showAddNoteSheet = true
        }
    }

    private func handleTapLookup(_ selection: String?, sentence: String?, at point: CGPoint, rect: CGRect?) {
        guard let tappedSelection = normalizedSelection(selection) else {
            lookupStack.removeAll()
            lookupHighlightClearRequestID += 1
            return
        }
        pendingSelectionAction = nil
        startLookup(for: tappedSelection, sentence: sentence, anchor: point, anchorRect: rect)
    }

    private func normalizedSelection(_ selection: String?) -> String? {
        let trimmedSelection = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSelection.isEmpty ? nil : trimmedSelection
    }

    private func normalizedSentence(_ sentence: String?) -> String? {
        let trimmedSentence = sentence?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSentence.isEmpty ? nil : trimmedSentence
    }

    private func startLookup(for query: String, sentence: String? = nil, anchor: CGPoint? = nil, anchorRect: CGRect? = nil, stacksOnTop: Bool = false) {
        let popup = ReaderLookupPopupState(
            query: query,
            sentence: normalizedSentence(sentence),
            anchor: anchor,
            anchorRect: anchorRect,
            isLoading: true
        )

        if stacksOnTop {
            lookupStack.append(popup)
        } else {
            lookupStack = [popup]
        }

        Task {
            do {
                let result = try await dictionaryLookupClient.lookup(
                    query,
                    dictionaryMaxResults,
                    dictionaryScanLength
                )
                updateLookupPopup(id: popup.id, result: result, isLoading: false)
                if let matched = result.entries.first?.matched?.nilIfBlank {
                    lookupHighlightLength = matched.count
                    lookupHighlightLengthRequestID += 1
                }
            } catch {
                removeLookupPopup(id: popup.id)
                lookupErrorMessage = error.localizedDescription
                showSelectionError = true
            }
        }
    }

    private func updateLookupPopup(id: UUID, result: DictionaryLookupResult, isLoading: Bool) {
        guard let index = lookupStack.firstIndex(where: { $0.id == id }) else {
            return
        }
        lookupStack[index].result = result
        lookupStack[index].isLoading = isLoading
    }

    private func removeLookupPopup(id: UUID) {
        lookupStack.removeAll { $0.id == id }
    }

    private func closeLookupPopup(id: UUID) {
        removeLookupPopup(id: id)
        if lookupStack.isEmpty {
            lookupHighlightClearRequestID += 1
        }
    }

    private func lookupPopupPosition(in size: CGSize, bottomInset: CGFloat, anchor: CGPoint?, anchorRect: CGRect?, stackDepth: Int) -> CGPoint {
        let horizontalMargin: CGFloat = 18
        let popupResolvedWidth = popupFullWidth
            ? max(size.width - horizontalMargin * 2, 0)
            : min(CGFloat(popupWidth), max(size.width - horizontalMargin * 2, 0))
        let popupHalfWidth = popupResolvedWidth / 2
        let popupHalfHeight = min(CGFloat(popupHeight) / 2, max(size.height / 2 - 56, 132))
        let stackedOffset = CGFloat(stackDepth) * min(36, popupHalfHeight * 0.22)

        guard popupFullWidth == false, let anchor else {
            return CGPoint(
                x: size.width / 2,
                y: max(136 + popupHalfHeight, size.height - bottomInset - popupHalfHeight - 48 - stackedOffset)
            )
        }

        let anchorBottom = anchorRect?.maxY ?? anchor.y
        let anchorTop = anchorRect?.minY ?? anchor.y
        let proposedBottomY = anchorBottom + popupHalfHeight + 6 - stackedOffset
        let fallbackTopY = anchorTop - popupHalfHeight - 6 - stackedOffset
        let minY = 136 + popupHalfHeight
        let maxY = size.height - bottomInset - popupHalfHeight - 20
        let resolvedY = proposedBottomY <= maxY ? proposedBottomY : max(fallbackTopY, minY)
        let resolvedX = min(
            max(anchor.x, popupHalfWidth + horizontalMargin),
            size.width - popupHalfWidth - horizontalMargin
        )

        return CGPoint(x: resolvedX, y: resolvedY)
    }

    private func makeDraft(for selectedText: String, sentence: String? = nil) -> AddNoteDraft {
        let sourceDescription = [book.title, chapter.title]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        let resolvedSentence = normalizedSentence(sentence) ?? selectedText

        return AddNoteDraft(
            deckID: selectedDeckID == 0 ? nil : Int64(selectedDeckID),
            fieldValues: [
                "Front": selectedText,
                "Text": selectedText,
                "Expression": selectedText,
                "Sentence": resolvedSentence,
                "Back": sourceDescription,
                "Source": sourceDescription,
                "Extra": sourceDescription
            ]
        )
    }

    private func makeLookupDraft(from payload: ReaderLookupNotePayload, sentence: String?) -> AddNoteDraft {
        let sourceDescription = [book.title, chapter.title]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        var resolvedPayload = payload
        resolvedPayload.sentence = normalizedSentence(payload.sentence) ?? sentence

        return lookupNoteTemplate.makeDraft(
            payload: resolvedPayload,
            fallbackDeckID: selectedDeckID == 0 ? nil : Int64(selectedDeckID),
            sourceDescription: sourceDescription
        )
    }
}

struct ReaderLookupPopupState: Identifiable, Hashable {
    let id = UUID()
    var query: String
    var sentence: String?
    var anchor: CGPoint?
    var anchorRect: CGRect?
    var result: DictionaryLookupResult?
    var isLoading: Bool
}

struct ReaderLookupPopup: View {
    @Environment(\.colorScheme) private var colorScheme

    let query: String
    let result: DictionaryLookupResult?
    let isLoading: Bool
    let sentence: String?
    let languageHint: String?
    let popupWidth: CGFloat
    let popupHeight: CGFloat
    let popupFontSize: CGFloat
    let popupFrequencyFontSize: CGFloat
    let popupContentFontSize: CGFloat
    let popupDictionaryNameFontSize: CGFloat
    let popupKanaFontSize: CGFloat
    let isFullWidth: Bool
    let swipeToDismiss: Bool
    let collapseDictionaries: Bool
    let compactGlossaries: Bool
    let audioSourceTemplate: String
    let localAudioEnabled: Bool
    let audioAutoplay: Bool
    let audioPlaybackMode: ReaderLookupAudioPlaybackMode
    let onAddNote: ((ReaderLookupNotePayload) -> Void)?
    let onLookupRequested: (String, String?) -> Void
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var popupCornerRadius: CGFloat { 18 }

    private var popupBackgroundFill: Color {
        colorScheme == .dark
            ? Color(.secondarySystemBackground).opacity(0.96)
            : Color(.systemBackground).opacity(0.96)
    }

    private var contentScale: CGFloat {
        max(0.6, popupContentFontSize / 14)
    }

    private var frequencyScale: CGFloat {
        max(0.6, popupFrequencyFontSize / 13)
    }

    private var dictionaryNameScale: CGFloat {
        max(0.6, popupDictionaryNameFontSize / 13)
    }

    private var loadingFont: CGFloat { 13 * contentScale }
    private var emptyFont: CGFloat { 13 * contentScale }
    private var sectionDictionaryFont: CGFloat { 13 * dictionaryNameScale }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L("reader_lookup_loading"))
                            .font(.system(size: loadingFont))
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                } else if let result, result.isPlaceholder {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("reader_lookup_placeholder"))
                            .font(.system(size: emptyFont))
                            .foregroundStyle(Color.amgiTextSecondary)
                        Text(L("reader_lookup_missing_source"))
                            .font(.system(size: sectionDictionaryFont))
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                } else if let result, result.entries.isEmpty == false {
                    ReaderLookupRichEntriesView(
                        result: result,
                        languageHint: languageHint,
                        popupFontSize: popupFontSize,
                        popupContentFontSize: popupContentFontSize,
                        popupDictionaryNameFontSize: popupDictionaryNameFontSize,
                        popupKanaFontSize: popupKanaFontSize,
                        popupFrequencyFontSize: popupFrequencyFontSize,
                        collapseDictionaries: collapseDictionaries,
                        compactGlossaries: compactGlossaries,
                        audioSourceTemplate: audioSourceTemplate,
                        localAudioEnabled: localAudioEnabled,
                        audioAutoplay: audioAutoplay,
                        audioPlaybackMode: audioPlaybackMode,
                        sentence: sentence,
                        onAddNote: onAddNote,
                        onLookupRequested: onLookupRequested
                    )
                } else {
                    Text(L("reader_lookup_empty"))
                        .font(.system(size: emptyFont))
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: max(140, popupHeight - 36))
        .padding(18)
        .frame(maxWidth: isFullWidth ? .infinity : popupWidth, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous)
                .fill(popupBackgroundFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: popupCornerRadius, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.34), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .offset(y: dragOffset)
        .gesture(
            swipeToDismiss ?
                DragGesture(minimumDistance: 10)
                .onChanged { value in
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 80 {
                        onClose()
                    }
                    dragOffset = 0
                }
            : nil
        )
    }
}

private struct ReaderChapterListSheet: View {
    let book: ReaderBook
    let currentChapterID: Int64
    let onSelect: (ReaderChapter) -> Void

    var body: some View {
        List {
            ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                Button {
                    onSelect(chapter)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.amgiAccent)
                            .frame(width: 28, height: 28)
                            .background(Color.amgiAccent.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(chapter.title)
                                .foregroundStyle(Color.amgiTextPrimary)
                                .multilineTextAlignment(.leading)
                            if let order = chapter.order {
                                Text(order)
                                    .font(.caption)
                                    .foregroundStyle(Color.amgiTextSecondary)
                                    .lineLimit(1)
                                    .amgiCapsuleControl(horizontalPadding: 8, verticalPadding: 3)
                            }
                        }

                        Spacer(minLength: 0)

                        if chapter.id == currentChapterID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.amgiAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("reader_reader_menu_chapters"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReaderChapterInfoOverlay: View {
    let title: String?
    let progressLabel: String?
    let background: Color

    var body: some View {
        VStack(spacing: 2) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.amgiTextSecondary)
                    .lineLimit(1)
            }

            if let progressLabel, !progressLabel.isEmpty {
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .monospacedDigit()
                    .tracking(-0.3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 112)
        .padding(.vertical, 1)
        .background(background)
    }
}

private struct ReaderChapterBottomProgressOverlay: View {
    let progressLabel: String

    var body: some View {
        Text(progressLabel)
            .font(.caption)
            .foregroundStyle(Color.amgiTextSecondary)
            .monospacedDigit()
            .tracking(-0.3)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 80)
    }
}

private struct ReaderChromeIconLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.amgiTextPrimary)
            .frame(width: 22, height: 22)
    }
}

private extension View {
    @ViewBuilder
    func readerChromeButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
    }
}

private extension UIApplication {
    static var readerSafeAreaInsets: UIEdgeInsets {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    static var readerTopSafeArea: CGFloat {
        readerSafeAreaInsets.top
    }

    static var readerBottomSafeArea: CGFloat {
        readerSafeAreaInsets.bottom
    }
}

private struct ReaderChapterWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let html: String
    let languageHint: String?
    let isVertical: Bool
    let fontFamily: String
    let fontSize: Double
    let pageBackgroundHex: String
    let contentBackgroundHex: String
    let textColorHex: String
    let hintColorHex: String
    let linkColorHex: String
    let hideFurigana: Bool
    let horizontalPadding: Int
    let verticalPadding: Int
    let avoidPageBreak: Bool
    let justifyText: Bool
    let lineHeight: Double
    let characterSpacing: Double
    let scanLength: Int
    let savedProgress: Double
    let selectionRequestID: Int
    let clearLookupHighlightRequestID: Int
    let lookupHighlightLengthRequestID: Int
    let lookupHighlightLength: Int
    let tapLookupEnabled: Bool
    let onProgressChange: (Double) -> Void
    let onSelectionResolved: (String?) -> Void
    let onLookupRequested: (String?, String?, CGPoint, CGRect?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            savedProgress: savedProgress,
            onProgressChange: onProgressChange,
            onSelectionResolved: onSelectionResolved,
            onLookupRequested: onLookupRequested
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(CardAssetScheme(), forURLScheme: CardAssetPath.scheme)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.selectionCacheScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.tapLookupScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = isVertical
        webView.scrollView.showsVerticalScrollIndicator = !isVertical
        webView.scrollView.delegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTapLookup(_:)))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        webView.addGestureRecognizer(tapRecognizer)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let document = htmlDocument(for: html)
        context.coordinator.parent = self
        context.coordinator.pendingProgress = savedProgress
        webView.scrollView.showsHorizontalScrollIndicator = isVertical
        webView.scrollView.showsVerticalScrollIndicator = !isVertical
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light

        if selectionRequestID != context.coordinator.lastSelectionRequestID {
            context.coordinator.lastSelectionRequestID = selectionRequestID
            webView.evaluateJavaScript("window.amgiReaderSelectionText ? window.amgiReaderSelectionText() : ''") { value, _ in
                context.coordinator.onSelectionResolved(value as? String)
            }
        }
        if clearLookupHighlightRequestID != context.coordinator.lastClearLookupHighlightRequestID {
            context.coordinator.lastClearLookupHighlightRequestID = clearLookupHighlightRequestID
            webView.evaluateJavaScript("window.amgiReaderSelection?.clearSelection()") { _, _ in }
        }
        if lookupHighlightLengthRequestID != context.coordinator.lastLookupHighlightLengthRequestID {
            context.coordinator.lastLookupHighlightLengthRequestID = lookupHighlightLengthRequestID
            webView.evaluateJavaScript("window.amgiReaderSelection?.highlightSelection(\(max(0, lookupHighlightLength)))") { _, _ in }
        }

        guard context.coordinator.lastHTML != document else { return }
        context.coordinator.lastHTML = document
        webView.loadHTMLString(document, baseURL: CardAssetPath.mediaBaseURL)
    }

    private static let selectionCacheScript = """
    (function() {
        window.amgiReaderLastSelection = '';
        window.amgiReaderSelectionText = function() {
            var current = window.getSelection ? String(window.getSelection()) : '';
            current = current.trim();
            return current || window.amgiReaderLastSelection || '';
        };
        document.addEventListener('selectionchange', function() {
            var current = window.getSelection ? String(window.getSelection()) : '';
            current = current.trim();
            if (current) {
                window.amgiReaderLastSelection = current;
            }
        });
    })();
    """

    private static let tapLookupScript = #"""
    (function() {
        window.amgiReaderSelection = {
            selection: null,
            scanDelimiters: '。、！？…‥「」『』（）()【】〈〉《》〔〕｛｝{}［］[]・：；:;，,.─\n\r',
            sentenceDelimiters: '。！？.!?\n\r',

            isScanBoundary(char) {
                return /^[\s\u3000]$/.test(char) || this.scanDelimiters.includes(char);
            },

            isLatinLookupChar(char) {
                return /^[A-Za-z0-9]$/.test(char || '');
            },

            isFurigana(node) {
                const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
                return !!el?.closest('rt, rp');
            },

            findParagraph(node) {
                let el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
                return el?.closest('p, .glossary-content') || null;
            },

            createWalker(rootNode) {
                const root = rootNode || document.body;
                return document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                    acceptNode: (node) => this.isFurigana(node) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
                });
            },

            inCharRange(charRange, x, y) {
                const rects = charRange.getClientRects();
                if (rects.length) {
                    for (const rect of rects) {
                        if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
                            return true;
                        }
                    }
                    return false;
                }

                const rect = charRange.getBoundingClientRect();
                return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
            },

            getCaretRange(x, y) {
                if (document.caretPositionFromPoint) {
                    const pos = document.caretPositionFromPoint(x, y);
                    if (!pos) {
                        return null;
                    }

                    const range = document.createRange();
                    range.setStart(pos.offsetNode, pos.offset);
                    range.collapse(true);
                    return range;
                }

                const element = document.elementFromPoint(x, y);
                if (!element) {
                    return null;
                }

                const container = element.closest('p, div, span, ruby, a') || document.body;
                const walker = this.createWalker(container);
                const range = document.createRange();
                let node;

                while ((node = walker.nextNode())) {
                    for (let index = 0; index < node.textContent.length; index += 1) {
                        range.setStart(node, index);
                        range.setEnd(node, index + 1);
                        if (this.inCharRange(range, x, y)) {
                            range.collapse(true);
                            return range;
                        }
                    }
                }

                return document.caretRangeFromPoint ? document.caretRangeFromPoint(x, y) : null;
            },

            getCharacterAtPoint(x, y) {
                const range = this.getCaretRange(x, y);
                if (!range) {
                    return null;
                }

                const node = range.startContainer;
                if (node.nodeType !== Node.TEXT_NODE) {
                    return null;
                }

                if (this.isFurigana(node)) {
                    return null;
                }

                const text = node.textContent || '';
                const caret = range.startOffset;

                for (const offset of [caret, caret - 1, caret + 1]) {
                    if (offset < 0 || offset >= text.length) {
                        continue;
                    }

                    const charRange = document.createRange();
                    charRange.setStart(node, offset);
                    charRange.setEnd(node, offset + 1);
                    if (this.inCharRange(charRange, x, y)) {
                        if (this.isScanBoundary(text[offset])) {
                            return null;
                        }
                        return { node, offset };
                    }
                }

                return null;
            },

            getSentence(startNode, startOffset) {
                const container = this.findParagraph(startNode) || document.body;
                const walker = this.createWalker(container);
                const trailingSentenceChars = '」』）】!?！？…';

                walker.currentNode = startNode;
                const partsBefore = [];
                let node = startNode;
                let limit = startOffset;

                while (node) {
                    const text = node.textContent || '';
                    let foundStart = false;
                    for (let i = limit - 1; i >= 0; i -= 1) {
                        if (this.sentenceDelimiters.includes(text[i])) {
                            partsBefore.push(text.slice(i + 1, limit));
                            foundStart = true;
                            break;
                        }
                    }

                    if (foundStart) {
                        break;
                    }

                    partsBefore.push(text.slice(0, limit));
                    node = walker.previousNode();
                    if (node) {
                        limit = node.textContent.length;
                    }
                }

                walker.currentNode = startNode;
                const partsAfter = [];
                node = startNode;
                let start = startOffset;

                while (node) {
                    const text = node.textContent || '';
                    let foundEnd = false;

                    for (let i = start; i < text.length; i += 1) {
                        if (this.sentenceDelimiters.includes(text[i])) {
                            let end = i + 1;

                            while (end < text.length) {
                                if (!trailingSentenceChars.includes(text[end])) {
                                    break;
                                }
                                end += 1;
                            }
                            partsAfter.push(text.slice(start, end));
                            foundEnd = true;
                            break;
                        }
                    }

                    if (foundEnd) {
                        break;
                    }

                    partsAfter.push(text.slice(start));

                    node = walker.nextNode();
                    start = 0;
                }

                return (partsBefore.reverse().join('') + partsAfter.join('')).trim();
            },

            getSelectionRect(x, y) {
                if (!this.selection?.ranges.length) {
                    return null;
                }

                const first = this.selection.ranges[0];
                const range = document.createRange();
                range.setStart(first.node, first.start);
                range.setEnd(first.node, Math.min(first.start + 1, first.node.textContent.length));

                const rects = Array.from(range.getClientRects());
                const rect = rects.find((entry) => x >= entry.left && x <= entry.right && y >= entry.top && y <= entry.bottom) || range.getBoundingClientRect();
                return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
            },

            rangesBetween(container, startNode, startOffset, endNode, endOffset) {
                const ranges = [];
                let node = startNode;
                let offset = startOffset;
                const walker = this.createWalker(container);

                while (node) {
                    const content = node.textContent || '';
                    const end = node === endNode ? endOffset : content.length;

                    if (end > offset) {
                        ranges.push({ node, start: offset, end });
                    }

                    if (node === endNode) {
                        break;
                    }

                    walker.currentNode = node;
                    node = walker.nextNode();
                    offset = 0;
                }

                return ranges;
            },

            rangeRect(node, start, end) {
                const range = document.createRange();
                range.setStart(node, start);
                range.setEnd(node, end);
                const rects = Array.from(range.getClientRects()).filter((rect) => rect.width > 0 && rect.height > 0);
                return rects[0] || null;
            },

            sameVisualLine(rect, reference) {
                const rectMidY = rect.top + rect.height / 2;
                const referenceMidY = reference.top + reference.height / 2;
                return Math.abs(rectMidY - referenceMidY) <= Math.max(rect.height, reference.height) * 0.65;
            },

            rangesFromVisualItems(items) {
                const ranges = [];

                for (const item of items) {
                    const last = ranges[ranges.length - 1];
                    if (last && last.node === item.node && last.end === item.offset) {
                        last.end = item.offset + 1;
                    } else {
                        ranges.push({ node: item.node, start: item.offset, end: item.offset + 1 });
                    }
                }

                return ranges;
            },

            visualLatinSelectionAt(container, hit, maxLength) {
                const walker = this.createWalker(container);
                const chars = [];
                let node;

                while ((node = walker.nextNode())) {
                    const content = node.textContent || '';
                    for (let index = 0; index < content.length; index += 1) {
                        const character = content[index];
                        if (!this.isLatinLookupChar(character)) {
                            continue;
                        }

                        const rect = this.rangeRect(node, index, index + 1);
                        if (!rect) {
                            continue;
                        }

                        chars.push({ node, offset: index, character, rect });
                    }
                }

                const hitIndex = chars.findIndex((item) => item.node === hit.node && item.offset === hit.offset);
                if (hitIndex < 0) {
                    return null;
                }

                const reference = chars[hitIndex].rect;
                const maxGap = Math.max(6, Math.min(18, reference.width * 1.4));
                let start = hitIndex;
                let end = hitIndex;

                for (let index = hitIndex - 1; index >= 0 && end - index + 1 <= maxLength; index -= 1) {
                    const current = chars[index];
                    const next = chars[index + 1];
                    if (!this.sameVisualLine(current.rect, reference)) {
                        break;
                    }

                    const gap = next.rect.left - current.rect.right;
                    if (gap > maxGap) {
                        break;
                    }

                    start = index;
                }

                for (let index = hitIndex + 1; index < chars.length && index - start + 1 <= maxLength; index += 1) {
                    const current = chars[index];
                    const previous = chars[index - 1];
                    if (!this.sameVisualLine(current.rect, reference)) {
                        break;
                    }

                    const gap = current.rect.left - previous.rect.right;
                    if (gap > maxGap) {
                        break;
                    }

                    end = index;
                }

                const selected = chars.slice(start, end + 1);
                const text = selected.map((item) => item.character).join('');
                return text ? { text, ranges: this.rangesFromVisualItems(selected) } : null;
            },

            latinSelectionAt(container, hit, maxLength) {
                const hitText = hit.node.textContent || '';
                if (!this.isLatinLookupChar(hitText[hit.offset])) {
                    return null;
                }

                let startNode = hit.node;
                let startOffset = hit.offset;
                let endNode = hit.node;
                let endOffset = hit.offset + 1;
                let before = '';
                let after = hitText[hit.offset];
                let node = hit.node;
                let offset = hit.offset - 1;
                let walker = this.createWalker(container);

                walker.currentNode = hit.node;
                while (node && before.length + after.length < maxLength) {
                    const content = node.textContent || '';
                    let reachedBoundary = false;

                    for (let i = offset; i >= 0 && before.length + after.length < maxLength; i -= 1) {
                        const character = content[i];
                        if (!this.isLatinLookupChar(character)) {
                            reachedBoundary = true;
                            break;
                        }
                        before = character + before;
                        startNode = node;
                        startOffset = i;
                    }

                    if (reachedBoundary) {
                        break;
                    }

                    node = walker.previousNode();
                    offset = node ? (node.textContent || '').length - 1 : -1;
                }

                node = hit.node;
                offset = hit.offset + 1;
                walker = this.createWalker(container);
                walker.currentNode = hit.node;
                while (node && before.length + after.length < maxLength) {
                    const content = node.textContent || '';
                    let reachedBoundary = false;

                    for (let i = offset; i < content.length && before.length + after.length < maxLength; i += 1) {
                        const character = content[i];
                        if (!this.isLatinLookupChar(character)) {
                            reachedBoundary = true;
                            break;
                        }
                        after += character;
                        endNode = node;
                        endOffset = i + 1;
                    }

                    if (reachedBoundary) {
                        break;
                    }

                    node = walker.nextNode();
                    offset = 0;
                }

                const text = (before + after).trim();
                if (!text) {
                    return null;
                }

                const selected = {
                    text,
                    ranges: this.rangesBetween(container, startNode, startOffset, endNode, endOffset)
                };

                if (text.length === 1) {
                    return this.visualLatinSelectionAt(container, hit, maxLength) || selected;
                }

                return selected;
            },

            forwardSelectionAt(container, hit, maxLength) {
                const walker = this.createWalker(container);
                let text = '';
                let node = hit.node;
                let offset = hit.offset;
                const ranges = [];

                walker.currentNode = node;
                while (text.length < maxLength && node) {
                    const content = node.textContent || '';
                    const start = offset;

                    while (offset < content.length && text.length < maxLength) {
                        const character = content[offset];
                        if (this.isScanBoundary(character)) {
                            break;
                        }
                        text += character;
                        offset += 1;
                    }

                    if (offset > start) {
                        ranges.push({ node, start, end: offset });
                    }

                    if (offset < content.length || text.length >= maxLength) {
                        break;
                    }

                    node = walker.nextNode();
                    offset = 0;
                }

                text = text.trim();
                return text ? { text, ranges } : null;
            },

            clearSelection() {
                window.getSelection()?.removeAllRanges();
                CSS.highlights?.clear();
                this.selection = null;
            },

            highlightSelection(charCount) {
                if (!this.selection?.ranges.length || !CSS.highlights) {
                    return;
                }

                const highlights = [];
                let remaining = charCount;

                for (const item of this.selection.ranges) {
                    if (remaining <= 0) {
                        break;
                    }

                    const length = item.end - item.start;
                    const end = remaining >= length ? item.end : item.start + remaining;
                    const range = document.createRange();
                    range.setStart(item.node, item.start);
                    range.setEnd(item.node, end);
                    highlights.push(range);
                    remaining -= length;
                }

                CSS.highlights.set('amgi-reader-selection', new Highlight(...highlights));
            },

            selectText(x, y, maxLength) {
                const hit = this.getCharacterAtPoint(x, y);
                if (!hit) {
                    this.clearSelection();
                    return null;
                }

                if (this.selection && hit.node === this.selection.startNode && hit.offset === this.selection.startOffset) {
                    this.clearSelection();
                    return null;
                }

                this.clearSelection();

                const container = this.findParagraph(hit.node) || document.body;
                const hitText = hit.node.textContent || '';
                const hitChar = hitText[hit.offset] || '';
                const selected = this.isLatinLookupChar(hitChar)
                    ? this.latinSelectionAt(container, hit, maxLength)
                    : this.forwardSelectionAt(container, hit, maxLength);

                if (!selected) {
                    return null;
                }

                this.selection = {
                    startNode: hit.node,
                    startOffset: hit.offset,
                    ranges: selected.ranges,
                    text: selected.text
                };

                const sentence = this.getSentence(hit.node, hit.offset);
                return {
                    text: selected.text,
                    sentence,
                    rect: this.getSelectionRect(x, y)
                };
            }
        };

        window.amgiReaderLookupPayloadAt = function(x, y) {
            return window.amgiReaderSelection.selectText(x, y, window.amgiReaderScanLength || 16);
        };

        window.amgiReaderLookupTextAt = function(x, y) {
            const result = window.amgiReaderLookupPayloadAt(x, y);
            return result ? result.text : '';
        };
    })();
    """#

    private func htmlDocument(for fragment: String) -> String {
        let textColor = textColorHex
        let linkColor = linkColorHex
        let backgroundColor = pageBackgroundHex
        let contentBackgroundColor = contentBackgroundHex
        let renderedContent = renderedFragment(for: fragment)
        let writingMode = isVertical ? "vertical-rl" : "horizontal-tb"
        let useLatinWordLayout = !isVertical && Self.prefersLatinWordLayout(languageHint: languageHint, fallbackText: fragment)
        let bodyWidthRule = isVertical ? "width: max-content; min-width: 100%;" : "max-width: 100%;"
        let wrappingRule = useLatinWordLayout
            ? "overflow-wrap: break-word; word-break: normal;"
            : "overflow-wrap: anywhere;"
        let resolvedHorizontalPadding = max(horizontalPadding, 0)
        let resolvedVerticalPadding = max(verticalPadding, 0)
        let bodyPadding = isVertical
            ? "padding: \(20 + resolvedVerticalPadding * 2)px \(20 + resolvedHorizontalPadding * 2)px \(24 + resolvedVerticalPadding * 2)px \(20 + resolvedHorizontalPadding * 2)px;"
            : "padding: \(20 + resolvedVerticalPadding * 2)px \(14 + resolvedHorizontalPadding * 2)px \(32 + resolvedVerticalPadding * 2)px \(14 + resolvedHorizontalPadding * 2)px;"
        let rubyRule = hideFurigana
            ? "ruby rt { display: none; }"
            : "ruby rt { font-size: 0.55em; color: \(hintColorHex); }"
        let letterSpacing = characterSpacing / 100
        let resolvedScanLength = max(scanLength, 1)
        let pageBreakRule = avoidPageBreak
            ? "p { break-inside: avoid; -webkit-column-break-inside: avoid; }"
            : ""
        let textAlign = justifyText && !useLatinWordLayout ? "justify" : "start"
        let hyphenRule = useLatinWordLayout ? "hyphens: auto; -webkit-hyphens: auto;" : ""

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset=\"utf-8\">
        <meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\">
        \(CardAssetPath.mediaBaseTag())
        <script>
        window.amgiReaderScanLength = \(resolvedScanLength);
        </script>
        <style>
        html, body {
            margin: 0;
            padding: 0;
            background: \(backgroundColor);
            color: \(textColor);
            \(wrappingRule)
            -webkit-text-size-adjust: 100%;
            text-size-adjust: 100%;
        }
        body {
            writing-mode: \(writingMode);
            text-orientation: mixed;
            font-family: \(fontFamily);
            font-size: \(fontSize)px;
            line-height: \(lineHeight);
            letter-spacing: \(letterSpacing)em;
            word-spacing: normal;
            text-align: \(textAlign);
            \(hyphenRule)
            \(bodyWidthRule)
            \(bodyPadding)
            box-sizing: border-box;
            background: \(contentBackgroundColor);
        }
        p {
            margin: 0 0 1em 0;
        }
        img, svg, video {
            display: block;
            max-width: 100%;
            height: auto;
        }
        audio {
            width: 100%;
        }
        a {
            color: \(linkColor);
        }
        ::highlight(amgi-reader-selection) {
            background-color: rgba(160, 160, 160, 0.4);
            color: inherit;
        }
        \(pageBreakRule)
        \(rubyRule)
        </style>
        </head>
        <body>\(renderedContent)</body>
        </html>
        """
    }

    private static func prefersLatinWordLayout(languageHint: String?, fallbackText: String) -> Bool {
        if let languageHint {
            let normalized = languageHint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasPrefix("en") || normalized == "eng" || normalized == "english" {
                return true
            }
            if normalized.hasPrefix("ja") || normalized == "jpn" || normalized == "japanese" {
                return false
            }
        }

        let plainText = fallbackText
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&[A-Za-z0-9#]+;", with: " ", options: .regularExpression)
        let latinCount = plainText.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 128 }.count
        let japaneseCount = plainText.unicodeScalars.filter {
            (0x3040...0x30FF).contains(Int($0.value)) ||
            (0x3400...0x9FFF).contains(Int($0.value))
        }.count

        return latinCount >= 40 && latinCount > japaneseCount * 2
    }

    private func renderedFragment(for fragment: String) -> String {
        if fragment.range(of: "<[A-Za-z!/][^>]*>", options: .regularExpression) != nil {
            return fragment
        }

        let escaped = fragment
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")

        return escaped
            .components(separatedBy: "\n\n")
            .map { paragraph in
                let lineBreakPreserved = paragraph.replacingOccurrences(of: "\n", with: "<br>")
                return "<p>\(lineBreakPreserved)</p>"
            }
            .joined()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ReaderChapterWebView?
        var lastHTML = ""
        var pendingProgress: Double
        var lastSelectionRequestID = 0
        var lastClearLookupHighlightRequestID = 0
        var lastLookupHighlightLengthRequestID = 0
        private var didRestoreInitialProgress = false
        private var isRestoringProgress = false
        private var restoreGeneration = 0
        private let onProgressChange: (Double) -> Void
        let onSelectionResolved: (String?) -> Void
        let onLookupRequested: (String?, String?, CGPoint, CGRect?) -> Void

        init(
            savedProgress: Double,
            onProgressChange: @escaping (Double) -> Void,
            onSelectionResolved: @escaping (String?) -> Void,
            onLookupRequested: @escaping (String?, String?, CGPoint, CGRect?) -> Void
        ) {
            self.pendingProgress = savedProgress
            self.onProgressChange = onProgressChange
            self.onSelectionResolved = onSelectionResolved
            self.onLookupRequested = onLookupRequested
        }

        @objc func handleTapLookup(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  parent?.tapLookupEnabled == true,
                  let webView = recognizer.view as? WKWebView else {
                return
            }

            let point = recognizer.location(in: webView)
            let script = "window.amgiReaderLookupPayloadAt ? window.amgiReaderLookupPayloadAt(\(point.x), \(point.y)) : null"
            webView.evaluateJavaScript(script) { [onLookupRequested] value, _ in
                if let payload = value as? [String: Any] {
                    onLookupRequested(
                        payload["text"] as? String,
                        payload["sentence"] as? String,
                        point,
                        Self.lookupRect(from: payload["rect"])
                    )
                } else {
                    onLookupRequested(nil, nil, point, nil)
                }
            }
        }

        private static func lookupRect(from value: Any?) -> CGRect? {
            guard let rectData = value as? [String: Any],
                  let x = cgFloatValue(rectData["x"]),
                  let y = cgFloatValue(rectData["y"]),
                  let width = cgFloatValue(rectData["width"]),
                  let height = cgFloatValue(rectData["height"]) else {
                return nil
            }
            return CGRect(x: x, y: y, width: width, height: height)
        }

        private static func cgFloatValue(_ value: Any?) -> CGFloat? {
            if let value = value as? CGFloat {
                return value
            }
            if let value = value as? Double {
                return CGFloat(value)
            }
            if let value = value as? NSNumber {
                return CGFloat(truncating: value)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            restoreGeneration += 1
            restoreProgress(in: webView.scrollView, remainingAttempts: 40, generation: restoreGeneration)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportProgress(for: scrollView)
        }

        private func restoreProgress(
            in scrollView: UIScrollView,
            remainingAttempts: Int,
            generation: Int
        ) {
            guard generation == restoreGeneration else {
                return
            }

            let clampedProgress = min(max(pendingProgress, 0), 1)
            let maxOffset = maximumOffset(for: scrollView)

            if clampedProgress > 0,
               maxOffset <= 0,
               remainingAttempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak scrollView] in
                    guard let self, let scrollView else {
                        return
                    }
                    self.restoreProgress(
                        in: scrollView,
                        remainingAttempts: remainingAttempts - 1,
                        generation: generation
                    )
                }
                return
            }

            if clampedProgress > 0,
               maxOffset <= 0 {
                // Content size is still not ready; do not overwrite persisted progress to 0.
                didRestoreInitialProgress = true
                isRestoringProgress = false
                return
            }

            let targetOffset: CGPoint

            if parent?.isVertical == true {
                targetOffset = CGPoint(x: maxOffset * clampedProgress, y: 0)
            } else {
                targetOffset = CGPoint(x: 0, y: maxOffset * clampedProgress)
            }

            didRestoreInitialProgress = false
            isRestoringProgress = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView, generation == self.restoreGeneration else {
                    return
                }
                scrollView.setContentOffset(targetOffset, animated: false)
                self.isRestoringProgress = false
                self.didRestoreInitialProgress = true
                if maxOffset > 0 {
                    self.onProgressChange(clampedProgress)
                } else {
                    self.reportProgress(for: scrollView)
                }
            }
        }

        private func maximumOffset(for scrollView: UIScrollView) -> CGFloat {
            scrollView.layoutIfNeeded()
            if parent?.isVertical == true {
                return max(scrollView.contentSize.width - scrollView.bounds.width, 0)
            }
            return max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        }

        private func reportProgress(for scrollView: UIScrollView) {
            guard didRestoreInitialProgress, isRestoringProgress == false else {
                return
            }

            let progress: Double
            if parent?.isVertical == true {
                let maxOffset = max(scrollView.contentSize.width - scrollView.bounds.width, 1)
                progress = Double(scrollView.contentOffset.x / maxOffset)
            } else {
                let maxOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 1)
                progress = Double(scrollView.contentOffset.y / maxOffset)
            }
            onProgressChange(min(max(progress, 0), 1))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct ReaderLookupSection: Identifiable {
    let index: Int
    let heading: String
    let dictionaryName: String?
    let term: String
    let reading: String?
    let definitions: [String]
    let pitch: String?

    var id: String {
        "\(index)-\(heading)-\(term)-\(dictionaryName ?? "")"
    }

    init(index: Int, entry: DictionaryLookupEntry) {
        self.index = index
        heading = L("reader_lookup_definition_section", index)
        let parsed = Self.parseGlossaries(entry.glossaries)
        dictionaryName = parsed.dictionaryName ?? entry.source?.nilIfBlank
        term = entry.term
        reading = entry.reading?.nilIfBlank
        definitions = parsed.definitions
        pitch = entry.pitch?.nilIfBlank
    }

    init(
        index: Int,
        dictionaryName: String?,
        term: String,
        reading: String?,
        definitions: [String],
        pitch: String?
    ) {
        self.index = index
        self.heading = L("reader_lookup_definition_section", index)
        self.dictionaryName = dictionaryName
        self.term = term
        self.reading = reading?.nilIfBlank
        self.definitions = definitions.filter { $0.nilIfBlank != nil }
        self.pitch = pitch?.nilIfBlank
    }

    static func sections(startingAt startIndex: Int, entry: DictionaryLookupEntry) -> [ReaderLookupSection] {
        let groupedGlossaries = groupedGlossaries(from: entry)
        guard groupedGlossaries.isEmpty == false else {
            return [ReaderLookupSection(index: startIndex, entry: entry)]
        }

        return groupedGlossaries.enumerated().map { offset, group in
            ReaderLookupSection(
                index: startIndex + offset,
                dictionaryName: group.dictionaryName ?? entry.source?.nilIfBlank,
                term: entry.term,
                reading: entry.reading,
                definitions: group.definitions,
                pitch: pitchText(for: entry, preferredDictionary: group.dictionaryName)
            )
        }
    }

    private static func groupedGlossaries(from entry: DictionaryLookupEntry) -> [(dictionaryName: String?, definitions: [String])] {
        guard entry.structuredGlossaries.isEmpty == false else {
            return []
        }

        var groups: [(dictionaryName: String?, definitions: [String])] = []
        for glossary in entry.structuredGlossaries {
            let dictionaryName = glossary.dictionary.nilIfBlank
            let definitions = glossary.definitions.filter { $0.nilIfBlank != nil }
            guard definitions.isEmpty == false else {
                continue
            }

            if let existingIndex = groups.firstIndex(where: { $0.dictionaryName == dictionaryName }) {
                groups[existingIndex].definitions.append(contentsOf: definitions)
            } else {
                groups.append((dictionaryName, definitions))
            }
        }
        return groups
    }

    private static func pitchText(for entry: DictionaryLookupEntry, preferredDictionary: String?) -> String? {
        guard entry.structuredPitches.isEmpty == false else {
            return entry.pitch?.nilIfBlank
        }

        let matchedPitches = entry.structuredPitches.filter { pitch in
            preferredDictionary == nil || pitch.dictionary.nilIfBlank == preferredDictionary
        }
        let source = matchedPitches.isEmpty ? entry.structuredPitches : matchedPitches
        let rendered = source.compactMap { pitch -> String? in
            guard pitch.positions.isEmpty == false else {
                return nil
            }
            let positions = pitch.positions.map(String.init).joined(separator: ", ")
            guard positions.isEmpty == false else {
                return nil
            }
            if let dictionaryName = pitch.dictionary.nilIfBlank {
                return "\(dictionaryName): \(positions)"
            }
            return positions
        }
        .joined(separator: "  ")

        return rendered.nilIfBlank ?? entry.pitch?.nilIfBlank
    }

    private static func parseGlossaries(_ glossaries: [String]) -> (dictionaryName: String?, definitions: [String]) {
        guard let first = glossaries.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              let separator = first.firstIndex(of: ":") else {
            return (nil, glossaries.filter { $0.nilIfBlank != nil })
        }

        let name = String(first[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let firstDefinition = String(first[first.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = glossaries.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let combined = ([firstDefinition] + rest).filter { !$0.isEmpty }
        return (name.nilIfBlank, combined)
    }
}

private struct ReaderLookupSectionView: View {
    let section: ReaderLookupSection
    let dictionaryFontSize: CGFloat
    let termFontSize: CGFloat
    let readingFontSize: CGFloat
    let definitionFontSize: CGFloat
    let pitchFontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dictionaryName = section.dictionaryName {
                Text(dictionaryName)
                    .font(.system(size: dictionaryFontSize, weight: .medium))
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.term)
                    .font(.system(size: termFontSize, weight: .bold))
                    .foregroundStyle(Color.amgiTextPrimary)
                if let reading = section.reading {
                    Text(reading)
                        .font(.system(size: readingFontSize))
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.definitions, id: \.self) { definition in
                    Text(definition)
                        .font(.system(size: definitionFontSize))
                        .foregroundStyle(Color.amgiTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let pitch = section.pitch {
                Text(pitch)
                    .font(.system(size: pitchFontSize))
                    .foregroundStyle(Color.amgiTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReaderLookupBadge: Identifiable {
    let name: String
    let value: String

    var id: String {
        "\(name)-\(value)"
    }

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if let separator = trimmed.firstIndex(of: ":") {
            let name = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.isEmpty == false, value.isEmpty == false else {
                return nil
            }
            self.name = name
            self.value = value
        } else {
            self.name = trimmed
            self.value = ""
        }
    }
}

private struct ReaderLookupFrequencyBadge: View {
    let badge: ReaderLookupBadge
    let fontSize: CGFloat

    private var horizontalPadding: CGFloat {
        max(6, fontSize * 0.62)
    }

    private var verticalPadding: CGFloat {
        max(3, fontSize * 0.24)
    }

    private var cornerRadius: CGFloat {
        max(6, fontSize * 0.65)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(badge.name)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Color.amgiAccent)

            if badge.value.isEmpty == false {
                Text(badge.value)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(Color.amgiTextPrimary)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background(Color(.systemBackground).opacity(0.9))
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.amgiAccent.opacity(0.45), lineWidth: 1)
        }
    }
}

@MainActor
private final class ReaderLookupSpeechPlayer {
    static let shared = ReaderLookupSpeechPlayer()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    static func normalizedLanguageHint(_ languageHint: String?, fallbackText: String) -> String? {
        if let trimmedHint = languageHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), trimmedHint.isEmpty == false {
            switch trimmedHint {
            case "ja", "ja-jp":
                return "ja-JP"
            case "zh", "zh-cn", "zh-hans":
                return "zh-CN"
            case "en", "en-us":
                return "en-US"
            default:
                return languageHint
            }
        }

        if fallbackText.containsJapaneseScript {
            return "ja-JP"
        }
        return nil
    }

    func speak(_ text: String, languageHint: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        if let languageHint = Self.normalizedLanguageHint(languageHint, fallbackText: trimmed),
           let voice = AVSpeechSynthesisVoice(language: languageHint) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        switch self?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case let value? where value.isEmpty == false:
            return value
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var containsJapaneseScript: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0x4E00...0x9FFF:
                return true
            default:
                return false
            }
        }
    }
}

private extension Color {
    init(readerHex: String, fallback: Color) {
        let sanitized = readerHex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard sanitized.count == 6,
              let value = Int(sanitized, radix: 16) else {
            self = fallback
            return
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}
