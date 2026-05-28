import SwiftUI
import WebKit
import UniformTypeIdentifiers
import AnkiKit
import AmgiReader
import AnkiClients
import AnkiServices
import Dependencies
import EPUBKit
import UIKit

private enum ReaderEpubSettingsRoute: String, Identifiable {
    case source
    case dictionaries
    case display
    case advanced

    var id: String { rawValue }
}

private enum ReaderEpubSheetRoute: String, Identifiable {
    case chapters
    case display
    case settings
    case statistics

    var id: String { rawValue }
}

private struct ReaderEpubAddNoteSheetDraft: Identifiable {
    let id = UUID()
    let draft: AddNoteDraft
}

private enum ReaderEpubLayout {
    static let bookCoverAspectRatio: CGFloat = 100 / 136
    static let bookGridSpacing: CGFloat = 12
}

struct ReaderEpubLibraryView: View {
    @Dependency(\.readerEpubLibraryClient) private var readerEpubLibraryClient

    @AppStorage(ReaderPreferences.Keys.bookshelfColumns) private var bookshelfColumns = 3

    @State private var libraryState = ReaderEpubLibraryState.empty
    @State private var isLoading = false
    @State private var showImporter = false
    @State private var showDeleteConfirmation = false
    @State private var isSelecting = false
    @State private var selectedBookIDs: Set<UUID> = []
    @State private var sortOption: SortOption = .recent
    @State private var settingsRoute: ReaderEpubSettingsRoute?
    @State private var errorMessage: String?
    @State private var showError = false

    private var resolvedBookshelfColumns: Int {
        bookshelfColumns == 2 ? 2 : 3
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: ReaderEpubLayout.bookGridSpacing, alignment: .top),
            count: resolvedBookshelfColumns
        )
    }

    private var sortedBooks: [BookMetadata] {
        switch sortOption {
        case .recent:
            return libraryState.books.sorted { $0.lastAccess > $1.lastAccess }
        case .title:
            return libraryState.books.sorted {
                ($0.title ?? "").localizedStandardCompare($1.title ?? "") == .orderedAscending
            }
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryState.books.isEmpty {
                ContentUnavailableView(
                    L("reader_library_empty_title"),
                    systemImage: "book.closed",
                    description: Text(L("reader_epub_empty_description"))
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

                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: ReaderEpubLayout.bookGridSpacing) {
                            ForEach(sortedBooks, id: \.id) { book in
                                if isSelecting {
                                    Button {
                                        toggleSelection(for: book)
                                    } label: {
                                        ReaderEpubBookCard(
                                            book: book,
                                            progress: libraryState.progressByBookID[book.id] ?? 0,
                                            isSelecting: true,
                                            isSelected: selectedBookIDs.contains(book.id)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    NavigationLink {
                                        ReaderEpubReaderView(book: book)
                                    } label: {
                                        ReaderEpubBookCard(
                                            book: book,
                                            progress: libraryState.progressByBookID[book.id] ?? 0
                                        )
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
                        Text(L("reader_library_sort_recent")).tag(SortOption.recent)
                        Text(L("reader_library_sort_title")).tag(SortOption.title)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }

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
                if isSelecting {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedBookIDs.isEmpty)
                }

                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel(Text(L("reader_epub_import_button")))

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
        .task {
            await loadState()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.epub],
            allowsMultipleSelection: true
        ) { result in
            Task {
                do {
                    let urls = try result.get()
                    libraryState = try readerEpubLibraryClient.importBooks(urls)
                    selectedBookIDs.formIntersection(Set(libraryState.books.map(\.id)))
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
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
            Text(errorMessage ?? L("common_error"))
        }
        .alert(L("common_delete"), isPresented: $showDeleteConfirmation) {
            Button(L("common_delete"), role: .destructive) {
                Task {
                    do {
                        libraryState = try readerEpubLibraryClient.deleteBooks(Array(selectedBookIDs))
                        clearSelection()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
            Button(L("common_cancel"), role: .cancel) {}
        } message: {
            Text(L("reader_epub_delete_confirmation", selectedBookIDs.count))
        }
    }

    private func loadState() async {
        isLoading = true
        defer { isLoading = false }
        do {
            libraryState = try readerEpubLibraryClient.loadState()
            selectedBookIDs.formIntersection(Set(libraryState.books.map(\.id)))
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func toggleSelection(for book: BookMetadata) {
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

private struct ReaderEpubBookCard: View {
    let book: BookMetadata
    let progress: Double
    var isSelecting = false
    var isSelected = false

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
                .aspectRatio(ReaderEpubLayout.bookCoverAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    if let coverURL = book.coverURL {
                        AsyncImage(url: coverURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "book.closed")
                                .font(.system(size: 32, weight: .medium))
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        Image(systemName: "book.closed")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
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
                Text(book.title ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.amgiTextPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 34, alignment: .topLeading)

                ProgressView(value: progress)
                    .tint(Color.amgiAccent)
            }
            .frame(height: 46, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReaderEpubReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Dependency(\.dictionaryLookupClient) private var dictionaryLookupClient
    @Dependency(\.mediaClient) private var mediaClient
    @Dependency(\.noteClient) private var noteClient
    @Dependency(\.ankiBackend) private var backend
    @Dependency(\.notetypesService) private var notetypesService

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
    @AppStorage(ReaderPreferences.Keys.popupAudioSourcePreset) private var popupAudioSourcePresetRawValue = ReaderLookupAudioDefaults.defaultRemoteAudioPreset.rawValue
    @AppStorage(ReaderPreferences.Keys.popupAudioSourceTemplate) private var popupAudioSourceTemplate = ReaderLookupAudioDefaults.defaultTemplate
    @AppStorage(ReaderPreferences.Keys.popupLocalAudioEnabled) private var popupLocalAudioEnabled = false
    @AppStorage(ReaderPreferences.Keys.popupAudioAutoplay) private var popupAudioAutoplay = false
    @AppStorage(ReaderPreferences.Keys.popupAudioPlaybackMode) private var popupAudioPlaybackModeRawValue = ReaderLookupAudioPlaybackMode.interrupt.rawValue
    @AppStorage(ReaderPreferences.Keys.popupDebugInfoEnabled) private var popupDebugInfoEnabled = false
    @AppStorage(ReaderPreferences.Keys.dictionaryMaxResults) private var dictionaryMaxResults = 16
    @AppStorage(ReaderPreferences.Keys.dictionaryScanLength) private var dictionaryScanLength = 16
    @AppStorage(ReaderPreferences.Keys.lookupNoteTemplate) private var lookupNoteTemplateData = ""
    @AppStorage(ReaderPreferences.Keys.enableStatistics) private var enableStatistics = false
    @AppStorage(ReaderPreferences.Keys.statisticsAutostartMode) private var statisticsAutostartModeRawValue = ReaderStatisticsAutostartMode.off.rawValue
    @AppStorage(ReviewPreferences.Keys.selectionMenuLookupEnabled) private var selectionMenuLookupEnabled = false
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIEnabled) private var selectionMenuAIEnabled = false

    let book: BookMetadata

    @State private var session: ReaderEpubSession?
    @State private var loadingErrorMessage: String?
    @State private var bridge = ReaderEpubWebViewBridge()
    @State private var pendingAddNoteDraft: ReaderEpubAddNoteSheetDraft?
    @State private var pendingAIAddNoteDraft: ReviewAIAddNoteSheetDraft?
    @State private var queuedAIAddNoteDraft: ReviewAIAddNoteSheetDraft?
    @State private var lookupPopupRefreshID = 0
    @State private var showSelectionError = false
    @State private var lookupErrorMessage: String?
    @State private var lookupStack: [ReaderLookupPopupState] = []
    @State private var activeSheet: ReaderEpubSheetRoute?
    @State private var selectionAIState: ReviewSelectionAIState?
    @State private var aiFavoriteRefreshToken = 0

    private var themeMode: ReaderThemeMode {
        ReaderThemeMode(rawValue: themeModeRawValue) ?? .system
    }

    private var lookupNoteTemplateStore: ReaderLookupNoteTemplateStore {
        ReaderLookupNoteTemplateStore.decode(from: lookupNoteTemplateData)
    }

    private var lookupNoteTemplate: ReaderLookupNoteTemplate {
        lookupNoteTemplateStore.template(for: nil)
    }

    private var popupAudioPlaybackMode: ReaderLookupAudioPlaybackMode {
        ReaderLookupAudioDefaults.resolvedPlaybackMode(popupAudioPlaybackModeRawValue)
    }

    private var lookupLanguageHint: String? {
        nil
    }

    private var statisticsAutostartMode: ReaderStatisticsAutostartMode {
        ReaderStatisticsAutostartMode(rawValue: statisticsAutostartModeRawValue) ?? .off
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

    private var resolvedPageBackgroundHex: String {
        switch themeMode {
        case .system:
            return systemPageBackgroundHex
        case .eyeCare:
            return "#EAF4E4"
        case .sepia:
            return "#F4ECD8"
        case .custom:
            return normalizedHexColor(customBackgroundColorHex, fallback: "#FFFDF8")
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
            return normalizedHexColor(customContentColorHex, fallback: "#FFFDF8")
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
            return normalizedHexColor(customTextColorHex, fallback: "#17212F")
        }
    }

    private var chapterContentBackground: Color {
        Color(readerHex: resolvedContentBackgroundHex, fallback: .amgiSurfaceElevated)
    }

    private var progressLabel: String {
        guard let session else {
            return ""
        }

        if showPercentage {
            let percent = session.bookInfo.characterCount > 0
                ? (Double(session.currentCharacter) / Double(session.bookInfo.characterCount) * 100)
                : 0
            return "\(session.currentCharacter) / \(session.bookInfo.characterCount)   \(String(format: "%.1f%%", percent))"
        }

        return "\(session.currentCharacter) / \(session.bookInfo.characterCount)"
    }

    var body: some View {
        bodyContent
        .toolbar(.hidden, for: .tabBar)
        .task {
            if self.session == nil {
                do {
                    loadingErrorMessage = nil
                    let loadedSession = try ReaderEpubSession(
                        book: book,
                        enableStatistics: enableStatistics,
                        autostartStatistics: statisticsAutostartMode == .on
                    )
                    self.session = loadedSession
                    if let action = loadedSession.initialAction() {
                        send(action)
                    }
                } catch {
                    loadingErrorMessage = error.localizedDescription
                }
            }
        }
        .task(id: session?.isTracking == true) {
            guard let session, session.isTracking, session.isPaused == false else {
                return
            }
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(1))
                guard session.isTracking, session.isPaused == false else {
                    return
                }
                await syncReadingProgress(session)
                session.updateStatistics()
            }
        }
        .onChange(of: enableStatistics) {
            session?.configureStatistics(enabled: enableStatistics, autostart: statisticsAutostartMode == .on)
        }
        .onChange(of: statisticsAutostartModeRawValue) {
            session?.configureStatistics(enabled: enableStatistics, autostart: statisticsAutostartMode == .on)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            session?.resumeTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            guard let session else {
                return
            }
            Task {
                await syncReadingProgress(session, persistBookmark: true)
                session.pauseTracking()
            }
        }
        .onDisappear {
            guard let session else {
                return
            }
            Task {
                await syncReadingProgress(session, persistBookmark: true)
                session.stopTracking()
            }
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        Group {
            if let session {
                GeometryReader { geometry in
                    let topSafeArea = max(UIApplication.readerEpubTopSafeArea, geometry.safeAreaInsets.top)
                    let bottomSafeArea = max(UIApplication.readerEpubBottomSafeArea, geometry.safeAreaInsets.bottom)
                    let topOverlayTopPadding = max(topSafeArea, 25)
                    let topOverlayHeight = topOverlayTopPadding + ((showTitle || showProgressTop) ? 34 : 10)
                    let bottomInset = max(bottomSafeArea - 8, 14)
                    let bottomChromeHeight = (bottomSafeArea > 25 ? bottomSafeArea : 44) + 10

                    VStack(spacing: 0) {
                        chapterContentBackground
                            .frame(height: topOverlayHeight)

                        ZStack(alignment: .bottom) {
                            ReaderEpubScrollWebView(
                                bridge: bridge,
                                viewSize: CGSize(width: geometry.size.width.rounded(), height: geometry.size.height.rounded()),
                                isVertical: verticalLayout,
                                fontFamily: ReaderFontOption.resolved(selectedFont).cssFontFamily,
                                fontSize: Double(readerFontSize),
                                hideFurigana: hideFurigana,
                                horizontalPadding: horizontalPadding,
                                verticalPadding: verticalPadding,
                                avoidPageBreak: avoidPageBreak,
                                justifyText: justifyText,
                                lineHeight: lineHeight,
                                characterSpacing: characterSpacing,
                                textColorHex: resolvedTextColorHex,
                                selectionMenuLookupEnabled: selectionMenuLookupEnabled,
                                selectionMenuAIEnabled: selectionMenuAIEnabled,
                                onNextChapter: {
                                    guard let action = session.actionForNextChapter() else {
                                        return false
                                    }
                                    startStatisticsTrackingForPageTurn(session)
                                    lookupStack.removeAll()
                                    bridge.send(.clearHighlight)
                                    send(action)
                                    return true
                                },
                                onPreviousChapter: {
                                    guard let action = session.actionForPreviousChapter() else {
                                        return false
                                    }
                                    startStatisticsTrackingForPageTurn(session)
                                    lookupStack.removeAll()
                                    bridge.send(.clearHighlight)
                                    send(action)
                                    return true
                                },
                                onSaveBookmark: { progress in
                                    session.saveBookmark(progress: progress)
                                    bridge.updateProgress(progress)
                                },
                                onProgressChange: { progress in
                                    session.syncProgress(progress)
                                    bridge.updateProgress(progress)
                                },
                                onInternalLink: { url in
                                    guard let action = session.actionForInternalLink(url) else {
                                        return false
                                    }
                                    lookupStack.removeAll()
                                    bridge.send(.clearHighlight)
                                    send(action)
                                    return true
                                },
                                onInternalJump: { progress in
                                    session.syncProgressAfterInternalJump(progress)
                                    bridge.updateProgress(progress)
                                },
                                onTextSelected: { selection in
                                    let offsetPoint = CGPoint(x: selection.rect.midX, y: selection.rect.midY + topOverlayHeight)
                                    let offsetRect = selection.rect.offsetBy(dx: 0, dy: topOverlayHeight)
                                    handleTapLookup(selection.text, sentence: selection.sentence, at: offsetPoint, rect: offsetRect)
                                },
                                onSelectionMenuAction: { action, snapshot in
                                    handleSelectionMenuAction(action, snapshot: snapshot)
                                },
                                onTapOutside: {
                                    lookupStack.removeAll()
                                    bridge.send(.clearHighlight)
                                },
                                onScroll: {
                                    lookupStack.removeAll()
                                    bridge.send(.clearHighlight)
                                    startStatisticsTrackingForPageTurn(session)
                                }
                            )
                            .background(chapterContentBackground)
                            .ignoresSafeArea(edges: .bottom)
                            .id(
                                ReaderEpubWebViewState(
                                    verticalWriting: verticalLayout,
                                    fontSize: readerFontSize,
                                    selectedFont: selectedFont,
                                    hideFurigana: hideFurigana,
                                    horizontalPadding: horizontalPadding,
                                    verticalPadding: verticalPadding,
                                    avoidPageBreak: avoidPageBreak,
                                    justifyText: justifyText,
                                    lineHeight: lineHeight,
                                    characterSpacing: characterSpacing,
                                    textColorHex: resolvedTextColorHex,
                                    size: geometry.size
                                )
                            )

                            HStack {
                                Button {
                                    persistProgressAndDismiss(session)
                                } label: {
                                    ReaderEpubChromeIconLabel(systemName: "chevron.left")
                                }
                                .readerEpubChromeButtonStyle()

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

                                    if enableStatistics {
                                        Button {
                                            activeSheet = .statistics
                                        } label: {
                                            Label(L("reader_reader_menu_statistics"), systemImage: "chart.xyaxis.line")
                                        }
                                    }
                                } label: {
                                    ReaderEpubChromeIconLabel(systemName: "ellipsis")
                                }
                                .readerEpubChromeButtonStyle()
                            }
                            .padding(.horizontal, 20)
                            .frame(height: bottomChromeHeight, alignment: .top)
                        }
                    }
                    .background(chapterContentBackground)
                    .overlay(alignment: .top) {
                        VStack {
                            if showTitle, let title = session.document.title, title.isEmpty == false {
                                Text(title)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.amgiTextSecondary)
                                    .padding(.horizontal, 30)
                                    .lineLimit(1)
                            }

                            if showProgressTop, progressLabel.isEmpty == false {
                                Text(progressLabel)
                                    .font(.caption)
                                    .foregroundStyle(Color.amgiTextSecondary)
                                    .monospacedDigit()
                                    .tracking(-0.4)
                            }
                        }
                        .padding(.top, topOverlayTopPadding)
                    }
                    .overlay(alignment: .bottom) {
                        if showProgressTop == false {
                            Text(progressLabel)
                                .font(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                                .monospacedDigit()
                                .tracking(-0.4)
                        }
                    }
                    .overlay {
                        if lookupStack.isEmpty == false {
                            GeometryReader { popupGeometry in
                                ZStack {
                                    Color.black.opacity(0.001)
                                        .ignoresSafeArea()
                                        .onTapGesture {
                                            lookupStack.removeAll()
                                            bridge.send(.clearHighlight)
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
                                            audioSourcePresetRawValue: popupAudioSourcePresetRawValue,
                                            audioSourceTemplate: popupAudioSourceTemplate,
                                            localAudioEnabled: popupLocalAudioEnabled,
                                            audioAutoplay: popupAudioAutoplay && index == lookupStack.count - 1,
                                            audioPlaybackMode: popupAudioPlaybackMode,
                                            needsAudio: lookupNoteTemplate.needsAudio,
                                            refreshID: lookupPopupRefreshID,
                                            showDebugInfo: popupDebugInfoEnabled,
                                            onAddNote: { payload in
                                                Task {
                                                    let draft = await makeLookupDraft(from: payload, session: session, sentence: popup.sentence)
                                                    await MainActor.run {
                                                        pendingAddNoteDraft = ReaderEpubAddNoteSheetDraft(draft: draft)
                                                    }
                                                }
                                            },
                                            duplicateCheck: { content in
                                                await hasExistingLookupNote(for: content, session: session, sentence: popup.sentence)
                                            },
                                            onLookupRequested: { query, sentence in
                                                startLookup(for: query, sentence: sentence, anchor: nil, anchorRect: nil, stacksOnTop: true)
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
                                        .transition(.opacity)
                                    }
                                }
                            }
                        }
                    }
                }
                .background(chapterContentBackground)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .sheet(item: $pendingAddNoteDraft, onDismiss: { pendingAddNoteDraft = nil }) { sheetDraft in
                    AddNoteView(
                        onSave: {
                            Task {
                                await ReaderLookupDuplicateCache.shared.invalidate(
                                    notetypeID: sheetDraft.draft.notetypeID ?? lookupNoteTemplate.notetypeID
                                )
                            }
                            lookupPopupRefreshID += 1
                            pendingAddNoteDraft = nil
                        },
                        draft: sheetDraft.draft
                    )
                }
                .sheet(item: $selectionAIState, onDismiss: {
                    presentQueuedAIAddNoteDraft()
                }) { state in
                    NavigationStack {
                        ReviewSelectionAISheetView(
                            state: aiSheetBinding(for: state.id),
                            presets: ReviewSelectionAIPresetStore.load().presets,
                            quickActions: ReviewAIQuickActionStore.load().actions,
                            isFavorited: isCurrentAIResponseFavorited,
                            onClose: {
                                selectionAIState = nil
                            },
                            onSubmit: { action in
                                submitSelectionAI(quickAction: action)
                            },
                            onToggleFavorite: {
                                toggleCurrentAIResponseFavorite()
                            },
                            onAddNote: {
                                openAddNoteFromCurrentAI()
                            }
                        )
                    }
                }
                .sheet(item: $pendingAIAddNoteDraft) { sheetDraft in
                    AddNoteView(
                        onSave: {
                            pendingAIAddNoteDraft = nil
                        },
                        draft: sheetDraft.draft
                    )
                }
                .sheet(item: $activeSheet) { route in
                    NavigationStack {
                        switch route {
                        case .chapters:
                            ReaderEpubChapterListSheet(session: session) { action in
                                activeSheet = nil
                                send(action)
                            }
                        case .display:
                            ReaderDisplaySettingsView()
                        case .settings:
                            ReaderSettingsHomeView()
                        case .statistics:
                            ReaderEpubStatisticsView(session: session)
                        }
                    }
                    .presentationDetents([.fraction(0.52), .large])
                    .presentationDragIndicator(.visible)
                }
                .alert(L("common_error"), isPresented: $showSelectionError) {
                    Button(L("common_ok"), role: .cancel) {}
                } message: {
                    Text(lookupErrorMessage ?? L("reader_reader_empty_selection"))
                }
                .animation(.easeOut(duration: 0.16), value: lookupStack)
                .ignoresSafeArea(edges: .top)
            } else if let loadingErrorMessage {
                ContentUnavailableView(
                    L("common_error"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadingErrorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.amgiBackground)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.amgiBackground)
            }
        }
    }

    @ViewBuilder
    private func readerSessionGeometryContent(session: ReaderEpubSession, geometry: GeometryProxy) -> some View {
        let topSafeArea = max(UIApplication.readerEpubTopSafeArea, geometry.safeAreaInsets.top)
        let bottomSafeArea = max(UIApplication.readerEpubBottomSafeArea, geometry.safeAreaInsets.bottom)
        let topOverlayTopPadding = max(topSafeArea, 25)
        let topOverlayHeight = topOverlayTopPadding + ((showTitle || showProgressTop) ? 34 : 10)
        let bottomInset = max(bottomSafeArea - 8, 14)
        let bottomChromeHeight = (bottomSafeArea > 25 ? bottomSafeArea : 44) + 10

        VStack(spacing: 0) {
            chapterContentBackground
                .frame(height: topOverlayHeight)

            ZStack(alignment: .bottom) {
                ReaderEpubScrollWebView(
                    bridge: bridge,
                    viewSize: CGSize(width: geometry.size.width.rounded(), height: geometry.size.height.rounded()),
                    isVertical: verticalLayout,
                    fontFamily: ReaderFontOption.resolved(selectedFont).cssFontFamily,
                    fontSize: Double(readerFontSize),
                    hideFurigana: hideFurigana,
                    horizontalPadding: horizontalPadding,
                    verticalPadding: verticalPadding,
                    avoidPageBreak: avoidPageBreak,
                    justifyText: justifyText,
                    lineHeight: lineHeight,
                    characterSpacing: characterSpacing,
                    textColorHex: resolvedTextColorHex,
                    selectionMenuLookupEnabled: selectionMenuLookupEnabled,
                    selectionMenuAIEnabled: selectionMenuAIEnabled,
                    onNextChapter: {
                        guard let action = session.actionForNextChapter() else {
                            return false
                        }
                        startStatisticsTrackingForPageTurn(session)
                        lookupStack.removeAll()
                        bridge.send(.clearHighlight)
                        send(action)
                        return true
                    },
                    onPreviousChapter: {
                        guard let action = session.actionForPreviousChapter() else {
                            return false
                        }
                        startStatisticsTrackingForPageTurn(session)
                        lookupStack.removeAll()
                        bridge.send(.clearHighlight)
                        send(action)
                        return true
                    },
                    onSaveBookmark: { progress in
                        session.saveBookmark(progress: progress)
                        bridge.updateProgress(progress)
                    },
                    onProgressChange: { progress in
                        session.syncProgress(progress)
                        bridge.updateProgress(progress)
                    },
                    onInternalLink: { url in
                        guard let action = session.actionForInternalLink(url) else {
                            return false
                        }
                        lookupStack.removeAll()
                        bridge.send(.clearHighlight)
                        send(action)
                        return true
                    },
                    onInternalJump: { progress in
                        session.syncProgressAfterInternalJump(progress)
                        bridge.updateProgress(progress)
                    },
                    onTextSelected: { selection in
                        let offsetPoint = CGPoint(x: selection.rect.midX, y: selection.rect.midY + topOverlayHeight)
                        let offsetRect = selection.rect.offsetBy(dx: 0, dy: topOverlayHeight)
                        handleTapLookup(selection.text, sentence: selection.sentence, at: offsetPoint, rect: offsetRect)
                    },
                    onSelectionMenuAction: { action, snapshot in
                        handleSelectionMenuAction(action, snapshot: snapshot)
                    },
                    onTapOutside: {
                        lookupStack.removeAll()
                        bridge.send(.clearHighlight)
                    },
                    onScroll: {
                        lookupStack.removeAll()
                        bridge.send(.clearHighlight)
                        startStatisticsTrackingForPageTurn(session)
                    }
                )
                .background(chapterContentBackground)
                .ignoresSafeArea(edges: .bottom)
                .id(
                    ReaderEpubWebViewState(
                        verticalWriting: verticalLayout,
                        fontSize: readerFontSize,
                        selectedFont: selectedFont,
                        hideFurigana: hideFurigana,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        avoidPageBreak: avoidPageBreak,
                        justifyText: justifyText,
                        lineHeight: lineHeight,
                        characterSpacing: characterSpacing,
                        textColorHex: resolvedTextColorHex,
                        size: geometry.size
                    )
                )

                HStack {
                    Button {
                        persistProgressAndDismiss(session)
                    } label: {
                        ReaderEpubChromeIconLabel(systemName: "chevron.left")
                    }
                    .readerEpubChromeButtonStyle()

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

                        if enableStatistics {
                            Button {
                                activeSheet = .statistics
                            } label: {
                                Label(L("reader_reader_menu_statistics"), systemImage: "chart.xyaxis.line")
                            }
                        }
                    } label: {
                        ReaderEpubChromeIconLabel(systemName: "ellipsis")
                    }
                    .readerEpubChromeButtonStyle()
                }
                .padding(.horizontal, 20)
                .frame(height: bottomChromeHeight, alignment: .top)
            }
        }
        .background(chapterContentBackground)
        .overlay(alignment: .top) {
            VStack {
                if showTitle, let title = session.document.title, title.isEmpty == false {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Color.amgiTextSecondary)
                        .padding(.horizontal, 30)
                        .lineLimit(1)
                }

                if showProgressTop, progressLabel.isEmpty == false {
                    Text(progressLabel)
                        .font(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                        .monospacedDigit()
                        .tracking(-0.4)
                }
            }
            .padding(.top, topOverlayTopPadding)
        }
        .overlay(alignment: .bottom) {
            if showProgressTop == false {
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .monospacedDigit()
                    .tracking(-0.4)
            }
        }
        .overlay {
            if lookupStack.isEmpty == false {
                GeometryReader { popupGeometry in
                    ZStack {
                        Color.black.opacity(0.001)
                            .ignoresSafeArea()
                            .onTapGesture {
                                lookupStack.removeAll()
                                bridge.send(.clearHighlight)
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
                                audioSourcePresetRawValue: popupAudioSourcePresetRawValue,
                                audioSourceTemplate: popupAudioSourceTemplate,
                                localAudioEnabled: popupLocalAudioEnabled,
                                audioAutoplay: popupAudioAutoplay && index == lookupStack.count - 1,
                                audioPlaybackMode: popupAudioPlaybackMode,
                                needsAudio: lookupNoteTemplate.needsAudio,
                                refreshID: lookupPopupRefreshID,
                                showDebugInfo: popupDebugInfoEnabled,
                                onAddNote: { payload in
                                    Task {
                                        let draft = await makeLookupDraft(from: payload, session: session, sentence: popup.sentence)
                                        await MainActor.run {
                                            pendingAddNoteDraft = ReaderEpubAddNoteSheetDraft(draft: draft)
                                        }
                                    }
                                },
                                duplicateCheck: { content in
                                    await hasExistingLookupNote(for: content, session: session, sentence: popup.sentence)
                                },
                                onLookupRequested: { query, sentence in
                                    startLookup(for: query, sentence: sentence, anchor: nil, anchorRect: nil, stacksOnTop: true)
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
                            .transition(.opacity)
                        }
                    }
                }
            }
        }
    }

    private func startStatisticsTrackingForPageTurn(_ session: ReaderEpubSession) {
        guard enableStatistics, statisticsAutostartMode == .pageTurn, session.isTracking == false else {
            return
        }
        session.startTracking()
    }

    private func syncReadingProgress(_ session: ReaderEpubSession, persistBookmark: Bool = false) async {
        let progress = await withCheckedContinuation { continuation in
            bridge.requestCurrentProgress { progress in
                continuation.resume(returning: progress)
            }
        }

        session.syncProgress(progress, persistBookmark: persistBookmark)
        bridge.updateProgress(progress)
    }

    private func persistProgressAndDismiss(_ session: ReaderEpubSession) {
        Task {
            await syncReadingProgress(session, persistBookmark: true)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func normalizedHexColor(_ value: String, fallback: String) -> String {
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

    private func send(_ action: ReaderEpubNavigationAction) {
        switch action {
        case let .loadChapter(url, progress, fragment):
            bridge.send(.loadChapter(url: url, progress: progress, fragment: fragment))
        case let .restoreProgress(progress):
            bridge.send(.restoreProgress(progress))
        case let .jumpToFragment(fragment):
            bridge.send(.jumpToFragment(fragment))
        }
    }

    private func normalizedSelection(_ selection: String?) -> String? {
        let trimmed = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedSentence(_ sentence: String?) -> String? {
        let trimmed = sentence?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func handleTapLookup(_ selection: String?, sentence: String?, at point: CGPoint, rect: CGRect?) {
        guard let tappedSelection = normalizedSelection(selection) else {
            lookupStack.removeAll()
            bridge.send(.clearHighlight)
            return
        }
        startLookup(for: tappedSelection, sentence: sentence, anchor: point, anchorRect: rect)
    }

    private func handleSelectionMenuAction(_ action: SelectedTextAction, snapshot: SelectedTextSnapshot) {
        guard let selection = snapshot.text.trimmedOrNil else { return }

        switch action {
        case .lookup:
            startLookup(for: selection, sentence: snapshot.sentence, anchor: nil, anchorRect: nil, stacksOnTop: true)
        case .ai:
            startSelectionAI(
                for: selection,
                context: ReviewAIQueryContext(
                    selectedText: selection,
                    sentence: normalizedSentence(snapshot.sentence),
                    source: readerAISelectionSource
                )
            )
        }
    }

    private func startSelectionAI(for selection: String, context: ReviewAIQueryContext) {
        guard selectionMenuAIEnabled else { return }
        switch ReviewAIFlow.makeInitialStateIfConfigured(selection: selection, context: context) {
        case let .success(state):
            selectionAIState = state
        case let .failure(error):
            lookupErrorMessage = error.message
            showSelectionError = true
            return
        }
        submitSelectionAI()
    }

    private func submitSelectionAI(quickAction: ReviewAIQuickAction? = nil) {
        guard let state = selectionAIState else { return }
        switch ReviewAIFlow.prepareSubmission(state: state, quickAction: quickAction) {
        case let .success(prepared):
            selectionAIState = prepared.state
            let requestID = prepared.state.id
            Task {
                do {
                    let response = try await ReviewAIFlow.requestResponse(
                        selection: prepared.selection,
                        context: prepared.state.context,
                        quickAction: quickAction,
                        presetID: prepared.config.presetID
                    )
                    await MainActor.run {
                        guard selectionAIState?.id == requestID else { return }
                        var nextState = selectionAIState ?? prepared.state
                        nextState.isLoading = false
                        nextState.response = response
                        nextState.errorMessage = nil
                        selectionAIState = nextState
                    }
                } catch {
                    await MainActor.run {
                        guard selectionAIState?.id == requestID else { return }
                        var nextState = selectionAIState ?? prepared.state
                        nextState.isLoading = false
                        nextState.response = nil
                        nextState.errorMessage = error.localizedDescription
                        selectionAIState = nextState
                    }
                }
            }
        case let .failure(error):
            lookupErrorMessage = error.message
            showSelectionError = true
            return
        }
    }

    private var readerAISelectionSource: String {
        var parts: [String] = []
        if let title = book.title?.trimmedOrNil {
            parts.append(title)
        }
        if let chapterTitle = session?.document.title?.trimmedOrNil,
           parts.last != chapterTitle {
            parts.append(chapterTitle)
        }
        return parts.joined(separator: " / ")
    }

    private func aiSheetBinding(for id: UUID) -> Binding<ReviewSelectionAIState> {
        Binding(
            get: {
                guard let selectionAIState, selectionAIState.id == id else {
                    return ReviewSelectionAIState(
                        selection: "",
                        context: ReviewAIQueryContext(selectedText: ""),
                        activePresetID: ReviewSelectionAIPresetStore.load().selectedPresetID
                    )
                }
                return selectionAIState
            },
            set: { newValue in
                guard selectionAIState?.id == id else { return }
                selectionAIState = newValue
            }
        )
    }

    private var currentAIFavoriteItem: ReviewAIFavoriteItem? {
        guard let state = selectionAIState else { return nil }
        return ReviewAIFlow.favoriteItem(for: state)
    }

    private var isCurrentAIResponseFavorited: Bool {
        _ = aiFavoriteRefreshToken
        return ReviewAIFlow.isFavorited(currentAIFavoriteItem)
    }

    private func toggleCurrentAIResponseFavorite() {
        ReviewAIFlow.toggleFavorite(currentAIFavoriteItem)
        aiFavoriteRefreshToken += 1
    }

    private func openAddNoteFromCurrentAI() {
        guard let state = selectionAIState else { return }
        queuedAIAddNoteDraft = ReviewAIFlow.makeAddNoteDraft(
            for: state,
            fallbackDeckID: selectedDeckID == 0 ? nil : Int64(selectedDeckID)
        )
        selectionAIState = nil
    }

    private func presentQueuedAIAddNoteDraft() {
        guard pendingAIAddNoteDraft == nil, let queuedAIAddNoteDraft else { return }
        pendingAIAddNoteDraft = queuedAIAddNoteDraft
        self.queuedAIAddNoteDraft = nil
    }

    private func startLookup(for query: String, sentence: String? = nil, anchor: CGPoint? = nil, anchorRect: CGRect? = nil, stacksOnTop: Bool = false) {
        let popup = ReaderLookupPopupState(
            query: query,
            sentence: normalizedSentence(sentence),
            anchor: anchor,
            anchorRect: anchorRect,
            result: nil,
            isLoading: true
        )

        if stacksOnTop {
            lookupStack.append(popup)
        } else {
            lookupStack = [popup]
        }

        Task {
            do {
                let result = try await dictionaryLookupClient.lookup(query, dictionaryMaxResults, dictionaryScanLength)
                updateLookupPopup(id: popup.id, result: result, isLoading: false)
                if let matched = result.entries.first?.matched?.nilIfBlank {
                    bridge.send(.highlightSelection(matched.count))
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
        if lookupStack.isEmpty {
            bridge.send(.clearHighlight)
        }
    }

    private func closeLookupPopup(id: UUID) {
        removeLookupPopup(id: id)
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

    private func makeLookupDraft(from content: [String: String], session: ReaderEpubSession, sentence: String?) async -> AddNoteDraft {
        let resolvedContent = await enrichLookupContentForDraft(content, session: session)

        return lookupNoteTemplate.makeDraft(
            content: resolvedContent,
            context: ReaderLookupMiningContext(
                sentence: normalizedSentence(sentence) ?? content["expression"] ?? "",
                documentTitle: session.document.title,
                coverURL: session.coverURL
            ),
            fallbackDeckID: selectedDeckID == 0 ? nil : Int64(selectedDeckID)
        )
    }

    private func enrichLookupContentForDraft(_ content: [String: String], session: ReaderEpubSession) async -> [String: String] {
        var resolvedContent = content

        if lookupNoteTemplate.needsAudio,
           let audioMarkup = await storedLookupAudioMarkup(from: content["audio"]) {
            resolvedContent["audio"] = audioMarkup
        }

        if lookupNoteTemplate.fieldMappings.values.contains(ReaderLookupHandlebar.bookCover.rawValue),
           let coverURL = session.coverURL,
           let coverMarkup = storedLookupCoverMarkup(from: coverURL) {
            resolvedContent["bookCover"] = coverMarkup
        }

        return resolvedContent
    }

    private func storedLookupAudioMarkup(from rawValue: String?) async -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false,
              let url = URL(string: rawValue) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let responseExtension = response.suggestedFilename.flatMap {
                URL(fileURLWithPath: $0).pathExtension.nilIfBlank
            }
            let contentType = responseExtension.flatMap { UTType(filenameExtension: $0) }
                ?? UTType(filenameExtension: url.pathExtension)
            let filename = NoteFieldMediaSupport.suggestedFilename(
                sourceURL: url,
                contentType: contentType,
                fallbackPrefix: "reader-audio"
            )
            let storedFilename = try mediaClient.save(data, filename)
            return NoteFieldMediaSupport.markup(for: storedFilename, contentType: contentType)
        } catch {
            return nil
        }
    }

    private func storedLookupCoverMarkup(from url: URL) -> String? {
        do {
            let data = try Data(contentsOf: url)
            let contentType = UTType(filenameExtension: url.pathExtension)
            let filename = NoteFieldMediaSupport.suggestedFilename(
                sourceURL: url,
                contentType: contentType,
                fallbackPrefix: "reader-cover"
            )
            let storedFilename = try mediaClient.save(data, filename)
            return NoteFieldMediaSupport.markup(for: storedFilename, contentType: contentType)
        } catch {
            return nil
        }
    }

    private func hasExistingLookupNote(for content: [String: String], session: ReaderEpubSession, sentence: String?) async -> Bool {
        guard let notetypeID = lookupNoteTemplate.notetypeID else {
            return false
        }

        let lookupTemplate = lookupNoteTemplate
        guard let notetype = try? notetypesService.getNotetype(notetypeID) else {
            return false
        }
        let validFieldNames = notetype.fieldNames
        let targetFieldName = lookupTemplate.duplicateCheckFieldName ?? validFieldNames.first
        let draft = await makeLookupDraft(from: content, session: session, sentence: sentence)
        guard let duplicateCheckValue = duplicateCheckValue(from: draft, targetFieldName: targetFieldName) else {
            return false
        }

        return await ReaderLookupDuplicateCache.shared.contains(
            word: duplicateCheckValue,
            notetypeID: notetypeID,
            fieldName: lookupTemplate.duplicateCheckFieldName
        ) { [noteClient] in
            let duplicateCheckFieldIndex = lookupTemplate.duplicateCheckFieldIndex(
                validFields: validFieldNames
            )
            let query = "note:\"\(Self.escapedSearchTerm(notetype.name))\""
            let noteIDs = try noteClient.searchIds(query)
            guard noteIDs.isEmpty == false else {
                return []
            }

            var duplicateCheckValues: [String] = []
            duplicateCheckValues.reserveCapacity(noteIDs.count)

            let batchSize = 250
            var startIndex = 0
            while startIndex < noteIDs.count {
                let endIndex = min(startIndex + batchSize, noteIDs.count)
                let batch = Array(noteIDs[startIndex..<endIndex])
                let notes = try noteClient.fetchBatch(batch)
                duplicateCheckValues.append(contentsOf: notes.compactMap {
                    $0.readerLookupFieldValue(at: duplicateCheckFieldIndex)
                })
                startIndex = endIndex
            }

            return duplicateCheckValues
        }
    }

        private func duplicateCheckValue(from draft: AddNoteDraft, targetFieldName: String?) -> String? {
                guard let targetFieldName,
                            let value = draft.fieldValues[targetFieldName]?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                            value.isEmpty == false else {
                        return nil
                }
                return value
    }

    nonisolated private static func escapedSearchTerm(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
}

private struct ReaderEpubChapterListSheet: View {
    let session: ReaderEpubSession
    let onSelect: (ReaderEpubNavigationAction) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rows: [ReaderEpubChapterRow] = []

    var body: some View {
        List {
            if let title = session.document.title {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        if let coverURL = session.coverURL {
                            AsyncImage(url: coverURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(Color.secondary.opacity(0.2))
                            }
                            .frame(width: 50, height: 75)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .lineLimit(2)

                            let percent = session.bookInfo.characterCount > 0
                                ? (Double(session.currentCharacter) / Double(session.bookInfo.characterCount) * 100)
                                : 0
                            Text("\(session.currentCharacter) / \(session.bookInfo.characterCount) (\(String(format: "%.1f%%", percent)))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            ForEach(rows) { row in
                Button {
                    if let action = session.actionForJumpToChapter(index: row.spineIndex, fragment: row.fragment) {
                        onSelect(action)
                    }
                    dismiss()
                } label: {
                    HStack {
                        Text(row.label)
                            .font(row.indentLevel > 0 ? .subheadline : .body)
                        Spacer()
                        if let count = row.characterCount {
                            Text("\(count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, CGFloat(row.indentLevel) * 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(row.isCurrent ? Color(uiColor: .systemGray5) : nil)
            }
        }
        .navigationTitle(L("reader_reader_menu_chapters"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if rows.isEmpty {
                rows = ReaderEpubChapterRow.makeRows(
                    document: session.document,
                    bookInfo: session.bookInfo,
                    currentIndex: session.index
                )
            }
        }
    }
}

private struct ReaderEpubChapterRow: Identifiable {
    let id = UUID()
    let label: String
    let spineIndex: Int
    let fragment: String?
    let characterCount: Int?
    let isCurrent: Bool
    let indentLevel: Int

    static func makeRows(document: EPUBDocument, bookInfo: BookInfo, currentIndex: Int) -> [ReaderEpubChapterRow] {
        flattenTOC(document: document, bookInfo: bookInfo, currentIndex: currentIndex, items: document.tableOfContents.subTable ?? [], indentLevel: 0)
    }

    private static func flattenTOC(document: EPUBDocument, bookInfo: BookInfo, currentIndex: Int, items: [EPUBTableOfContents], indentLevel: Int) -> [ReaderEpubChapterRow] {
        items.flatMap { item -> [ReaderEpubChapterRow] in
            let row: [ReaderEpubChapterRow]
            if let index = findSpineIndex(document: document, item: item) {
                let parts = item.item?.split(separator: "#", maxSplits: 1)
                let fragment = (parts?.count ?? 0) > 1 ? String(parts![1]) : nil
                row = [
                    ReaderEpubChapterRow(
                        label: item.label,
                        spineIndex: index,
                        fragment: fragment,
                        characterCount: characterCount(bookInfo: bookInfo, item: item),
                        isCurrent: index == currentIndex,
                        indentLevel: indentLevel
                    )
                ]
            } else {
                row = []
            }
            return row + flattenTOC(document: document, bookInfo: bookInfo, currentIndex: currentIndex, items: item.subTable ?? [], indentLevel: indentLevel + 1)
        }
    }

    private static func characterCount(bookInfo: BookInfo, item: EPUBTableOfContents) -> Int? {
        guard let tocPath = item.item else {
            return nil
        }
        let basePath = tocPath.components(separatedBy: "#").first ?? tocPath
        return bookInfo.chapterInfo[basePath]?.currentTotal
    }

    private static func findSpineIndex(document: EPUBDocument, item: EPUBTableOfContents) -> Int? {
        guard let tocPath = item.item else {
            return nil
        }
        let basePath = tocPath.components(separatedBy: "#").first ?? tocPath

        for (index, spineItem) in document.spine.items.enumerated() {
            if let manifestItem = document.manifest.items[spineItem.idref],
               manifestItem.path == basePath || manifestItem.path.hasSuffix(basePath) || basePath.hasSuffix(manifestItem.path) {
                return index
            }
        }
        return nil
    }
}

private struct ReaderEpubWebViewState: Hashable {
    var verticalWriting: Bool
    var fontSize: Int
    var selectedFont: String
    var hideFurigana: Bool
    var horizontalPadding: Int
    var verticalPadding: Int
    var avoidPageBreak: Bool
    var justifyText: Bool
    var lineHeight: Double
    var characterSpacing: Double
    var textColorHex: String
    var size: CGSize
}

private struct ReaderEpubSelectionData {
    let text: String
    let sentence: String
    let rect: CGRect
}

private enum ReaderEpubWebCommand {
    case loadChapter(url: URL, progress: Double, fragment: String?)
    case restoreProgress(Double)
    case jumpToFragment(String)
    case clearHighlight
    case highlightSelection(Int)
}

private final class ReaderEpubWebViewBridge {
    fileprivate var chapterURL: URL?
    fileprivate var progress: Double = 0
    fileprivate var pendingCommands: [ReaderEpubWebCommand] = []
    fileprivate var currentProgressFetcher: (((@escaping (Double) -> Void)) -> Void)?

    func send(_ command: ReaderEpubWebCommand) {
        pendingCommands.append(command)
    }

    func updateState(url: URL, progress: Double) {
        self.chapterURL = url
        self.progress = progress
    }

    func updateProgress(_ progress: Double) {
        self.progress = progress
    }

    func requestCurrentProgress(_ completion: @escaping (Double) -> Void) {
        if let currentProgressFetcher {
            currentProgressFetcher { [weak self] progress in
                self?.progress = progress
                completion(progress)
            }
        } else {
            completion(progress)
        }
    }
}

private struct ReaderEpubScrollWebView: UIViewRepresentable {
    let bridge: ReaderEpubWebViewBridge
    let viewSize: CGSize
    let isVertical: Bool
    let fontFamily: String
    let fontSize: Double
    let hideFurigana: Bool
    let horizontalPadding: Int
    let verticalPadding: Int
    let avoidPageBreak: Bool
    let justifyText: Bool
    let lineHeight: Double
    let characterSpacing: Double
    let textColorHex: String
    let selectionMenuLookupEnabled: Bool
    let selectionMenuAIEnabled: Bool
    var onNextChapter: () -> Bool
    var onPreviousChapter: () -> Bool
    var onSaveBookmark: (Double) -> Void
    var onProgressChange: (Double) -> Void
    var onInternalLink: (URL) -> Bool
    var onInternalJump: (Double) -> Void
    var onTextSelected: (ReaderEpubSelectionData) -> Void
    var onSelectionMenuAction: (SelectedTextAction, SelectedTextSnapshot) -> Void
    var onTapOutside: () -> Void
    var onScroll: () -> Void

    private var selectionMenuActions: [SelectedTextAction] {
        var actions: [SelectedTextAction] = []
        if selectionMenuLookupEnabled {
            actions.append(.lookup)
        }
        if selectionMenuAIEnabled {
            actions.append(.ai)
        }
        return actions
    }

    let maxSelectionLength = 16

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "textSelected")
        configuration.userContentController.add(context.coordinator, name: "restoreCompleted")
        configuration.userContentController.add(context.coordinator, name: "amgiSelectionState")
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile

        let webView = SelectedTextActionWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.delegate = context.coordinator
        webView.scrollView.alwaysBounceVertical = !isVertical
        webView.scrollView.alwaysBounceHorizontal = isVertical
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.navigationDelegate = context.coordinator
        webView.availableSelectionActions = selectionMenuActions
        webView.onSelectionAction = { action, snapshot in
            context.coordinator.handleSelectionMenuAction(action, snapshot: snapshot)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)

        context.coordinator.webView = webView
        webView.alpha = 0
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let menuWebView = webView as? SelectedTextActionWebView {
            menuWebView.availableSelectionActions = selectionMenuActions
        }
        bridge.currentProgressFetcher = { [weak bridge, weak coordinator = context.coordinator] completion in
            guard let coordinator else {
                completion(bridge?.progress ?? 0)
                return
            }
            coordinator.fetchCurrentProgress(completion)
        }

        if !bridge.pendingCommands.isEmpty {
            let commands = bridge.pendingCommands
            bridge.pendingCommands.removeAll()
            for command in commands {
                switch command {
                case let .loadChapter(url, progress, fragment):
                    context.coordinator.currentURL = url
                    context.coordinator.pendingProgress = progress
                    context.coordinator.pendingFragment = fragment
                    if let documentsDirectory = try? BookStorage.getDocumentsDirectory() {
                        bridge.updateState(url: url, progress: progress)
                        webView.scrollView.delegate = nil
                        (webView as? SelectedTextActionWebView)?.currentSelectionSnapshot = nil
                        webView.alpha = 0
                        webView.loadFileURL(url, allowingReadAccessTo: documentsDirectory)
                    }
                case let .restoreProgress(progress):
                    context.coordinator.pendingProgress = progress
                    context.coordinator.pendingFragment = nil
                    context.coordinator.shouldSyncProgressAfterRestore = false
                    bridge.progress = progress
                    webView.evaluateJavaScript("window.hoshiReader.restoreProgress(\(progress))") { (_: Any?, _: Error?) in }
                case let .jumpToFragment(fragment):
                    context.coordinator.jumpToFragment(fragment)
                case .clearHighlight:
                    context.coordinator.clearHighlight()
                case let .highlightSelection(count):
                    context.coordinator.highlightSelection(count: count)
                }
            }
            return
        }

        if context.coordinator.currentURL == nil, let url = bridge.chapterURL {
            context.coordinator.currentURL = url
            context.coordinator.pendingProgress = bridge.progress
            context.coordinator.pendingFragment = nil
            guard let documentsDirectory = try? BookStorage.getDocumentsDirectory() else { return }
            webView.scrollView.delegate = nil
            (webView as? SelectedTextActionWebView)?.currentSelectionSnapshot = nil
            webView.alpha = 0
            webView.loadFileURL(url, allowingReadAccessTo: documentsDirectory)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.parent.bridge.currentProgressFetcher = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "restoreCompleted")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "amgiSelectionState")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
        var parent: ReaderEpubScrollWebView
        weak var webView: WKWebView?
        var currentURL: URL?
        var pendingProgress: Double = 0
        var pendingFragment: String?
        var shouldSyncProgressAfterRestore = false
        private var lastReportedProgress = -1.0

        init(parent: ReaderEpubScrollWebView) {
            self.parent = parent
        }

        func handleSelectionMenuAction(_ action: SelectedTextAction, snapshot: SelectedTextSnapshot) {
            parent.onSelectionMenuAction(action, snapshot)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "restoreCompleted" {
                webView?.scrollView.delegate = self
                if shouldSyncProgressAfterRestore {
                    shouldSyncProgressAfterRestore = false
                    syncLinkJumpProgress()
                }
                UIView.animate(withDuration: 0.25) {
                    message.webView?.alpha = 1
                }
            } else if message.name == "amgiSelectionState" {
                if let body = message.body as? [String: Any],
                   let text = body["text"] as? String {
                    (webView as? SelectedTextActionWebView)?.currentSelectionSnapshot = SelectedTextSnapshot(
                        text: text,
                        sentence: body["sentence"] as? String
                    )
                } else {
                    (webView as? SelectedTextActionWebView)?.currentSelectionSnapshot = nil
                }
            } else if message.name == "textSelected" {
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String,
                      let sentence = body["sentence"] as? String,
                      let rectData = body["rect"] as? [String: Any],
                      let x = rectData["x"] as? CGFloat,
                      let y = rectData["y"] as? CGFloat,
                      let w = rectData["width"] as? CGFloat,
                      let h = rectData["height"] as? CGFloat else {
                    return
                }
                parent.onTextSelected(ReaderEpubSelectionData(text: text, sentence: sentence, rect: CGRect(x: x, y: y, width: w, height: h)))
            }
        }

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if handleInternalLink(url: url) {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let writingMode = parent.isVertical ? "vertical-rl" : "horizontal-tb"
            let textAlign = parent.justifyText ? "justify" : "start"
            let imageWidth = parent.isVertical ? "none" : "\(100 - parent.horizontalPadding)vw"
            let imageHeight = parent.isVertical ? "\(100 - parent.verticalPadding)vh" : "none"

            let css = """
            html {
                -webkit-line-box-contain: block glyphs replaced;
            }
            html, body {
                margin: 0 !important;
                padding: 0 !important;
                writing-mode: \(writingMode) !important;
                color: \(parent.textColorHex) !important;
                background: transparent !important;
                \(parent.isVertical ? "overflow-y: hidden" : "overflow-x: hidden") !important;
            }
            body {
                font-family: \(parent.fontFamily), serif !important;
                font-size: \(parent.fontSize)px !important;
                -webkit-text-size-adjust: none !important;
                line-height: \(parent.lineHeight) !important;
                letter-spacing: \((parent.characterSpacing / 100.0))em !important;
                text-align: \(textAlign) !important;
                box-sizing: border-box !important;
                padding: \(Double(parent.verticalPadding) / 2)vh \(Double(parent.horizontalPadding) / 2)vw !important;
            }
            img.block-img {
                max-width: \(imageWidth) !important;
                max-height: \(imageHeight) !important;
                width: auto !important;
                height: auto !important;
                display: block !important;
                margin: auto !important;
                object-fit: contain !important;
                \(parent.avoidPageBreak ? "break-inside: avoid !important; -webkit-column-break-inside: avoid !important;" : "")
            }
            svg {
                max-width: \(imageWidth) !important;
                max-height: \(imageHeight) !important;
                width: 100% !important;
                height: 100% !important;
                display: block !important;
                margin: auto !important;
            }
            ::highlight(hoshi-selection) {
                background-color: rgba(160, 160, 160, 0.4) !important;
                color: inherit;
            }
            a {
                color: rgba(66, 108, 245, 1) !important;
            }
            \(parent.avoidPageBreak ? "p { break-inside: avoid !important; -webkit-column-break-inside: avoid !important; }" : "")
            """

            let initialRestoreScript: String = {
                if let fragment = pendingFragment {
                    shouldSyncProgressAfterRestore = true
                    return "window.hoshiReader.jumpToFragment(\(javaScriptStringLiteral(fragment)));"
                }
                shouldSyncProgressAfterRestore = false
                return "window.hoshiReader.restoreProgress(\(self.pendingProgress));"
            }()
            pendingFragment = nil

            let script = """
            (function() {
                var viewport = document.querySelector('meta[name="viewport"]');
                if (viewport) { viewport.remove(); }

                var newViewport = document.createElement('meta');
                newViewport.name = 'viewport';
                newViewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(newViewport);

                var style = document.createElement('style');
                style.innerHTML = `\(css)`;
                document.head.appendChild(style);

                \(ReaderEpubScripts.selection)
                \(ReaderEpubScripts.selectionMenuState)
                \(ReaderEpubScripts.reader)
                window.hoshiReader.pageHeight = \(max(Int(parent.viewSize.height), 1));
                window.hoshiReader.pageWidth = \(max(Int(parent.viewSize.width), 1));
                window.hoshiReaderSnapEnabled = false;
                window.hoshiReader.registerCopyText();

                if (\(parent.hideFurigana)) {
                    document.querySelectorAll('rt').forEach(rt => rt.remove());
                }

                document.querySelectorAll('ruby').forEach(ruby => {
                    ruby.childNodes.forEach(node => {
                        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
                            const span = document.createElement('span');
                            span.textContent = node.textContent;
                            node.replaceWith(span);
                        }
                    });
                });

                var images = document.querySelectorAll('img');
                var imagePromises = Array.from(images).map(img => {
                    return new Promise(resolve => {
                        if (img.complete && img.naturalWidth > 0) {
                            if (img.naturalWidth > 256 || img.naturalHeight > 256) {
                                img.classList.add('block-img');
                            }
                            resolve();
                        } else {
                            img.onload = () => {
                                if (img.naturalWidth > 256 || img.naturalHeight > 256) {
                                    img.classList.add('block-img');
                                }
                                resolve();
                            };
                            img.onerror = () => resolve();
                        }
                    });
                });

                Promise.all(imagePromises).then(() => document.fonts.ready).then(() => new Promise(resolve => setTimeout(resolve, 50))).then(() => {
                    \(initialRestoreScript)
                });
            })();
            """

            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let webView, webView.scrollView.isDecelerating == false else {
                return
            }

            let point = gesture.location(in: webView)
            let script = "window.hoshiSelection.selectText(\(point.x), \(point.y), \(parent.maxSelectionLength))"

            webView.evaluateJavaScript(script) { (result: Any?, _: Error?) in
                if result is NSNull || result == nil {
                    self.parent.onTapOutside()
                }
            }
        }

        func saveBookmark() {
            fetchCurrentProgress { [weak self] progress in
                self?.parent.onSaveBookmark(progress)
            }
        }

        private func reportVisibleProgressIfNeeded(for scrollView: UIScrollView, force: Bool = false) {
            let progress = currentProgress(for: scrollView)
            let progressDelta = Swift.abs(progress - lastReportedProgress)
            guard force || progressDelta >= 0.001 else {
                return
            }

            lastReportedProgress = progress
            parent.onProgressChange(progress)
        }

        private func currentProgress(for scrollView: UIScrollView) -> Double {
            let contentExtent = parent.isVertical ? scrollView.contentSize.width : scrollView.contentSize.height
            let viewportExtent = parent.isVertical ? scrollView.bounds.width : scrollView.bounds.height
            let maxOffset = max(contentExtent - viewportExtent, 0)

            guard maxOffset > 0 else {
                return 0
            }

            let rawOffset = parent.isVertical ? scrollView.contentOffset.x : scrollView.contentOffset.y
            let clampedOffset = min(max(rawOffset, 0), maxOffset)
            let normalizedOffset = parent.isVertical ? (maxOffset - clampedOffset) : clampedOffset
            return min(max(normalizedOffset / maxOffset, 0), 1)
        }

        func jumpToFragment(_ fragment: String) {
            guard let webView else { return }
            shouldSyncProgressAfterRestore = true
            webView.evaluateJavaScript("window.hoshiReader.jumpToFragment(\(javaScriptStringLiteral(fragment)))") { (_: Any?, _: Error?) in }
        }

        private func syncLinkJumpProgress() {
            fetchCurrentProgress { [weak self] progress in
                self?.parent.onInternalJump(progress)
            }
        }

        func fetchCurrentProgress(_ completion: @escaping (Double) -> Void) {
            if let scrollView = webView?.scrollView {
                completion(currentProgress(for: scrollView))
                return
            }

            completion(0)
        }

        private func javaScriptStringLiteral(_ value: String) -> String {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "'\(escaped)'"
        }

        @discardableResult
        private func handleInternalLink(url: URL) -> Bool {
            if url.isFileURL {
                return parent.onInternalLink(url)
            }

            guard let scheme = url.scheme?.lowercased() else {
                return false
            }
            if scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                return true
            }
            return false
        }

        func highlightSelection(count: Int) {
            guard let webView else { return }
            webView.evaluateJavaScript("window.hoshiSelection.highlightSelection(\(count))") { (_: Any?, _: Error?) in }
        }

        func clearHighlight() {
            guard let webView else { return }
            webView.evaluateJavaScript("window.hoshiSelection.clearHighlight()") { (_: Any?, _: Error?) in }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let offset = parent.isVertical ? scrollView.contentOffset.x : scrollView.contentOffset.y
            let contentSize = parent.isVertical ? scrollView.contentSize.width : scrollView.contentSize.height
            let viewSize = parent.isVertical ? scrollView.bounds.width : scrollView.bounds.height
            let maxOffset = max(contentSize - viewSize, 0)
            let threshold: CGFloat = 20

            let scrolledPastEnd = parent.isVertical ? offset < -threshold : offset > maxOffset + threshold
            let scrolledPastStart = parent.isVertical ? offset > maxOffset + threshold : offset < -threshold

            if scrolledPastEnd {
                webView?.scrollView.delegate = nil
                if parent.onNextChapter() {
                    webView?.alpha = 0
                } else {
                    webView?.scrollView.delegate = self
                }
            } else if scrolledPastStart {
                webView?.scrollView.delegate = nil
                if parent.onPreviousChapter() {
                    webView?.alpha = 0
                } else {
                    webView?.scrollView.delegate = self
                }
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            reportVisibleProgressIfNeeded(for: scrollView, force: true)
            parent.onScroll()
            saveBookmark()
            clearHighlight()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if decelerate == false {
                reportVisibleProgressIfNeeded(for: scrollView, force: true)
                parent.onScroll()
                saveBookmark()
                clearHighlight()
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportVisibleProgressIfNeeded(for: scrollView)
        }
    }
}

private struct ReaderEpubWebView: UIViewRepresentable {
    let bridge: ReaderEpubWebViewBridge
    let viewSize: CGSize
    let isVertical: Bool
    let fontFamily: String
    let fontSize: Double
    let hideFurigana: Bool
    let horizontalPadding: Int
    let verticalPadding: Int
    let avoidPageBreak: Bool
    let justifyText: Bool
    let lineHeight: Double
    let characterSpacing: Double
    let textColorHex: String
    var onNextChapter: () -> Bool
    var onPreviousChapter: () -> Bool
    var onSaveBookmark: (Double) -> Void
    var onInternalLink: (URL) -> Bool
    var onInternalJump: (Double) -> Void
    var onTextSelected: (ReaderEpubSelectionData) -> Void
    var onTapOutside: () -> Void
    var onPageTurn: () -> Void

    let maxSelectionLength = 16

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "textSelected")
        configuration.userContentController.add(context.coordinator, name: "restoreCompleted")
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator

        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft(_:)))
        swipeLeft.direction = .left
        swipeLeft.delegate = context.coordinator
        webView.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight(_:)))
        swipeRight.direction = .right
        swipeRight.delegate = context.coordinator
        webView.addGestureRecognizer(swipeRight)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.require(toFail: swipeLeft)
        tap.require(toFail: swipeRight)
        webView.addGestureRecognizer(tap)

        context.coordinator.webView = webView
        webView.alpha = 0
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        if !bridge.pendingCommands.isEmpty {
            let commands = bridge.pendingCommands
            bridge.pendingCommands.removeAll()
            for command in commands {
                switch command {
                case let .loadChapter(url, progress, fragment):
                    context.coordinator.currentURL = url
                    context.coordinator.pendingProgress = progress
                    context.coordinator.pendingFragment = fragment
                    if let documentsDirectory = try? BookStorage.getDocumentsDirectory() {
                        bridge.updateState(url: url, progress: progress)
                        webView.alpha = 0
                        webView.loadFileURL(url, allowingReadAccessTo: documentsDirectory)
                    }
                case let .restoreProgress(progress):
                    context.coordinator.pendingProgress = progress
                    context.coordinator.pendingFragment = nil
                    context.coordinator.shouldSyncProgressAfterRestore = false
                    bridge.progress = progress
                    webView.evaluateJavaScript("window.hoshiReader.restoreProgress(\(progress))") { (_: Any?, _: Error?) in }
                case let .jumpToFragment(fragment):
                    context.coordinator.jumpToFragment(fragment)
                case .clearHighlight:
                    context.coordinator.clearHighlight()
                case let .highlightSelection(count):
                    context.coordinator.highlightSelection(count: count)
                }
            }
            return
        }

        if context.coordinator.currentURL == nil, let url = bridge.chapterURL {
            context.coordinator.currentURL = url
            context.coordinator.pendingProgress = bridge.progress
            context.coordinator.pendingFragment = nil
            guard let documentsDirectory = try? BookStorage.getDocumentsDirectory() else { return }
            webView.alpha = 0
            webView.loadFileURL(url, allowingReadAccessTo: documentsDirectory)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "textSelected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "restoreCompleted")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate, WKScriptMessageHandler {
        var parent: ReaderEpubWebView
        weak var webView: WKWebView?
        var currentURL: URL?
        var pendingProgress: Double = 0
        var pendingFragment: String?
        var shouldSyncProgressAfterRestore = false

        init(parent: ReaderEpubWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "restoreCompleted" {
                if shouldSyncProgressAfterRestore {
                    shouldSyncProgressAfterRestore = false
                    syncLinkJumpProgress()
                }
                UIView.animate(withDuration: 0.25) {
                    message.webView?.alpha = 1
                }
            } else if message.name == "textSelected" {
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String,
                      let sentence = body["sentence"] as? String,
                      let rectData = body["rect"] as? [String: Any],
                      let x = rectData["x"] as? CGFloat,
                      let y = rectData["y"] as? CGFloat,
                      let w = rectData["width"] as? CGFloat,
                      let h = rectData["height"] as? CGFloat else {
                    return
                }
                parent.onTextSelected(ReaderEpubSelectionData(text: text, sentence: sentence, rect: CGRect(x: x, y: y, width: w, height: h)))
            }
        }

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if handleInternalLink(url: url) {
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let pageHeight = max(Int(parent.viewSize.height), 1)
            let pageWidth = max(Int(parent.viewSize.width), 1)
            let writingMode = parent.isVertical ? "vertical-rl" : "horizontal-tb"
            let columnGapUnit = parent.isVertical ? "vh" : "vw"
            let columnGapValue = parent.isVertical ? parent.verticalPadding : parent.horizontalPadding
            let textAlign = parent.justifyText ? "justify" : "start"

            let css = """
            html {
                -webkit-line-box-contain: block glyphs replaced;
            }
            html, body {
                overflow: hidden !important;
                height: var(--page-height, 100vh) !important;
                width: var(--page-width, 100vw) !important;
                margin: 0 !important;
                padding: 0 !important;
                writing-mode: \(writingMode) !important;
                color: \(parent.textColorHex) !important;
                background: transparent !important;
            }
            body {
                font-family: \(parent.fontFamily), serif !important;
                font-size: \(parent.fontSize)px !important;
                -webkit-text-size-adjust: none !important;
                line-height: \(parent.lineHeight) !important;
                letter-spacing: \((parent.characterSpacing / 100.0))em !important;
                text-align: \(textAlign) !important;
                box-sizing: border-box !important;
                column-width: var(--page-width, 100vw) !important;
                column-gap: \(columnGapValue)\(columnGapUnit);
                padding: \(Double(parent.verticalPadding) / 2)vh \(Double(parent.horizontalPadding) / 2)vw !important;
            }
            img.block-img {
                max-width: \(100 - parent.horizontalPadding)vw !important;
                max-height: \(100 - parent.verticalPadding)vh !important;
                width: auto !important;
                height: auto !important;
                display: block !important;
                margin: auto !important;
                break-inside: avoid !important;
                -webkit-column-break-inside: avoid !important;
                object-fit: contain !important;
            }
            svg {
                max-width: \(100 - parent.horizontalPadding)vw !important;
                max-height: \(100 - parent.verticalPadding)vh !important;
                width: 100% !important;
                height: 100% !important;
                display: block !important;
                margin: auto !important;
                break-inside: avoid !important;
                -webkit-column-break-inside: avoid !important;
            }
            ::highlight(hoshi-selection) {
                background-color: rgba(160, 160, 160, 0.4) !important;
                color: inherit;
            }
            a {
                color: rgba(66, 108, 245, 1) !important;
            }
            \(parent.avoidPageBreak ? "p { break-inside: avoid !important; -webkit-column-break-inside: avoid !important; }" : "")
            """

            let initialRestoreScript: String = {
                if let fragment = pendingFragment {
                    shouldSyncProgressAfterRestore = true
                    return "window.hoshiReader.jumpToFragment(\(javaScriptStringLiteral(fragment)));"
                }
                shouldSyncProgressAfterRestore = false
                return "window.hoshiReader.restoreProgress(\(self.pendingProgress));"
            }()
            pendingFragment = nil

            let script = """
            (function() {
                var viewport = document.querySelector('meta[name="viewport"]');
                if (viewport) { viewport.remove(); }

                var newViewport = document.createElement('meta');
                newViewport.name = 'viewport';
                newViewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(newViewport);

                document.documentElement.style.setProperty('--page-height', '\(pageHeight)px');
                document.documentElement.style.setProperty('--page-width', '\(pageWidth)px');

                var style = document.createElement('style');
                style.innerHTML = `\(css)`;
                document.head.appendChild(style);

                \(ReaderEpubScripts.selection)
                \(ReaderEpubScripts.reader)
                window.hoshiReader.pageHeight = \(pageHeight);
                window.hoshiReader.pageWidth = \(pageWidth);
                window.hoshiReaderSnapEnabled = true;
                window.hoshiReader.registerCopyText();

                if (\(parent.hideFurigana)) {
                    document.querySelectorAll('rt').forEach(rt => rt.remove());
                }

                document.querySelectorAll('ruby').forEach(ruby => {
                    ruby.childNodes.forEach(node => {
                        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim()) {
                            const span = document.createElement('span');
                            span.textContent = node.textContent;
                            node.replaceWith(span);
                        }
                    });
                });

                var images = document.querySelectorAll('img');
                var imagePromises = Array.from(images).map(img => {
                    return new Promise(resolve => {
                        if (img.complete && img.naturalWidth > 0) {
                            if (img.naturalWidth > 256 || img.naturalHeight > 256) {
                                img.classList.add('block-img');
                            }
                            resolve();
                        } else {
                            img.onload = () => {
                                if (img.naturalWidth > 256 || img.naturalHeight > 256) {
                                    img.classList.add('block-img');
                                }
                                resolve();
                            };
                            img.onerror = () => resolve();
                        }
                    });
                });

                Promise.all(imagePromises).then(() => document.fonts.ready).then(() => new Promise(resolve => setTimeout(resolve, 50))).then(() => {
                    \(initialRestoreScript)
                });
            })();
            """

            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func navigate(_ direction: NavigationDirection) {
            guard let webView else { return }

            clearHighlight()

            let script = paginationScript(direction: direction)
            webView.evaluateJavaScript(script) { [weak self] (result: Any?, _: Error?) in
                guard let self else { return }

                if let res = result as? String, res == "scrolled" {
                    self.parent.onPageTurn()
                    self.saveBookmark()
                } else {
                    let chapterChanged = direction == .forward ? self.parent.onNextChapter() : self.parent.onPreviousChapter()
                    if chapterChanged {
                        webView.alpha = 0
                    }
                }
            }
        }

        private func paginationScript(direction: NavigationDirection) -> String {
            let jsDirection = direction == .forward ? "forward" : "backward"
            return """
            (function() {
                if (!window.hoshiReader || typeof window.hoshiReader.paginate !== 'function') {
                    return "limit";
                }
                return window.hoshiReader.paginate('\(jsDirection)');
            })()
            """
        }

        @objc func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
            navigate(parent.isVertical ? .backward : .forward)
        }

        @objc func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
            navigate(parent.isVertical ? .forward : .backward)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let webView else { return }

            let point = gesture.location(in: webView)
            let script = "window.hoshiSelection.selectText(\(point.x), \(point.y), \(parent.maxSelectionLength))"

            webView.evaluateJavaScript(script) { (result: Any?, _: Error?) in
                if result is NSNull || result == nil {
                    self.parent.onTapOutside()
                }
            }
        }

        func saveBookmark() {
            fetchCurrentProgress { [weak self] progress in
                self?.parent.onSaveBookmark(progress)
            }
        }

        func jumpToFragment(_ fragment: String) {
            guard let webView else { return }
            shouldSyncProgressAfterRestore = true
            webView.evaluateJavaScript("window.hoshiReader.jumpToFragment(\(javaScriptStringLiteral(fragment)))") { (_: Any?, _: Error?) in }
        }

        private func syncLinkJumpProgress() {
            fetchCurrentProgress { [weak self] progress in
                self?.parent.onInternalJump(progress)
            }
        }

        private func fetchCurrentProgress(_ completion: @escaping (Double) -> Void) {
            guard let webView else { return }
            webView.evaluateJavaScript("window.hoshiReader.calculateProgress()") { (result: Any?, _: Error?) in
                guard let progress = result as? Double else { return }
                completion(progress)
            }
        }

        private func javaScriptStringLiteral(_ value: String) -> String {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            return "'\(escaped)'"
        }

        @discardableResult
        private func handleInternalLink(url: URL) -> Bool {
            if url.isFileURL {
                return parent.onInternalLink(url)
            }

            guard let scheme = url.scheme?.lowercased() else {
                return false
            }
            if scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                return true
            }
            return false
        }

        func highlightSelection(count: Int) {
            guard let webView else { return }
            webView.evaluateJavaScript("window.hoshiSelection.highlightSelection(\(count))") { (_: Any?, _: Error?) in }
        }

        func clearHighlight() {
            guard let webView else { return }
            webView.evaluateJavaScript("window.hoshiSelection.clearHighlight()") { (_: Any?, _: Error?) in }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct ReaderEpubChromeIconLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.headline.weight(.semibold))
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
    }
}

private struct ReaderEpubChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private extension View {
    func readerEpubChromeButtonStyle() -> some View {
        buttonStyle(ReaderEpubChromeButtonStyle())
    }
}

private extension UIApplication {
    static var readerEpubSafeAreaInsets: UIEdgeInsets {
        shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    static var readerEpubTopSafeArea: CGFloat {
        readerEpubSafeAreaInsets.top
    }

    static var readerEpubBottomSafeArea: CGFloat {
        readerEpubSafeAreaInsets.bottom
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

private enum ReaderEpubScripts {
    static let selection = #"""
window.hoshiSelection = {
    selection: null,
    scanDelimiters: '。、！？…‥「」『』（）()【】〈〉《》〔〕｛｝{}［］[]・：；:;，,.─\n\r',
    sentenceDelimiters: '。！？.!?\n\r',
    isVertical() {
        return window.getComputedStyle(document.body).writingMode === "vertical-rl";
    },
    isScanBoundary(char) {
        return /^[\s\u3000]$/.test(char) || this.scanDelimiters.includes(char);
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
            acceptNode: (n) => this.isFurigana(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
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
            if (!pos) return null;
            const range = document.createRange();
            range.setStart(pos.offsetNode, pos.offset);
            range.collapse(true);
            return range;
        }
        const element = document.elementFromPoint(x, y);
        if (!element) return null;
        const container = element.closest('p, div, span, ruby, a') || document.body;
        const walker = this.createWalker(container);
        const range = document.createRange();
        let node;
        while (node = walker.nextNode()) {
            for (let i = 0; i < node.textContent.length; i++) {
                range.setStart(node, i);
                range.setEnd(node, i + 1);
                if (this.inCharRange(range, x, y)) {
                    range.collapse(true);
                    return range;
                }
            }
        }
        return document.caretRangeFromPoint(x, y);
    },
    getCharacterAtPoint(x, y) {
        const range = this.getCaretRange(x, y);
        if (!range) return null;
        const node = range.startContainer;
        if (node.nodeType !== Node.TEXT_NODE || this.isFurigana(node)) return null;
        const text = node.textContent;
        const caret = range.startOffset;
        for (const offset of [caret, caret - 1, caret + 1]) {
            if (offset < 0 || offset >= text.length) continue;
            const charRange = document.createRange();
            charRange.setStart(node, offset);
            charRange.setEnd(node, offset + 1);
            if (this.inCharRange(charRange, x, y)) {
                if (this.isScanBoundary(text[offset])) return null;
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
            const text = node.textContent;
            let foundStart = false;
            for (let i = limit - 1; i >= 0; i--) {
                if (this.sentenceDelimiters.includes(text[i])) {
                    partsBefore.push(text.slice(i + 1, limit));
                    foundStart = true;
                    break;
                }
            }
            if (foundStart) break;
            partsBefore.push(text.slice(0, limit));
            node = walker.previousNode();
            if (node) limit = node.textContent.length;
        }
        walker.currentNode = startNode;
        const partsAfter = [];
        node = startNode;
        let start = startOffset;
        while (node) {
            const text = node.textContent;
            let foundEnd = false;
            for (let i = start; i < text.length; i++) {
                if (this.sentenceDelimiters.includes(text[i])) {
                    let end = i + 1;
                    while (end < text.length) {
                        if (!trailingSentenceChars.includes(text[end])) break;
                        end += 1;
                    }
                    partsAfter.push(text.slice(start, end));
                    foundEnd = true;
                    break;
                }
            }
            if (foundEnd) break;
            partsAfter.push(text.slice(start));
            node = walker.nextNode();
            start = 0;
        }
        return (partsBefore.reverse().join('') + partsAfter.join('')).trim();
    },
    selectText(x, y, maxLength) {
        const hit = this.getCharacterAtPoint(x, y);
        if (!hit) {
            this.clearHighlight();
            return null;
        }
        if (this.selection && hit.node === this.selection.startNode && hit.offset === this.selection.startOffset) {
            this.clearHighlight();
            return null;
        }
        this.clearHighlight();
        const container = this.findParagraph(hit.node) || document.body;
        const walker = this.createWalker(container);
        let text = '';
        let node = hit.node;
        let offset = hit.offset;
        let ranges = [];
        walker.currentNode = node;
        while (text.length < maxLength && node) {
            const content = node.textContent;
            const start = offset;
            while (offset < content.length && text.length < maxLength) {
                const char = content[offset];
                if (this.isScanBoundary(char)) break;
                text += char;
                offset++;
            }
            if (offset > start) ranges.push({ node, start, end: offset });
            if (offset < content.length || text.length >= maxLength) break;
            node = walker.nextNode();
            offset = 0;
        }
        if (!text) return null;
        this.selection = { startNode: hit.node, startOffset: hit.offset, ranges, text };
        const sentence = this.getSentence(hit.node, hit.offset);
        webkit.messageHandlers.textSelected.postMessage({ text, sentence, rect: this.getSelectionRect(x, y) });
        return text;
    },
    getSelectionRect(x, y) {
        if (!this.selection?.ranges.length) return null;
        const first = this.selection.ranges[0];
        const range = document.createRange();
        range.setStart(first.node, first.start);
        range.setEnd(first.node, first.start + 1);
        const rects = Array.from(range.getClientRects());
        const rect = rects.find(rect => x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) ?? range.getBoundingClientRect();
        return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    },
    highlightSelection(charCount) {
        if (!this.selection?.ranges.length) return;
        const highlights = [];
        let remaining = charCount;
        for (const r of this.selection.ranges) {
            if (remaining <= 0) break;
            const length = r.end - r.start;
            const end = remaining >= length ? r.end : r.start + remaining;
            const range = document.createRange();
            range.setStart(r.node, r.start);
            range.setEnd(r.node, end);
            highlights.push(range);
            remaining -= length;
        }
        CSS.highlights?.set('hoshi-selection', new Highlight(...highlights));
    },
    clearHighlight() {
        window.getSelection()?.removeAllRanges();
        CSS.highlights?.clear();
        this.selection = null;
    }
};
"""#

    static let selectionMenuState = #"""
(function() {
    function postSelectionState() {
        const selection = window.getSelection ? window.getSelection() : null;
        const text = selection ? String(selection).trim() : '';
        if (!selection || !text || selection.rangeCount === 0) {
            webkit.messageHandlers.amgiSelectionState.postMessage(null);
            return;
        }

        let sentence = (() => {
            try {
                const range = selection.getRangeAt(0);
                return window.hoshiSelection?.getSentence(range.startContainer, range.startOffset) || null;
            } catch (_) {
                return null;
            }
        })();

        webkit.messageHandlers.amgiSelectionState.postMessage({ text, sentence });
    }

    document.addEventListener('selectionchange', () => {
        window.requestAnimationFrame(postSelectionState);
    });
    document.addEventListener('pointerup', () => {
        window.requestAnimationFrame(postSelectionState);
    });
})();
"""#

    static let reader = #"""
window.hoshiReader = {
    ttuRegex: /[^0-9A-Z○◯々-〇〻ぁ-ゖゝ-ゞァ-ヺー０-９Ａ-Ｚｦ-ﾝ\p{Radical}\p{Unified_Ideograph}]+/gimu,
    isVertical() {
        return window.getComputedStyle(document.body).writingMode === "vertical-rl";
    },
    shouldSnapPages() {
        return window.hoshiReaderSnapEnabled !== false;
    },
    isFurigana(node) {
        const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
        return !!el?.closest('rt, rp');
    },
    countChars(text) {
        return text.replace(this.ttuRegex, '').length;
    },
    createWalker(rootNode) {
        const root = rootNode || document.body;
        return document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: (n) => this.isFurigana(n) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
        });
    },
    getRect(target) {
        const rect = target.getClientRects()[0];
        return rect || target.getBoundingClientRect();
    },
    usesHorizontalScroll(vertical) {
        return this.shouldSnapPages() ? !vertical : vertical;
    },
    usesReverseProgress(context) {
        return context.vertical && !this.shouldSnapPages();
    },
    currentScroll(context) {
        if (context.horizontalScroll) {
            return this.shouldSnapPages() ? context.scrollEl.scrollLeft : window.scrollX;
        }
        return this.shouldSnapPages() ? context.scrollEl.scrollTop : window.scrollY;
    },
    calculateProgress() {
        var vertical = this.isVertical();
        var walker = this.createWalker();
        var totalChars = 0;
        var exploredChars = 0;
        var node;

        while (node = walker.nextNode()) {
            var nodeLen = this.countChars(node.textContent);
            totalChars += nodeLen;

            if (nodeLen > 0) {
                var range = document.createRange();
                range.selectNodeContents(node);
                var rect = this.shouldSnapPages() ? this.getRect(range) : range.getBoundingClientRect();
                var isExplored = this.shouldSnapPages()
                    ? ((vertical ? rect.top : rect.left) < 0)
                    : (vertical ? (rect.left > window.innerWidth) : (rect.bottom < 0));
                if (isExplored) {
                    exploredChars += nodeLen;
                }
            }
        }

        return totalChars > 0 ? exploredChars / totalChars : 0;
    },
    registerSnapScroll(initialScroll) {
        if (!this.shouldSnapPages()) return;
        if (window.snapScrollRegistered) return;
        window.snapScrollRegistered = true;
        window.lastPageScroll = initialScroll;
        var vertical = this.isVertical();
        var horizontalScroll = this.usesHorizontalScroll(vertical);
        var pageSize = horizontalScroll ? this.pageWidth : this.pageHeight;
        document.body.addEventListener('scroll', function () {
            if (horizontalScroll) {
                var currentScroll = document.body.scrollLeft;
                var snappedScroll = Math.round(currentScroll / pageSize) * pageSize;
                if (Math.abs(currentScroll - snappedScroll) > 1) {
                    document.body.scrollLeft = window.lastPageScroll;
                } else {
                    window.lastPageScroll = snappedScroll;
                }
            } else {
                var currentScroll = document.body.scrollTop;
                var snappedScroll = Math.round(currentScroll / pageSize) * pageSize;
                if (Math.abs(currentScroll - snappedScroll) > 1) {
                    document.body.scrollTop = window.lastPageScroll;
                } else {
                    window.lastPageScroll = snappedScroll;
                }
            }
        }, { passive: true });
    },
    registerCopyText() {
        if (window.copyTextRegistered) return;
        window.copyTextRegistered = true;
        document.addEventListener('copy', function (event) {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) return;
            const fragment = selection.getRangeAt(0).cloneContents();
            fragment.querySelectorAll('rt, rp').forEach(el => el.remove());
            const text = fragment.textContent;
            if (!text) return;
            event.preventDefault();
            event.clipboardData.setData('text/plain', text);
        }, true);
    },
    notifyRestoreComplete() {
        window.webkit?.messageHandlers?.restoreCompleted?.postMessage(null);
    },
    getScrollContext() {
        var vertical = this.isVertical();
        var horizontalScroll = this.usesHorizontalScroll(vertical);
        var scrollEl = document.body;
        var pageSize = horizontalScroll ? this.pageWidth : this.pageHeight;
        var totalSize = horizontalScroll ? scrollEl.scrollWidth : scrollEl.scrollHeight;
        var maxScroll = Math.max(0, totalSize - pageSize);
        return { vertical, horizontalScroll, scrollEl, pageSize, maxScroll };
    },
    setScrollOffset(context, scroll) {
        var clampedScroll = Math.min(Math.max(0, scroll), context.maxScroll);
        if (this.shouldSnapPages()) {
            if (context.horizontalScroll) {
                context.scrollEl.scrollLeft = clampedScroll;
            } else {
                context.scrollEl.scrollTop = clampedScroll;
            }
        } else {
            if (context.horizontalScroll) {
                window.scrollTo(clampedScroll, 0);
            } else {
                window.scrollTo(0, clampedScroll);
            }
        }
        return clampedScroll;
    },
    alignToPage(context, anchor) {
        if (!this.shouldSnapPages()) {
            return Math.min(Math.max(0, anchor), context.maxScroll);
        }
        if (context.pageSize <= 0) return 0;
        var pageIndex = Math.floor(Math.max(0, anchor) / context.pageSize);
        return Math.min(Math.max(0, pageIndex * context.pageSize), context.maxScroll);
    },
    paginate(direction) {
        var vertical = this.isVertical();
        var horizontalScroll = this.usesHorizontalScroll(vertical);
        var pageSize = horizontalScroll ? this.pageWidth : this.pageHeight;
        if (pageSize <= 0) return 'limit';
        if (direction === 'forward') {
            var totalSize = horizontalScroll ? document.body.scrollWidth : document.body.scrollHeight;
            var maxScroll = Math.max(0, totalSize - pageSize);
            var maxAlignedScroll = Math.floor(maxScroll / pageSize) * pageSize;
            var currentScroll = horizontalScroll ? document.body.scrollLeft : document.body.scrollTop;
            if (vertical) {
                if ((currentScroll + pageSize) <= (maxAlignedScroll + 1)) {
                    document.body.scrollTop += pageSize;
                    return 'scrolled';
                }
                return 'limit';
            }
            if ((currentScroll + pageSize) <= (maxAlignedScroll + 1)) {
                if (horizontalScroll) {
                    document.body.scrollLeft += pageSize;
                } else {
                    document.body.scrollTop += pageSize;
                }
                return 'scrolled';
            }
            return 'limit';
        }
        var currentScroll = horizontalScroll ? document.body.scrollLeft : document.body.scrollTop;
        if (vertical) {
            if (currentScroll > 0) {
                document.body.scrollTop -= pageSize;
                return 'scrolled';
            }
            return 'limit';
        }
        if (currentScroll > 0) {
            if (horizontalScroll) {
                document.body.scrollLeft -= pageSize;
            } else {
                document.body.scrollTop -= pageSize;
            }
            return 'scrolled';
        }
        return 'limit';
    },
    async restoreProgress(progress) {
        await document.fonts.ready;

        if (!this.shouldSnapPages()) {
            if (progress <= 0) {
                this.notifyRestoreComplete();
                return;
            }

            var walker = this.createWalker();
            var totalChars = 0;
            var node;

            while (node = walker.nextNode()) {
                totalChars += this.countChars(node.textContent);
            }

            if (totalChars <= 0) {
                this.notifyRestoreComplete();
                return;
            }

            var targetCharCount = Math.ceil(totalChars * progress);
            var runningSum = 0;
            var targetNode = null;

            walker = this.createWalker();
            while (node = walker.nextNode()) {
                runningSum += this.countChars(node.textContent);
                targetNode = node;
                if (runningSum > targetCharCount) {
                    break;
                }
            }

            if (targetNode) {
                var el = targetNode.parentElement;
                if (el) {
                    el.scrollIntoView({
                        block: progress >= 0.999999 ? 'end' : 'start',
                        behavior: 'instant'
                    });
                }
            }

            requestAnimationFrame(() => {
                requestAnimationFrame(() => this.notifyRestoreComplete());
            });
            return;
        }

        var context = this.getScrollContext();

        if (context.pageSize <= 0) {
            this.registerSnapScroll(0);
            this.notifyRestoreComplete();
            return;
        }

        if (progress <= 0) {
            this.setScrollOffset(context, 0);
            this.registerSnapScroll(0);
            this.notifyRestoreComplete();
            return;
        }

        if (progress >= 0.99) {
            var lastPage = Math.floor(context.maxScroll / context.pageSize) * context.pageSize;
            lastPage = Math.max(0, lastPage);
            this.setScrollOffset(context, lastPage);
            requestAnimationFrame(() => {
                this.setScrollOffset(context, lastPage);
                this.registerSnapScroll(lastPage);
                requestAnimationFrame(() => this.notifyRestoreComplete());
            });
            return;
        }

        var walker = this.createWalker();
        var totalChars = 0;
        var node;

        while (node = walker.nextNode()) {
            totalChars += this.countChars(node.textContent);
        }

        if (totalChars <= 0) {
            this.registerSnapScroll(0);
            this.notifyRestoreComplete();
            return;
        }

        var targetCharCount = Math.ceil(totalChars * progress);
        var runningSum = 0;
        var targetNode = null;

        walker = this.createWalker();
        while (node = walker.nextNode()) {
            runningSum += this.countChars(node.textContent);
            if (runningSum > targetCharCount) {
                targetNode = node;
                break;
            }
        }

        if (targetNode) {
            var range = document.createRange();
            range.setStart(targetNode, 0);
            range.setEnd(targetNode, 1);
            var rect = this.getRect(range);
            var anchor = (context.vertical ? rect.top : rect.left) + (context.vertical ? context.scrollEl.scrollTop : context.scrollEl.scrollLeft);
            var targetScroll = this.alignToPage(context, anchor);

            this.setScrollOffset(context, targetScroll);
            requestAnimationFrame(() => {
                this.setScrollOffset(context, targetScroll);
                this.registerSnapScroll(targetScroll);
            });
        } else {
            this.registerSnapScroll(0);
        }

        requestAnimationFrame(() => {
            requestAnimationFrame(() => this.notifyRestoreComplete());
        });
    },
    jumpToFragment(fragment) {
        var context = this.getScrollContext();
        var rawFragment = (fragment || '').trim();
        var target = rawFragment && (document.getElementById(rawFragment) || document.getElementsByName(rawFragment)[0]);
        if (context.pageSize <= 0 || !target) {
            this.registerSnapScroll(0);
            this.notifyRestoreComplete();
            return false;
        }
        var rect = target.getBoundingClientRect();
        var currentScroll = this.currentScroll(context);
        var anchor = (context.horizontalScroll ? rect.left : rect.top) + currentScroll;
        var targetScroll = this.alignToPage(context, anchor);
        this.setScrollOffset(context, targetScroll);
        requestAnimationFrame(() => {
            this.setScrollOffset(context, targetScroll);
            this.registerSnapScroll(targetScroll);
            this.notifyRestoreComplete();
        });
        return true;
    }
};
"""#
}

private enum NavigationDirection {
    case forward
    case backward
}

private struct ReaderEpubStatisticsView: View {
    @Bindable var session: ReaderEpubSession

    var body: some View {
        List {
            Section(L("reader_statistics_session")) {
                statisticsRow(title: L("reader_statistics_characters"), value: session.sessionStatistics.charactersRead.formatted(.number.grouping(.never)))
                statisticsRow(title: L("reader_statistics_reading_speed"), value: "\(session.sessionStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h")
                statisticsRow(title: L("reader_statistics_reading_time"), value: Duration.seconds(session.sessionStatistics.readingTime).formatted())

                Button(session.isTracking ? L("reader_statistics_tracking_stop") : L("reader_statistics_tracking_start")) {
                    if session.isTracking {
                        session.stopTracking()
                    } else {
                        session.startTracking()
                    }
                }
            }

            Section(L("reader_statistics_today")) {
                statisticsRow(title: L("reader_statistics_characters"), value: session.todaysStatistics.charactersRead.formatted(.number.grouping(.never)))
                statisticsRow(title: L("reader_statistics_reading_speed"), value: "\(session.todaysStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h")
                statisticsRow(title: L("reader_statistics_reading_time"), value: Duration.seconds(session.todaysStatistics.readingTime).formatted())
            }

            Section(L("reader_statistics_all_time")) {
                statisticsRow(title: L("reader_statistics_characters"), value: session.allTimeStatistics.charactersRead.formatted(.number.grouping(.never)))
                statisticsRow(title: L("reader_statistics_reading_speed"), value: "\(session.allTimeStatistics.lastReadingSpeed.formatted(.number.grouping(.never))) / h")
                statisticsRow(title: L("reader_statistics_reading_time"), value: Duration.seconds(session.allTimeStatistics.readingTime).formatted())
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("reader_statistics_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statisticsRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AmgiSpacing.md) {
            Text(title)
                .foregroundStyle(SettingsValueStyle.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(SettingsValueStyle.secondary)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}
