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
}
