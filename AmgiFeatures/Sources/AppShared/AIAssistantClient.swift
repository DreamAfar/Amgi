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
            String(localized: "Add a service with its address and model in Settings › Review › AI and Translation.", bundle: .module)
        case .service(let status, let message):
            String(localized: "The AI service answered with an error (\(status)): \(message)", bundle: .module)
        case .emptyAnswer:
            String(localized: "The AI service sent back an empty answer.", bundle: .module)
        }
    }
}

/// Explains and translates selected text with the provider, service and
/// prompts chosen in Settings, read at the moment of each request.
public struct AIAssistantClient: Sendable {
    public var explain: @Sendable (_ request: AIAssistantRequest) async throws -> String
    public var translate: @Sendable (_ request: AIAssistantRequest) async throws -> String
    /// A tiny request to check that a service answers: the one given, or with
    /// nil the provider and service in use.
    public var testConnection: @Sendable (_ service: AIServiceProfile?) async throws -> String

    public init(
        explain: @escaping @Sendable (_ request: AIAssistantRequest) async throws -> String,
        translate: @escaping @Sendable (_ request: AIAssistantRequest) async throws -> String,
        testConnection: @escaping @Sendable (_ service: AIServiceProfile?) async throws -> String
    ) {
        self.explain = explain
        self.translate = translate
        self.testConnection = testConnection
    }
}

extension AIAssistantClient: DependencyKey {
    public static let liveValue = AIAssistantClient(
        explain: { request in
            let prompt = AIAssistantPrompt(request: request, preset: AIServiceStore.selectedPrompt(for: .explain))
            return try await AIAssistantLive.answer(instructions: prompt.instructions, prompt: prompt.prompt)
        },
        translate: { request in
            let prompt = AIAssistantPrompt(request: request, preset: AIServiceStore.selectedPrompt(for: .translate))
            return try await AIAssistantLive.answer(instructions: prompt.instructions, prompt: prompt.prompt)
        },
        testConnection: { service in
            let instructions = "Reply with the single word: OK"
            if let service {
                return try await AIAssistantLive.openAIAnswer(service: service, instructions: instructions, prompt: "Ping")
            }
            return try await AIAssistantLive.answer(instructions: instructions, prompt: "Ping")
        }
    )

    public static let testValue = AIAssistantClient(
        explain: { _ in "" },
        translate: { _ in "" },
        testConnection: { _ in "OK" }
    )
}

public extension DependencyValues {
    var aiAssistantClient: AIAssistantClient {
        get { self[AIAssistantClient.self] }
        set { self[AIAssistantClient.self] = newValue }
    }
}

/// The instructions and prompt for a request, from a prompt preset with its
/// placeholders filled.
public struct AIAssistantPrompt: Sendable, Equatable {
    public let instructions: String
    public let prompt: String

    public init(request: AIAssistantRequest, preset: AIPromptPreset = .explainInContext) {
        let fill = { (template: String) in
            AIPromptPreset.fill(template, text: request.text, sentence: request.sentence, language: request.answerLanguage)
        }
        instructions = fill(preset.instructions)
        if let followUp = request.followUp, !followUp.isEmpty {
            // A follow-up keeps the preset's voice but not its answer format:
            // it's a question about the answer already given.
            var lines = ["Selected text: \(request.text)"]
            if let sentence = request.sentence, sentence != request.text, !sentence.isEmpty {
                lines.append("Sentence: \(sentence)")
            }
            if let previous = request.previousAnswer, !previous.isEmpty {
                lines.append("Your earlier explanation:\n\(previous)")
            }
            lines.append("Follow-up question: \(followUp)")
            prompt = lines.joined(separator: "\n")
        } else {
            prompt = fill(preset.prompt)
        }
    }
}

enum AIAssistantLive {
    static func answer(instructions: String, prompt: String) async throws -> String {
        switch AIAssistantProvider.current {
        case .apple:
            return try await appleAnswer(instructions: instructions, prompt: prompt)
        case .openAI:
            guard let service = AIServiceStore.selectedService else { throw AIAssistantError.notConfigured }
            return try await openAIAnswer(service: service, instructions: instructions, prompt: prompt)
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

    static func openAIAnswer(service: AIServiceProfile, instructions: String, prompt: String) async throws -> String {
        let model = service.model.trimmingCharacters(in: .whitespaces)
        guard let url = AIAssistantEndpoint.chatCompletionsURL(base: service.baseURL), !model.isEmpty else {
            throw AIAssistantError.notConfigured
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = AIKeychain.apiKey(for: service.id), !key.isEmpty {
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

/// Each AI service's API key, kept in the Keychain on this device only —
/// never in preferences, and never synced with the collection.
public enum AIKeychain {
    private static let service = "com.amgiapp.ai"
    /// The one key of earlier versions, which had a single service.
    private static let legacyAccount = "openai-compatible"

    private static func account(for id: UUID) -> String { "\(legacyAccount).\(id.uuidString)" }

    public static func apiKey(for id: UUID) -> String? { read(account(for: id)) }

    public static func setAPIKey(_ key: String, for id: UUID) { write(key, account: account(for: id)) }

    public static func deleteAPIKey(for id: UUID) { write("", account: account(for: id)) }

    static var legacyAPIKey: String? { read(legacyAccount) }

    private static func read(_ account: String) -> String? {
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

    /// Saves a key; an empty one deletes it.
    private static func write(_ key: String, account: String) {
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
