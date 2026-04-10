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
    @State private var showEditSheet = false
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
                    Text("\(session.sessionStats.reviewed) reviewed")
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
                    Button("Done") { onDismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("编辑") {
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
        .sheet(isPresented: $showEditSheet) {
            if let editingNote {
                NavigationStack {
                    NoteEditorView(note: editingNote) {
                        Task { await session.refreshAfterCardMutation() }
                    }
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
                    Text("Show Answer")
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
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
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
            Text("Congratulations!")
                .font(.title2.weight(.semibold))
            Text("You've reviewed \(session.sessionStats.reviewed) cards")
                .foregroundStyle(.secondary)
            if session.sessionStats.reviewed > 0 {
                Text("Accuracy: \(Int(session.sessionStats.accuracy * 100))%")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .padding()
        }
    }

    private func openEditorForCurrentCard() async {
        guard let noteId = session.currentCard?.card.noteID else { return }
        guard let note = try? noteClient.fetch(noteId) else { return }
        editingNote = note
        showEditSheet = true
    }
}

private struct ReviewCardInfoSheet: View {
    let queuedCard: Anki_Scheduler_QueuedCards.QueuedCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                row("Card ID", "\(queuedCard.card.id)")
                row("Note ID", "\(queuedCard.card.noteID)")
                row("Deck ID", "\(queuedCard.card.deckID)")
                row("Queue", "\(queuedCard.card.queue)")
                row("Due", "\(queuedCard.card.due)")
                row("Interval", "\(queuedCard.card.interval)")
                row("Reps", "\(queuedCard.card.reps)")
                row("Lapses", "\(queuedCard.card.lapses)")
                row("Flags", "\(queuedCard.card.flags)")
            }
            .navigationTitle("Card Info")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
