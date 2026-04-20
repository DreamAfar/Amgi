import SwiftUI
import Charts
import AVFAudio
import AnkiBackend
import AnkiKit
import AnkiClients
import AnkiProto
import SwiftProtobuf
import Dependencies
import UIKit

struct ReviewView: View {
    @Environment(\.colorScheme) private var colorScheme

    let deckId: Int64
    let onDismiss: () -> Void

    @Dependency(\.noteClient) var noteClient
    @Dependency(\.deckClient) var deckClient
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.ankiBackend) var backend

    @State private var session: ReviewSession
    @State private var editingNote: NoteRecord?
    @State private var showCardInfo = false
    @State private var currentCardStatsTarget: ReviewCardStatsTarget?
    @State private var replayRequestID = 0
    @State private var isAudioPlaying = false
    @State private var autoAdvanceTask: Task<Void, Never>?
    @State private var answerFeedbackSymbol: String?
    @State private var showDeckStats = false
    @State private var templateEditorTarget: ReviewTemplateEditorTarget?
    @State private var showMoveToDeck = false
    @State private var availableDecks: [DeckInfo] = []
    @State private var showChangeNotetype = false
    @State private var noteIDsForNotetypeChange: [Int64] = []
    @State private var fieldManagerTarget: ReviewFieldManagerTarget?
    @State private var toolbarErrorMessage: String?
    @State private var showToolbarError = false
    @State private var showDeleteNoteConfirm = false
    @State private var showUndoError = false
    @State private var undoErrorMessage: String?
    @State private var isUndoing = false
    @State private var showSetDueDateSheet = false
    @State private var setDueDateInput = ""
    @State private var setDueDateCardID: Int64?
    @State private var typedAnswerRequestID = 0
    @State private var isKeyboardVisible = false
    @State private var cardChromeUIColor: UIColor = .systemBackground
    @State private var cardChromeIsDark = false

    @AppStorage(ReviewPreferences.Keys.autoplayAudio) private var prefAutoplayAudio = true
    @AppStorage(ReviewPreferences.Keys.playAudioInSilentMode) private var prefPlayAudioInSilentMode = false
    @AppStorage(ReviewPreferences.Keys.showContextMenuButton) private var prefShowContextMenuButton = true
    @AppStorage(ReviewPreferences.Keys.showAudioReplayButton) private var prefShowAudioReplayButton = true
    @AppStorage(ReviewPreferences.Keys.showCorrectnessSymbols) private var prefShowCorrectnessSymbols = false
    @AppStorage(ReviewPreferences.Keys.disperseAnswerButtons) private var prefDisperseAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.showAnswerButtons) private var prefShowAnswerButtons = true
    @AppStorage(ReviewPreferences.Keys.showRemainingDays) private var prefShowRemainingDays = true
    @AppStorage(ReviewPreferences.Keys.showNextReviewTime) private var prefShowNextReviewTime = false
    @AppStorage(ReviewPreferences.Keys.openLinksExternally) private var prefOpenLinksExternally = true
    @AppStorage(ReviewPreferences.Keys.cardContentAlignment) private var prefCardContentAlignmentRaw = CardWebView.ContentAlignment.top.rawValue
    @AppStorage(ReviewPreferences.Keys.glassAnswerButtons) private var prefGlassAnswerButtons = false
    @AppStorage(ReviewPreferences.Keys.autoMatchCardBackground) private var prefAutoMatchCardBackground = true
    @State private var actionBarHeight: CGFloat = 0

    private var prefCardContentAlignment: CardWebView.ContentAlignment {
        CardWebView.ContentAlignment(rawValue: prefCardContentAlignmentRaw) ?? .top
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
        .background(cardChromeColor.ignoresSafeArea())
        .task {
            cardChromeIsDark = (colorScheme == .dark)
            session.start()
            configureAudioSession()
            scheduleAutoAdvanceIfNeeded()
            await preloadAvailableDecks()
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
            scheduleAutoAdvanceIfNeeded()
        }
        .onChange(of: session.showAnswer) { _, _ in
            scheduleAutoAdvanceIfNeeded()
        }
        .onChange(of: isAudioPlaying) { _, _ in
            scheduleAutoAdvanceIfNeeded()
        }
        .onDisappear {
            autoAdvanceTask?.cancel()
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
        .sheet(isPresented: $showChangeNotetype) {
            ChangeNotetypeSheet(noteIDs: noteIDsForNotetypeChange) {
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
        .sheet(isPresented: $showDeckStats) {
            NavigationStack {
                StatsDashboardView(initialDeckID: deckId)
            }
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
    }

    private var reviewNavigationContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    DeckCountsView(counts: session.remainingCounts)
                    Spacer()
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

    @ToolbarContentBuilder
    private var reviewToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(L("common_done")) { onDismiss() }
                .amgiToolbarTextButton(tone: .neutral)
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
                    replayRequestID += 1
                } label: {
                    Image(systemName: "speaker.wave.2")
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
            .disabled(session.currentCard == nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showDeckStats = true
                } label: {
                    Label(L("stats_nav_title"), systemImage: "chart.bar.doc.horizontal")
                }
                .disabled(session.currentCard == nil)

                Button {
                    Task { await openMoveCurrentCardToDeck() }
                } label: {
                    Label(L("browse_batch_move_deck"), systemImage: "rectangle.stack.badge.plus")
                }
                .disabled(session.currentCard == nil)

                Button {
                    openChangeCurrentCardNotetype()
                } label: {
                    Label(L("browse_batch_change_notetype"), systemImage: "doc.badge.gearshape")
                }
                .disabled(session.currentCard == nil)

                Divider()

                Button(role: .destructive) {
                    showDeleteNoteConfirm = true
                } label: {
                    Label(L("browse_batch_delete_notes"), systemImage: "trash")
                }
                .disabled(session.currentCard == nil)

                Button {
                    showCardInfo = true
                } label: {
                    Label(L("card_info_title"), systemImage: "info.circle")
                }
                .disabled(session.currentCard == nil)
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

        CardWebView(
            html: cardHTML,
            autoplayEnabled: session.autoplayAudio && prefAutoplayAudio,
            isAnswerSide: session.showAnswer,
            cardOrdinal: session.currentCard?.card.templateIdx ?? 0,
            replayRequestID: replayRequestID,
            typedAnswerRequestID: typedAnswerRequestID,
            replayMode: replayMode,
            showInlineAudioReplayButtons: prefShowAudioReplayButton,
            openLinksExternally: prefOpenLinksExternally,
            prefetchHTML: session.showAnswer ? nil : session.backHTML,
            contentAlignment: prefCardContentAlignment,
            bottomContentInset: actionBarHeight,
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
            }
        )
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

                HStack {
                    if usesCompactShowAnswerButton {
                        Spacer()
                    }

                    Button {
                        if session.requiresTypedAnswerInput {
                            typedAnswerRequestID += 1
                        } else {
                            session.revealAnswer()
                        }
                    } label: {
                        Text(L("review_show_answer"))
                            .font(usesCompactShowAnswerButton ? .footnote.weight(.semibold) : .headline)
                            .frame(maxWidth: usesCompactShowAnswerButton ? nil : .infinity)
                            .padding(.horizontal, usesCompactShowAnswerButton ? 12 : 16)
                            .padding(.vertical, usesCompactShowAnswerButton ? 8 : 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(usesCompactShowAnswerButton ? .small : .regular)
                    .clipShape(Capsule())

                    if usesCompactShowAnswerButton {
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, usesCompactShowAnswerButton ? 8 : 16)
                .background(.clear)
                .animation(.easeInOut(duration: 0.18), value: usesCompactShowAnswerButton)
            }
        }
        // Keep the floating review controls transparent so they do not paint an
        // opaque strip over the card content again. The surrounding review screen
        // still provides the toolbar/safe-area chrome color.
        .background(.clear)
    }

    private var answerButtons: some View {
        Group {
            if prefDisperseAnswerButtons {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ratingButton(.again, color: .red)
                        ratingButton(.hard, color: .orange)
                    }
                    HStack(spacing: 8) {
                        ratingButton(.good, color: .green)
                        ratingButton(.easy, color: .blue)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ratingButton(.again, color: .red)
                    ratingButton(.hard, color: .orange)
                    ratingButton(.good, color: .green)
                    ratingButton(.easy, color: .blue)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var compactAnswerMenu: some View {
        Menu {
            Button(ratingLabel(.again)) { session.answer(rating: .again) }
            Button(ratingLabel(.hard)) { session.answer(rating: .hard) }
            Button(ratingLabel(.good)) { session.answer(rating: .good) }
            Button(ratingLabel(.easy)) { session.answer(rating: .easy) }
        } label: {
            Text(L("review_answer_button"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }

    @ViewBuilder
    private func ratingButton(_ rating: Rating, color: Color) -> some View {
        if #available(iOS 26.0, *), prefGlassAnswerButtons {
            Button {
                ratingButtonAction(rating)
            } label: {
                ratingButtonLabel(rating)
            }
            .buttonStyle(.glassProminent)
            .tint(color)
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
        VStack(spacing: 4) {
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
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
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
        if days == 0 { return "<1d" }
        if days < 30 { return "\(days)d" }
        if days < 365 { return "\(days / 30)mo" }
        return String(format: "%.1fy", Double(days) / 365.0)
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
            Button(L("common_done")) { onDismiss() }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }

    private func openEditorForCurrentCard() async {
        guard let noteId = session.currentCard?.card.noteID else { return }
        guard let note = try? noteClient.fetch(noteId) else { return }
        editingNote = note
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

    private func openChangeCurrentCardNotetype() {
        guard let noteId = session.currentCard?.card.noteID else { return }
        noteIDsForNotetypeChange = [noteId]
        showChangeNotetype = true
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
        let notetypeName: String
        do {
            var request = Anki_Notetypes_NotetypeId()
            request.ntid = note.mid
            let notetype: Anki_Notetypes_Notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: request
            )
            notetypeName = notetype.name
        } catch {
            notetypeName = ""
        }
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

    private func scheduleAutoAdvanceIfNeeded() {
        autoAdvanceTask?.cancel()
        guard !session.isFinished, session.currentCard != nil else { return }
        guard let delaySeconds = session.currentAutoAdvanceDelay else { return }
        guard delaySeconds > 0 else { return }
        if session.waitForAudioBeforeAutoAdvance && isAudioPlaying {
            return
        }

        autoAdvanceTask = Task {
            let delayNanos = UInt64(delaySeconds * 1_000_000_000)
            if delayNanos > 0 {
                try? await Task.sleep(nanoseconds: delayNanos)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !session.isFinished, session.currentCard != nil else { return }
                if session.waitForAudioBeforeAutoAdvance && isAudioPlaying {
                    return
                }
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
                    .amgiToolbarTextButton(tone: .neutral)
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
                        .amgiToolbarTextButton()
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
        if seconds < 86_400 { return String(format: "%.1fh", Double(seconds) / 3600.0) }
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
                        .amgiToolbarTextButton()
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
        if seconds < 86_400 { return String(format: "%.1fh", Double(seconds) / 3600.0) }
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
