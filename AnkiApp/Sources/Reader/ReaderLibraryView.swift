import SwiftUI
import WebKit
import AVFAudio
import AnkiKit
import AnkiReader
import AnkiClients
import Dependencies

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

    fileprivate static let bookCardWidth: CGFloat = 100
    fileprivate static let bookCoverHeight: CGFloat = 136
    fileprivate static let bookGridSpacing: CGFloat = 12

    @AppStorage(ReaderPreferences.Keys.deckID) private var selectedDeckID = 0
    @AppStorage(ReaderPreferences.Keys.notetypeID) private var selectedNotetypeID = 0
    @AppStorage(ReaderPreferences.Keys.bookIDField) private var bookIDField = ""
    @AppStorage(ReaderPreferences.Keys.bookTitleField) private var bookTitleField = ""
    @AppStorage(ReaderPreferences.Keys.chapterTitleField) private var chapterTitleField = ""
    @AppStorage(ReaderPreferences.Keys.chapterOrderField) private var chapterOrderField = ""
    @AppStorage(ReaderPreferences.Keys.contentField) private var contentField = ""
    @AppStorage(ReaderPreferences.Keys.languageField) private var languageField = ""
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

    private var configurationSignature: String {
        [
            String(selectedDeckID),
            String(selectedNotetypeID),
            bookIDField,
            bookTitleField,
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
                .fixed(Self.bookCardWidth),
                spacing: Self.bookGridSpacing,
                alignment: .top
            ),
            count: 3
        )
    }

    private var gridContentWidth: CGFloat {
        Self.bookCardWidth * 3 + Self.bookGridSpacing * 2
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

                        LazyVGrid(columns: bookGridColumns, alignment: .center, spacing: Self.bookGridSpacing) {
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
                        .frame(width: gridContentWidth)
                        .frame(maxWidth: .infinity)
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

            ToolbarItem(placement: .topBarTrailing) {
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.amgiAccent.opacity(0.18), Color.amgiSurfaceElevated],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: ReaderLibraryView.bookCardWidth, height: ReaderLibraryView.bookCoverHeight)
                .overlay {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Color.amgiAccent)
                }
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
        .frame(width: ReaderLibraryView.bookCardWidth)
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
    private var resolvedListBackground: Color {
        switch themeMode {
        case .system:
            return colorScheme == .dark ? Color(red: 0.09, green: 0.11, blue: 0.15) : Color(red: 1.0, green: 0.99, blue: 0.97)
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
        List {
            if let resumeChapter {
                Section {
                    NavigationLink {
                        ReaderChapterView(book: book, chapter: resumeChapter)
                    } label: {
                        Label(L("reader_book_continue"), systemImage: "book.fill")
                            .foregroundStyle(Color.amgiTextPrimary)
                    }
                }
                .listRowBackground(resolvedListBackground)
            }

            Section(L("reader_book_chapters", book.chapters.count)) {
                ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                    NavigationLink {
                        ReaderChapterView(book: book, chapter: chapter)
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
                                if let order = chapter.order {
                                    Text(order)
                                        .font(.caption)
                                        .foregroundStyle(Color.amgiTextSecondary)
                                }
                            }
                        }
                    }
                    .listRowBackground(resolvedListBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
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
    @AppStorage(ReaderPreferences.Keys.fontSize) private var readerFontSize = 24
    @AppStorage(ReaderPreferences.Keys.hideFurigana) private var hideFurigana = false
    @AppStorage(ReaderPreferences.Keys.horizontalPadding) private var horizontalPadding = 5
    @AppStorage(ReaderPreferences.Keys.verticalPadding) private var verticalPadding = 0
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
    @State private var showLookupSheet = false
    @State private var lookupQuery = ""
    @State private var lookupSentence: String?
    @State private var lookupResult: DictionaryLookupResult?
    @State private var isLookingUp = false
    @State private var lookupErrorMessage: String?
    @State private var lookupAnchor: CGPoint?
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

    private var resolvedPageBackgroundHex: String {
        switch themeMode {
        case .system:
            return colorScheme == .dark ? "#0F141C" : "#FFFDF8"
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
            return colorScheme == .dark ? "#0F141C" : "#FFFDF8"
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
            return colorScheme == .dark ? "#F2F4F8" : "#17212F"
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
            return "#7F7F7F"
        case .eyeCare:
            return "#64715D"
        case .sepia:
            return "#7A6852"
        case .custom:
            return Self.normalizedHexColor(customHintColorHex, fallback: "#7F7F7F")
        }
    }

    private var chapterContentBackground: Color {
        Color(readerHex: resolvedContentBackgroundHex, fallback: .amgiBackground)
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
            let topSafeArea = max(geometry.safeAreaInsets.top, 44)
            let showsTopInfo = showTitle || showProgressTop
            let topOverlayHeight = topSafeArea + (showsTopInfo ? 60 : 18)
            let bottomInset = max(geometry.safeAreaInsets.bottom - 8, 14)

            VStack(spacing: 0) {
                Color.amgiBackground
                    .frame(height: topOverlayHeight)

                ZStack(alignment: .bottom) {
                    ReaderChapterWebView(
                        html: chapter.content,
                        isVertical: verticalLayout,
                        fontSize: Double(readerFontSize),
                        pageBackgroundHex: resolvedPageBackgroundHex,
                        contentBackgroundHex: resolvedContentBackgroundHex,
                        textColorHex: resolvedTextColorHex,
                        hintColorHex: resolvedHintColorHex,
                        hideFurigana: hideFurigana,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        lineHeight: lineHeight,
                        characterSpacing: characterSpacing,
                        scanLength: dictionaryScanLength,
                        savedProgress: savedProgress,
                        selectionRequestID: selectionRequestID,
                        tapLookupEnabled: tapLookupEnabled,
                        onProgressChange: { newProgress in
                            progress = newProgress
                            ReaderProgressStore.save(bookID: book.id, chapterID: chapter.id, progress: newProgress)
                        },
                        onSelectionResolved: { selection in
                            handleResolvedSelection(selection)
                        },
                        onLookupRequested: { selection, sentence, point in
                            handleTapLookup(selection, sentence: sentence, at: point)
                        }
                    )
                    .background(Color.amgiBackground)
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
                    .padding(.bottom, bottomInset * 1.5)
                }
            }
            .background(Color.amgiBackground)
            .overlay(alignment: .top) {
                ReaderChapterInfoOverlay(
                    title: showTitle ? book.title : nil,
                    progressLabel: showProgressTop ? progressLabel : nil
                )
                    .background(chapterContentBackground)
                    .padding(.top, topSafeArea + 4)
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
                .padding(.top, topSafeArea + 14)
                .padding(.trailing, 20)
            }
            .overlay {
                if showLookupSheet {
                    GeometryReader { popupGeometry in
                        ZStack {
                            Color.black.opacity(0.001)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    showLookupSheet = false
                                    lookupAnchor = nil
                                }

                            ReaderLookupPopup(
                                query: lookupQuery,
                                result: lookupResult,
                                isLoading: isLookingUp,
                                languageHint: lookupLanguageHint,
                                popupWidth: CGFloat(popupWidth),
                                popupHeight: CGFloat(popupHeight),
                                popupHeaderFontSize: CGFloat(popupFontSize),
                                popupFrequencyFontSize: CGFloat(popupFrequencyFontSize),
                                popupContentFontSize: CGFloat(popupContentFontSize),
                                popupDictionaryNameFontSize: CGFloat(popupDictionaryNameFontSize),
                                popupKanaFontSize: CGFloat(popupKanaFontSize),
                                isFullWidth: popupFullWidth,
                                swipeToDismiss: popupSwipeToDismiss,
                                onAddNote: { payload in
                                    pendingDraft = makeLookupDraft(from: payload)
                                    showLookupSheet = false
                                    lookupAnchor = nil
                                    showAddNoteSheet = true
                                },
                                onClose: {
                                    showLookupSheet = false
                                    lookupAnchor = nil
                                }
                            )
                            .frame(maxWidth: popupFullWidth ? .infinity : CGFloat(popupWidth))
                            .padding(.horizontal, 14)
                            .position(lookupPopupPosition(in: popupGeometry.size, bottomInset: bottomInset))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .background(Color.amgiBackground)
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
        }
        .navigationDestination(item: $chapterNavigationTarget) { target in
            ReaderChapterView(book: book, chapter: target)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: showLookupSheet)
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

    private func handleTapLookup(_ selection: String?, sentence: String?, at point: CGPoint) {
        guard let tappedSelection = normalizedSelection(selection) else {
            return
        }
        pendingSelectionAction = nil
        startLookup(for: tappedSelection, sentence: sentence, anchor: point)
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

    private func startLookup(for query: String, sentence: String? = nil, anchor: CGPoint? = nil) {
        lookupQuery = query
        lookupSentence = normalizedSentence(sentence)
        lookupResult = nil
        lookupAnchor = anchor
        showLookupSheet = true
        isLookingUp = true
        Task {
            do {
                lookupResult = try await dictionaryLookupClient.lookup(
                    query,
                    dictionaryMaxResults,
                    dictionaryScanLength
                )
            } catch {
                showLookupSheet = false
                lookupAnchor = nil
                lookupErrorMessage = error.localizedDescription
                showSelectionError = true
            }
            isLookingUp = false
        }
    }

    private func lookupPopupPosition(in size: CGSize, bottomInset: CGFloat) -> CGPoint {
        let horizontalMargin: CGFloat = 18
        let popupResolvedWidth = popupFullWidth
            ? max(size.width - horizontalMargin * 2, 0)
            : min(CGFloat(popupWidth), max(size.width - horizontalMargin * 2, 0))
        let popupHalfWidth = popupResolvedWidth / 2
        let popupHalfHeight = min(CGFloat(popupHeight) / 2, max(size.height / 2 - 56, 132))

        guard popupFullWidth == false, let lookupAnchor else {
            return CGPoint(
                x: size.width / 2,
                y: size.height - bottomInset - popupHalfHeight - 48
            )
        }

        let proposedBottomY = lookupAnchor.y + popupHalfHeight + 26
        let fallbackTopY = lookupAnchor.y - popupHalfHeight - 26
        let minY = 136 + popupHalfHeight
        let maxY = size.height - bottomInset - popupHalfHeight - 20
        let resolvedY = proposedBottomY <= maxY ? proposedBottomY : max(fallbackTopY, minY)
        let resolvedX = min(
            max(lookupAnchor.x, popupHalfWidth + horizontalMargin),
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

    private func makeLookupDraft(from payload: ReaderLookupNotePayload) -> AddNoteDraft {
        let sourceDescription = [book.title, chapter.title]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
        var resolvedPayload = payload
        resolvedPayload.sentence = normalizedSentence(payload.sentence) ?? lookupSentence

        return lookupNoteTemplate.makeDraft(
            payload: resolvedPayload,
            fallbackDeckID: selectedDeckID == 0 ? nil : Int64(selectedDeckID),
            sourceDescription: sourceDescription
        )
    }
}

private struct ReaderLookupPopup: View {
    let query: String
    let result: DictionaryLookupResult?
    let isLoading: Bool
    let languageHint: String?
    let popupWidth: CGFloat
    let popupHeight: CGFloat
    let popupHeaderFontSize: CGFloat
    let popupFrequencyFontSize: CGFloat
    let popupContentFontSize: CGFloat
    let popupDictionaryNameFontSize: CGFloat
    let popupKanaFontSize: CGFloat
    let isFullWidth: Bool
    let swipeToDismiss: Bool
    let onAddNote: (ReaderLookupNotePayload) -> Void
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var sections: [ReaderLookupSection] {
        guard let result else {
            return []
        }

        return result.entries.enumerated().map { index, entry in
            ReaderLookupSection(index: index + 1, entry: entry)
        }
    }

    private var primaryEntry: DictionaryLookupEntry? {
        result?.entries.first
    }

    private var matchedQueryText: String? {
        primaryEntry?.source?
            .components(separatedBy: "•")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    private var displayedQueryText: String {
        matchedQueryText
            ?? primaryEntry?.term.nilIfBlank
            ?? query
    }

    private var readingText: String? {
        primaryEntry?.reading?.nilIfBlank
    }

    private var noteDefinitions: [String] {
        sections.flatMap(\.definitions)
    }

    private var notePayload: ReaderLookupNotePayload {
        ReaderLookupNotePayload(
            term: displayedQueryText,
            reading: readingText,
            sentence: nil,
            definitions: noteDefinitions
        )
    }

    private var frequencyBadges: [ReaderLookupBadge] {
        guard let frequency = primaryEntry?.frequency else {
            return []
        }

        return frequency
            .components(separatedBy: "  ")
            .compactMap(ReaderLookupBadge.init(rawValue:))
    }

    private var preferredSpeechLanguage: String? {
        ReaderLookupSpeechPlayer.normalizedLanguageHint(languageHint, fallbackText: readingText ?? displayedQueryText)
    }

    private var headerScale: CGFloat {
        max(0.6, popupHeaderFontSize / 14)
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

    private var kanaScale: CGFloat {
        max(0.6, popupKanaFontSize / 14)
    }

    private var headerWordFont: CGFloat { 14 * headerScale }
    private var headerReadingFont: CGFloat { 7 * kanaScale }
    private var buttonIconFont: CGFloat { 14 * headerScale }
    private var loadingFont: CGFloat { 13 * contentScale }
    private var emptyFont: CGFloat { 13 * contentScale }
    private var sectionDictionaryFont: CGFloat { 13 * dictionaryNameScale }
    private var sectionTermFont: CGFloat { 22 * contentScale }
    private var sectionReadingFont: CGFloat { 14 * kanaScale }
    private var sectionDefinitionFont: CGFloat { 14 * contentScale }
    private var sectionPitchFont: CGFloat { 12 * contentScale }
    private var badgeFont: CGFloat { 13 * frequencyScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if let readingText {
                        Text(readingText)
                            .font(.system(size: headerReadingFont, weight: .medium))
                            .foregroundStyle(Color.amgiTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(displayedQueryText)
                        .font(.system(size: headerWordFont, weight: .bold))
                        .foregroundStyle(Color.amgiTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button {
                        ReaderLookupSpeechPlayer.shared.speak(displayedQueryText, languageHint: preferredSpeechLanguage)
                    } label: {
                        Image(systemName: "speaker.wave.2")
                            .font(.system(size: buttonIconFont, weight: .medium))
                            .foregroundStyle(Color.amgiTextSecondary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onAddNote(notePayload)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: buttonIconFont, weight: .medium))
                            .foregroundStyle(Color.amgiTextSecondary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if frequencyBadges.isEmpty == false {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(frequencyBadges) { badge in
                                    ReaderLookupFrequencyBadge(badge: badge, fontSize: badgeFont)
                                }
                            }
                        }
                    }

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
                                .font(.system(size: sectionPitchFont))
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                    } else if sections.isEmpty == false {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            if index > 0 {
                                Divider()
                                    .overlay(Color.amgiBorder.opacity(0.32))
                            }
                            ReaderLookupSectionView(
                                section: section,
                                dictionaryFontSize: sectionDictionaryFont,
                                termFontSize: sectionTermFont,
                                readingFontSize: sectionReadingFont,
                                definitionFontSize: sectionDefinitionFont,
                                pitchFontSize: sectionPitchFont
                            )
                        }
                    } else {
                        Text(L("reader_lookup_empty"))
                            .font(.system(size: emptyFont))
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: max(140, popupHeight - 94))
        }
        .padding(18)
        .frame(maxWidth: isFullWidth ? .infinity : popupWidth, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.amgiBorder.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)
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

    var body: some View {
        VStack(spacing: 6) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(Color.amgiTextSecondary)
                    .lineLimit(1)
            }

            if let progressLabel, !progressLabel.isEmpty {
                Text(progressLabel)
                    .font(.subheadline)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .monospacedDigit()
                    .tracking(-0.3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 112)
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

private struct ReaderChapterWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let html: String
    let isVertical: Bool
    let fontSize: Double
    let pageBackgroundHex: String
    let contentBackgroundHex: String
    let textColorHex: String
    let hintColorHex: String
    let hideFurigana: Bool
    let horizontalPadding: Int
    let verticalPadding: Int
    let lineHeight: Double
    let characterSpacing: Double
    let scanLength: Int
    let savedProgress: Double
    let selectionRequestID: Int
    let tapLookupEnabled: Bool
    let onProgressChange: (Double) -> Void
    let onSelectionResolved: (String?) -> Void
    let onLookupRequested: (String?, String?, CGPoint) -> Void

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
            sentenceDelimiters: '。！？!?…‥\n\r',

            isWordDelimiter(char) {
                return /[^\w\p{L}\p{N}]/u.test(char);
            },

            isJapaneseLike(char) {
                return /[\u3040-\u30FF\u31F0-\u31FF\u4E00-\u9FFF\u3400-\u4DBF\u30FC]/u.test(char);
            },

            isScanBoundary(char) {
                return /^[\s\u3000]$/.test(char) || this.scanDelimiters.includes(char) || this.isWordDelimiter(char);
            },

            isFurigana(node) {
                const element = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
                return !!element?.closest('rt, rp');
            },

            findParagraph(node) {
                const element = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
                return element?.closest('p, li, blockquote, h1, h2, h3, h4, h5, h6, div') || document.body;
            },

            createWalker(rootNode) {
                const root = rootNode || document.body;
                return document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                    acceptNode: (node) => this.isFurigana(node) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
                });
            },

            buildTextIndex(rootNode) {
                const walker = this.createWalker(rootNode);
                const segments = [];
                let text = '';
                let node;

                while ((node = walker.nextNode())) {
                    const content = node.textContent || '';
                    if (!content) {
                        continue;
                    }

                    const start = text.length;
                    text += content;
                    segments.push({ node, start, end: text.length });
                }

                return { text, segments };
            },

            absoluteOffsetForNode(segments, targetNode, targetOffset) {
                const segment = segments.find((entry) => entry.node === targetNode);
                if (!segment) {
                    return null;
                }

                const clampedOffset = Math.min(
                    Math.max(targetOffset, 0),
                    segment.end - segment.start
                );
                return segment.start + clampedOffset;
            },

            extractSentence(container, startNode, startOffset, selectedText) {
                const index = this.buildTextIndex(container);
                const fullText = index.text;
                if (!fullText) {
                    return '';
                }

                const absoluteStart = this.absoluteOffsetForNode(index.segments, startNode, startOffset);
                if (absoluteStart === null) {
                    return fullText.trim();
                }

                let sentenceStart = absoluteStart;
                while (
                    sentenceStart > 0 &&
                    !this.sentenceDelimiters.includes(fullText[sentenceStart - 1])
                ) {
                    sentenceStart -= 1;
                }

                let sentenceEnd = absoluteStart + Math.max(selectedText.length, 1);
                while (
                    sentenceEnd < fullText.length &&
                    !this.sentenceDelimiters.includes(fullText[sentenceEnd])
                ) {
                    sentenceEnd += 1;
                }

                if (sentenceEnd < fullText.length) {
                    sentenceEnd += 1;
                }

                return fullText.slice(sentenceStart, sentenceEnd).trim();
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
                    const position = document.caretPositionFromPoint(x, y);
                    if (!position) {
                        return null;
                    }

                    const range = document.createRange();
                    range.setStart(position.offsetNode, position.offset);
                    range.collapse(true);
                    return range;
                }

                const element = document.elementFromPoint(x, y);
                if (!element) {
                    return null;
                }

                const container = element.closest('p, div, span, ruby, a, li, blockquote') || document.body;
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
                const element = document.elementFromPoint(x, y);
                if (element && element.closest('a, button, input, textarea, select, audio, video')) {
                    return null;
                }

                const range = this.getCaretRange(x, y);
                if (!range) {
                    return null;
                }

                const node = range.startContainer;
                if (node.nodeType !== Node.TEXT_NODE || this.isFurigana(node)) {
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

            clearSelection() {
                window.getSelection()?.removeAllRanges();
                this.selection = null;
            },

            expandStartOffset(hit) {
                const initialContent = hit.node.textContent || '';
                const initialChar = initialContent[hit.offset] || '';
                if (this.isJapaneseLike(initialChar)) {
                    return { node: hit.node, offset: hit.offset };
                }

                const container = this.findParagraph(hit.node) || document.body;
                const walker = this.createWalker(container);
                let node = hit.node;
                let offset = hit.offset;

                walker.currentNode = node;

                while (node) {
                    const content = node.textContent || '';

                    while (offset > 0) {
                        const previousChar = content[offset - 1];
                        if (this.isScanBoundary(previousChar)) {
                            return { node, offset };
                        }
                        offset -= 1;
                    }

                    const previousNode = walker.previousNode();
                    if (!previousNode) {
                        break;
                    }

                    node = previousNode;
                    offset = (node.textContent || '').length;
                }

                return { node: hit.node, offset: 0 };
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
                const walker = this.createWalker(container);
                let text = '';
                const start = this.expandStartOffset(hit);
                let node = start.node;
                let offset = start.offset;
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

                if (!text) {
                    return null;
                }

                this.selection = {
                    startNode: hit.node,
                    startOffset: hit.offset,
                    ranges,
                    text,
                    sentence: this.extractSentence(container, hit.node, hit.offset, text)
                };

                return {
                    text,
                    sentence: this.selection.sentence,
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
        let linkColor = colorScheme == .dark ? "#8FB8FF" : "#1E5BB8"
        let backgroundColor = pageBackgroundHex
        let contentBackgroundColor = contentBackgroundHex
        let renderedContent = renderedFragment(for: fragment)
        let writingMode = isVertical ? "vertical-rl" : "horizontal-tb"
        let bodyWidthRule = isVertical ? "width: max-content; min-width: 100%;" : "max-width: 100%;"
        let resolvedHorizontalPadding = max(horizontalPadding, 0)
        let resolvedVerticalPadding = max(verticalPadding, 0)
        let bodyPadding = isVertical
            ? "padding: \(24 + resolvedVerticalPadding * 2)px \(28 + resolvedHorizontalPadding * 2)px \(28 + resolvedVerticalPadding * 2)px \(28 + resolvedHorizontalPadding * 2)px;"
            : "padding: \(24 + resolvedVerticalPadding * 2)px \(20 + resolvedHorizontalPadding * 2)px \(40 + resolvedVerticalPadding * 2)px \(20 + resolvedHorizontalPadding * 2)px;"
        let rubyRule = hideFurigana
            ? "ruby rt { display: none; }"
            : "ruby rt { font-size: 0.55em; color: \(hintColorHex); }"
        let letterSpacing = characterSpacing / 100
        let resolvedScanLength = max(scanLength, 1)

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
            overflow-wrap: anywhere;
        }
        body {
            writing-mode: \(writingMode);
            text-orientation: mixed;
            font-family: -apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif;
            font-size: \(fontSize)px;
            line-height: \(lineHeight);
            letter-spacing: \(letterSpacing)em;
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
        \(rubyRule)
        </style>
        </head>
        <body>\(renderedContent)</body>
        </html>
        """
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
        private var didRestoreInitialProgress = false
        private var isRestoringProgress = false
        private var restoreGeneration = 0
        private let onProgressChange: (Double) -> Void
        let onSelectionResolved: (String?) -> Void
        let onLookupRequested: (String?, String?, CGPoint) -> Void

        init(
            savedProgress: Double,
            onProgressChange: @escaping (Double) -> Void,
            onSelectionResolved: @escaping (String?) -> Void,
            onLookupRequested: @escaping (String?, String?, CGPoint) -> Void
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
                    onLookupRequested(payload["text"] as? String, payload["sentence"] as? String, point)
                } else {
                    onLookupRequested(nil, nil, point)
                }
            }
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

    var body: some View {
        HStack(spacing: 0) {
            Text(badge.name)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.amgiAccent)

            if badge.value.isEmpty == false {
                Text(badge.value)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(Color.amgiTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground).opacity(0.9))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
