import SwiftUI
import WebKit
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
        [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 16, alignment: .top)]
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

                        LazyVGrid(columns: bookGridColumns, alignment: .leading, spacing: 16) {
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
                    Label(L("reader_library_sort_menu"), systemImage: "arrow.up.arrow.down.circle")
                }

                Button {
                    if isSelecting {
                        clearSelection()
                    } else {
                        isSelecting = true
                    }
                } label: {
                    Text(isSelecting ? L("common_done") : L("reader_library_multi_select"))
                }
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

    private var previewText: String {
        let content = book.chapters.first?.content ?? ""
        let withoutTags = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return withoutTags
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.amgiAccent.opacity(0.22), Color.amgiSurfaceElevated],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 96)
                    .overlay {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.amgiAccent)
                    }

                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.amgiTextPrimary)
                        .multilineTextAlignment(.leading)
                    Text(L("reader_book_chapters", book.chapters.count))
                        .font(.subheadline)
                        .foregroundStyle(Color.amgiTextSecondary)
                    if !previewText.isEmpty {
                        Text(previewText)
                            .font(.footnote)
                            .foregroundStyle(Color.amgiTextSecondary)
                            .lineLimit(4)
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progressValue)
                    .tint(Color.amgiAccent)
                Text(L("reader_book_progress", progressValue * 100))
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .monospacedDigit()
            }
        }
        .padding(18)
        .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.amgiBorder.opacity(0.22), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.amgiAccent : Color.amgiTextSecondary)
                    .padding(12)
            }
        }
    }
}

private struct ReaderBookDetailView: View {
    let book: ReaderBook

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
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
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
    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient

    @AppStorage(ReaderPreferences.Keys.deckID) private var selectedDeckID = 0
    @AppStorage(ReaderPreferences.Keys.verticalLayout) private var verticalLayout = false
    @AppStorage(ReaderPreferences.Keys.fontSize) private var readerFontSize = 24
    @AppStorage(ReaderPreferences.Keys.tapLookup) private var tapLookupEnabled = true

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
    @State private var lookupResult: DictionaryLookupResult?
    @State private var isLookingUp = false
    @State private var lookupErrorMessage: String?
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
        L("reader_reader_position", currentChapterIndex + 1, book.chapters.count, progress * 100)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ReaderChapterWebView(
                html: chapter.content,
                isVertical: verticalLayout,
                fontSize: Double(readerFontSize),
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
                onLookupRequested: { selection in
                    handleTapLookup(selection)
                }
            )
            .background(Color.amgiBackground)
            .ignoresSafeArea(edges: .bottom)

            HStack {
                Button {
                    dismiss()
                } label: {
                    ReaderFloatingChromeButton(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
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
                    ReaderFloatingChromeButton(systemName: "slider.horizontal.3")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.amgiTextSecondary)
                    .lineLimit(1)
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 36)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(Color.amgiBackground.opacity(0.96))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pendingSelectionAction = .lookup
                    selectionRequestID += 1
                } label: {
                    Label(L("reader_reader_lookup"), systemImage: "text.magnifyingglass")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    pendingSelectionAction = .addNote
                    selectionRequestID += 1
                } label: {
                    Label(L("reader_reader_add_note"), systemImage: "square.and.pencil")
                }
            }
        }
        .background(Color.amgiBackground)
        .overlay {
            if showLookupSheet {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showLookupSheet = false
                        }

                    ReaderLookupPopup(
                        query: lookupQuery,
                        result: lookupResult,
                        isLoading: isLookingUp,
                        onAddNote: {
                            pendingDraft = makeDraft(for: lookupQuery)
                            showLookupSheet = false
                            showAddNoteSheet = true
                        },
                        onClose: {
                            showLookupSheet = false
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showAddNoteSheet, onDismiss: {
            pendingDraft = nil
        }) {
            if let pendingDraft {
                AddNoteView(onSave: {}, draft: pendingDraft)
            }
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

    private func handleTapLookup(_ selection: String?) {
        guard let tappedSelection = normalizedSelection(selection) else {
            return
        }
        pendingSelectionAction = nil
        startLookup(for: tappedSelection)
    }

    private func normalizedSelection(_ selection: String?) -> String? {
        let trimmedSelection = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSelection.isEmpty ? nil : trimmedSelection
    }

    private func startLookup(for query: String) {
        lookupQuery = query
        lookupResult = nil
        showLookupSheet = true
        isLookingUp = true
        Task {
            do {
                lookupResult = try await dictionaryLookupClient.lookup(query)
            } catch {
                showLookupSheet = false
                lookupErrorMessage = error.localizedDescription
                showSelectionError = true
            }
            isLookingUp = false
        }
    }

    private func makeDraft(for selectedText: String) -> AddNoteDraft {
        let sourceDescription = [book.title, chapter.title]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")

        return AddNoteDraft(
            deckID: selectedDeckID == 0 ? nil : Int64(selectedDeckID),
            fieldValues: [
                "Front": selectedText,
                "Text": selectedText,
                "Expression": selectedText,
                "Sentence": selectedText,
                "Back": sourceDescription,
                "Source": sourceDescription,
                "Extra": sourceDescription
            ]
        )
    }
}

private struct ReaderLookupPopup: View {
    let query: String
    let result: DictionaryLookupResult?
    let isLoading: Bool
    let onAddNote: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(query)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Text(L("reader_lookup_query_label"))
                        .font(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.amgiTextSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.amgiSurfaceElevated.opacity(0.9), in: Circle())
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(L("reader_lookup_loading"))
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                    } else if let result, result.isPlaceholder {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("reader_lookup_placeholder"))
                                .foregroundStyle(Color.amgiTextSecondary)
                            Text(L("reader_lookup_missing_source"))
                                .font(.footnote)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                    } else if let result, result.entries.isEmpty == false {
                        ForEach(result.entries) { entry in
                            ReaderLookupEntryCard(entry: entry)
                        }
                    } else {
                        Text(L("reader_lookup_empty"))
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 300)

            Button(action: onAddNote) {
                Label(L("reader_lookup_add_note"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.amgiBorder.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)
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

private struct ReaderFloatingChromeButton: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.amgiTextPrimary)
            .frame(width: 56, height: 56)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.amgiBorder.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 18, y: 8)
    }
}

private struct ReaderLookupEntryCard: View {
    let entry: DictionaryLookupEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(entry.term)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.amgiTextPrimary)
                if let reading = entry.reading, !reading.isEmpty {
                    Text(reading)
                        .font(.subheadline)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }

            if !entry.glossaries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.glossaries, id: \.self) { glossary in
                        Text(glossary)
                            .font(.body)
                            .foregroundStyle(Color.amgiTextPrimary)
                    }
                }
            }

            if let frequency = entry.frequency, !frequency.isEmpty {
                Text(frequency)
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if let pitch = entry.pitch, !pitch.isEmpty {
                Text(pitch)
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if let source = entry.source, !source.isEmpty {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.amgiBorder.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct ReaderChapterWebView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    let html: String
    let isVertical: Bool
    let fontSize: Double
    let savedProgress: Double
    let selectionRequestID: Int
    let tapLookupEnabled: Bool
    let onProgressChange: (Double) -> Void
    let onSelectionResolved: (String?) -> Void
    let onLookupRequested: (String?) -> Void

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

    private static let tapLookupScript = """
    (function() {
        function amgiReaderBoundaryCharacter(ch) {
            return !ch || /[\s\u00A0.,!?;:'"()\[\]{}<>\/\\|`~@#$%^&*=+，。！？；：、“”‘’（）〔〕【】《》〈〉「」『』…—-]/.test(ch);
        }

        function amgiReaderAsciiWordCharacter(ch) {
            return !!ch && /[A-Za-z0-9_'-]/.test(ch);
        }

        window.amgiReaderLookupTextAt = function(x, y) {
            var node = null;
            var offset = 0;

            if (document.caretRangeFromPoint) {
                var range = document.caretRangeFromPoint(x, y);
                if (range) {
                    node = range.startContainer;
                    offset = range.startOffset;
                }
            } else if (document.caretPositionFromPoint) {
                var position = document.caretPositionFromPoint(x, y);
                if (position) {
                    node = position.offsetNode;
                    offset = position.offset;
                }
            }

            if (!node || node.nodeType !== Node.TEXT_NODE) {
                return '';
            }

            var parentElement = node.parentElement;
            if (parentElement && parentElement.closest('a, button, input, textarea, select, audio, video')) {
                return '';
            }

            var text = node.textContent || '';
            if (!text.trim()) {
                return '';
            }

            var index = Math.min(Math.max(offset, 0), Math.max(text.length - 1, 0));
            if (index > 0 && amgiReaderBoundaryCharacter(text[index]) && !amgiReaderBoundaryCharacter(text[index - 1])) {
                index -= 1;
            }

            var current = text[index] || '';
            var previous = text[index - 1] || '';
            if (amgiReaderAsciiWordCharacter(current) || amgiReaderAsciiWordCharacter(previous)) {
                var start = amgiReaderAsciiWordCharacter(current) ? index : Math.max(index - 1, 0);
                while (start > 0 && amgiReaderAsciiWordCharacter(text[start - 1])) {
                    start -= 1;
                }
                var end = start;
                while (end < text.length && amgiReaderAsciiWordCharacter(text[end])) {
                    end += 1;
                }
                return text.slice(start, end).trim();
            }

            while (index < text.length && amgiReaderBoundaryCharacter(text[index])) {
                index += 1;
            }

            var maxLength = 16;
            var endIndex = index;
            while (endIndex < text.length && !amgiReaderBoundaryCharacter(text[endIndex]) && endIndex - index < maxLength) {
                endIndex += 1;
            }
            return text.slice(index, endIndex).trim();
        };
    })();
    """

    private func htmlDocument(for fragment: String) -> String {
        let textColor = colorScheme == .dark ? "#F2F4F8" : "#17212F"
        let linkColor = colorScheme == .dark ? "#8FB8FF" : "#1E5BB8"
        let backgroundColor = colorScheme == .dark ? "#0F141C" : "#FFFDF8"
        let renderedContent = renderedFragment(for: fragment)
        let writingMode = isVertical ? "vertical-rl" : "horizontal-tb"
        let bodyWidthRule = isVertical ? "width: max-content; min-width: 100%;" : "max-width: 100%;"
        let bodyPadding = isVertical ? "padding: 24px 28px 28px 28px;" : "padding: 24px 20px 40px 20px;"

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset=\"utf-8\">
        <meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\">
        \(CardAssetPath.mediaBaseTag())
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
            line-height: 1.85;
            letter-spacing: 0.01em;
            \(bodyWidthRule)
            \(bodyPadding)
            box-sizing: border-box;
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
        ruby rt {
            font-size: 0.55em;
            color: rgba(127, 127, 127, 0.9);
        }
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
        private let onProgressChange: (Double) -> Void
        let onSelectionResolved: (String?) -> Void
        let onLookupRequested: (String?) -> Void

        init(
            savedProgress: Double,
            onProgressChange: @escaping (Double) -> Void,
            onSelectionResolved: @escaping (String?) -> Void,
            onLookupRequested: @escaping (String?) -> Void
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
            let script = "window.amgiReaderLookupTextAt ? window.amgiReaderLookupTextAt(\(point.x), \(point.y)) : ''"
            webView.evaluateJavaScript(script) { [onLookupRequested] value, _ in
                onLookupRequested(value as? String)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            restoreProgress(in: webView.scrollView)
            reportProgress(for: webView.scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportProgress(for: scrollView)
        }

        private func restoreProgress(in scrollView: UIScrollView) {
            let clampedProgress = min(max(pendingProgress, 0), 1)
            let targetOffset: CGPoint

            if parent?.isVertical == true {
                let maxOffset = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
                targetOffset = CGPoint(x: maxOffset * clampedProgress, y: 0)
            } else {
                let maxOffset = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
                targetOffset = CGPoint(x: 0, y: maxOffset * clampedProgress)
            }

            DispatchQueue.main.async {
                scrollView.setContentOffset(targetOffset, animated: false)
            }
        }

        private func reportProgress(for scrollView: UIScrollView) {
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