//
//  ReaderConfigurationView.swift
//  ReaderFeature
//
//  Created by Vladimir Gusev on 05.05.2026.
//

import Theme
import AnkiClients
import AnkiKit
import Dependencies
import Reader
import Sharing
import SwiftUI

/// Picks the deck that holds books, the notetype its chapters use, and
/// which of that notetype's fields feed the book/chapter shape the reader
/// expects. Persists each value via `@Shared(.appStorage)` so the library
/// view sees changes immediately.
struct ReaderConfigurationView: View {
    let onDismiss: () -> Void

    @State private var model = ReaderConfigurationModel()
    @Environment(\.palette) private var palette

    @Shared(.appStorage(ReaderPreferenceKey.deckName)) private var deckName: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.notetypeID)) private var notetypeID: Int? = nil
    @Shared(.appStorage(ReaderPreferenceKey.bookIDField)) private var bookIDField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.bookTitleField)) private var bookTitleField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.bookCoverField)) private var bookCoverField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.chapterTitleField)) private var chapterTitleField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.chapterOrderField)) private var chapterOrderField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.contentField)) private var contentField: String = ""
    @Shared(.appStorage(ReaderPreferenceKey.languageField)) private var languageField: String = ""

    private var selectedNotetype: ReaderNotetypeChoice? {
        model.notetype(id: notetypeID)
    }

    var body: some View {
        Form {
            Section(String(localized: "Deck", bundle: .module)) {
                if model.decks.isEmpty {
                    Text("Loading decks…", bundle: .module).foregroundStyle(palette.textSecondary)
                } else {
                    Picker(String(localized: "Deck", bundle: .module), selection: Binding($deckName)) {
                        Text("Select a deck", bundle: .module).tag("")
                        ForEach(model.decks, id: \.id) { deck in
                            Text(deck.name).tag(deck.name)
                        }
                    }
                }
                notetypeRow
            }

            Section {
                ForEach(ReaderFieldSlot.allCases, id: \.self) { slot in
                    fieldRow(slot)
                }
            } header: {
                Text("Field mapping", bundle: .module)
            } footer: {
                Text(fieldMappingFooter)
            }

            if let loadError = model.loadError {
                Section { Text(loadError).foregroundStyle(palette.danger) }
            }
            if let notetypeError = model.notetypeError {
                Section { Text(notetypeError).foregroundStyle(palette.danger) }
            }
        }
        .navigationTitle(String(localized: "Reader Setup", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done", bundle: .module)) { onDismiss() }
            }
        }
        .task { await model.loadDecks() }
        .task(id: deckName) {
            await model.loadNotetypes(deckName: deckName)
            // A failed load says nothing about the stored notetype; keep it.
            guard !Task.isCancelled, model.notetypesDeckName == deckName, model.notetypeError == nil else { return }
            selectNotetype(model.resolvedNotetypeID(current: notetypeID))
        }
    }

    // MARK: - Notetype

    @ViewBuilder
    private var notetypeRow: some View {
        if deckName.isEmpty {
            EmptyView()
        } else if model.isLoadingNotetypes || model.notetypesDeckName != deckName {
            LabeledContent(String(localized: "Note type", bundle: .module)) {
                ProgressView()
            }
        } else if model.notetypes.isEmpty {
            Text("This deck has no notes yet.", bundle: .module)
                .foregroundStyle(palette.textSecondary)
        } else if model.notetypes.count == 1 {
            LabeledContent(String(localized: "Note type", bundle: .module), value: model.notetypes[0].name)
        } else {
            Picker(String(localized: "Note type", bundle: .module), selection: Binding(
                get: { notetypeID },
                set: { selectNotetype($0) }
            )) {
                Text("Select a note type", bundle: .module).tag(Int?.none)
                ForEach(model.notetypes) { choice in
                    Text(choice.name).tag(Int?.some(Int(choice.id.rawValue)))
                }
            }
        }
    }

    /// Stores the notetype and fills any still-empty slot with a field
    /// whose name clearly matches. Slots the user already set are kept,
    /// even when the new notetype lacks that field; the row flags it.
    private func selectNotetype(_ id: Int?) {
        $notetypeID.withLock { $0 = id }
        guard let choice = model.notetype(id: id) else { return }
        let guesses = ReaderFieldSlot.guessMapping(fieldNames: choice.fieldNames)
        for slot in ReaderFieldSlot.allCases {
            guard value(for: slot).isEmpty, let guess = guesses[slot] else { continue }
            setValue(guess, for: slot)
        }
    }

    // MARK: - Field rows

    @ViewBuilder
    private func fieldRow(_ slot: ReaderFieldSlot) -> some View {
        let current = value(for: slot)
        let fieldNames = selectedNotetype?.fieldNames ?? []
        let isMissing = !current.isEmpty && !fieldNames.contains(current)

        Picker(selection: Binding(get: { current }, set: { setValue($0, for: slot) })) {
            if slot.isOptional {
                Text("None", bundle: .module).tag("")
            } else {
                Text("Select a field", bundle: .module).tag("")
            }
            ForEach(fieldNames, id: \.self) { name in
                Text(name).tag(name)
            }
            if isMissing {
                Text("\(current) (not found)", bundle: .module).tag(current)
            }
        } label: {
            Text(title(for: slot))
            if isMissing, selectedNotetype != nil {
                Text("Not a field of this note type", bundle: .module)
                    .foregroundStyle(palette.danger)
            }
        }
        .disabled(selectedNotetype == nil)
    }

    private var fieldMappingFooter: String {
        if !deckName.isEmpty, selectedNotetype == nil, model.notetypes.count > 1 {
            return String(localized: "Choose a note type to pick its fields.", bundle: .module)
        }
        return String(localized: "Each note becomes a chapter; chapters with the same Book ID collapse into one book.", bundle: .module)
    }

    private func title(for slot: ReaderFieldSlot) -> String {
        switch slot {
        case .bookID: String(localized: "Book ID", bundle: .module)
        case .bookTitle: String(localized: "Book title", bundle: .module)
        case .bookCover: String(localized: "Book cover", bundle: .module)
        case .chapterTitle: String(localized: "Chapter title", bundle: .module)
        case .chapterOrder: String(localized: "Chapter order", bundle: .module)
        case .content: String(localized: "Content", bundle: .module)
        case .language: String(localized: "Language", bundle: .module)
        }
    }

    private func value(for slot: ReaderFieldSlot) -> String {
        switch slot {
        case .bookID: bookIDField
        case .bookTitle: bookTitleField
        case .bookCover: bookCoverField
        case .chapterTitle: chapterTitleField
        case .chapterOrder: chapterOrderField
        case .content: contentField
        case .language: languageField
        }
    }

    private func setValue(_ newValue: String, for slot: ReaderFieldSlot) {
        switch slot {
        case .bookID: $bookIDField.withLock { $0 = newValue }
        case .bookTitle: $bookTitleField.withLock { $0 = newValue }
        case .bookCover: $bookCoverField.withLock { $0 = newValue }
        case .chapterTitle: $chapterTitleField.withLock { $0 = newValue }
        case .chapterOrder: $chapterOrderField.withLock { $0 = newValue }
        case .content: $contentField.withLock { $0 = newValue }
        case .language: $languageField.withLock { $0 = newValue }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    // deckClient.previewValue feeds the deck picker; the field-mapping rows
    // read their @Shared appStorage defaults.
    let _ = prepareDependencies { $0.deckClient = .previewValue }
    return NavigationStack {
        ReaderConfigurationView(onDismiss: {})
    }
}
#endif
