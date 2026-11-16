//
//  LookupNoteTemplateView.swift
//  SettingsFeature
//

import AnkiClients
import AnkiKit
import AppCore
import Dependencies
import Foundation
import Sharing
import SwiftUI
import Theme

/// Loads the decks and note types the vocabulary-card template can use.
/// Owns the clients so the view carries no `@Dependency`.
@Observable
@MainActor
final class LookupNoteTemplateModel {
    struct NotetypeChoice: Identifiable, Hashable {
        let id: Int64
        let name: String
        let fields: [String]
    }

    private(set) var decks: [DeckInfo] = []
    private(set) var notetypes: [NotetypeChoice] = []
    private(set) var isLoading = true

    @ObservationIgnored @Dependency(\.deckClient) private var deckClient
    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient

    func load() async {
        isLoading = true
        defer { isLoading = false }
        decks = ((try? await deckClient.fetchAll()) ?? [])
            .filter { !$0.isFiltered }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var found: [NotetypeChoice] = []
        for entry in (try? await notetypesClient.listAll()) ?? [] {
            guard let notetype = try? await notetypesClient.get(entry.id) else { continue }
            found.append(NotetypeChoice(id: entry.id.rawValue, name: entry.name, fields: notetype.fields.map(\.name)))
        }
        notetypes = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func fields(of notetypeID: Int64?) -> [String] {
        notetypes.first { $0.id == notetypeID }?.fields ?? []
    }
}

/// Where a new vocabulary note goes and which of its fields each piece of
/// looked-up content fills. Used by the reader's dictionary popup, the
/// reader's "make a card from the selection" button, and quick cards made
/// from a selection during review.
struct LookupNoteTemplateView: View {
    @Shared(.appStorage(ReaderPreferences.Keys.lookupNoteTemplate))
    private var serialized: String = ""

    @State private var model = LookupNoteTemplateModel()

    private var template: ReaderLookupNoteTemplate {
        serialized.isEmpty ? .empty : ReaderLookupNoteTemplate.decode(from: serialized)
    }

    private func update(_ change: (inout ReaderLookupNoteTemplate) -> Void) {
        var value = template
        change(&value)
        $serialized.withLock { $0 = value.encodedString() }
    }

    private struct Slot: Identifiable {
        let id: WritableKeyPath<ReaderLookupNoteTemplate, String>
        let title: String
        let systemImage: String
    }

    private var slots: [Slot] {
        [
            Slot(id: \.termField, title: String(localized: "Word", bundle: .module), systemImage: "character.cursor.ibeam"),
            Slot(id: \.readingField, title: String(localized: "Reading", bundle: .module), systemImage: "textformat.characters"),
            Slot(id: \.sentenceField, title: String(localized: "Sentence", bundle: .module), systemImage: "text.quote"),
            Slot(id: \.definition1Field, title: String(localized: "Definition 1", bundle: .module), systemImage: "book"),
            Slot(id: \.definition2Field, title: String(localized: "Definition 2", bundle: .module), systemImage: "book"),
            Slot(id: \.definition3Field, title: String(localized: "Definition 3", bundle: .module), systemImage: "book"),
            Slot(id: \.explanationField, title: String(localized: "AI explanation", bundle: .module), systemImage: "sparkles"),
            Slot(id: \.translationField, title: String(localized: "Translation", bundle: .module), systemImage: "translate"),
            Slot(id: \.dictionariesField, title: String(localized: "Dictionary names", bundle: .module), systemImage: "books.vertical"),
            Slot(id: \.frequencyField, title: String(localized: "Frequency", bundle: .module), systemImage: "chart.bar"),
            Slot(id: \.pitchField, title: String(localized: "Pitch accent", bundle: .module), systemImage: "waveform"),
            Slot(id: \.deinflectionField, title: String(localized: "Deinflection", bundle: .module), systemImage: "arrow.triangle.branch"),
            Slot(id: \.matchedField, title: String(localized: "Matched text", bundle: .module), systemImage: "highlighter"),
            Slot(id: \.sourceField, title: String(localized: "Source", bundle: .module), systemImage: "link"),
            Slot(id: \.rulesField, title: String(localized: "Grammar rules", bundle: .module), systemImage: "list.bullet"),
        ]
    }

    var body: some View {
        SettingsPage {
            Group {
                SettingsSectionHeader(title: String(localized: "Destination", bundle: .module))
                SettingsGroup {
                    SettingsPickerRow(
                        title: String(localized: "Deck", bundle: .module),
                        systemImage: "rectangle.stack",
                        tone: .accent,
                        selection: Binding(
                            get: { template.deckID ?? 0 },
                            set: { id in update { $0.deckID = id == 0 ? nil : id } }
                        )
                    ) {
                        Text("Default", bundle: .module).tag(Int64(0))
                        ForEach(model.decks) { deck in
                            Text(deck.name).tag(deck.id.rawValue)
                        }
                    }
                    SettingsSeparator()
                    SettingsPickerRow(
                        title: String(localized: "Note type", bundle: .module),
                        systemImage: "doc.text",
                        tone: .accent,
                        selection: Binding(
                            get: { template.notetypeID ?? 0 },
                            set: { id in selectNotetype(id == 0 ? nil : id) }
                        )
                    ) {
                        Text("Default", bundle: .module).tag(Int64(0))
                        ForEach(model.notetypes) { notetype in
                            Text(notetype.name).tag(notetype.id)
                        }
                    }
                }
            }

            let fields = model.fields(of: template.notetypeID)
            if !fields.isEmpty {
                Group {
                    SettingsSectionHeader(title: String(localized: "Fields", bundle: .module))
                    SettingsGroup {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                            if index > 0 { SettingsSeparator() }
                            SettingsPickerRow(
                                title: slot.title,
                                systemImage: slot.systemImage,
                                tone: .neutral,
                                selection: Binding(
                                    get: { template[keyPath: slot.id] },
                                    set: { field in update { $0[keyPath: slot.id] = field } }
                                )
                            ) {
                                Text("Don't fill", bundle: .module).tag("")
                                ForEach(fields, id: \.self) { field in
                                    Text(field).tag(field)
                                }
                            }
                        }
                    }
                    SettingsFootnote(String(localized: "Choosing a note type fills these from field names it recognizes; change any of them. Content without a field is left out.", bundle: .module))
                }
            } else {
                SettingsFootnote(String(localized: "Choose a note type to set which field gets the word, the sentence, the definitions and so on. Until then new cards use the Front and Back fields.", bundle: .module))
            }
        }
        .navigationTitle(String(localized: "Vocabulary Card Template", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.load() }
    }

    /// Switching note type drops mappings to fields it doesn't have and
    /// fills empty slots from the new type's field names.
    private func selectNotetype(_ id: Int64?) {
        let fields = model.fields(of: id)
        update { template in
            template.notetypeID = id
            template.clearInvalidFields(validFields: fields)
            template.autoMap(fields: fields)
        }
    }
}
