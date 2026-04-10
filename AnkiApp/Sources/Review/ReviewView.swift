import SwiftUI
import AnkiKit
import AnkiClients
import AnkiProto
import Dependencies

struct ReviewView: View {
    let deckId: Int64
    let onDismiss: () -> Void

    @Dependency(\.noteClient) var noteClient

    @State private var session: ReviewSession
    @State private var editingNote: NoteRecord?
    @State private var showCardInfo = false

    init(deckId: Int64, onDismiss: @escaping () -> Void) {
        self.deckId = deckId
        self.onDismiss = onDismiss
        self._session = State(initialValue: ReviewSession(deckId: deckId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    DeckCountsView(counts: session.remainingCounts)
                    Spacer()
                    Text(L("review_reviewed_count", session.sessionStats.reviewed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if session.isFinished {
                    finishedView
                } else {
                    cardView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_done")) { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("review_edit_button")) {
                        Task { await openEditorForCurrentCard() }
                    }
                    .disabled(session.currentCard == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCardInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .disabled(session.currentCard == nil)
                }
            }
        }
        .task {
            session.start()
        }
        .sheet(item: $editingNote) { note in
            NavigationStack {
                NoteEditorView(note: note) {
                    Task { await session.refreshAfterCardMutation() }
                }
            }
        }
        .sheet(isPresented: $showCardInfo) {
            if let queued = session.currentCard {
                ReviewCardInfoSheet(queuedCard: queued)
            }
        }
    }

    @ViewBuilder
    private var cardView: some View {
        VStack(spacing: 0) {
            if session.showAnswer {
                CardWebView(html: session.backHTML)
            } else {
                CardWebView(html: session.frontHTML)
            }

            Spacer()

            if session.showAnswer {
                HStack {
                    Spacer()
                    if !session.isFinished, let current = session.currentCard {
                        CardContextMenu(
                            cardId: current.card.id,
                            onActionSuccess: { shouldAdvance in
                                if shouldAdvance {
                                    session.refreshAndAdvance()
                                } else {
                                    Task { await session.refreshAfterCardMutation() }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                answerButtons
            } else {
                Button {
                    session.revealAnswer()
                } label: {
                    Text(L("review_show_answer"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }

    private var answerButtons: some View {
        HStack(spacing: 8) {
            ratingButton(.again, color: .red)
            ratingButton(.hard, color: .orange)
            ratingButton(.good, color: .green)
            ratingButton(.easy, color: .blue)
        }
        .padding()
    }

    private func ratingButton(_ rating: Rating, color: Color) -> some View {
        Button {
            session.answer(rating: rating)
        } label: {
            VStack(spacing: 4) {
                Text(session.nextIntervals[rating] ?? "")
                    .font(.caption2)
                Text(ratingLabel(rating))
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private func ratingLabel(_ rating: Rating) -> String {
        switch rating {
        case .again: L("review_rating_again")
        case .hard: L("review_rating_hard")
        case .good: L("review_rating_good")
        case .easy: L("review_rating_easy")
        }
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
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(L("review_finished_title"))
                .font(.title2.weight(.semibold))
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
}

private struct ReviewCardInfoSheet: View {
    let queuedCard: Anki_Scheduler_QueuedCards.QueuedCard
    @Environment(\.dismiss) private var dismiss

    private var card: Anki_Cards_Card { queuedCard.card }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 复习状态
                Section(L("card_info_section_review_status")) {
                    row(L("card_info_queue"), queueLabel(queuedCard.queue))
                    row(L("card_info_interval"), formatInterval(Int(card.interval)))
                    row(L("card_info_due"), dueDateString(card.due, queue: queuedCard.queue))
                    row(L("card_info_reps"), "\(card.reps)")
                    row(L("card_info_lapses"), "\(card.lapses)")
                    if card.interval > 0 {
                        row(L("card_info_ease"), String(format: "%.0f%%", Double(card.easeFactor) / 10.0))
                    }
                }

                // MARK: - FSRS 状态（有 memoryState 时显示）
                if card.hasMemoryState {
                    Section(L("card_info_section_fsrs")) {
                        row(L("card_info_stability"), String(format: L("card_info_stability_fmt"), card.memoryState.stability))
                        row(L("card_info_difficulty"), String(format: "%.2f", card.memoryState.difficulty))
                        if card.hasDesiredRetention {
                            row(L("card_info_retention"), String(format: "%.0f%%", Double(card.desiredRetention) * 100))
                        }
                        if card.hasDecay {
                            row(L("card_info_decay"), String(format: "%.4f", card.decay))
                        }
                        if card.hasLastReviewTimeSecs {
                            row(L("card_info_last_review"), relativeDate(card.lastReviewTimeSecs))
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
            }
            .navigationTitle(L("card_info_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                }
            }
        }
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

    private func relativeDate(_ unixSecs: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(unixSecs))
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = .current
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func flagLabel(_ flags: UInt32) -> String {
        let names: [String] = ["", L("flag_red"), L("flag_orange"), L("flag_green"), L("flag_blue"), L("flag_pink"), L("flag_cyan"), L("flag_purple")]
        let idx = Int(flags)
        return (idx >= 0 && idx < names.count && !names[idx].isEmpty) ? names[idx] : L("flag_other", flags)
    }
}
