import SwiftUI
import Charts
import AVFAudio
import AnkiBackend
import AnkiKit
import AnkiClients
import AnkiServices
import AmgiReader
import AnkiProto
import SwiftProtobuf
import Dependencies
import UIKit
import GameController

struct ReviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let deckId: Int64
    let onDismiss: () -> Void

    @Dependency(\.noteClient) var noteClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.tagClient) var tagClient
    @Dependency(\.notetypesClient) var notetypesClient
    @Dependency(\.notetypesService) var notetypesService
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.dictionaryLookupClient) var dictionaryLookupClient

    @State private var session: ReviewSession
    @State private var editingNote: NoteRecord?
    @State private var showCardInfo = false
    @State private var currentCardStatsTarget: ReviewCardStatsTarget?
    @State private var replayRequestID = 0
    @State private var stopAudioRequestID = 0
    @State private var isAudioPlaying = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var answerFeedbackSymbol: String?
    @State private var showDeckStats = false
    @State private var templateEditorTarget: ReviewTemplateEditorTarget?
    @State private var showMoveToDeck = false
    @State private var availableDecks: [DeckInfo] = []
    @State private var changeNotetypeTarget: AnkiClients.ChangeNotetypeTarget?
    @State private var fieldManagerTarget: ReviewFieldManagerTarget?
    @State private var toolbarErrorMessage: String?
    @State private var showToolbarError = false
    @State private var ankiJSToastState: AnkiJSToastState?
    @State private var ankiJSToastDismissTask: Task<Void, Never>?
    @State private var showDeleteNoteConfirm = false
    @State private var showTriggeredContextMenu = false
    @State private var showUndoError = false
    @State private var undoErrorMessage: String?
    @State private var isUndoing = false
    @State private var showSetDueDateSheet = false
    @State private var setDueDateInput = ""
    @State private var setDueDateCardID: Int64?
    @State private var typedAnswerRequestID = 0
    @State private var userActionRequestID = 0
    @State private var pendingUserActionIndex: Int?
    @State private var isKeyboardVisible = false
    @State private var cardChromeUIColor: UIColor = .systemBackground
    @State private var cardChromeIsDark = false
    @State private var autoAdvanceDeadline: Date?
    @State private var lookupStack: [ReaderLookupPopupState] = []
    @State private var lookupErrorMessage: String?
    @State private var showLookupError = false
    @State private var selectionAIState: ReviewSelectionAIState?
    @State private var pendingAIAddNoteDraft: ReviewAIAddNoteSheetDraft?
    @State private var queuedAIAddNoteDraft: ReviewAIAddNoteSheetDraft?
    @State private var currentDeckName: String?
    @State private var ankiJSSearchSheetRequest: AnkiJSSearchSheetRequest?
    @State private var aiFavoriteRefreshToken = 0
    @State private var controllerMonitor = ReviewControllerMonitor()
    @State private var keyboardMonitor = ReviewKeyboardMonitor()
    @State private var reviewViewportWidth: CGFloat = 0
    @State private var showFinishedCelebration = false
    @State private var finishedCelebrationStart: Date?
    @State private var finishedCelebrationToken = 0
    @State private var finishedCelebrationHideTask: Task<Void, Never>?

    @AppStorage(ReviewPreferences.Keys.playAudioInSilentMode) private var prefPlayAudioInSilentMode = false
    @AppStorage(ReviewPreferences.Keys.showContextMenuButton) private var prefShowContextMenuButton = true
    @AppStorage(ReviewPreferences.Keys.showAudioReplayButton) private var prefShowAudioReplayButton = true
    @AppStorage(ReviewPreferences.Keys.showCorrectnessSymbols) private var prefShowCorrectnessSymbols = false
    @AppStorage(ReviewPreferences.Keys.disperseAnswerButtons) private var prefDisperseAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.showAnswerButtons) private var prefShowAnswerButtons = true
    @AppStorage(ReviewPreferences.Keys.smallReviewButtons) private var prefSmallReviewButtons = false
    @AppStorage(ReviewPreferences.Keys.hideHardAndEasyButtons) private var prefHideHardAndEasyButtons = false
    @AppStorage(ReviewPreferences.Keys.showRemainingDays) private var prefShowRemainingDays = true
    @AppStorage(ReviewPreferences.Keys.showNextReviewTime) private var prefShowNextReviewTime = false
    @AppStorage(ReviewPreferences.Keys.openLinksExternally) private var prefOpenLinksExternally = true
    @AppStorage(ReviewPreferences.Keys.lookupPopupEnabled) private var prefLookupPopupEnabled = true
    @AppStorage(ReviewPreferences.Keys.lookupPopupFrontEnabled) private var prefLookupPopupFrontEnabled = false
    @AppStorage(ReviewPreferences.Keys.lookupPopupBackEnabled) private var prefLookupPopupBackEnabled = true
    @AppStorage(ReviewPreferences.Keys.selectionMenuLookupEnabled) private var prefSelectionMenuLookupEnabled = false
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIEnabled) private var prefSelectionMenuAIEnabled = false
    @AppStorage(ReviewPreferences.Keys.cardContentAlignment) private var prefCardContentAlignmentRaw = CardWebView.ContentAlignment.top.rawValue
    @AppStorage(ReviewPreferences.Keys.glassAnswerButtons) private var prefGlassAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.autoMatchCardBackground) private var prefAutoMatchCardBackground = true
    @AppStorage(ReviewPreferences.Keys.frontTapGestureAction) private var prefFrontTapGestureActionRaw = ReviewPreferences.GestureAction.showAnswer.rawValue
    @AppStorage(ReviewPreferences.Keys.frontSwipeLeftGestureAction) private var prefFrontSwipeLeftGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.frontSwipeRightGestureAction) private var prefFrontSwipeRightGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.backTapGestureAction) private var prefBackTapGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.backSwipeLeftGestureAction) private var prefBackSwipeLeftGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.backSwipeRightGestureAction) private var prefBackSwipeRightGestureActionRaw = ReviewPreferences.GestureAction.none.rawValue
    @AppStorage(ReviewPreferences.Keys.tapGestureLayout) private var prefTapGestureLayoutRaw = ReviewPreferences.TapGestureLayout.threeRows.rawValue
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
    @State private var actionBarHeight: CGFloat = 0

    private var prefCardContentAlignment: CardWebView.ContentAlignment {
        CardWebView.ContentAlignment(rawValue: prefCardContentAlignmentRaw) ?? .top
    }

    private var ankiJSContext: AnkiJSContext {
        AnkiJSContext(
            isDisplayingAnswer: {
                session.showAnswer
            },
            isNightMode: {
                colorScheme == .dark
            },
            showAnswer: { typedAnswer in
                session.revealAnswer(typedAnswer: typedAnswer)
            },
            answerEase: { ease, typedAnswer in
                if session.showAnswer {
                    session.answer(rating: try rating(forAnkiEase: ease))
                } else {
                    session.revealAnswer(typedAnswer: typedAnswer)
                }
            },
            getCounts: {
                session.remainingCounts
            },
            getETA: {
                estimatedAnkiJSETA()
            },
            getNextTime: { ease in
                guard let rating = try? rating(forAnkiEase: ease) else {
                    return nil
                }
                return session.nextIntervals[rating]
            },
            getCardInfo: {
                try currentAnkiJSCardInfo()
            },
            getDeckName: {
                if let cached = currentDeckName?.trimmedOrNil {
                    return cached
                }
                let resolvedDeckID = session.currentCard?.card.deckID ?? deckId
                return try? deckClient.fetchDeck(resolvedDeckID).name
            },
            buryCard: {
                let cardId = try currentReviewCardID()
                try cardClient.bury(cardId)
                session.refreshAndAdvance()
            },
            buryNote: {
                let noteId = try currentReviewNoteID()
                for card in try cardClient.fetchByNote(noteId) {
                    try cardClient.bury(card.id)
                }
                session.refreshAndAdvance()
            },
            suspendCard: {
                let cardId = try currentReviewCardID()
                try cardClient.suspend(cardId)
                session.refreshAndAdvance()
            },
            suspendNote: {
                let noteId = try currentReviewNoteID()
                for card in try cardClient.fetchByNote(noteId) {
                    try cardClient.suspend(card.id)
                }
                session.refreshAndAdvance()
            },
            resetProgress: {
                let cardId = try currentReviewCardID()
                try cardClient.resetToNew(cardId)
                session.refreshAndAdvance()
            },
            setCardDue: { days in
                let cardId = try currentReviewCardID()
                try cardClient.setDueDate(cardId, days)
                session.refreshAndAdvance()
            },
            toggleMark: {
                let noteId = try currentReviewNoteID()
                let existingTags = try loadNoteTags(noteId: noteId)
                let isMarked = existingTags.contains { $0.caseInsensitiveCompare(reviewMarkedTag) == .orderedSame }
                if isMarked {
                    try tagClient.removeTagFromNotes(reviewMarkedTag, [noteId])
                } else {
                    try tagClient.addTagToNotes(reviewMarkedTag, [noteId])
                }
                Task { [session] in
                    await session.refreshAfterCardMutation()
                }
                return !isMarked
            },
            setFlag: { value in
                let cardId = try currentReviewCardID()
                try cardClient.flag(cardId, value)
                Task { [session] in
                    await session.refreshAfterCardMutation()
                }
            },
            getNoteTags: {
                try loadNoteTags(noteId: currentReviewNoteID())
            },
            setNoteTags: { tags in
                let noteId = try currentReviewNoteID()
                guard var note = try noteClient.fetch(noteId) else {
                    throw AnkiJSBridgeError.noteNotFound(noteId)
                }
                note.tags = sanitizeAnkiJSTags(tags).joined(separator: " ")
                try noteClient.save(note)
                Task { [session] in
                    await session.refreshAfterCardMutation()
                }
            },
            addTagToCurrentCard: {
                let noteId = try currentReviewNoteID()
                guard let note = try noteClient.fetch(noteId) else {
                    throw AnkiJSBridgeError.noteNotFound(noteId)
                }
                editingNote = note
            },
            addTagToNote: { noteId, tag in
                let targetNoteID: Int64
                if let noteId {
                    targetNoteID = noteId
                } else {
                    targetNoteID = try currentReviewNoteID()
                }
                let normalizedTag = sanitizeAnkiJSTags([tag]).first ?? ""
                guard normalizedTag.isEmpty == false else {
                    throw AnkiJSBridgeError.invalidArgument("tag")
                }
                try tagClient.addTagToNotes(normalizedTag, [targetNoteID])
                if targetNoteID == session.currentCard?.card.noteID {
                    Task { [session] in
                        await session.refreshAfterCardMutation()
                    }
                }
            },
            searchCard: { query in
                ankiJSSearchSheetRequest = .init(
                    query: query.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            },
            searchCardWithCallbackPayload: { query in
                try makeAnkiJSSearchCallbackPayload(query: query)
            },
            showToast: { message, shortLength in
                presentAnkiJSToast(message: message, shortLength: shortLength)
            }
        )
    }

    private var isLookupPopupEnabledForCurrentSide: Bool {
        prefLookupPopupEnabled && (session.showAnswer ? prefLookupPopupBackEnabled : prefLookupPopupFrontEnabled)
    }

    private var popupAudioPlaybackMode: ReaderLookupAudioPlaybackMode {
        ReaderLookupAudioDefaults.resolvedPlaybackMode(popupAudioPlaybackModeRawValue)
    }

    private var prefTapGestureLayout: ReviewPreferences.TapGestureLayout {
        ReviewPreferences.TapGestureLayout(rawValue: prefTapGestureLayoutRaw) ?? .threeRows
    }

    private var cardChromeColor: Color {
        Color(uiColor: resolvedCardChromeUIColor)
    }

    private var resolvedCardChromeUIColor: UIColor {
        prefAutoMatchCardBackground ? cardChromeUIColor : .systemBackground
    }

    private var resolvedCardChromeIsDark: Bool {
        prefAutoMatchCardBackground ? cardChromeIsDark : (colorScheme == .dark)
    }

    private var usesExpandedToolbarLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var usesWidePadReviewControls: Bool {
        isPadDevice && horizontalSizeClass == .regular && reviewControlAvailableWidth > 0
    }

    private var reviewControlAvailableWidth: CGFloat {
        max(reviewViewportWidth - 32, 0)
    }

    private var reviewControlsBottomPadding: CGFloat {
        isPadDevice ? 16 : 0
    }

    private var usesFullscreenPadReviewControls: Bool {
        guard usesWidePadReviewControls else { return false }
        return reviewViewportWidth >= UIScreen.main.bounds.width * 0.9
    }

    private var reviewPrimaryButtonMaxWidth: CGFloat? {
        guard usesWidePadReviewControls else { return nil }
        let widthRatio = usesFullscreenPadReviewControls ? (1.0 / 3.0) : (2.0 / 3.0)
        let preferredWidth = reviewControlAvailableWidth * widthRatio
        let minimumWidth: CGFloat = prefSmallReviewButtons ? 260 : 320
        return min(reviewControlAvailableWidth, max(preferredWidth, minimumWidth))
    }

    private var reviewAnswerButtonsMaxWidth: CGFloat? {
        guard usesWidePadReviewControls else { return nil }
        let minimumButtonWidth: CGFloat = prefSmallReviewButtons ? 76 : 92
        let minimumTotalWidth = CGFloat(visibleRatings.count) * minimumButtonWidth
            + CGFloat(max(visibleRatings.count - 1, 0)) * 8
        let preferredWidth = reviewControlAvailableWidth * 0.6
        return min(reviewControlAvailableWidth, max(preferredWidth, minimumTotalWidth))
    }

    private var reviewButtonControlSize: ControlSize {
        prefSmallReviewButtons ? .small : .regular
    }

    private var reviewButtonHorizontalPadding: CGFloat {
        prefSmallReviewButtons ? 14 : 16
    }

    private var reviewButtonMinimumHeight: CGFloat {
        prefSmallReviewButtons ? 44 : 52
    }

    private var reviewButtonTitleFont: Font {
        prefSmallReviewButtons ? .subheadline.weight(.semibold) : .headline
    }

    private var reviewRatingSpacing: CGFloat {
        prefSmallReviewButtons ? 2 : 4
    }

    private var reviewRatingTitleFont: Font {
        prefSmallReviewButtons ? .footnote.weight(.semibold) : .subheadline.weight(.medium)
    }

    private var hasCurrentCard: Bool {
        session.currentCard != nil
    }

    private var currentCardFlagView: some View {
        Group {
            if let currentCard = session.currentCard?.card {
                let userFlag = currentCard.flags & 0b111
                Menu {
                    reviewFlagButton(0, cardId: currentCard.id)
                    reviewFlagButton(1, cardId: currentCard.id)
                    reviewFlagButton(2, cardId: currentCard.id)
                    reviewFlagButton(3, cardId: currentCard.id)
                    reviewFlagButton(4, cardId: currentCard.id)
                    reviewFlagButton(5, cardId: currentCard.id)
                    reviewFlagButton(6, cardId: currentCard.id)
                    reviewFlagButton(7, cardId: currentCard.id)
                } label: {
                    Image(systemName: userFlag == 0 ? "flag.slash.fill" : "flag.fill")
                        .font(.caption)
                        .foregroundStyle(reviewFlagColor(for: userFlag))
                        .accessibilityLabel(flagLabel(userFlag))
                }
            }
        }
    }

    init(deckId: Int64, onDismiss: @escaping () -> Void) {
        self.deckId = deckId
        self.onDismiss = onDismiss
        self._session = State(initialValue: ReviewSession(deckId: deckId))
    }

    var body: some View {
        reviewPresentationContent
    }

    private var reviewLifecycleContent: some View {
        reviewNavigationContent
        .overlay {
            if session.isFinished,
               showFinishedCelebration,
               let finishedCelebrationStart {
                ReviewFinishedConfettiView(startDate: finishedCelebrationStart)
                    .id(finishedCelebrationToken)
                    .transition(.opacity)
            }
        }
        .background(cardChromeColor.ignoresSafeArea())
        .task {
            cardChromeIsDark = (colorScheme == .dark)
            session.start()
            configureAudioSession()
            controllerMonitor.onButton = { button in
                Task { @MainActor in
                    handleControllerButton(button)
                }
            }
            controllerMonitor.start()
            keyboardMonitor.onShortcut = { shortcut in
                Task { @MainActor in
                    handleKeyboardShortcut(shortcut)
                }
            }
            keyboardMonitor.start()
            scheduleAutoAdvanceIfNeeded()
            await preloadAvailableDecks()
            await preloadCurrentDeckName()
        }
        .onChange(of: prefPlayAudioInSilentMode) { _, _ in
            configureAudioSession()
        }
        .onChange(of: colorScheme) { _, newValue in
            if !prefAutoMatchCardBackground {
                cardChromeIsDark = (newValue == .dark)
            }
        }
        .onChange(of: session.currentCard?.card.id) { _, _ in
            lookupStack.removeAll()
            scheduleAutoAdvanceIfNeeded()
        }
        .onChange(of: session.showAnswer) { _, _ in
            lookupStack.removeAll()
            scheduleAutoAdvanceIfNeeded()
        }
        .onChange(of: session.isFinished) { oldValue, newValue in
            if !oldValue, newValue {
                triggerFinishedCelebration()
            } else if oldValue, !newValue {
                finishedCelebrationHideTask?.cancel()
                showFinishedCelebration = false
            }
        }
        .onChange(of: isAudioPlaying) { _, _ in
            scheduleAutoAdvanceIfNeeded()
        }
        .onChange(of: prefLookupPopupEnabled) { _, isEnabled in
            if isEnabled == false {
                lookupStack.removeAll()
            }
        }
        .onChange(of: prefLookupPopupFrontEnabled) { _, _ in
            if isLookupPopupEnabledForCurrentSide == false {
                lookupStack.removeAll()
            }
        }
        .onChange(of: prefLookupPopupBackEnabled) { _, _ in
            if isLookupPopupEnabledForCurrentSide == false {
                lookupStack.removeAll()
            }
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
            finishedCelebrationHideTask?.cancel()
            controllerMonitor.stop()
            keyboardMonitor.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private var reviewModalContent: some View {
        reviewLifecycleContent
        .sheet(item: regularEditingNoteBinding) { note in
            NoteEditingDestinationView(note: note, embedInNavigationStack: true) {
                Task { await session.refreshAfterCardMutation() }
            }
        }
        .fullScreenCover(item: imageOcclusionEditingNoteBinding) { note in
            NoteEditingDestinationView(note: note, embedInNavigationStack: true) {
                Task { await session.refreshAfterCardMutation() }
            }
        }
        .sheet(item: $currentCardStatsTarget) { target in
            ReviewCardStatsSheet(queuedCard: target.queuedCard)
        }
        .sheet(item: $templateEditorTarget) { target in
            TemplateEditorView(
                notetypeId: target.notetypeId,
                previewNoteId: target.noteId,
                initialTemplateIndex: target.templateIndex,
                mode: .currentCard,
                onSaved: {
                    await session.refreshAfterCardMutation()
                }
            )
        }
        .sheet(item: $fieldManagerTarget) { target in
            NavigationStack {
                NotetypeFieldManagerView(
                    notetypeId: target.notetypeId,
                    preferredName: target.notetypeName,
                    onSaved: {
                        await session.refreshAfterCardMutation()
                    }
                )
            }
        }
        .sheet(isPresented: $showMoveToDeck) {
            MoveToDeckSheet(decks: availableDecks) { targetDeck in
                Task { await moveCurrentCard(to: targetDeck) }
            }
        }
        .sheet(item: $changeNotetypeTarget) { target in
            ChangeNotetypeSheet(
                noteIDs: target.noteIDs,
                sourceNotetypeID: target.sourceNotetypeID
            ) {
                Task { await session.refreshAfterCardMutation() }
            }
        }
        .sheet(isPresented: $showSetDueDateSheet) {
            ReviewSetDueDateSheet(
                dueDays: $setDueDateInput,
                onSave: {
                    Task { await applySetDueDate() }
                }
            )
        }
        .sheet(isPresented: $showTriggeredContextMenu) {
            ReviewContextActionsSheet(
                hasNote: (session.currentCard?.card.noteID ?? 0) != 0,
                onClose: { showTriggeredContextMenu = false },
                onSuspend: {
                    showTriggeredContextMenu = false
                    performCurrentCardAction(
                        { try cardClient.suspend($0) },
                        errorKey: "card_action_error_suspend"
                    )
                },
                onBury: {
                    showTriggeredContextMenu = false
                    performCurrentCardAction(
                        { try cardClient.bury($0) },
                        errorKey: "card_action_error_bury"
                    )
                },
                onMarkAndSuspend: {
                    showTriggeredContextMenu = false
                    performMarkThenCurrentCardAction(
                        { try cardClient.suspend($0) },
                        errorKey: "card_action_error_suspend"
                    )
                },
                onMarkAndBury: {
                    showTriggeredContextMenu = false
                    performMarkThenCurrentCardAction(
                        { try cardClient.bury($0) },
                        errorKey: "card_action_error_bury"
                    )
                },
                onReset: {
                    showTriggeredContextMenu = false
                    performCurrentCardAction(
                        { try cardClient.resetToNew($0) },
                        errorKey: "card_action_error_reset_to_new"
                    )
                },
                onSetDueDate: {
                    showTriggeredContextMenu = false
                    openSetDueDateForCurrentCard()
                },
                onUndo: {
                    showTriggeredContextMenu = false
                    Task { await performUndo() }
                },
                onFlag: { value in
                    showTriggeredContextMenu = false
                    setCurrentCardFlag(value)
                },
                onUserAction: { index in
                    showTriggeredContextMenu = false
                    triggerUserAction(index)
                }
            )
        }
        .sheet(isPresented: $showDeckStats) {
            NavigationStack {
                StatsDashboardView(initialDeckID: deckId)
            }
        }
        .sheet(item: $ankiJSSearchSheetRequest) { request in
            NavigationStack {
                BrowseView(initialSearchQuery: request.query)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L("common_done")) {
                                ankiJSSearchSheetRequest = nil
                            }
                        }
                    }
            }
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
        .sheet(isPresented: $showCardInfo) {
            if let queued = session.currentCard {
                ReviewCardInfoSheet(queuedCard: queued)
            }
        }
    }

    private var imageOcclusionEditingNoteBinding: Binding<NoteRecord?> {
        Binding(
            get: {
                guard let editingNote, editingNote.isImageOcclusionNote else { return nil }
                return editingNote
            },
            set: { newValue in
                if let newValue {
                    editingNote = newValue
                } else if editingNote?.isImageOcclusionNote == true {
                    editingNote = nil
                }
            }
        )
    }

    private var regularEditingNoteBinding: Binding<NoteRecord?> {
        Binding(
            get: {
                guard let editingNote, !editingNote.isImageOcclusionNote else { return nil }
                return editingNote
            },
            set: { newValue in
                if let newValue {
                    editingNote = newValue
                } else if editingNote?.isImageOcclusionNote != true {
                    editingNote = nil
                }
            }
        )
    }

    private var reviewPresentationContent: some View {
        reviewModalContent
        .alert(L("common_error"), isPresented: $showToolbarError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(toolbarErrorMessage ?? L("common_unknown_error"))
        }
        .alert(L("card_action_error_title"), isPresented: $showUndoError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(undoErrorMessage ?? L("common_unknown_error"))
        }
        .alert(L("common_error"), isPresented: $showLookupError) {
            Button(L("common_ok"), role: .cancel) {}
        } message: {
            Text(lookupErrorMessage ?? L("common_unknown_error"))
        }
        .alert(L("browse_batch_delete_notes"), isPresented: $showDeleteNoteConfirm) {
            Button(L("common_cancel"), role: .cancel) {}
            Button(L("common_delete"), role: .destructive) {
                Task { await deleteCurrentNote() }
            }
        } message: {
            Text(L("review_delete_note_message"))
        }
        .overlay {
            if let symbol = answerFeedbackSymbol {
                Text(symbol)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let toast = ankiJSToastState {
                AnkiJSToastView(message: toast.message)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var reviewNavigationContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    DeckCountsView(counts: session.remainingCounts)
                    Spacer()
                    autoAdvanceTimerView
                    currentCardFlagView
                    Text(L("review_reviewed_count", session.sessionStats.reviewed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(cardChromeColor)

                if session.isFinished {
                    finishedView
                } else {
                    cardView
                }
            }
            .background(cardChromeColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { reviewToolbarContent }
            .toolbarBackground(cardChromeColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(resolvedCardChromeIsDark ? .dark : .light, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var autoAdvanceTimerView: some View {
        if let fallbackSeconds = session.currentAutoAdvanceDelay, fallbackSeconds > 0 {
            ReviewAutoAdvanceTimerView(
                deadline: autoAdvanceDeadline,
                fallbackSeconds: fallbackSeconds
            )
        }
    }

    @ToolbarContentBuilder
    private var reviewToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
            }
            .accessibilityLabel(L("common_done"))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await performUndo() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .accessibilityLabel(L("card_action_undo"))
            .disabled(session.currentCard == nil || !session.canUndo || isUndoing)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await openEditorForCurrentCard() }
            } label: {
                Image(systemName: "pencil")
            }
            .accessibilityLabel(L("review_edit_button"))
            .disabled(session.currentCard == nil)
        }
        if prefShowAudioReplayButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isAudioPlaying {
                        stopAudioRequestID += 1
                    } else {
                        replayRequestID += 1
                    }
                } label: {
                    Image(systemName: isAudioPlaying ? "pause.circle" : "play.circle")
                }
                .disabled(session.currentCard == nil)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await openCurrentCardTemplateEditor() }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel(L("card_template_editor_title"))
            .disabled(!hasCurrentCard)
        }
        if usesExpandedToolbarLayout {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDeckStats = true
                } label: {
                    Image(systemName: "chart.bar.doc.horizontal")
                }
                .accessibilityLabel(L("stats_nav_title"))
                .disabled(!hasCurrentCard)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await openMoveCurrentCardToDeck() }
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus")
                }
                .accessibilityLabel(L("browse_batch_move_deck"))
                .disabled(!hasCurrentCard)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await openChangeCurrentCardNotetype() }
                } label: {
                    Image(systemName: "doc.badge.gearshape")
                }
                .accessibilityLabel(L("browse_batch_change_notetype"))
                .disabled(!hasCurrentCard)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCardInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel(L("card_info_title"))
                .disabled(!hasCurrentCard)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if !usesExpandedToolbarLayout {
                    Button {
                        showDeckStats = true
                    } label: {
                        Label(L("stats_nav_title"), systemImage: "chart.bar.doc.horizontal")
                    }
                    .disabled(!hasCurrentCard)

                    Button {
                        Task { await openMoveCurrentCardToDeck() }
                    } label: {
                        Label(L("browse_batch_move_deck"), systemImage: "rectangle.stack.badge.plus")
                    }
                    .disabled(!hasCurrentCard)

                    Button {
                        Task { await openChangeCurrentCardNotetype() }
                    } label: {
                        Label(L("browse_batch_change_notetype"), systemImage: "doc.badge.gearshape")
                    }
                    .disabled(!hasCurrentCard)

                    Button {
                        showCardInfo = true
                    } label: {
                        Label(L("card_info_title"), systemImage: "info.circle")
                    }
                    .disabled(!hasCurrentCard)

                    Divider()
                }

                Button(role: .destructive) {
                    showDeleteNoteConfirm = true
                } label: {
                    Label(L("browse_batch_delete_notes"), systemImage: "trash")
                }
                .disabled(!hasCurrentCard)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(L("review_more_actions"))
        }
    }

    @ViewBuilder
    private var cardView: some View {
        let cardHTML = session.showAnswer ? session.backHTML : session.frontHTML
        let replayMode: CardWebView.ReplayMode = session.showAnswer
            ? (session.includeQuestionAudioOnAnswerReplay ? .answerWithQuestion : .answerOnly)
            : .question

        ZStack {
            CardWebView(
                html: cardHTML,
                cardCSS: session.cardCSS,
                autoplayEnabled: session.autoplayAudio,
                isAnswerSide: session.showAnswer,
                questionAVTags: session.questionAVTags,
                answerAVTags: session.answerAVTags,
                cardOrdinal: session.currentCard?.card.templateIdx ?? 0,
                replayRequestID: replayRequestID,
                stopAudioRequestID: stopAudioRequestID,
                typedAnswerRequestID: typedAnswerRequestID,
                userActionRequestID: userActionRequestID,
                userActionIndex: pendingUserActionIndex,
                replayMode: replayMode,
                playAudioInSilentMode: prefPlayAudioInSilentMode,
                showInlineAudioReplayButtons: prefShowAudioReplayButton,
                openLinksExternally: prefOpenLinksExternally,
                lookupPopupEnabled: isLookupPopupEnabledForCurrentSide,
                selectionMenuLookupEnabled: prefSelectionMenuLookupEnabled,
                selectionMenuAIEnabled: prefSelectionMenuAIEnabled,
                prefetchHTML: session.showAnswer ? nil : session.backHTML,
                contentAlignment: prefCardContentAlignment,
                bottomContentInset: actionBarHeight,
                ankiJSContext: ankiJSContext,
                onTypedAnswerSubmitted: { typedAnswer in
                    session.revealAnswer(typedAnswer: typedAnswer)
                },
                onAudioStateChange: { isPlaying in
                    Task { @MainActor in
                        self.isAudioPlaying = isPlaying
                    }
                },
                onCardBackgroundColorChange: { color, isDark in
                    Task { @MainActor in
                        self.cardChromeUIColor = color
                        self.cardChromeIsDark = isDark
                    }
                },
                onLookupRequested: { selection, sentence, point in
                    handleCardLookup(selection, sentence: sentence, at: point)
                },
                onCardGesture: { gesture in
                    handleCardGesture(gesture)
                },
                onSelectionMenuAction: { action, snapshot in
                    handleSelectionMenuAction(action, snapshot: snapshot)
                }
            )

            reviewLookupOverlay
            ReviewKeyboardCommandBridge()
                .frame(width: 0, height: 0)
        }
        .onGeometryChange(for: CGFloat.self) { geo in
            geo.size.width
        } action: { width in
            reviewViewportWidth = width
        }
        .overlay(alignment: .bottom) {
            cardActionBar
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.height
                } action: { height in
                    actionBarHeight = height
                }
        }
    }

    @ViewBuilder
    private var cardActionBar: some View {
        Group {
            if session.showAnswer {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        if prefShowContextMenuButton, !session.isFinished, let current = session.currentCard {
                            CardContextMenu(
                                cardId: current.card.id,
                                noteId: current.card.noteID,
                                onActionSuccess: { shouldAdvance in
                                    if shouldAdvance {
                                        session.refreshAndAdvance()
                                    } else {
                                        Task { await session.refreshAfterCardMutation() }
                                    }
                                },
                                onRequestSetDueDate: { _ in
                                    openSetDueDateForCurrentCard()
                                },
                                onTriggerUserAction: { index in
                                    triggerUserAction(index)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if prefShowAnswerButtons {
                        answerButtons
                    } else {
                        compactAnswerMenu
                    }
                }
                .background(.clear)
            } else {
                let usesCompactShowAnswerButton = session.requiresTypedAnswerInput && isKeyboardVisible

                Group {
                    if usesCompactShowAnswerButton {
                        HStack {
                            Spacer()

                            Button {
                                typedAnswerRequestID += 1
                            } label: {
                                Text(L("review_show_answer"))
                                    .font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .clipShape(Capsule())

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    } else {
                        HStack {
                            Spacer()

                            Button {
                                session.revealAnswer()
                            } label: {
                                Text(L("review_show_answer"))
                                    .font(reviewButtonTitleFont)
                                    .frame(maxWidth: .infinity, minHeight: reviewButtonMinimumHeight)
                                    .padding(.horizontal, reviewButtonHorizontalPadding)
                            }
                            .frame(maxWidth: reviewPrimaryButtonMaxWidth ?? .infinity)
                            .buttonStyle(.borderedProminent)
                            .controlSize(reviewButtonControlSize)
                            .clipShape(Capsule())

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .background(.clear)
                .animation(.easeInOut(duration: 0.18), value: usesCompactShowAnswerButton)
            }
        }
        .padding(.bottom, reviewControlsBottomPadding)
        // Keep the floating review controls transparent so they do not paint an
        // opaque strip over the card content again. The surrounding review screen
        // still provides the toolbar/safe-area chrome color.
        .background(.clear)
    }

    @ViewBuilder
    private var reviewLookupOverlay: some View {
        if lookupStack.isEmpty == false {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            lookupStack.removeAll()
                        }

                    ForEach(Array(lookupStack.enumerated()), id: \.element.id) { index, popup in
                        ReaderLookupPopup(
                            query: popup.query,
                            result: popup.result,
                            isLoading: popup.isLoading,
                            sentence: popup.sentence,
                            languageHint: nil,
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
                            needsAudio: false,
                            refreshID: 0,
                            showDebugInfo: popupDebugInfoEnabled,
                            onAddNote: { _ in },
                            duplicateCheck: { _ in false },
                            onLookupRequested: { query, sentence in
                                startCardLookup(for: query, sentence: sentence, anchor: nil, stacksOnTop: true)
                            },
                            onClose: {
                                removeLookupPopup(id: popup.id)
                            }
                        )
                        .frame(maxWidth: popupFullWidth ? .infinity : CGFloat(popupWidth))
                        .padding(.horizontal, 14)
                        .position(
                            lookupPopupPosition(
                                in: geometry.size,
                                anchor: popup.anchor,
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

    private func handleCardLookup(_ selection: String?, sentence: String?, at point: CGPoint) {
        guard isLookupPopupEnabledForCurrentSide,
              let query = normalizedLookupText(selection) else {
            handleCardGesture("tap:middleCenter")
            return
        }
        startCardLookup(for: query, sentence: sentence, anchor: point)
    }

    private func rating(forAnkiEase ease: Int) throws -> Rating {
        switch ease {
        case 1:
            .again
        case 2:
            .hard
        case 3:
            .good
        case 4:
            .easy
        default:
            throw AnkiJSBridgeError.invalidArgument("ease")
        }
    }

    private func currentReviewCardID() throws -> Int64 {
        guard let cardId = session.currentCard?.card.id else {
            throw AnkiJSBridgeError.noCurrentCard
        }
        return cardId
    }

    private func currentReviewNoteID() throws -> Int64 {
        guard let noteId = session.currentCard?.card.noteID, noteId != 0 else {
            throw AnkiJSBridgeError.noCurrentNote
        }
        return noteId
    }

    private func loadNoteTags(noteId: Int64) throws -> [String] {
        guard let note = try noteClient.fetch(noteId) else {
            throw AnkiJSBridgeError.noteNotFound(noteId)
        }
        return note.tags
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.isEmpty == false }
    }

    private func sanitizeAnkiJSTags(_ tags: [String]) -> [String] {
        tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return trimmed
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "\u{3000}", with: "_")
        }
    }

    private func currentAnkiJSCardInfo() throws -> AnkiJSCardInfo {
        guard let card = session.currentCard?.card else {
            throw AnkiJSBridgeError.noCurrentCard
        }

        let tags = try loadNoteTags(noteId: card.noteID)
        let isMarked = tags.contains { $0.caseInsensitiveCompare(reviewMarkedTag) == .orderedSame }
        let userFlag = Int(card.flags & 0b111)

        return AnkiJSCardInfo(
            cardId: card.id,
            noteId: card.noteID,
            deckId: card.deckID,
            cardType: Int(card.ctype),
            left: Int(card.remainingSteps),
            originalDeckId: card.originalDeckID,
            originalDue: Int(card.originalDue),
            queue: Int(card.queue),
            lapses: Int(card.lapses),
            due: Int(card.due),
            reps: Int(card.reps),
            interval: Int(card.interval),
            factor: Int(card.easeFactor),
            modified: Int(card.mtimeSecs),
            userFlag: userFlag,
            isMarked: isMarked
        )
    }

    private func estimatedAnkiJSETA() -> Int {
        let remaining = session.remainingCounts.newCount
            + session.remainingCounts.learnCount
            + session.remainingCounts.reviewCount
        guard remaining > 0 else { return 0 }

        let reviewed = session.sessionStats.reviewed
        let averageSecondsPerCard: Double
        if reviewed > 0, session.sessionStats.totalTimeMs > 0 {
            averageSecondsPerCard = Double(session.sessionStats.totalTimeMs) / Double(reviewed) / 1000
        } else {
            averageSecondsPerCard = 20
        }

        let estimatedMinutes = Int(ceil((Double(remaining) * averageSecondsPerCard) / 60))
        return max(1, estimatedMinutes)
    }

    private func makeAnkiJSSearchCallbackPayload(query: String) throws -> String {
        let cards = try cardClient.search(query)
        let noteIDs = Array(Set(cards.map(\.nid)))
        let notes = try noteClient.fetchBatch(noteIDs)
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })

        var fieldNamesByNotetype: [Int64: [String]] = [:]
        for note in notes where fieldNamesByNotetype[note.mid] == nil {
            fieldNamesByNotetype[note.mid] = try fetchNotetypeFieldNames(note.mid)
        }

        let results = cards.compactMap { card -> AnkiJSSearchCallbackResult? in
            guard let note = notesByID[card.nid] else { return nil }
            let fieldNames = fieldNamesByNotetype[note.mid] ?? []
            let fieldValues = splitAnkiJSFields(note.flds)
            var fieldsData: [String: String] = [:]
            for (index, fieldName) in fieldNames.enumerated() {
                fieldsData[fieldName] = index < fieldValues.count ? fieldValues[index] : ""
            }
            return AnkiJSSearchCallbackResult(
                cardId: card.id,
                noteId: note.id,
                fieldsData: fieldsData
            )
        }

        let data = try JSONEncoder().encode(results)
        return String(decoding: data, as: UTF8.self)
    }

    private func fetchNotetypeFieldNames(_ notetypeID: Int64) throws -> [String] {
        try notetypesService.getNotetypeFields(notetypeID)
            .sorted { $0.ordinal < $1.ordinal }
            .map(\.name)
    }

    private func splitAnkiJSFields(_ raw: String) -> [String] {
        raw.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
    }

    private func handleSelectionMenuAction(_ action: CardWebView.SelectionMenuAction, snapshot: CardWebView.SelectionSnapshot) {
        let trimmedSelection = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSelection.isEmpty == false else { return }

        switch action {
        case .lookup:
            openSelectionLookup(for: trimmedSelection)
        case .ai:
            startSelectionAI(
                for: trimmedSelection,
                context: ReviewAIQueryContext(
                    selectedText: trimmedSelection,
                    sentence: normalizedLookupText(snapshot.sentence),
                    source: reviewAISelectionSource
                )
            )
        }
    }

    private func openSelectionLookup(for selection: String) {
        guard prefSelectionMenuLookupEnabled else { return }
        let preset = ReviewSelectionLookupPresetStore.load().activePreset
        guard let url = ReviewSelectionURLBuilder.resolve(
            template: preset.template,
            selection: selection,
            shouldEncodeSelection: preset.encodeSelection
        ) else {
            toolbarErrorMessage = L("review_selection_lookup_invalid_template")
            showToolbarError = true
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func startSelectionAI(for selection: String, context: ReviewAIQueryContext) {
        guard prefSelectionMenuAIEnabled else { return }
        switch ReviewAIFlow.makeInitialStateIfConfigured(selection: selection, context: context) {
        case let .success(state):
            selectionAIState = state
        case let .failure(error):
            toolbarErrorMessage = error.message
            showToolbarError = true
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
            toolbarErrorMessage = error.message
            showToolbarError = true
            return
        }
    }

    private var reviewAISelectionSource: String {
        let deckLabel = currentDeckName?.trimmedOrNil ?? "Deck \(deckId)"
        let templateLabel = "#\((session.currentCard?.card.templateIdx ?? 0) + 1)"
        let sideLabel = session.showAnswer ? L("deck_template_preview_back") : L("deck_template_preview_front")
        return "\(deckLabel) / \(templateLabel) / \(sideLabel)"
    }

    private func startCardLookup(for query: String, sentence: String? = nil, anchor: CGPoint? = nil, stacksOnTop: Bool = false) {
        guard isLookupPopupEnabledForCurrentSide else {
            lookupStack.removeAll()
            return
        }

        let popup = ReaderLookupPopupState(
            query: query,
            sentence: normalizedLookupText(sentence),
            anchor: anchor,
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
            } catch {
                removeLookupPopup(id: popup.id)
                lookupErrorMessage = error.localizedDescription
                showLookupError = true
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

    private func normalizedLookupText(_ text: String?) -> String? {
        let trimmed = text?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private var isCurrentAIResponseFavorited: Bool {
        _ = aiFavoriteRefreshToken
        return ReviewAIFlow.isFavorited(currentAIFavoriteItem)
    }

    private var currentAIFavoriteItem: ReviewAIFavoriteItem? {
        guard let state = selectionAIState,
              let queryText = state.trimmedSelection,
              let responseText = state.response?.trimmedOrNil else {
            return nil
        }

        let presetStore = ReviewSelectionAIPresetStore.load()
        let config = presetStore.config(for: state.activePresetID)
        let context = ReviewAIQueryContext(
            selectedText: queryText,
            sentence: state.context.sentence,
            source: state.context.source
        )
        return ReviewAIFavoriteItem(
            id: ReviewAIFavoriteStore.load().favoriteID(
                queryText: queryText,
                responseText: responseText,
                presetID: config.presetID
            ) ?? UUID().uuidString,
            presetID: config.presetID,
            presetName: config.presetName,
            queryText: queryText,
            responseText: responseText,
            sentence: context.sentence,
            source: context.source
        )
    }

    private func toggleCurrentAIResponseFavorite() {
        ReviewAIFlow.toggleFavorite(currentAIFavoriteItem)
        aiFavoriteRefreshToken += 1
    }

    private func openAddNoteFromCurrentAI() {
        guard let state = selectionAIState else { return }
        queuedAIAddNoteDraft = ReviewAIFlow.makeAddNoteDraft(for: state, fallbackDeckID: deckId)
        selectionAIState = nil
    }

    private func presentQueuedAIAddNoteDraft() {
        guard pendingAIAddNoteDraft == nil, let queuedAIAddNoteDraft else { return }
        pendingAIAddNoteDraft = queuedAIAddNoteDraft
        self.queuedAIAddNoteDraft = nil
    }

    private func lookupPopupPosition(in size: CGSize, anchor: CGPoint?, stackDepth: Int) -> CGPoint {
        let horizontalMargin: CGFloat = 18
        let bottomInset = max(actionBarHeight, 28)
        let popupResolvedWidth = popupFullWidth
            ? max(size.width - horizontalMargin * 2, 0)
            : min(CGFloat(popupWidth), max(size.width - horizontalMargin * 2, 0))
        let popupHalfWidth = popupResolvedWidth / 2
        let popupHalfHeight = min(CGFloat(popupHeight) / 2, max(size.height / 2 - 56, 132))
        let stackedOffset = CGFloat(stackDepth) * min(36, popupHalfHeight * 0.22)

        guard popupFullWidth == false, let anchor else {
            return CGPoint(
                x: size.width / 2,
                y: max(24 + popupHalfHeight, size.height - bottomInset - popupHalfHeight - 20 - stackedOffset)
            )
        }

        let proposedBottomY = anchor.y + popupHalfHeight + 26 - stackedOffset
        let fallbackTopY = anchor.y - popupHalfHeight - 26 - stackedOffset
        let minY = 24 + popupHalfHeight
        let maxY = size.height - bottomInset - popupHalfHeight - 20
        let resolvedY = proposedBottomY <= maxY ? proposedBottomY : max(fallbackTopY, minY)
        let resolvedX = min(
            max(anchor.x, popupHalfWidth + horizontalMargin),
            size.width - popupHalfWidth - horizontalMargin
        )

        return CGPoint(x: resolvedX, y: resolvedY)
    }

    private var answerButtons: some View {
        HStack {
            Spacer(minLength: 0)

            Group {
                if prefDisperseAnswerButtons {
                    if visibleRatings.count <= 2 {
                        HStack(spacing: 8) {
                            ForEach(visibleRatings, id: \.self) { rating in
                                ratingButton(rating, color: ratingColor(rating))
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                ForEach(Array(visibleRatings.prefix(2)), id: \.self) { rating in
                                    ratingButton(rating, color: ratingColor(rating))
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach(Array(visibleRatings.dropFirst(2)), id: \.self) { rating in
                                    ratingButton(rating, color: ratingColor(rating))
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(visibleRatings, id: \.self) { rating in
                            ratingButton(rating, color: ratingColor(rating))
                        }
                    }
                }
            }
            .frame(maxWidth: reviewAnswerButtonsMaxWidth ?? .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var compactAnswerMenu: some View {
        if shouldForceCapsuleAnswerButtonsOnPad {
            HStack {
                Spacer(minLength: 0)

                Menu {
                    ForEach(visibleRatings, id: \.self) { rating in
                        Button(ratingLabel(rating)) { session.answer(rating: rating) }
                    }
                } label: {
                    Text(L("review_answer_button"))
                        .font(reviewButtonTitleFont)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: reviewButtonMinimumHeight)
                        .padding(.horizontal, reviewButtonHorizontalPadding)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(reviewButtonControlSize)
                .clipShape(Capsule())
                .frame(maxWidth: reviewAnswerButtonsMaxWidth ?? .infinity)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
        } else {
            HStack {
                Spacer(minLength: 0)

                Menu {
                    ForEach(visibleRatings, id: \.self) { rating in
                        Button(ratingLabel(rating)) { session.answer(rating: rating) }
                    }
                } label: {
                    Text(L("review_answer_button"))
                        .font(reviewButtonTitleFont)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: reviewButtonMinimumHeight)
                        .padding(.horizontal, reviewButtonHorizontalPadding)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(reviewButtonControlSize)
                .frame(maxWidth: reviewAnswerButtonsMaxWidth ?? .infinity)

                Spacer(minLength: 0)
            }
            .padding(.horizontal)
        }
    }

    private var visibleRatings: [Rating] {
        prefHideHardAndEasyButtons ? [.again, .good] : [.again, .hard, .good, .easy]
    }

    private var shouldForceCapsuleAnswerButtonsOnPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private func ratingColor(_ rating: Rating) -> Color {
        switch rating {
        case .again: return .red
        case .hard: return .orange
        case .good: return .green
        case .easy: return .blue
        }
    }

    @ViewBuilder
    private func ratingButton(_ rating: Rating, color: Color) -> some View {
        if #available(iOS 26.0, *), prefGlassAnswerButtons {
            if shouldForceCapsuleAnswerButtonsOnPad {
                Button {
                    ratingButtonAction(rating)
                } label: {
                    ratingButtonLabel(rating)
                }
                .buttonStyle(.glassProminent)
                .tint(color)
                .clipShape(Capsule())
            } else {
                Button {
                    ratingButtonAction(rating)
                } label: {
                    ratingButtonLabel(rating)
                }
                .buttonStyle(.glassProminent)
                .tint(color)
            }
        } else {
            if shouldForceCapsuleAnswerButtonsOnPad {
                Button {
                    ratingButtonAction(rating)
                } label: {
                    ratingButtonLabel(rating)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .clipShape(Capsule())
            } else {
                Button {
                    ratingButtonAction(rating)
                } label: {
                    ratingButtonLabel(rating)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
            }
        }
    }

    private func ratingButtonAction(_ rating: Rating) {
        if prefShowCorrectnessSymbols {
            answerFeedbackSymbol = feedbackSymbol(for: rating)
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                await MainActor.run { answerFeedbackSymbol = nil }
            }
        }
        session.answer(rating: rating)
    }

    @ViewBuilder
    private func ratingButtonLabel(_ rating: Rating) -> some View {
        VStack(spacing: reviewRatingSpacing) {
            if prefShowRemainingDays {
                Text(session.nextIntervals[rating] ?? "")
                    .font(.caption2)
            }
            if prefShowNextReviewTime,
               let seconds = session.nextIntervalSeconds[rating] {
                Text(formatNextReviewTime(seconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(ratingLabel(rating))
                .font(reviewRatingTitleFont)
        }
        .frame(maxWidth: .infinity, minHeight: reviewButtonMinimumHeight)
        .padding(.horizontal, 8)
    }

    private func ratingLabel(_ rating: Rating) -> String {
        switch rating {
        case .again: return L("review_rating_again")
        case .hard: return L("review_rating_hard")
        case .good: return L("review_rating_good")
        case .easy: return L("review_rating_easy")
        }
    }

    private func feedbackSymbol(for rating: Rating) -> String {
        switch rating {
        case .again: return "✗"
        case .hard: return "△"
        case .good: return "✓"
        case .easy: return "✓✓"
        }
    }

    private func formatNextReviewTime(_ seconds: UInt32) -> String {
        let target = Date().addingTimeInterval(Double(seconds))
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: target)
    }

    private func formatInterval(_ days: Int) -> String {
        if days == 0 { return L("card_interval_less_than_1d_short") }
        if days < 30 { return L("card_interval_days_short", days) }
        if days < 365 { return L("card_interval_months_short", days / 30) }
        return L("card_interval_years_short", Double(days) / 365.0)
    }

    private var finishedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Label(L("review_finished_title"), systemImage: "checkmark.circle.fill")
                .amgiStatusText(.positive, font: .sectionHeading)
            Text(L("review_finished_count", session.sessionStats.reviewed))
                .foregroundStyle(.secondary)
            if session.sessionStats.reviewed > 0 {
                Text(L("review_finished_accuracy", Int(session.sessionStats.accuracy * 100)))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            GeometryReader { geometry in
                let availableWidth = max(geometry.size.width - 32, 0)
                let buttonWidth = availableWidth / 3

                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Text(L("common_done"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 16)
                    }
                    .frame(width: buttonWidth)
                    .buttonStyle(.borderedProminent)
                    .clipShape(Capsule())
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 56)
            .padding(.bottom, 16)
        }
    }

    private func triggerFinishedCelebration() {
        guard session.sessionStats.reviewed > 0 else { return }

        finishedCelebrationHideTask?.cancel()
        finishedCelebrationStart = .now
        finishedCelebrationToken += 1

        withAnimation(.easeIn(duration: 0.12)) {
            showFinishedCelebration = true
        }

        finishedCelebrationHideTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    showFinishedCelebration = false
                }
            }
        }
    }

    private func handleCardGesture(_ gesture: String) {
        guard lookupStack.isEmpty else { return }

        let action: ReviewPreferences.GestureAction
        switch gesture {
        case let tapGesture where tapGesture.hasPrefix("tap:"):
            let rawRegion = String(tapGesture.dropFirst(4))
            let region = ReviewPreferences.TapGestureRegion(rawValue: rawRegion) ?? .middleCenter
            action = configuredTapGestureAction(for: region)
        case "swipeLeft":
            let raw = session.showAnswer ? prefBackSwipeLeftGestureActionRaw : prefFrontSwipeLeftGestureActionRaw
            action = ReviewPreferences.GestureAction(rawValue: raw) ?? .none
        case "swipeRight":
            let raw = session.showAnswer ? prefBackSwipeRightGestureActionRaw : prefFrontSwipeRightGestureActionRaw
            action = ReviewPreferences.GestureAction(rawValue: raw) ?? .none
        default:
            return
        }

        performGestureAction(action)
    }

    private func configuredTapGestureAction(
        for rawRegion: ReviewPreferences.TapGestureRegion
    ) -> ReviewPreferences.GestureAction {
        let resolvedRegion: ReviewPreferences.TapGestureRegion
        switch prefTapGestureLayout {
        case .threeRows:
            resolvedRegion = rawRegion.collapsedToThreeRows
        case .nineGrid:
            resolvedRegion = rawRegion
        }

        let raw = UserDefaults.standard.string(
            forKey: ReviewPreferences.Keys.tapGestureRegionAction(
                isBackSide: session.showAnswer,
                region: resolvedRegion
            )
        ) ?? legacyTapGestureFallbackRawValue(isBackSide: session.showAnswer)

        return ReviewPreferences.GestureAction(rawValue: raw)
            ?? (session.showAnswer ? .none : .showAnswer)
    }

    private func legacyTapGestureFallbackRawValue(isBackSide: Bool) -> String {
        if isBackSide {
            return prefBackTapGestureActionRaw
        }
        return prefFrontTapGestureActionRaw
    }

    private func performGestureAction(_ action: ReviewPreferences.GestureAction) {
        guard session.currentCard != nil else { return }

        switch action {
        case .none:
            return
        case .showAnswer:
            guard !session.showAnswer else { return }
            if session.requiresTypedAnswerInput {
                typedAnswerRequestID += 1
            } else {
                session.revealAnswer()
            }
        case .again:
            guard session.showAnswer else { return }
            ratingButtonAction(.again)
        case .hard:
            guard session.showAnswer else { return }
            ratingButtonAction(.hard)
        case .good:
            guard session.showAnswer else { return }
            ratingButtonAction(.good)
        case .easy:
            guard session.showAnswer else { return }
            ratingButtonAction(.easy)
        case .replayAudio:
            if isAudioPlaying {
                stopAudioRequestID += 1
            } else {
                replayRequestID += 1
            }
        case .goBack:
            onDismiss()
        case .showContextMenu:
            showTriggeredContextMenu = true
        case .editNote:
            Task { await openEditorForCurrentCard() }
        case .editTemplate:
            Task { await openCurrentCardTemplateEditor() }
        case .undo:
            Task { await performUndo() }
        case .showDeckStats:
            showDeckStats = true
        case .showCardInfo:
            showCardInfo = true
        case .moveToDeck:
            Task { await openMoveCurrentCardToDeck() }
        case .changeNotetype:
            Task { await openChangeCurrentCardNotetype() }
        case .setDueDate:
            openSetDueDateForCurrentCard()
        case .suspendCard:
            performCurrentCardAction(
                { try cardClient.suspend($0) },
                errorKey: "card_action_error_suspend"
            )
        case .buryCard:
            performCurrentCardAction(
                { try cardClient.bury($0) },
                errorKey: "card_action_error_bury"
            )
        case .resetCard:
            performCurrentCardAction(
                { try cardClient.resetToNew($0) },
                errorKey: "card_action_error_reset_to_new"
            )
        case .flagNone:
            setCurrentCardFlag(0)
        case .flagRed:
            setCurrentCardFlag(1)
        case .flagOrange:
            setCurrentCardFlag(2)
        case .flagGreen:
            setCurrentCardFlag(3)
        case .flagBlue:
            setCurrentCardFlag(4)
        case .flagPink:
            setCurrentCardFlag(5)
        case .flagCyan:
            setCurrentCardFlag(6)
        case .flagPurple:
            setCurrentCardFlag(7)
        case .userAction1:
            triggerUserAction(1)
        case .userAction2:
            triggerUserAction(2)
        case .userAction3:
            triggerUserAction(3)
        case .userAction4:
            triggerUserAction(4)
        case .userAction5:
            triggerUserAction(5)
        case .userAction6:
            triggerUserAction(6)
        case .userAction7:
            triggerUserAction(7)
        case .userAction8:
            triggerUserAction(8)
        case .userAction9:
            triggerUserAction(9)
        }
    }

    private func triggerUserAction(_ index: Int) {
        pendingUserActionIndex = index
        userActionRequestID += 1
    }

    private func performMarkThenCurrentCardAction(
        _ action: (Int64) throws -> Void,
        errorKey: String
    ) {
        guard let current = session.currentCard?.card else { return }
        do {
            if current.noteID != 0 {
                try tagClient.addTagToNotes(reviewMarkedTag, [current.noteID])
            }
            try action(current.id)
            session.refreshAndAdvance()
        } catch {
            toolbarErrorMessage = L(errorKey, error.localizedDescription)
            showToolbarError = true
        }
    }

    private func performCurrentCardAction(
        _ action: (Int64) throws -> Void,
        errorKey: String
    ) {
        guard let cardId = session.currentCard?.card.id else { return }
        do {
            try action(cardId)
            session.refreshAndAdvance()
        } catch {
            toolbarErrorMessage = L(errorKey, error.localizedDescription)
            showToolbarError = true
        }
    }

    private func setCurrentCardFlag(_ value: UInt32) {
        guard let cardId = session.currentCard?.card.id else { return }
        Task { await setCurrentCardFlag(cardId: cardId, value: value) }
    }

    private func handleControllerButton(_ button: ReviewPreferences.ControllerButton) {
        guard lookupStack.isEmpty else { return }
        let key = ReviewPreferences.Keys.controllerButtonAction(button)
        let raw = UserDefaults.standard.string(forKey: key) ?? defaultControllerAction(for: button).rawValue
        let action = ReviewPreferences.GestureAction(rawValue: raw) ?? .none
        performGestureAction(action)
    }

    private func defaultControllerAction(for button: ReviewPreferences.ControllerButton) -> ReviewPreferences.GestureAction {
        switch button {
        case .buttonA: return session.showAnswer ? .good : .showAnswer
        case .buttonB: return .again
        case .buttonX: return .easy
        case .buttonY: return .hard
        case .rightShoulder: return .replayAudio
        default: return .none
        }
    }

    private func handleKeyboardShortcut(_ shortcut: ReviewPreferences.KeyboardShortcut) {
        guard lookupStack.isEmpty else { return }
        let key = ReviewPreferences.Keys.keyboardShortcutAction(shortcut)
        let raw = UserDefaults.standard.string(forKey: key) ?? defaultKeyboardAction(for: shortcut).rawValue
        let action = ReviewPreferences.GestureAction(rawValue: raw) ?? .none
        performGestureAction(action)
    }

    private func defaultKeyboardAction(for shortcut: ReviewPreferences.KeyboardShortcut) -> ReviewPreferences.GestureAction {
        switch shortcut {
        case .space, .enter:
            return session.showAnswer ? .good : .showAnswer
        case .number1:
            return .again
        case .number2:
            return .hard
        case .number3:
            return .good
        case .number4:
            return .easy
        case .replay:
            return .replayAudio
        case .command1:
            return .userAction1
        case .command2:
            return .userAction2
        case .command3:
            return .userAction3
        case .command4:
            return .userAction4
        case .command5:
            return .userAction5
        case .command6:
            return .userAction6
        case .command7:
            return .userAction7
        case .command8:
            return .userAction8
        case .command9:
            return .userAction9
        }
    }

    private func openEditorForCurrentCard() async {
        guard let noteId = session.currentCard?.card.noteID else { return }
        guard let note = try? noteClient.fetch(noteId) else { return }
        editingNote = note
    }

    private func presentAnkiJSToast(message: String, shortLength: Bool) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.isEmpty == false else { return }
        ankiJSToastDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            ankiJSToastState = AnkiJSToastState(message: trimmedMessage)
        }
        let duration: Duration = shortLength ? .seconds(2) : .seconds(3.5)
        ankiJSToastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                ankiJSToastState = nil
            }
        }
    }

    private func deleteCurrentNote() async {
        guard let noteId = session.currentCard?.card.noteID else { return }
        do {
            try noteClient.delete(noteId)
            await session.refreshAfterCardMutation()
        } catch {
            toolbarErrorMessage = L("review_delete_note_error", error.localizedDescription)
            showToolbarError = true
        }
    }

    private func performUndo() async {
        guard !isUndoing else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            try cardClient.undo()
            await session.refreshAfterUndo()
        } catch {
            undoErrorMessage = L("card_action_error_undo", error.localizedDescription)
            showUndoError = true
        }
    }

    private func openCurrentCardStats() {
        guard let queued = session.currentCard else { return }
        currentCardStatsTarget = ReviewCardStatsTarget(queuedCard: queued)
    }

    @MainActor
    private func openCurrentCardTemplateEditor() async {
        guard let currentCard = session.currentCard?.card else { return }
        guard let note = try? noteClient.fetch(currentCard.noteID) else { return }
        templateEditorTarget = ReviewTemplateEditorTarget(
            notetypeId: note.mid,
            noteId: currentCard.noteID,
            templateIndex: Int(currentCard.templateIdx)
        )
    }

    @MainActor
    private func openMoveCurrentCardToDeck() async {
        do {
            if availableDecks.isEmpty {
                availableDecks = try deckClient.fetchAll().sorted(by: { $0.name < $1.name })
            }
            guard !availableDecks.isEmpty else {
                toolbarErrorMessage = L("review_no_decks_available")
                showToolbarError = true
                return
            }
            showMoveToDeck = true
        } catch {
            toolbarErrorMessage = L("review_move_deck_failed", error.localizedDescription)
            showToolbarError = true
        }
    }

    @MainActor
    private func preloadAvailableDecks() async {
        do {
            availableDecks = try deckClient.fetchAll().sorted(by: { $0.name < $1.name })
        } catch {
            availableDecks = []
        }
    }

    @MainActor
    private func preloadCurrentDeckName() async {
        do {
            currentDeckName = try deckClient.fetchNamesOnly().first(where: { $0.id == deckId })?.name
        } catch {
            currentDeckName = nil
        }
    }

    @MainActor
    private func openChangeCurrentCardNotetype() async {
        guard let noteId = session.currentCard?.card.noteID else { return }
        do {
            changeNotetypeTarget = try notetypesClient.prepareChangeTarget([noteId])
        } catch {
            toolbarErrorMessage = error.localizedDescription
            showToolbarError = true
        }
    }

    private func openSetDueDateForCurrentCard() {
        guard let cardId = session.currentCard?.card.id else { return }
        setDueDateCardID = cardId
        setDueDateInput = ""
        showSetDueDateSheet = true
    }

    @MainActor
    private func openCurrentCardFieldManager() async {
        guard let currentCard = session.currentCard?.card else { return }
        guard let note = try? noteClient.fetch(currentCard.noteID) else {
            toolbarErrorMessage = L("notetype_field_load_failed", L("common_unknown_error"))
            showToolbarError = true
            return
        }
        let notetypeName = (try? notetypesService.getNotetype(note.mid).name) ?? ""
        fieldManagerTarget = ReviewFieldManagerTarget(notetypeId: note.mid, notetypeName: notetypeName)
    }

    @MainActor
    private func moveCurrentCard(to targetDeck: DeckInfo) async {
        guard let cardId = session.currentCard?.card.id else { return }
        do {
            try cardClient.moveToDeck(cardId, targetDeck.id)
            await session.refreshAfterCardMutation()
        } catch {
            toolbarErrorMessage = L("review_move_deck_failed", error.localizedDescription)
            showToolbarError = true
        }
    }

    @MainActor
    private func applySetDueDate() async {
        guard let cardId = setDueDateCardID else { return }
        let days = setDueDateInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !days.isEmpty else { return }

        do {
            try cardClient.setDueDate(cardId, days)
            showSetDueDateSheet = false
            setDueDateCardID = nil
            session.refreshAndAdvance()
        } catch {
            toolbarErrorMessage = L("review_set_due_failed", error.localizedDescription)
            showToolbarError = true
        }
    }

    private func flagLabel(_ flags: UInt32) -> String {
        let userFlag = flags & 0b111
        if userFlag == 0 {
            return L("review_flag_none")
        }
        let names: [String] = ["", L("review_flag_red"), L("review_flag_orange"), L("review_flag_green"), L("review_flag_blue"), L("review_flag_pink"), L("review_flag_cyan"), L("review_flag_purple")]
        let index = Int(userFlag)
        return (index >= 0 && index < names.count && !names[index].isEmpty) ? names[index] : L("flag_other", userFlag)
    }

    private func reviewFlagColor(for value: UInt32) -> Color {
        switch value & 0b111 {
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        case 5: return .pink
        case 6: return .cyan
        case 7: return .purple
        default: return .secondary
        }
    }

    private func reviewFlagButton(_ value: UInt32, cardId: Int64) -> some View {
        let color = reviewFlagColor(for: value)
        return Button {
            Task { await setCurrentCardFlag(cardId: cardId, value: value) }
        } label: {
            Label {
                Text(flagLabel(value))
                    .foregroundStyle(color)
            } icon: {
                reviewFlagMenuIcon(for: value)
            }
        }
    }

    private func reviewFlagMenuIcon(for value: UInt32) -> Image {
        let symbolName = value == 0 ? "flag.slash.fill" : "flag.fill"
        let tint = UIColor(reviewFlagColor(for: value))
        if let image = UIImage(systemName: symbolName)?.withTintColor(tint, renderingMode: .alwaysOriginal) {
            return Image(uiImage: image)
        }
        return Image(systemName: symbolName)
    }

    @MainActor
    private func setCurrentCardFlag(cardId: Int64, value: UInt32) async {
        do {
            try cardClient.flag(cardId, value)
            await session.refreshAfterCardMutation()
        } catch {
            toolbarErrorMessage = L("card_action_error_flag", error.localizedDescription)
            showToolbarError = true
        }
    }

    @MainActor
    private func scheduleAutoAdvanceIfNeeded() {
        autoAdvanceTask?.cancel()
        autoAdvanceDeadline = nil
        guard !session.isFinished, session.currentCard != nil else { return }
        guard let delaySeconds = session.currentAutoAdvanceDelay else { return }
        guard delaySeconds > 0 else { return }
        if session.waitForAudioBeforeAutoAdvance && isAudioPlaying {
            return
        }

        autoAdvanceDeadline = Date().addingTimeInterval(delaySeconds)

        autoAdvanceTask = Task {
            let delayNanos = UInt64(delaySeconds * 1_000_000_000)
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !session.isFinished, session.currentCard != nil else { return }
                if session.waitForAudioBeforeAutoAdvance && isAudioPlaying {
                    autoAdvanceDeadline = nil
                    return
                }
                autoAdvanceDeadline = nil
                session.performAutoAdvanceAction()
            }
        }
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if prefPlayAudioInSilentMode {
                try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            } else {
                try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            try audioSession.setActive(true)
        } catch {
            print("[ReviewView] Audio session configure failed: \(error)")
        }
    }
}

@MainActor
final class ReviewControllerMonitor {
    var onButton: ((ReviewPreferences.ControllerButton) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        connectExistingControllers()
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.connectExistingControllers()
                }
            }
        )
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        GCController.controllers().forEach { controller in
            controller.extendedGamepad?.valueChangedHandler = nil
        }
    }

    private func connectExistingControllers() {
        GCController.controllers().forEach(configure)
    }

    private func configure(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.valueChangedHandler = { [weak self] gamepad, element in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let button = self.controllerButton(for: gamepad, element: element) else { return }
                self.onButton?(button)
            }
        }
    }

    private func controllerButton(
        for gamepad: GCExtendedGamepad,
        element: GCControllerElement
    ) -> ReviewPreferences.ControllerButton? {
        if let button = gamepad.leftThumbstickButton,
           element === button,
           button.isPressed {
            return .leftThumbstick
        }
        if let button = gamepad.rightThumbstickButton,
           element === button,
           button.isPressed {
            return .rightThumbstick
        }
        if let button = gamepad.buttonOptions,
           element === button,
           button.isPressed {
            return .options
        }

        switch element {
        case gamepad.buttonA where gamepad.buttonA.isPressed: return .buttonA
        case gamepad.buttonB where gamepad.buttonB.isPressed: return .buttonB
        case gamepad.buttonX where gamepad.buttonX.isPressed: return .buttonX
        case gamepad.buttonY where gamepad.buttonY.isPressed: return .buttonY
        case gamepad.dpad.up where gamepad.dpad.up.isPressed: return .dpadUp
        case gamepad.dpad.down where gamepad.dpad.down.isPressed: return .dpadDown
        case gamepad.dpad.left where gamepad.dpad.left.isPressed: return .dpadLeft
        case gamepad.dpad.right where gamepad.dpad.right.isPressed: return .dpadRight
        case gamepad.leftShoulder where gamepad.leftShoulder.isPressed: return .leftShoulder
        case gamepad.rightShoulder where gamepad.rightShoulder.isPressed: return .rightShoulder
        case gamepad.leftTrigger where gamepad.leftTrigger.isPressed: return .leftTrigger
        case gamepad.rightTrigger where gamepad.rightTrigger.isPressed: return .rightTrigger
        case gamepad.buttonMenu where gamepad.buttonMenu.isPressed: return .menu
        default: return nil
        }
    }
}

@MainActor
final class ReviewKeyboardMonitor {
    var onShortcut: ((ReviewPreferences.KeyboardShortcut) -> Void)?

    private var token: Any?

    func start() {
        token = NotificationCenter.default.addObserver(
            forName: .reviewKeyboardShortcut,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let shortcut = notification.object as? ReviewPreferences.KeyboardShortcut else { return }
            Task { @MainActor [weak self] in
                self?.onShortcut?(shortcut)
            }
        }
    }

    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
    }
}

private extension Notification.Name {
    static let reviewKeyboardShortcut = Notification.Name("amgi.review.keyboard-shortcut")
}

private let reviewMarkedTag = "marked"

private struct AnkiJSToastState: Equatable {
    let message: String
}

private struct AnkiJSSearchSheetRequest: Identifiable {
    let id = UUID()
    let query: String
}

private struct AnkiJSSearchCallbackResult: Encodable, Equatable {
    let cardId: Int64
    let noteId: Int64
    let fieldsData: [String: String]
}

private struct AnkiJSToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 16)
    }
}

private final class ReviewKeyboardCommandHost: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [
            command(input: " ", action: .space),
            command(input: "\r", action: .enter),
            command(input: "1", action: .number1),
            command(input: "2", action: .number2),
            command(input: "3", action: .number3),
            command(input: "4", action: .number4),
            command(input: "r", action: .replay),
            command(input: "1", modifiers: .command, action: .command1),
            command(input: "2", modifiers: .command, action: .command2),
            command(input: "3", modifiers: .command, action: .command3),
            command(input: "4", modifiers: .command, action: .command4),
            command(input: "5", modifiers: .command, action: .command5),
            command(input: "6", modifiers: .command, action: .command6),
            command(input: "7", modifiers: .command, action: .command7),
            command(input: "8", modifiers: .command, action: .command8),
            command(input: "9", modifiers: .command, action: .command9)
        ]
    }

    private func command(
        input: String,
        modifiers: UIKeyModifierFlags = [],
        action: ReviewPreferences.KeyboardShortcut
    ) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: modifiers,
            action: #selector(handleKeyCommand(_:))
        )
        command.discoverabilityTitle = action.rawValue
        return command
    }

    @objc private func handleKeyCommand(_ sender: UIKeyCommand) {
        guard let shortcut = ReviewPreferences.KeyboardShortcut(rawValue: sender.discoverabilityTitle ?? "") else {
            return
        }
        NotificationCenter.default.post(name: .reviewKeyboardShortcut, object: shortcut)
    }
}

private struct ReviewKeyboardCommandBridge: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ReviewKeyboardCommandHost {
        ReviewKeyboardCommandHost()
    }

    func updateUIViewController(_ uiViewController: ReviewKeyboardCommandHost, context: Context) {}
}

private struct ReviewCardStatsTarget: Identifiable {
    let queuedCard: Anki_Scheduler_QueuedCards.QueuedCard

    var id: Int64 {
        queuedCard.card.id
    }
}

private struct ReviewTemplateEditorTarget: Identifiable {
    let notetypeId: Int64
    let noteId: Int64
    let templateIndex: Int

    var id: String {
        "\(notetypeId)-\(noteId)-\(templateIndex)"
    }
}

private struct ReviewFieldManagerTarget: Identifiable {
    let notetypeId: Int64
    let notetypeName: String

    var id: Int64 {
        notetypeId
    }
}

private struct ReviewContextActionsSheet: View {
    let hasNote: Bool
    let onClose: () -> Void
    let onSuspend: () -> Void
    let onBury: () -> Void
    let onMarkAndSuspend: () -> Void
    let onMarkAndBury: () -> Void
    let onReset: () -> Void
    let onSetDueDate: () -> Void
    let onUndo: () -> Void
    let onFlag: (UInt32) -> Void
    let onUserAction: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(L("review_context_section_card_actions")) {
                    Button(L("card_action_suspend"), action: onSuspend)
                    Button(L("card_action_bury"), action: onBury)
                    if hasNote {
                        Button(L("card_action_mark_and_suspend"), action: onMarkAndSuspend)
                        Button(L("card_action_mark_and_bury"), action: onMarkAndBury)
                    }
                    Button(L("card_action_reset_to_new"), action: onReset)
                    Button(L("card_action_set_due_date"), action: onSetDueDate)
                    Button(L("card_action_undo"), action: onUndo)
                }

                Section(L("card_action_flag")) {
                    Button(L("review_flag_clear")) { onFlag(0) }
                    Button(L("review_flag_red")) { onFlag(1) }
                    Button(L("review_flag_orange")) { onFlag(2) }
                    Button(L("review_flag_green")) { onFlag(3) }
                    Button(L("review_flag_blue")) { onFlag(4) }
                    Button(L("review_flag_pink")) { onFlag(5) }
                    Button(L("review_flag_cyan")) { onFlag(6) }
                    Button(L("review_flag_purple")) { onFlag(7) }
                }

                Section(L("review_user_actions")) {
                    ForEach(1...9, id: \.self) { index in
                        Button(String(format: L("review_user_action_number"), index)) {
                            onUserAction(index)
                        }
                    }
                }
            }
            .navigationTitle(L("review_context_menu_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done"), action: onClose)
                }
            }
        }
    }
}

private struct ReviewSetDueDateSheet: View {
    @Binding var dueDays: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var trimmedDueDays: String {
        dueDays.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L("review_set_due_prompt"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField(L("review_set_due_placeholder"), text: $dueDays)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(L("review_set_due_hint"))
                }
            }
            .navigationTitle(L("review_set_due_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common_save")) {
                        onSave()
                    }
                    .amgiToolbarTextButton()
                    .disabled(trimmedDueDays.isEmpty)
                }
            }
        }
    }
}

private struct ReviewAutoAdvanceTimerView: View {
    let deadline: Date?
    let fallbackSeconds: Double

    var body: some View {
        Group {
            if let deadline {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    timerLabel(seconds: max(deadline.timeIntervalSince(context.date), 0))
                }
            } else {
                timerLabel(seconds: fallbackSeconds)
            }
        }
    }

    private func timerLabel(seconds: Double) -> some View {
        Label {
            Text(formattedSeconds(seconds))
                .monospacedDigit()
        } icon: {
            Image(systemName: "timer")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func formattedSeconds(_ seconds: Double) -> String {
        if seconds >= 10 {
            return L("card_interval_seconds_short", Int(seconds.rounded()))
        }
        return L("card_interval_seconds_short_decimal", seconds)
    }
}

private struct ReviewCardStatsSheet: View {
    let queuedCard: Anki_Scheduler_QueuedCards.QueuedCard
    @Dependency(\.statsClient) var statsClient
    @Environment(\.dismiss) private var dismiss

    @State private var cardStats: Anki_Stats_CardStatsResponse?
    @State private var isLoadingStats = true
    @State private var statsError: String?

    private var card: Anki_Cards_Card { queuedCard.card }

    private var memoryState: Anki_Cards_FsrsMemoryState? {
        if let cardStats, cardStats.hasMemoryState {
            return cardStats.memoryState
        }
        if card.hasMemoryState {
            return card.memoryState
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoadingStats {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if let statsError {
                    Section {
                        Text(statsError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L("card_info_section_review_status")) {
                    row(L("card_info_queue"), queueLabel(queuedCard.queue))

                    if let cardStats {
                        row(L("card_info_added"), absoluteDate(cardStats.added))
                        if cardStats.hasFirstReview {
                            row(L("card_info_first_review"), absoluteDate(cardStats.firstReview))
                        }
                        if cardStats.hasLatestReview {
                            row(L("card_info_last_review"), absoluteDate(cardStats.latestReview))
                        }
                        if cardStats.hasDueDate {
                            row(L("card_info_due"), absoluteDate(cardStats.dueDate))
                        } else {
                            row(L("card_info_due"), dueDateString(card.due, queue: queuedCard.queue))
                        }
                        if cardStats.hasDuePosition {
                            row(L("card_info_due_position"), "\(cardStats.duePosition)")
                        }
                        row(L("card_info_interval"), formatInterval(Int(cardStats.interval)))
                        if cardStats.ease > 0 {
                            row(L("card_info_ease"), String(format: "%.0f%%", Double(cardStats.ease) / 10.0))
                        }
                        row(L("card_info_reps"), "\(cardStats.reviews)")
                        row(L("card_info_lapses"), "\(cardStats.lapses)")
                        if cardStats.averageSecs > 0 {
                            row(L("card_info_average_time"), formatDurationSeconds(Double(cardStats.averageSecs)))
                        }
                        if cardStats.totalSecs > 0 {
                            row(L("card_info_total_time"), formatDurationSeconds(Double(cardStats.totalSecs)))
                        }
                    } else {
                        row(L("card_info_interval"), formatInterval(Int(card.interval)))
                        row(L("card_info_due"), dueDateString(card.due, queue: queuedCard.queue))
                        row(L("card_info_reps"), "\(card.reps)")
                        row(L("card_info_lapses"), "\(card.lapses)")
                        if card.interval > 0 {
                            row(L("card_info_ease"), String(format: "%.0f%%", Double(card.easeFactor) / 10.0))
                        }
                    }
                }

                if let memoryState {
                    Section(L("card_info_section_fsrs")) {
                        row(L("card_info_stability"), formatStability(memoryState.stability))
                        row(L("card_info_difficulty"), String(format: "%.0f%%", Double(memoryState.difficulty) * 10.0))
                        if let cardStats, cardStats.hasFsrsRetrievability {
                            row(L("card_info_retrievability"), String(format: "%.0f%%", Double(cardStats.fsrsRetrievability) * 100.0))
                        }
                        if let cardStats, cardStats.hasDesiredRetention {
                            row(L("card_info_retention"), String(format: "%.0f%%", Double(cardStats.desiredRetention) * 100.0))
                        } else if card.hasDesiredRetention {
                            row(L("card_info_retention"), String(format: "%.0f%%", Double(card.desiredRetention) * 100))
                        }
                        if let cardStats, cardStats.hasLatestReview {
                            row(L("card_info_last_review"), absoluteDate(cardStats.latestReview))
                        } else if card.hasLastReviewTimeSecs {
                            row(L("card_info_last_review"), absoluteDate(card.lastReviewTimeSecs))
                        }
                    }
                }

                if memoryState != nil {
                    Section(L("card_info_section_forgetting_curve")) {
                        forgettingCurveView
                    }
                }

                if let cardStats, !cardStats.revlog.isEmpty {
                    Section(L("card_info_section_history")) {
                        historyHeader
                        ForEach(Array(cardStats.revlog.prefix(30).enumerated()), id: \.offset) { _, entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .navigationTitle(L("review_current_card_stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                }
            }
            .task {
                await loadCardStats()
            }
        }
    }

    private var forgettingCurveView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(forgettingCurvePoints, id: \.day) { point in
                    LineMark(
                        x: .value("day", point.day),
                        y: .value("retention", point.retention * 100.0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)

                    AreaMark(
                        x: .value("day", point.day),
                        y: .value("retention", point.retention * 100.0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.22), .blue.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                RuleMark(y: .value("target", targetRetention * 100.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.cyan)

                if let latest = forgettingCurvePoints.last {
                    PointMark(
                        x: .value("day", latest.day),
                        y: .value("retention", latest.retention * 100.0)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .frame(height: 200)
            .chartYScale(domain: 0...100)
            .chartXAxis { AxisMarks(position: .bottom) }
            .chartYAxis { AxisMarks(position: .leading) }

            Text(L("card_info_curve_target", Int((targetRetention * 100.0).rounded())))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var targetRetention: Double {
        if let cardStats, cardStats.hasDesiredRetention {
            return min(max(Double(cardStats.desiredRetention), 0.0), 1.0)
        }
        if card.hasDesiredRetention {
            return min(max(Double(card.desiredRetention), 0.0), 1.0)
        }
        return 0.80
    }

    private var forgettingCurvePoints: [(day: Double, retention: Double)] {
        guard let memoryState else { return [] }

        let stability = max(Double(memoryState.stability), 0.05)
        let horizon = min(max(stability * 6.0, 7.0), 365.0)
        let step = max(horizon / 40.0, 0.25)

        var points: [(day: Double, retention: Double)] = []
        var day = 0.0
        while day <= horizon {
            let retention = exp(log(0.9) * day / stability)
            points.append((day: day, retention: retention))
            day += step
        }

        if points.last?.day ?? 0 < horizon {
            let retention = exp(log(0.9) * horizon / stability)
            points.append((day: horizon, retention: retention))
        }
        return points
    }

    private var historyHeader: some View {
        HStack {
            Text(L("card_info_history_date"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L("card_info_history_rating"))
                .frame(width: 44, alignment: .center)
            Text(L("card_info_history_interval"))
                .frame(width: 78, alignment: .trailing)
            Text(L("card_info_history_time"))
                .frame(width: 78, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func historyRow(_ entry: Anki_Stats_CardStatsResponse.StatsRevlogEntry) -> some View {
        HStack {
            Text(absoluteDateFlexible(entry.time))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entry.buttonChosen)")
                .foregroundStyle(entry.buttonChosen == 1 ? .red : .primary)
                .frame(width: 44, alignment: .center)
            Text(formatIntervalSeconds(Int(entry.interval)))
                .frame(width: 78, alignment: .trailing)
            Text(formatDurationSeconds(Double(entry.takenSecs)))
                .frame(width: 78, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func queueLabel(_ queue: Anki_Scheduler_QueuedCards.Queue) -> String {
        switch queue {
        case .new: return L("card_queue_new")
        case .learning: return L("card_queue_learning")
        case .review: return L("card_queue_review")
        case .UNRECOGNIZED(let v): return L("card_queue_unknown", v)
        }
    }

    private func formatInterval(_ days: Int) -> String {
        if days == 0 { return L("card_interval_less_than_1d") }
        if days < 30 { return L("card_interval_days", days) }
        if days < 365 { return L("card_interval_months", days / 30) }
        return L("card_interval_years", Double(days) / 365.0)
    }

    private func formatIntervalSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return L("card_info_seconds_fmt", seconds) }
        if seconds < 3600 { return L("card_info_minutes_fmt", Double(seconds) / 60.0) }
        if seconds < 86_400 { return L("card_interval_hours_short_decimal", Double(seconds) / 3600.0) }
        return L("card_interval_days", Int(Double(seconds) / 86_400.0))
    }

    private func formatDurationSeconds(_ seconds: Double) -> String {
        if seconds < 60 { return L("card_info_seconds_fmt", Int(seconds.rounded())) }
        return L("card_info_minutes_fmt", seconds / 60.0)
    }

    private func formatStability(_ days: Float) -> String {
        if days < 1 {
            let hours = max(1, Int((Double(days) * 24.0).rounded()))
            return L("card_info_hours_fmt", hours)
        }
        return String(format: L("card_info_stability_fmt"), days)
    }

    private func dueDateString(_ due: Int32, queue: Anki_Scheduler_QueuedCards.Queue) -> String {
        switch queue {
        case .new:
            return L("card_due_position", due)
        case .learning:
            let date = Date(timeIntervalSince1970: Double(due))
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = .current
            return fmt.localizedString(for: date, relativeTo: Date())
        case .review:
            let ankiEpoch: TimeInterval = 1136073600
            let dueDate = Date(timeIntervalSince1970: ankiEpoch + Double(due) * 86400)
            if Calendar.current.isDateInToday(dueDate) { return L("common_today") }
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = .current
            return fmt.localizedString(for: dueDate, relativeTo: Date())
        default:
            return "\(due)"
        }
    }

    private func absoluteDate(_ unixSecs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(unixSecs))
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private func absoluteDateFlexible(_ unix: Int64) -> String {
        let seconds = unix > 100_000_000_000 ? Double(unix) / 1000.0 : Double(unix)
        let date = Date(timeIntervalSince1970: seconds)
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private func loadCardStats() async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        do {
            let data = try statsClient.fetchCardStats(card.id)
            cardStats = try Anki_Stats_CardStatsResponse(serializedBytes: data)
            statsError = nil
        } catch {
            statsError = error.localizedDescription
        }
    }
}

private struct ReviewCardInfoSheet: View {
    let queuedCard: Anki_Scheduler_QueuedCards.QueuedCard
    @Dependency(\.statsClient) var statsClient
    @Environment(\.dismiss) private var dismiss

    @State private var cardStats: Anki_Stats_CardStatsResponse?
    @State private var isLoadingStats = true
    @State private var statsError: String?

    private var card: Anki_Cards_Card { queuedCard.card }

    private var memoryState: Anki_Cards_FsrsMemoryState? {
        if let cardStats, cardStats.hasMemoryState {
            return cardStats.memoryState
        }
        if card.hasMemoryState {
            return card.memoryState
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                if isLoadingStats {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                if let statsError {
                    Section {
                        Text(statsError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - 复习状态
                Section(L("card_info_section_review_status")) {
                    row(L("card_info_queue"), queueLabel(queuedCard.queue))

                    if let cardStats {
                        row(L("card_info_added"), absoluteDate(cardStats.added))
                        if cardStats.hasFirstReview {
                            row(L("card_info_first_review"), absoluteDate(cardStats.firstReview))
                        }
                        if cardStats.hasLatestReview {
                            row(L("card_info_last_review"), absoluteDate(cardStats.latestReview))
                        }
                        if cardStats.hasDueDate {
                            row(L("card_info_due"), absoluteDate(cardStats.dueDate))
                        } else {
                            row(L("card_info_due"), dueDateString(card.due, queue: queuedCard.queue))
                        }
                        if cardStats.hasDuePosition {
                            row(L("card_info_due_position"), "\(cardStats.duePosition)")
                        }
                        row(L("card_info_interval"), formatInterval(Int(cardStats.interval)))
                        if cardStats.ease > 0 {
                            row(L("card_info_ease"), String(format: "%.0f%%", Double(cardStats.ease) / 10.0))
                        }
                        row(L("card_info_reps"), "\(cardStats.reviews)")
                        row(L("card_info_lapses"), "\(cardStats.lapses)")
                        if cardStats.averageSecs > 0 {
                            row(L("card_info_average_time"), formatDurationSeconds(Double(cardStats.averageSecs)))
                        }
                        if cardStats.totalSecs > 0 {
                            row(L("card_info_total_time"), formatDurationSeconds(Double(cardStats.totalSecs)))
                        }
                    } else {
                        row(L("card_info_interval"), formatInterval(Int(card.interval)))
                        row(L("card_info_due"), dueDateString(card.due, queue: queuedCard.queue))
                        row(L("card_info_reps"), "\(card.reps)")
                        row(L("card_info_lapses"), "\(card.lapses)")
                        if card.interval > 0 {
                            row(L("card_info_ease"), String(format: "%.0f%%", Double(card.easeFactor) / 10.0))
                        }
                    }
                }

                // MARK: - FSRS 状态（有 memoryState 时显示）
                if let memoryState {
                    Section(L("card_info_section_fsrs")) {
                        row(L("card_info_stability"), formatStability(memoryState.stability))
                        row(L("card_info_difficulty"), String(format: "%.0f%%", Double(memoryState.difficulty) * 10.0))
                        if let cardStats, cardStats.hasFsrsRetrievability {
                            row(L("card_info_retrievability"), String(format: "%.0f%%", Double(cardStats.fsrsRetrievability) * 100.0))
                        }
                        if let cardStats, cardStats.hasDesiredRetention {
                            row(L("card_info_retention"), String(format: "%.0f%%", Double(cardStats.desiredRetention) * 100.0))
                        } else if card.hasDesiredRetention {
                            row(L("card_info_retention"), String(format: "%.0f%%", Double(card.desiredRetention) * 100))
                        }
                        if let cardStats, cardStats.hasLatestReview {
                            row(L("card_info_last_review"), absoluteDate(cardStats.latestReview))
                        } else if card.hasLastReviewTimeSecs {
                            row(L("card_info_last_review"), absoluteDate(card.lastReviewTimeSecs))
                        }
                    }
                }

                if memoryState != nil {
                    Section(L("card_info_section_forgetting_curve")) {
                        forgettingCurveView
                    }
                }

                if let cardStats {
                    Section(L("card_info_section_metadata")) {
                        if !cardStats.cardType.isEmpty {
                            row(L("card_info_template"), cardStats.cardType)
                        }
                        if !cardStats.notetype.isEmpty {
                            row(L("card_info_notetype"), cardStats.notetype)
                        }
                        if !cardStats.deck.isEmpty {
                            row(L("card_info_deck"), cardStats.deck)
                        }
                        if !cardStats.preset.isEmpty {
                            row(L("card_info_preset"), cardStats.preset)
                        }
                        if cardStats.hasOriginalDeck {
                            row(L("card_info_original_deck"), cardStats.originalDeck)
                        }
                    }
                }

                // MARK: - ID 信息（技术参考）
                Section(L("card_info_section_ids")) {
                    row(L("card_info_card_id"), "\(card.id)")
                    row(L("card_info_note_id"), "\(card.noteID)")
                    row(L("card_info_deck_id"), "\(card.deckID)")
                    row(L("card_info_template"), "\(card.templateIdx)")
                    if card.flags != 0 {
                        row(L("card_info_flags"), flagLabel(card.flags))
                    }
                }

                if let cardStats, !cardStats.revlog.isEmpty {
                    Section(L("card_info_section_history")) {
                        historyHeader
                        ForEach(Array(cardStats.revlog.prefix(30).enumerated()), id: \.offset) { _, entry in
                            historyRow(entry)
                        }
                    }
                }
            }
            .navigationTitle(L("card_info_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                }
            }
            .task {
                await loadCardStats()
            }
        }
    }

    private var forgettingCurveView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(forgettingCurvePoints, id: \.day) { point in
                    LineMark(
                        x: .value("day", point.day),
                        y: .value("retention", point.retention * 100.0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.blue)

                    AreaMark(
                        x: .value("day", point.day),
                        y: .value("retention", point.retention * 100.0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.22), .blue.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                RuleMark(y: .value("target", targetRetention * 100.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.cyan)

                if let latest = forgettingCurvePoints.last {
                    PointMark(
                        x: .value("day", latest.day),
                        y: .value("retention", latest.retention * 100.0)
                    )
                    .foregroundStyle(.blue)
                }
            }
            .frame(height: 200)
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }

            Text(L("card_info_curve_target", Int((targetRetention * 100.0).rounded())))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var targetRetention: Double {
        if let cardStats, cardStats.hasDesiredRetention {
            return min(max(Double(cardStats.desiredRetention), 0.0), 1.0)
        }
        if card.hasDesiredRetention {
            return min(max(Double(card.desiredRetention), 0.0), 1.0)
        }
        return 0.80
    }

    private var forgettingCurvePoints: [(day: Double, retention: Double)] {
        guard let memoryState else { return [] }

        let stability = max(Double(memoryState.stability), 0.05)
        let horizon = min(max(stability * 6.0, 7.0), 365.0)
        let step = max(horizon / 40.0, 0.25)

        var points: [(day: Double, retention: Double)] = []
        var day = 0.0
        while day <= horizon {
            // FSRS stability definition: at t = stability, retention is about 90%.
            let retention = exp(log(0.9) * day / stability)
            points.append((day: day, retention: retention))
            day += step
        }

        if points.last?.day ?? 0 < horizon {
            let retention = exp(log(0.9) * horizon / stability)
            points.append((day: horizon, retention: retention))
        }
        return points
    }

    private var historyHeader: some View {
        HStack {
            Text(L("card_info_history_date"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L("card_info_history_rating"))
                .frame(width: 44, alignment: .center)
            Text(L("card_info_history_interval"))
                .frame(width: 78, alignment: .trailing)
            Text(L("card_info_history_time"))
                .frame(width: 78, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func historyRow(_ entry: Anki_Stats_CardStatsResponse.StatsRevlogEntry) -> some View {
        HStack {
            Text(absoluteDateFlexible(entry.time))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entry.buttonChosen)")
                .foregroundStyle(entry.buttonChosen == 1 ? .red : .primary)
                .frame(width: 44, alignment: .center)
            Text(formatIntervalSeconds(Int(entry.interval)))
                .frame(width: 78, alignment: .trailing)
            Text(formatDurationSeconds(Double(entry.takenSecs)))
                .frame(width: 78, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func queueLabel(_ queue: Anki_Scheduler_QueuedCards.Queue) -> String {
        switch queue {
        case .new: return L("card_queue_new")
        case .learning: return L("card_queue_learning")
        case .review: return L("card_queue_review")
        case .UNRECOGNIZED(let v): return L("card_queue_unknown", v)
        }
    }

    private func formatInterval(_ days: Int) -> String {
        if days == 0 { return L("card_interval_less_than_1d") }
        if days < 30 { return L("card_interval_days", days) }
        if days < 365 { return L("card_interval_months", days / 30) }
        return L("card_interval_years", Double(days) / 365.0)
    }

    private func formatIntervalSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return L("card_info_seconds_fmt", seconds) }
        if seconds < 3600 { return L("card_info_minutes_fmt", Double(seconds) / 60.0) }
        if seconds < 86_400 { return L("card_interval_hours_short_decimal", Double(seconds) / 3600.0) }
        return L("card_interval_days", Int(Double(seconds) / 86_400.0))
    }

    private func formatDurationSeconds(_ seconds: Double) -> String {
        if seconds < 60 { return L("card_info_seconds_fmt", Int(seconds.rounded())) }
        return L("card_info_minutes_fmt", seconds / 60.0)
    }

    private func formatStability(_ days: Float) -> String {
        if days < 1 {
            let hours = max(1, Int((Double(days) * 24.0).rounded()))
            return L("card_info_hours_fmt", hours)
        }
        return String(format: L("card_info_stability_fmt"), days)
    }

    private func dueDateString(_ due: Int32, queue: Anki_Scheduler_QueuedCards.Queue) -> String {
        switch queue {
        case .new:
            return L("card_due_position", due)
        case .learning:
            // due is Unix timestamp for learning cards
            let date = Date(timeIntervalSince1970: Double(due))
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = .current
            return fmt.localizedString(for: date, relativeTo: Date())
        case .review:
            // due is days since epoch (Anki day 0 = 2006-01-01)
            let ankiEpoch: TimeInterval = 1136073600 // 2006-01-01 UTC
            let dueDate = Date(timeIntervalSince1970: ankiEpoch + Double(due) * 86400)
            if Calendar.current.isDateInToday(dueDate) { return L("common_today") }
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = .current
            return fmt.localizedString(for: dueDate, relativeTo: Date())
        default:
            return "\(due)"
        }
    }

    private func absoluteDate(_ unixSecs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(unixSecs))
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private func absoluteDateFlexible(_ unix: Int64) -> String {
        let seconds = unix > 100_000_000_000 ? Double(unix) / 1000.0 : Double(unix)
        let date = Date(timeIntervalSince1970: seconds)
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private func relativeDate(_ unixSecs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(unixSecs))
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = .current
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func loadCardStats() async {
        isLoadingStats = true
        defer { isLoadingStats = false }

        do {
            let data = try statsClient.fetchCardStats(card.id)
            cardStats = try Anki_Stats_CardStatsResponse(serializedBytes: data)
            statsError = nil
        } catch {
            statsError = error.localizedDescription
        }
    }

    private func flagLabel(_ flags: UInt32) -> String {
        let userFlag = flags & 0b111
        if userFlag == 0 {
            return L("flag_none")
        }
        let names: [String] = ["", L("flag_red"), L("flag_orange"), L("flag_green"), L("flag_blue"), L("flag_pink"), L("flag_cyan"), L("flag_purple")]
        let idx = Int(userFlag)
        return (idx >= 0 && idx < names.count && !names[idx].isEmpty) ? names[idx] : L("flag_other", userFlag)
    }

    private func reviewFlagColor(for value: UInt32) -> Color {
        switch value & 0b111 {
        case 1: return .red
        case 2: return .orange
        case 3: return .green
        case 4: return .blue
        case 5: return .pink
        case 6: return .cyan
        case 7: return .purple
        default: return .secondary
        }
    }
}
