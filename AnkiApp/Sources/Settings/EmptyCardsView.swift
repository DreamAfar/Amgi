import SwiftUI
import AnkiBackend
import AnkiClients
import AnkiProto
import Dependencies
import SwiftProtobuf

struct EmptyCardsView: View {
    @Dependency(\.ankiBackend) var backend
    @Dependency(\.cardClient) var cardClient
    @Dependency(\.deckClient) var deckClient
    @Environment(\.dismiss) private var dismiss

    @State private var isLoading = true
    @State private var report: String = ""
    @State private var noteEntries: [NoteEntry] = []
    @State private var isDeletingAll = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSuccess = false

    struct NoteEntry: Identifiable {
        let id: Int64
        let cardIds: [Int64]
        let totalCards: Int
        let emptyCards: Int
        let deckName: String
        let willDeleteNote: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.amgiBackground)
                } else {
                    resultsList
                }
            }
            .navigationTitle(L("empty_cards_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                        .amgiToolbarTextButton()
                }
            }
            .alert(L("empty_cards_delete_confirm_title"), isPresented: $showDeleteConfirm) {
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_delete"), role: .destructive) {
                    Task { await deleteAllEmpty() }
                }
            } message: {
                Text(L("empty_cards_delete_confirm_msg", noteEntries.reduce(0) { $0 + $1.cardIds.count }))
            }
            .alert(L("common_done"), isPresented: $showSuccess) {
                Button(L("common_ok"), role: .cancel) { dismiss() }
            } message: {
                Text(L("empty_cards_deleted_ok"))
            }
            .alert(L("common_error"), isPresented: $showError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await loadEmptyCards() }
        }
    }

    private var resultsList: some View {
        List {
            if noteEntries.isEmpty {
                Section {
                    Label(L("empty_cards_none_found"), systemImage: "checkmark.circle")
                        .amgiStatusText(.positive)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.amgiSurfaceElevated)
                }
            } else {
                Section {
                    Label(
                        L("empty_cards_found_count", noteEntries.reduce(0) { $0 + $1.cardIds.count }),
                        systemImage: "rectangle.stack.badge.minus"
                    )
                    .amgiStatusText(.warning)
                    .listRowBackground(Color.amgiSurfaceElevated)

                    if !report.isEmpty {
                        DisclosureGroup(L("empty_cards_report")) {
                            Text(report)
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                        .listRowBackground(Color.amgiSurfaceElevated)
                    }
                }

                Section(L("empty_cards_section_list")) {
                    ForEach(noteEntries) { entry in
                        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                            Text(L("empty_cards_note_id", entry.id))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.amgiTextPrimary)
                            Text(L("empty_cards_note_summary", entry.totalCards, entry.emptyCards))
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                            Text(L("empty_cards_note_deck", entry.deckName))
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                            if entry.willDeleteNote {
                                Text(L("empty_cards_will_delete_note"))
                                    .amgiStatusText(.danger, font: .caption)
                            }
                        }
                        .listRowBackground(Color.amgiSurfaceElevated)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        if isDeletingAll {
                            HStack {
                                Text(L("empty_cards_delete_all"))
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Label(L("empty_cards_delete_all"), systemImage: "trash")
                        }
                    }
                    .disabled(isDeletingAll)
                    .listRowBackground(Color.amgiSurfaceElevated)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
    }

    private func loadEmptyCards() async {
        let capturedBackend = backend
        let capturedCardClient = cardClient
        let capturedDeckClient = deckClient
        do {
            let response: Anki_CardRendering_EmptyCardsReport = try await Task.detached {
                try capturedBackend.invoke(
                    service: AnkiBackend.Service.cardRendering,
                    method: AnkiBackend.CardRenderingMethod.getEmptyCards
                )
            }.value
            report = response.report

            let deckById = (try? capturedDeckClient.fetchAll())?.reduce(into: [Int64: String]()) { partial, deck in
                partial[deck.id] = deck.name
            } ?? [:]

            noteEntries = response.notes.map { note in
                let cards = (try? capturedCardClient.fetchByNote(note.noteID)) ?? []
                let totalCards = max(cards.count, note.cardIds.count)
                let deckName = cards.first.flatMap { deckById[$0.did] } ?? "-"
                return NoteEntry(
                    id: note.noteID,
                    cardIds: note.cardIds,
                    totalCards: totalCards,
                    emptyCards: note.cardIds.count,
                    deckName: deckName,
                    willDeleteNote: note.willDeleteNote
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isLoading = false
    }

    private func deleteAllEmpty() async {
        isDeletingAll = true
        let allCardIds = noteEntries.flatMap { $0.cardIds }
        let capturedBackend = backend
        do {
            var req = Anki_Cards_RemoveCardsRequest()
            req.cardIds = allCardIds
            try await Task.detached {
                try capturedBackend.callVoid(
                    service: AnkiBackend.Service.cards,
                    method: AnkiBackend.CardsMethod.removeCards,
                    request: req
                )
            }.value
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isDeletingAll = false
    }
}
