//
//  ReviewSelectionModel.swift
//  ReviewFeature
//

import AnkiClients
import AnkiKit
import AppShared
import AVFoundation
import Dependencies
import Foundation
import NaturalLanguage
import Observation

/// The text-selection actions of the review card: AI explanation,
/// translation, speaking, and a quick card. Owns the AI client so the
/// views carry no `@Dependency`.
@Observable
@MainActor
final class ReviewSelectionModel {
    enum Tab: Hashable {
        case explain
        case translate
    }

    /// The selection sheet, while open.
    struct Assist: Identifiable, Equatable {
        let id = UUID()
        let selection: WebSelection
        var tab: Tab
    }

    enum Answer: Equatable {
        case idle
        case loading
        case done(String)
        case failed(String)

        var text: String? {
            if case .done(let text) = self { return text }
            return nil
        }
    }

    struct Exchange: Identifiable, Equatable {
        let id = UUID()
        let question: String
        var answer: Answer
    }

    var assist: Assist?
    var quickCard: QuickCard?
    private(set) var explanation: Answer = .idle
    private(set) var followUps: [Exchange] = []
    /// Set by the sheet once the translation framework has answered, or
    /// by `translateWithAI` when translations go to the AI provider.
    var translation: String?
    private(set) var aiTranslation: Answer = .idle

    struct QuickCard: Identifiable {
        let id = UUID()
        let draft: AddNoteDraft
    }

    @ObservationIgnored @Dependency(\.aiAssistantClient) private var aiClient
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// Explanations already fetched this session, by selection and
    /// language, so reopening the same word costs nothing.
    @ObservationIgnored private var cache: [String: String] = [:]
    @ObservationIgnored private var explainTask: Task<Void, Never>?
    @ObservationIgnored private var translateTask: Task<Void, Never>?

    func open(_ selection: WebSelection, tab: Tab) {
        explainTask?.cancel()
        translateTask?.cancel()
        explanation = .idle
        followUps = []
        translation = nil
        aiTranslation = .idle
        assist = Assist(selection: selection, tab: tab)
    }

    func close() {
        explainTask?.cancel()
        translateTask?.cancel()
        assist = nil
    }

    // MARK: - Explanation

    /// Explains the open selection, from the cache when it was asked before.
    func explain(language: String) {
        guard let selection = assist?.selection else { return }
        let key = Self.cacheKey(selection, language: language, purpose: .explain)
        if let cached = cache[key] {
            explanation = .done(cached)
            return
        }
        guard explanation == .idle || isFailed(explanation) else { return }
        explanation = .loading
        let request = AIAssistantRequest(
            text: selection.text,
            sentence: selection.sentence,
            answerLanguage: AIAssistantLanguage.name(for: language)
        )
        let client = aiClient
        explainTask = Task {
            do {
                let text = try await client.explain(request)
                guard !Task.isCancelled else { return }
                cache[key] = text
                explanation = .done(text)
            } catch {
                guard !Task.isCancelled else { return }
                explanation = .failed(error.localizedDescription)
            }
        }
    }

    func retryExplanation(language: String) {
        explanation = .idle
        explain(language: language)
    }

    /// Asks again after the prompt or service changed: the answer and any
    /// follow-ups were for the old one.
    func restartExplanation(language: String) {
        explainTask?.cancel()
        followUps = []
        explanation = .idle
        explain(language: language)
    }

    // MARK: - AI translation

    /// Translates the open selection with the AI provider and the chosen
    /// translation prompt, when translations are set to go there.
    func translateWithAI(language: String, force: Bool = false) {
        guard let selection = assist?.selection else { return }
        let key = Self.cacheKey(selection, language: language, purpose: .translate)
        if !force, let cached = cache[key] {
            aiTranslation = .done(cached)
            translation = cached
            return
        }
        guard force || aiTranslation == .idle || isFailed(aiTranslation) else { return }
        translateTask?.cancel()
        aiTranslation = .loading
        let request = AIAssistantRequest(
            text: selection.text,
            sentence: selection.sentence,
            answerLanguage: AIAssistantLanguage.name(for: language)
        )
        let client = aiClient
        translateTask = Task {
            do {
                let text = try await client.translate(request)
                guard !Task.isCancelled else { return }
                cache[key] = text
                aiTranslation = .done(text)
                translation = text
            } catch {
                guard !Task.isCancelled else { return }
                aiTranslation = .failed(error.localizedDescription)
            }
        }
    }

    /// A follow-up question about the explanation.
    func ask(_ question: String, language: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection = assist?.selection, !trimmed.isEmpty else { return }
        let exchange = Exchange(question: trimmed, answer: .loading)
        followUps.append(exchange)
        let request = AIAssistantRequest(
            text: selection.text,
            sentence: selection.sentence,
            answerLanguage: AIAssistantLanguage.name(for: language),
            followUp: trimmed,
            previousAnswer: followUps.dropLast().last?.answer.text ?? explanation.text
        )
        let client = aiClient
        Task {
            let answer: Answer
            do {
                answer = .done(try await client.explain(request))
            } catch {
                answer = .failed(error.localizedDescription)
            }
            if let index = followUps.firstIndex(where: { $0.id == exchange.id }) {
                followUps[index].answer = answer
            }
        }
    }

    // MARK: - Speech

    /// Speaks in the language the text is written in.
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let language = Self.dominantLanguage(of: text) {
            utterance.voice = Self.bestVoice(for: language)
        }
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Quick card

    /// Opens Add Note filled from the vocabulary card template, with the
    /// explanation and translation fetched so far.
    func makeCard(from selection: WebSelection, templateJSON: String) {
        let template = templateJSON.isEmpty ? ReaderLookupNoteTemplate.empty : ReaderLookupNoteTemplate.decode(from: templateJSON)
        let isOpen = assist?.selection == selection
        var draft = template.makeDraft(
            payload: ReaderLookupNotePayload(
                term: selection.text,
                sentence: selection.sentenceHTML,
                source: String(localized: "Review", bundle: .module),
                explanation: isOpen ? explanation.text : nil,
                translation: isOpen ? translation : nil
            ),
            fallbackDeckID: nil,
            sourceDescription: String(localized: "Review", bundle: .module)
        )
        draft.tags.append("from-review")
        explainTask?.cancel()
        let wasOpen = assist != nil
        assist = nil
        let card = QuickCard(draft: draft)
        guard wasOpen else {
            quickCard = card
            return
        }
        // A sheet presented while another is still going away is dropped.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            quickCard = card
        }
    }

    // MARK: - Helpers

    private func isFailed(_ answer: Answer) -> Bool {
        if case .failed = answer { return true }
        return false
    }

    /// Answers depend on the prompt and service as much as on the text, so
    /// switching either asks again instead of showing the old answer.
    static func cacheKey(_ selection: WebSelection, language: String, purpose: AIPromptPreset.Purpose) -> String {
        [
            selection.text, selection.sentence ?? "", language, purpose.rawValue,
            AIServiceStore.selectedPrompt(for: purpose).id,
            AIAssistantProvider.current.rawValue,
            AIServiceStore.selectedService?.id.uuidString ?? "",
        ].joined(separator: "\u{1F}")
    }

    /// The voice for a language: the system's own choice, unless the user
    /// has downloaded a better-sounding one (enhanced or premium) for the
    /// same language in Settings.
    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let code: String = switch language {
        case "zh-Hans": "zh-CN"
        case "zh-Hant": "zh-TW"
        default: language
        }
        guard let standard = AVSpeechSynthesisVoice(language: code) else { return nil }
        let better = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == standard.language && $0.quality.rawValue > standard.quality.rawValue }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return better ?? standard
    }

    static func dominantLanguage(of text: String) -> String? {
        // Kana settles it: a short phrase that is mostly kanji is otherwise
        // taken for Chinese.
        if text.unicodeScalars.contains(where: { (0x3040...0x30FF).contains($0.value) }) { return "ja" }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return language.rawValue
    }
}
