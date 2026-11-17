//
//  NoteFieldTextTests.swift
//  AnkiClientsTests
//

import Testing
@testable import AnkiClients
import Reader

struct NoteFieldTextTests {
    @Test func plainTextKeepsItsLines() {
        #expect(NoteFieldText.html(fromPlain: "紙。\r\na < b & c\n\nlast") == "紙。<br>a &lt; b &amp; c<br><br>last")
    }

    @Test func anExplanationKeepsItsSectionsBoldAndBullets() {
        let text = """
        【In this sentence】 **あくせく** means busily.
        ## Usage
        - with 働く
        * 2 ** 3 is not bold
        """
        #expect(NoteFieldText.html(fromExplanation: text) == [
            "<b>【In this sentence】</b> <b>あくせく</b> means busily.",
            "<b>Usage</b>",
            "• with 働く",
            "• 2 ** 3 is not bold",
        ].joined(separator: "<br>"))
    }

    @Test func aDraftGetsLineBreaksNotOneRunOfText() {
        let template = ReaderLookupNoteTemplate(
            definition1Field: "Meaning", explanationField: "Notes", translationField: "Translation"
        )
        let draft = template.makeDraft(
            payload: ReaderLookupNotePayload(
                term: "紙", definitions: ["① paper\n② newspaper"],
                explanation: "【Usage】\ncommon", translation: "line one\nline two"
            ),
            fallbackDeckID: nil,
            sourceDescription: "Reader lookup"
        )
        #expect(draft.fieldValues["Meaning"] == "① paper<br>② newspaper")
        #expect(draft.fieldValues["Notes"] == "<b>【Usage】</b><br>common")
        #expect(draft.fieldValues["Translation"] == "line one<br>line two")
    }

    @Test func styledDefinitionsGoInAsTheyAre() {
        let glossaries = [
            DictionaryLookupGlossary(dictionary: "A", content: "one\ntwo"),
            DictionaryLookupGlossary(dictionary: "B", content: "three"),
            DictionaryLookupGlossary(dictionary: "A", content: "four"),
        ]
        let styled = ReaderLookupNotePayload.styledDefinitionsByDictionary(from: glossaries, styles: ["A": "b { color: red }"])
        #expect(styled.count == 2)
        #expect(styled[0].contains("<ol><li>one<br>two</li><li>four</li></ol>"))
        #expect(styled[0].contains(#"<style>.yomitan-glossary [data-dictionary="A"] b { color: red }</style>"#))
        #expect(!styled[1].contains("<style>"))

        let draft = ReaderLookupNoteTemplate(definition1Field: "Meaning").makeDraft(
            payload: ReaderLookupNotePayload(term: "x", definitions: styled, definitionsAreHTML: true),
            fallbackDeckID: nil,
            sourceDescription: "Reader lookup"
        )
        #expect(draft.fieldValues["Meaning"] == styled[0])
    }

    @Test func oldTemplatesKeepDictionaryStylingOn() {
        #expect(ReaderLookupNoteTemplate.decode(from: #"{"termField":"Front"}"#).styledDefinitions)
        var template = ReaderLookupNoteTemplate(termField: "Front")
        template.styledDefinitions = false
        #expect(!ReaderLookupNoteTemplate.decode(from: template.encodedString()).styledDefinitions)
    }
}
