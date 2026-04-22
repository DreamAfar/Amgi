import SwiftUI
import WebKit
import AnkiKit
import AnkiClients
import Dependencies

struct ReaderLibraryView: View {
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.readerBookClient) var readerBookClient

    @AppStorage(ReaderPreferences.Keys.deckID) private var selectedDeckID = 0
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

    private var configurationSignature: String {
        [
            String(selectedDeckID),
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
                    LazyVStack(spacing: 16) {
                        ForEach(books) { book in
                            NavigationLink {
                                ReaderBookDetailView(book: book)
                            } label: {
                                ReaderBookCard(book: book)
                            }
                            .buttonStyle(.plain)
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
        .task(id: configurationSignature) {
            await loadBooks()
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
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}

private struct ReaderBookCard: View {
    let book: ReaderBook

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
                            .lineLimit(3)
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

    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient

    @AppStorage(ReaderPreferences.Keys.deckID) private var selectedDeckID = 0
    @AppStorage(ReaderPreferences.Keys.verticalLayout) private var verticalLayout = false
    @AppStorage(ReaderPreferences.Keys.fontSize) private var readerFontSize = 24

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

    var body: some View {
        VStack(spacing: 0) {
            ReaderChapterWebView(
                html: chapter.content,
                isVertical: verticalLayout,
                fontSize: Double(readerFontSize),
                savedProgress: savedProgress,
                selectionRequestID: selectionRequestID,
                onProgressChange: { newProgress in
                    progress = newProgress
                    ReaderProgressStore.save(bookID: book.id, chapterID: chapter.id, progress: newProgress)
                },
                onSelectionResolved: { selection in
                    handleResolvedSelection(selection)
                }
            )
            .background(Color.amgiBackground)
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(chapter.title)
        .navigationBarTitleDisplayMode(.inline)
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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Text(L("reader_reader_position", currentChapterIndex + 1, book.chapters.count, progress * 100))
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .monospacedDigit()

                HStack(spacing: 12) {
                    if let previousChapter {
                        NavigationLink {
                            ReaderChapterView(book: book, chapter: previousChapter)
                        } label: {
                            Label(L("reader_reader_previous_chapter"), systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if let nextChapter {
                        NavigationLink {
                            ReaderChapterView(book: book, chapter: nextChapter)
                        } label: {
                            Label(L("reader_reader_next_chapter"), systemImage: "chevron.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
        .background(Color.amgiBackground)
        .sheet(isPresented: $showAddNoteSheet, onDismiss: {
            pendingDraft = nil
        }) {
            if let pendingDraft {
                AddNoteView(onSave: {}, draft: pendingDraft)
            }
        }
        .sheet(isPresented: $showLookupSheet) {
            NavigationStack {
                ReaderLookupSheet(
                    query: lookupQuery,
                    result: lookupResult,
                    isLoading: isLookingUp,
                    onAddNote: {
                        pendingDraft = makeDraft(for: lookupQuery)
                        showLookupSheet = false
                        showAddNoteSheet = true
                    }
                )
            }
            .presentationDetents([.medium, .large])
        }
        .alert(L("common_error"), isPresented: $showSelectionError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(lookupErrorMessage ?? L("reader_reader_empty_selection"))
        }
    }

    private func handleResolvedSelection(_ selection: String?) {
        let trimmedSelection = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedSelection.isEmpty else {
            lookupErrorMessage = L("reader_reader_empty_selection")
            showSelectionError = true
            return
        }

        let action = pendingSelectionAction
        pendingSelectionAction = nil

        switch action {
        case .lookup:
            lookupQuery = trimmedSelection
            lookupResult = nil
            showLookupSheet = true
            isLookingUp = true
            Task {
                do {
                    lookupResult = try await dictionaryLookupClient.lookup(trimmedSelection)
                } catch {
                    showLookupSheet = false
                    lookupErrorMessage = error.localizedDescription
                    showSelectionError = true
                }
                isLookingUp = false
            }
        case .addNote, .none:
            pendingDraft = makeDraft(for: trimmedSelection)
            showAddNoteSheet = true
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

private struct ReaderLookupSheet: View {
    let query: String
    let result: DictionaryLookupResult?
    let isLoading: Bool
    let onAddNote: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(query)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Color.amgiTextPrimary)
                    Text(L("reader_lookup_query_label"))
                        .font(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }

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
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(result.entries) { entry in
                            ReaderLookupEntryCard(entry: entry)
                        }
                    }
                } else {
                    Text(L("reader_lookup_empty"))
                        .foregroundStyle(Color.amgiTextSecondary)
                }

                Button(action: onAddNote) {
                    Label(L("reader_lookup_add_note"), systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("reader_lookup_title"))
        .navigationBarTitleDisplayMode(.inline)
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
    let onProgressChange: (Double) -> Void
    let onSelectionResolved: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            savedProgress: savedProgress,
            onProgressChange: onProgressChange,
            onSelectionResolved: onSelectionResolved
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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = !isVertical
        webView.scrollView.showsVerticalScrollIndicator = isVertical == false
        webView.scrollView.delegate = context.coordinator
        webView.navigationDelegate = context.coordinator
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

    final class Coordinator: NSObject, WKNavigationDelegate, UIScrollViewDelegate {
        var parent: ReaderChapterWebView?
        var lastHTML = ""
        var pendingProgress: Double
        var lastSelectionRequestID = 0
        private let onProgressChange: (Double) -> Void
        let onSelectionResolved: (String?) -> Void

        init(
            savedProgress: Double,
            onProgressChange: @escaping (Double) -> Void,
            onSelectionResolved: @escaping (String?) -> Void
        ) {
            self.pendingProgress = savedProgress
            self.onProgressChange = onProgressChange
            self.onSelectionResolved = onSelectionResolved
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
    }
}