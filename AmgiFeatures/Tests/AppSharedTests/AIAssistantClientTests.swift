//
//  AIAssistantClientTests.swift
//  AppSharedTests
//

import Foundation
import Testing
@testable import AppShared

@Suite("AI assistant")
struct AIAssistantClientTests {

    @Test func endpointAcceptsABaseOrTheFullURL() {
        #expect(AIAssistantEndpoint.chatCompletionsURL(base: "https://api.deepseek.com/v1")?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        #expect(AIAssistantEndpoint.chatCompletionsURL(base: "https://x.ai/v1/")?.absoluteString == "https://x.ai/v1/chat/completions")
        #expect(AIAssistantEndpoint.chatCompletionsURL(base: "http://192.168.1.5:11434/v1/chat/completions")?.absoluteString == "http://192.168.1.5:11434/v1/chat/completions")
        #expect(AIAssistantEndpoint.chatCompletionsURL(base: "") == nil)
        #expect(AIAssistantEndpoint.chatCompletionsURL(base: "ftp://x/v1") == nil)
        #expect(AIAssistantEndpoint.chatCompletionsURL(base: "not a url") == nil)
    }

    @Test func readsTheAnswerAndErrors() {
        let ok = Data(#"{"choices":[{"message":{"role":"assistant","content":"  忙忙碌碌  "}}]}"#.utf8)
        #expect(AIAssistantEndpoint.answer(in: ok) == "忙忙碌碌")
        #expect(AIAssistantEndpoint.answer(in: Data("{}".utf8)) == nil)
        let error = Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)
        #expect(AIAssistantEndpoint.errorMessage(in: error) == "Invalid API key")
    }

    @Test func promptCarriesTheSelectionAndSentence() {
        let prompt = AIAssistantPrompt(request: AIAssistantRequest(text: "あくせく", sentence: "彼はあくせく働く。", answerLanguage: "简体中文"))
        #expect(prompt.instructions.contains("简体中文"))
        #expect(prompt.prompt.contains("Selected text: あくせく"))
        #expect(prompt.prompt.contains("Sentence: 彼はあくせく働く。"))
        #expect(prompt.prompt.contains("【Usage】"))
    }

    @Test func followUpsCarryTheEarlierAnswer() {
        let prompt = AIAssistantPrompt(request: AIAssistantRequest(
            text: "word", sentence: nil, answerLanguage: "English", followUp: "Simpler?", previousAnswer: "A long answer"
        ))
        #expect(prompt.prompt.contains("Follow-up question: Simpler?"))
        #expect(prompt.prompt.contains("A long answer"))
        #expect(!prompt.prompt.contains("【Usage】"))
        #expect(!prompt.prompt.contains("Sentence:"))
    }

    @Test func placeholdersAreFilledAndEmptySentenceLinesDropped() {
        let template = "Text: {{text}}\nSentence: {{sentence}}\nAnswer in {{language}}."
        #expect(AIPromptPreset.fill(template, text: "猫", sentence: "猫がいる。", language: "English")
            == "Text: 猫\nSentence: 猫がいる。\nAnswer in English.")
        // No sentence, or one that is just the selection: the line goes.
        #expect(AIPromptPreset.fill(template, text: "猫", sentence: nil, language: "English") == "Text: 猫\nAnswer in English.")
        #expect(AIPromptPreset.fill(template, text: "猫", sentence: "猫", language: "English") == "Text: 猫\nAnswer in English.")
    }

    @Test func aCustomPresetShapesThePrompt() {
        let preset = AIPromptPreset(name: "Mine", purpose: .explain, instructions: "Be a poet in {{language}}.", prompt: "Rhyme with {{text}}.")
        let prompt = AIAssistantPrompt(request: AIAssistantRequest(text: "moon", sentence: nil, answerLanguage: "English"), preset: preset)
        #expect(prompt.instructions == "Be a poet in English.")
        #expect(prompt.prompt == "Rhyme with moon.")
        #expect(!preset.isBuiltIn)
    }

    @Test func translationPresetsAskForTheTranslationOnly() {
        let prompt = AIAssistantPrompt(
            request: AIAssistantRequest(text: "あくせく", sentence: "彼はあくせく働く。", answerLanguage: "简体中文"),
            preset: .translateNatural
        )
        #expect(prompt.instructions.contains("简体中文"))
        #expect(prompt.prompt.contains("あくせく"))
        #expect(prompt.prompt.contains("彼はあくせく働く。"))
    }

    @Test func builtInsCoverBothPurposesWithUniqueIDs() {
        let ids = AIPromptPreset.builtIns.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(AIPromptPreset.builtIns.allSatisfy(\.isBuiltIn))
        #expect(AIPromptPreset.defaultPreset(for: .explain).purpose == .explain)
        #expect(AIPromptPreset.defaultPreset(for: .translate).purpose == .translate)
        let copy = AIPromptPreset.explainBrief.duplicate(named: "Copy")
        #expect(!copy.isBuiltIn && copy.prompt == AIPromptPreset.explainBrief.prompt)
    }
}
