//
//  AIServiceStore.swift
//  AppShared
//

import AppCore
public import Foundation

// MARK: - Services

/// One OpenAI-compatible service: where it is and which model to ask. Its
/// key is in the Keychain under the profile's id, never in preferences.
public struct AIServiceProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var model: String

    public init(id: UUID = UUID(), name: String, baseURL: String, model: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
    }

    /// The name, or the host when the name was left empty.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if let host = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host { return host }
        return String(localized: "Untitled Service", bundle: .module)
    }

    /// "model · host", for a row's second line.
    public var summary: String {
        let host = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host ?? ""
        return [model, host].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The id given to the service carried over from the single-service
    /// settings of earlier versions: fixed, so two readers migrating at once
    /// make the same entry rather than two.
    static let migratedID = UUID(uuidString: "6A1F0D2E-0000-4000-8000-000000000001")!
}

// MARK: - Prompts

/// What the AI is asked to do with a selection, and in what words.
///
/// `instructions` is the system message and `prompt` the user message. Both
/// may use `{{text}}` (the selection), `{{sentence}}` (the sentence around
/// it; a line with it is dropped when there is none) and `{{language}}` (the
/// answer language).
public struct AIPromptPreset: Codable, Identifiable, Hashable, Sendable {
    public enum Purpose: String, Codable, CaseIterable, Sendable {
        case explain, translate
    }

    public var id: String
    public var name: String
    public var purpose: Purpose
    public var instructions: String
    public var prompt: String

    public init(id: String = "custom.\(UUID().uuidString)", name: String, purpose: Purpose, instructions: String, prompt: String) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.instructions = instructions
        self.prompt = prompt
    }

    /// The built-in prompts can be used and copied, not changed.
    public var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    /// A copy the user can edit.
    public func duplicate(named name: String) -> AIPromptPreset {
        AIPromptPreset(name: name, purpose: purpose, instructions: instructions, prompt: prompt)
    }

    public static let placeholders = ["{{text}}", "{{sentence}}", "{{language}}"]

    /// `template` with the placeholders filled. Lines naming `{{sentence}}`
    /// go when there's no separate sentence, rather than reading "Sentence: ".
    public static func fill(_ template: String, text: String, sentence: String?, language: String) -> String {
        let sentence = sentence.flatMap { $0 == text || $0.isEmpty ? nil : $0 }
        let lines = template.components(separatedBy: "\n").filter { sentence != nil || !$0.contains("{{sentence}}") }
        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "{{text}}", with: text)
            .replacingOccurrences(of: "{{sentence}}", with: sentence ?? "")
            .replacingOccurrences(of: "{{language}}", with: language)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public extension AIPromptPreset {
    /// The explanation of earlier versions, kept as the default.
    static let explainInContext = AIPromptPreset(
        id: "builtin.explain.context",
        name: String(localized: "Meaning in context", bundle: .module),
        purpose: .explain,
        instructions: """
        You help a language learner reviewing flashcards. Answer in {{language}}. \
        Be concise and concrete; no greetings, no preamble, no Markdown tables. \
        Explain what the selected text means in this particular sentence, not every sense it can have.
        """,
        prompt: """
        Selected text: {{text}}
        Sentence: {{sentence}}
        Write three short sections, each starting with its label on its own line:
        【In this sentence】what it means here and the nuance it carries
        【Usage】part of speech, typical patterns or collocations, register
        【Example】one natural example sentence with its translation
        Translate the three labels into {{language}}.
        """
    )

    static let explainBrief = AIPromptPreset(
        id: "builtin.explain.brief",
        name: String(localized: "Brief meaning", bundle: .module),
        purpose: .explain,
        instructions: """
        You help a language learner reviewing flashcards. Answer in {{language}}, \
        in at most three short lines, with no preamble.
        """,
        prompt: """
        Selected text: {{text}}
        Sentence: {{sentence}}
        Give its meaning in this sentence, its reading or pronunciation if that isn't obvious, \
        and its dictionary form if it is inflected.
        """
    )

    static let explainGrammar = AIPromptPreset(
        id: "builtin.explain.grammar",
        name: String(localized: "Grammar", bundle: .module),
        purpose: .explain,
        instructions: """
        You are a patient grammar teacher for a language learner. Answer in {{language}}. \
        Be concise; no greetings, no Markdown tables.
        """,
        prompt: """
        Selected text: {{text}}
        Sentence: {{sentence}}
        Explain the grammar of the selected text in this sentence: its form, \
        any conjugation or particles, how it connects to the rest of the sentence, \
        and one similar example with its translation.
        """
    )

    static let translateNatural = AIPromptPreset(
        id: "builtin.translate.natural",
        name: String(localized: "Natural translation", bundle: .module),
        purpose: .translate,
        instructions: """
        You are a translator. Translate into {{language}}. \
        Reply with the translation only: no notes, no quotes, no preamble.
        """,
        prompt: """
        Translate the selected text as it is used in the sentence, then the whole sentence, on two lines.
        Selected text: {{text}}
        Sentence: {{sentence}}
        """
    )

    static let translateLiteral = AIPromptPreset(
        id: "builtin.translate.literal",
        name: String(localized: "Literal and natural", bundle: .module),
        purpose: .translate,
        instructions: """
        You are a translator helping a language learner. Answer in {{language}}, with no preamble.
        """,
        prompt: """
        Selected text: {{text}}
        Sentence: {{sentence}}
        Give a word-for-word translation, then a natural one, each on its own line \
        and starting with its label translated into {{language}}.
        """
    )

    static let builtIns: [AIPromptPreset] = [
        .explainInContext, .explainBrief, .explainGrammar,
        .translateNatural, .translateLiteral,
    ]

    static func defaultPreset(for purpose: Purpose) -> AIPromptPreset {
        purpose == .explain ? .explainInContext : .translateNatural
    }
}

// MARK: - Store

/// The services and prompts, in user defaults. Read from any thread: the
/// client asks it which service and prompt to use at the moment of a request.
public enum AIServiceStore {
    private static var defaults: UserDefaults { .standard }

    // MARK: Services

    /// The services set up. On first read after an update, the single service
    /// of earlier versions becomes the first entry, with its key.
    public static var services: [AIServiceProfile] {
        if let data = defaults.string(forKey: ReviewPreferences.Keys.aiServices)?.data(using: .utf8),
           let services = try? JSONDecoder().decode([AIServiceProfile].self, from: data) {
            return services
        }
        return migrateLegacyService()
    }

    public static func saveServices(_ services: [AIServiceProfile]) {
        guard let data = try? JSONEncoder().encode(services) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: ReviewPreferences.Keys.aiServices)
    }

    /// The service in use: the chosen one, or the first.
    public static var selectedService: AIServiceProfile? {
        let services = services
        let id = defaults.string(forKey: ReviewPreferences.Keys.aiSelectedService).flatMap(UUID.init(uuidString:))
        return services.first { $0.id == id } ?? services.first
    }

    public static func select(_ service: AIServiceProfile) {
        defaults.set(service.id.uuidString, forKey: ReviewPreferences.Keys.aiSelectedService)
    }

    private static func migrateLegacyService() -> [AIServiceProfile] {
        let base = (defaults.string(forKey: ReviewPreferences.Keys.aiBaseURL) ?? "").trimmingCharacters(in: .whitespaces)
        let model = (defaults.string(forKey: ReviewPreferences.Keys.aiModel) ?? "").trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty || !model.isEmpty else { return [] }
        let service = AIServiceProfile(id: AIServiceProfile.migratedID, name: "", baseURL: base, model: model)
        if AIKeychain.apiKey(for: service.id) == nil, let key = AIKeychain.legacyAPIKey {
            AIKeychain.setAPIKey(key, for: service.id)
        }
        saveServices([service])
        select(service)
        return [service]
    }

    // MARK: Prompts

    public static var customPrompts: [AIPromptPreset] {
        guard let data = defaults.string(forKey: ReviewPreferences.Keys.aiCustomPrompts)?.data(using: .utf8),
              let prompts = try? JSONDecoder().decode([AIPromptPreset].self, from: data) else { return [] }
        return prompts
    }

    public static func saveCustomPrompts(_ prompts: [AIPromptPreset]) {
        guard let data = try? JSONEncoder().encode(prompts.filter { !$0.isBuiltIn }) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: ReviewPreferences.Keys.aiCustomPrompts)
    }

    /// The built-in prompts for a purpose, then the user's own.
    public static func prompts(for purpose: AIPromptPreset.Purpose) -> [AIPromptPreset] {
        (AIPromptPreset.builtIns + customPrompts).filter { $0.purpose == purpose }
    }

    public static func selectionKey(for purpose: AIPromptPreset.Purpose) -> String {
        purpose == .explain ? ReviewPreferences.Keys.aiExplainPrompt : ReviewPreferences.Keys.aiTranslatePrompt
    }

    /// The prompt in use for a purpose; the default when the chosen one was deleted.
    public static func selectedPrompt(for purpose: AIPromptPreset.Purpose) -> AIPromptPreset {
        let id = defaults.string(forKey: selectionKey(for: purpose))
        return prompts(for: purpose).first { $0.id == id } ?? .defaultPreset(for: purpose)
    }
}

/// Where selections are translated.
public enum AITranslationProvider: String, CaseIterable, Sendable {
    /// Apple Translation, on this device.
    case apple
    /// The AI provider chosen for explanations, with a translation prompt.
    case ai

    public static var current: AITranslationProvider {
        AITranslationProvider(rawValue: UserDefaults.standard.string(forKey: ReviewPreferences.Keys.translationProvider) ?? "") ?? .apple
    }
}
