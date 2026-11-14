//
//  NoteCardPreviewModel.swift
//  BrowseFeature
//

import AnkiClients
import AnkiKit
import AnkiServices
import Dependencies
import Foundation

/// Renders the note being edited — its current, unsaved fields — as each of
/// its cards would appear, for the editors' Preview sheet (Anki's "Cards…"
/// preview). Owns the engine calls so the sheet carries no `@Dependency`.
@Observable
@MainActor
final class NoteCardPreviewModel {
    /// One card the note makes: a template of a normal notetype, or a
    /// cloze number of a cloze notetype.
    struct CardChoice: Hashable, Identifiable {
        let templateIndex: Int
        let ordinal: UInt32
        let title: String
        var id: UInt32 { ordinal }
    }

    enum State: Equatable {
        case loading
        case failed(String)
        /// Nothing to show: a cloze note with no `{{c1::…}}` yet, or a card
        /// whose front comes out empty with these fields.
        case empty(String)
        case rendered(front: String, back: String, css: String)
    }

    private(set) var state: State = .loading
    private(set) var choices: [CardChoice] = []
    var selected: CardChoice?

    let notetypeID: NotetypeID
    let fields: [String]
    @ObservationIgnored private var notetype: Notetype?
    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient
    @ObservationIgnored @Dependency(\.cardRenderingService) private var renderer

    init(notetypeID: NotetypeID, fields: [String]) {
        self.notetypeID = notetypeID
        self.fields = fields
    }

    func load() async {
        do {
            let notetype = try await notetypesClient.get(notetypeID)
            self.notetype = notetype
            choices = Self.choices(for: notetype, fields: fields)
            selected = choices.first
            if choices.isEmpty {
                state = .empty(notetype.config.kind == .cloze
                    ? String(localized: "Add a cloze like {{c1::text}} to see its card.", bundle: .module)
                    : String(localized: "This note type has no card templates.", bundle: .module))
                return
            }
            // Rendering follows from `selected`; the sheet's task keyed on it
            // draws the first card.
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func render() async {
        guard let notetype, let choice = selected else { return }
        state = .loading
        let renderer = renderer
        let fields = fields
        do {
            let rendered = try await Task.detached(priority: .userInitiated) {
                try renderer.renderNoteCard(notetype, choice.templateIndex, choice.ordinal, fields)
            }.value
            guard selected == choice else { return }
            if rendered.frontHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Anki doesn't create a card whose front is empty.
                state = .empty(String(localized: "With these fields this card's front is empty, so the note won't have this card.", bundle: .module))
            } else {
                state = .rendered(front: rendered.frontHTML, back: rendered.backHTML, css: rendered.cardCSS)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Normal notetypes: one card per template. Cloze notetypes: one card per
    /// cloze number found in the fields, all from template 0.
    nonisolated static func choices(for notetype: Notetype, fields: [String]) -> [CardChoice] {
        if notetype.config.kind == .cloze {
            return clozeNumbers(in: fields).map { number in
                CardChoice(
                    templateIndex: 0,
                    ordinal: UInt32(number - 1),
                    title: String(localized: "Cloze \(number)", bundle: .module)
                )
            }
        }
        return notetype.templates.enumerated().map { index, template in
            CardChoice(templateIndex: index, ordinal: UInt32(clamping: template.ord ?? index), title: template.name)
        }
    }

    /// Distinct `{{cN::` numbers, ascending.
    nonisolated static func clozeNumbers(in fields: [String]) -> [Int] {
        var numbers = Set<Int>()
        for field in fields {
            var rest = field[...]
            while let open = rest.range(of: "{{c") {
                let digits = rest[open.upperBound...].prefix { $0.isNumber }
                let after = rest[open.upperBound...].dropFirst(digits.count)
                if let number = Int(digits), number > 0, after.hasPrefix("::") {
                    numbers.insert(number)
                }
                rest = rest[open.upperBound...]
            }
        }
        return numbers.sorted()
    }
}
