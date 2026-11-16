//
//  AIAssistantClient.swift
//  AppShared
//

import AppCore
public import Dependencies
public import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What to explain: a selection, the sentence it sits in, and optionally a
/// follow-up question about an earlier answer.
public struct AIAssistantRequest: Sendable, Equatable {
    public var text: String
    public var sentence: String?
    /// The language to answer in, as a name the model understands
    /// ("简体中文", "English").
    public var answerLanguage: String
    public var followUp: String?
    public var previousAnswer: String?

    public init(text: String, sentence: String?, answerLanguage: String, followUp: String? = nil, previousAnswer: String? = nil) {
        self.text = text
        self.sentence = sentence
        self.answerLanguage = answerLanguage
        self.followUp = followUp
        self.previousAnswer = previousAnswer
    }
}

public enum AIAssistantProvider: String, CaseIterable, Sendable {
    /// Apple's on-device model (iOS 26+, Apple Intelligence devices).
    case apple
    /// Any service with the OpenAI chat-completions API: OpenAI, DeepSeek,
    /// Qwen, a local Ollama, …
    case openAI = "openai"

    public static var current: AIAssistantProvider {
        AIAssistantProvider(rawValue: UserDefaults.standard.string(forKey: ReviewPreferences.Keys.aiProvider) ?? "") ?? .apple
    }
}

public enum AIAssistantError: LocalizedError, Equatable {
    case appleModelUnavailable
    case notConfigured
    case service(status: Int, message: String)
    case emptyAnswer

    public var errorDescription: String? {
        switch self {
        case .appleModelUnavailable:
            String(localized: "The on-device model isn't available on this device. Turn on Apple Intelligence, or set up an OpenAI-compatible service in Settings › Review › AI and Translation.", bundle: .module)
        case .notConfigured:
            String(localized: "Set the service address and model in Settings › Review › AI and Translation.", bundle: .module)
        case .service(let status, let message):
            String(localized: "The AI service answered with an error (\(status)): \(message)", bundle: .module)
        case .emptyAnswer:
            String(localized: "The AI service sent back an empty answer.", bundle: .module)
        }
    }
}

/// Explains selected text with the provider chosen in Settings.
public struct AIAssistantClient: Sendable {
    public var explain: @Sendable (_ request: AIAssistantRequest) async throws -> String
    /// A tiny request to check that the chosen provider answers.
    public var testConnection: @Sendable () async throws -> String

    public init(
        explain: @escaping @Sendable (_ request: AIAssistantRequest) async throws -> String,
        testConnection: @escaping @Sendable () async throws -> String
    ) {
        self.explain = explain
        self.testConnection = testConnection
    }
}

extension AIAssistantClient: DependencyKey {
    public static let liveValue = AIAssistantClient(
        explain: { request in
            let prompt = AIAssistantPrompt(request: request)
            return try await AIAssistantLive.answer(instructions: prompt.instructions, prompt: prompt.prompt)
        },
        testConnection: {
            try await AIAssistantLive.answer(instructions: "Reply with the single word: OK", prompt: "Ping")
        }
    )

    public static let testValue = AIAssistantClient(
        explain: { _ in "" },
        testConnection: { "OK" }
    )
}

public extension DependencyValues {
    var aiAssistantClient: AIAssistantClient {
        get { self[AIAssistantClient.self] }
        set { self[AIAssistantClient.self] = newValue }
    }
}

/// The instructions and prompt for a request. Plain text with fixed
/// section labels, so any model's answer renders the same way.
public struct AIAssistantPrompt: Sendable, Equatable {
    public let instructions: String
    public let prompt: String

    public init(request: AIAssistantRequest) {
        instructions = """
        You help a language learner reviewing flashcards. Answer in \(request.answerLanguage). \
        Be concise and concrete; no greetings, no preamble, no Markdown tables. \
        Explain what the selected text means in this particular sentence, not every sense it can have.
        """
        var lines: [String] = []
        lines.append("Selected text: \(request.text)")
        if let sentence = request.sentence, sentence != request.text {
            lines.append("Sentence: \(sentence)")
        }
        if let followUp = request.followUp, !followUp.isEmpty {
            if let previous = request.previousAnswer, !previous.isEmpty {
                lines.append("Your earlier explanation:\n\(previous)")
            }
            lines.append("Follow-up question: \(followUp)")
        } else {
            lines.append("""
            Write three short sections, each starting with its label on its own line:
            【In this sentence】what it means here and the nuance it carries
            【Usage】part of speech, typical patterns or collocations, register
            【Example】one natural example sentence with its translation
            Translate the three labels into \(request.answerLanguage).
            """)
        }
        prompt = lines.joined(separator: "\n")
    }
}

enum AIAssistantLive {
    static func answer(instructions: String, prompt: String) async throws -> String {
        switch AIAssistantProvider.current {
        case .apple:
            return try await appleAnswer(instructions: instructions, prompt: prompt)
        case .openAI:
            return try await openAIAnswer(instructions: instructions, prompt: prompt)
        }
    }

    private static func appleAnswer(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw AIAssistantError.appleModelUnavailable
            }
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AIAssistantError.emptyAnswer }
            return text
        }
        #endif
        throw AIAssistantError.appleModelUnavailable
    }

    private static func openAIAnswer(instructions: String, prompt: String) async throws -> String {
        let defaults = UserDefaults.standard
        let base = (defaults.string(forKey: ReviewPreferences.Keys.aiBaseURL) ?? "").trimmingCharacters(in: .whitespaces)
        let model = (defaults.string(forKey: ReviewPreferences.Keys.aiModel) ?? "").trimmingCharacters(in: .whitespaces)
        guard let url = AIAssistantEndpoint.chatCompletionsURL(base: base), !model.isEmpty else {
            throw AIAssistantError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = AIKeychain.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIAssistantError.service(status: status, message: AIAssistantEndpoint.errorMessage(in: data))
        }
        guard let text = AIAssistantEndpoint.answer(in: data), !text.isEmpty else {
            throw AIAssistantError.emptyAnswer
        }
        return text
    }
}

/// Request and response details of the OpenAI chat-completions API.
public enum AIAssistantEndpoint {
    /// Accepts a base URL (".../v1") or the full chat-completions URL.
    public static func chatCompletionsURL(base: String) -> URL? {
        var base = base.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        let full = base.hasSuffix("/chat/completions") ? base : base + "/chat/completions"
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    public static func answer(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func errorMessage(in data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let message = json["message"] as? String { return message }
        }
        return String(String(data: data, encoding: .utf8)?.prefix(200) ?? "")
    }
}

/// The AI service's API key, kept in the Keychain on this device only —
/// never in preferences, and never synced with the collection.
public enum AIKeychain {
    private static let service = "com.amgiapp.ai"
    private static let account = "openai-compatible"

    public static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func setAPIKey(_ key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// The languages explanations and translations can be set to.
public enum AIAssistantLanguage {
    public static let codes = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "fr", "de", "es"]

    /// The language's name in itself, which is also what the prompt uses.
    public static func name(for code: String) -> String {
        Locale(identifier: code).localizedString(forIdentifier: code) ?? code
    }

    /// The user's preferred language if it's one of `codes`, else English.
    public static var deviceDefault: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") {
            return preferred.contains("Hant") || preferred.contains("TW") || preferred.contains("HK") ? "zh-Hant" : "zh-Hans"
        }
        let base = String(preferred.prefix(2))
        return codes.contains(base) ? base : "en"
    }
}
