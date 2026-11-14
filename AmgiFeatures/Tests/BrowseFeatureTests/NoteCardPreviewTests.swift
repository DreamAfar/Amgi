//
//  NoteCardPreviewTests.swift
//  BrowseFeatureTests
//

import AnkiKit
import Testing
@testable import BrowseFeature

@Suite("Note card preview")
struct NoteCardPreviewTests {
    @Test("cloze numbers are found once each, in order")
    func clozeNumbers() {
        let fields = ["{{c2::Paris}} is the capital of {{c1::France}}", "{{c2::again}} and {{c10::ten}}", "{{c::no}} {{cx::no}}"]
        #expect(NoteCardPreviewModel.clozeNumbers(in: fields) == [1, 2, 10])
    }

    @Test("a cloze note offers one card per cloze number, all from the first template")
    func clozeChoices() {
        let notetype = Notetype(
            config: Notetype.Config(kind: .cloze),
            templates: [Notetype.Template(ord: 0, name: "Cloze")]
        )
        let choices = NoteCardPreviewModel.choices(for: notetype, fields: ["{{c1::a}} {{c3::b}}"])
        #expect(choices.map(\.ordinal) == [0, 2])
        #expect(choices.allSatisfy { $0.templateIndex == 0 })
    }

    @Test("a normal note offers one card per template")
    func templateChoices() {
        let notetype = Notetype(templates: [
            Notetype.Template(ord: 0, name: "Card 1"),
            Notetype.Template(ord: 1, name: "Card 2"),
        ])
        let choices = NoteCardPreviewModel.choices(for: notetype, fields: ["a", "b"])
        #expect(choices.map(\.title) == ["Card 1", "Card 2"])
        #expect(choices.map(\.ordinal) == [0, 1])
    }
}
