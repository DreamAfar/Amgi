//
//  WebSelectionTests.swift
//  AppSharedTests
//

#if canImport(UIKit)
import Testing
@testable import AppShared

@Suite("Web selection")
struct WebSelectionTests {
    @Test func readsTheScriptResult() {
        let selection = WebSelection(scriptResult: ["text": " あくせく ", "sentence": "彼はあくせく働く。"])
        #expect(selection == WebSelection(text: "あくせく", sentence: "彼はあくせく働く。"))
        #expect(WebSelection(scriptResult: ["text": "  "]) == nil)
        #expect(WebSelection(scriptResult: nil) == nil)
        #expect(WebSelection(scriptResult: ["text": "a", "sentence": ""])?.sentence == nil)
    }

    @Test func boldsTheSelectionInTheSentence() {
        #expect(WebSelection(text: "fox", sentence: "The fox jumps.").sentenceHTML == "The <b>fox</b> jumps.")
        #expect(WebSelection(text: "cat", sentence: "The fox jumps.").sentenceHTML == "The fox jumps.")
        #expect(WebSelection(text: "fox", sentence: nil).sentenceHTML == nil)
    }
}
#endif
