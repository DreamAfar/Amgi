//
//  ReaderConfigurationModel.swift
//  ReaderFeature
//
//  Created by Vladimir Gusev on 22.06.2026.
//

import AnkiClients
import AnkiKit
import Dependencies
import Foundation

/// A notetype that has notes in the reader deck, with the field names the
/// mapping pickers offer.
struct ReaderNotetypeChoice: Identifiable, Equatable {
    let id: NotetypeID
    let name: String
    let fieldNames: [String]
}

/// Engine I/O for the reader configuration screen: the deck list, and the
/// notetypes (with their fields) used by notes in the chosen deck. The
/// field-mapping values stay as `@Shared(.appStorage)` bindings on the
/// View; the model owns the engine calls so the View carries no
/// `@Dependency`.
@Observable
@MainActor
final class ReaderConfigurationModel {
    var decks: [DeckInfo] = []
    var loadError: String?

    /// Notetypes with at least one note in the loaded deck, sorted by name.
    var notetypes: [ReaderNotetypeChoice] = []
    var isLoadingNotetypes = false
    var notetypeError: String?
    /// Deck name `notetypes` was loaded for; nil until the first load.
    private(set) var notetypesDeckName: String?

    @ObservationIgnored @Dependency(\.deckClient) private var deckClient
    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient
    @ObservationIgnored @Dependency(\.noteClient) private var noteClient

    func loadDecks() async {
        do {
            decks = try await deckClient.fetchAll().sorted { $0.name < $1.name }
        } catch {
            loadError = String(localized: "Failed to load decks: \(error.localizedDescription)", bundle: .module)
        }
    }

    /// Finds the notetypes used in `deckName` (subdecks included, matching
    /// how the library searches). One `mid:` probe per notetype keeps this
    /// cheap: it never loads the deck's notes.
    func loadNotetypes(deckName: String) async {
        notetypeError = nil
        guard !deckName.isEmpty else {
            notetypes = []
            notetypesDeckName = deckName
            return
        }

        isLoadingNotetypes = true
        defer { isLoadingNotetypes = false }

        do {
            let deckTerm = DeckSearch.term(deckName)
            var found: [ReaderNotetypeChoice] = []
            for entry in try await notetypesClient.listAll() {
                let hits = try await noteClient.search("\(deckTerm) mid:\(entry.id.rawValue)", 1)
                guard !hits.isEmpty else { continue }
                let notetype = try await notetypesClient.get(entry.id)
                found.append(ReaderNotetypeChoice(
                    id: entry.id,
                    name: entry.name,
                    fieldNames: notetype.fields.map(\.name)
                ))
            }
            guard !Task.isCancelled else { return }
            notetypes = found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            notetypesDeckName = deckName
        } catch {
            guard !Task.isCancelled else { return }
            notetypes = []
            notetypesDeckName = deckName
            notetypeError = String(localized: "Failed to load note types: \(error.localizedDescription)", bundle: .module)
        }
    }

    /// The notetype the mapping should use after a load: the stored one if
    /// the deck still uses it, the only one if there is exactly one, and
    /// otherwise none, so the user picks.
    func resolvedNotetypeID(current: Int?) -> Int? {
        if let current, notetypes.contains(where: { $0.id.rawValue == Int64(current) }) {
            return current
        }
        if notetypes.count == 1 {
            return Int(notetypes[0].id.rawValue)
        }
        return nil
    }

    func notetype(id: Int?) -> ReaderNotetypeChoice? {
        guard let id else { return nil }
        return notetypes.first { $0.id.rawValue == Int64(id) }
    }
}
