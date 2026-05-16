import SwiftUI
import Foundation
import AnkiSync

struct ReviewSelectionAIState: Identifiable {
    let id = UUID()
    let selection: String
    var isLoading = true
    var response: String?
    var errorMessage: String?
}

struct ReviewSelectionAIConfig {
    let endpoint: String
    let model: String
    let systemPrompt: String
    let glossary: String
    let apiKey: String?

    static func load(defaults: UserDefaults = .standard) -> Self {
        Self(
            endpoint: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAIEndpoint) ?? "",
            model: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAIModel) ?? "",
            systemPrompt: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAISystemPrompt) ?? "",
            glossary: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAIGlossary) ?? "",
            apiKey: KeychainHelper.loadReviewSelectionAIAPIKey()
        )
    }
}

enum ReviewSelectionURLBuilder {
    static func resolve(template: String, selection: String) -> URL? {
        guard let trimmedTemplate = template.trimmedOrNil else { return nil }
        let encodedSelection = selection.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selection
        let rawSelection = selection.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? selection
        let resolved = trimmedTemplate
            .replacingOccurrences(of: "{text}", with: encodedSelection)
            .replacingOccurrences(of: "{text_raw}", with: rawSelection)
        guard let url = URL(string: resolved), let scheme = url.scheme?.lowercased(), scheme.isEmpty == false else {
            return nil
        }
        return url
    }
}

enum ReviewSelectionAIClient {
    static func generateResponse(for selection: String, config: ReviewSelectionAIConfig) async throws -> String {
        guard let endpoint = config.endpoint.trimmedOrNil, let url = URL(string: endpoint) else {
            throw ReviewSelectionAIError.missingEndpoint
        }
        guard let model = config.model.trimmedOrNil else {
            throw ReviewSelectionAIError.missingModel
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = config.apiKey?.trimmedOrNil {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: resolvedSystemPrompt(from: config)),
                ChatMessage(role: "user", content: selection)
            ]
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReviewSelectionAIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw ReviewSelectionAIError.serverError(
                message: decodeErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmedOrNil else {
            throw ReviewSelectionAIError.emptyResponse
        }
        return content
    }

    private static func resolvedSystemPrompt(from config: ReviewSelectionAIConfig) -> String {
        let basePrompt = config.systemPrompt.trimmedOrNil
            ?? "Explain the selected text clearly and concisely in Chinese. Preserve important terms and point out ambiguity when needed."
        guard let glossary = config.glossary.trimmedOrNil else {
            return basePrompt
        }
        return "\(basePrompt)\n\nTerminology notes:\n\(glossary)"
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return decoded.error.message.trimmedOrNil
        }
        return String(data: data, encoding: .utf8)?.trimmedOrNil
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
    }

    private struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message

            struct Message: Decodable {
                let content: String
            }
        }
    }

    private struct APIErrorEnvelope: Decodable {
        let error: APIError

        struct APIError: Decodable {
            let message: String
        }
    }
}

private enum ReviewSelectionAIError: LocalizedError {
    case missingEndpoint
    case missingModel
    case invalidResponse
    case serverError(message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return L("review_selection_ai_missing_endpoint")
        case .missingModel:
            return L("review_selection_ai_missing_model")
        case .invalidResponse:
            return L("common_unknown_error")
        case let .serverError(message):
            return message
        case .emptyResponse:
            return L("review_selection_ai_empty_response")
        }
    }
}

struct ReviewSelectionMenuSettingsView: View {
    @AppStorage(ReviewPreferences.Keys.selectionMenuLookupEnabled) private var selectionMenuLookupEnabled = false
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIEnabled) private var selectionMenuAIEnabled = false

    var body: some View {
        List {
            Section {
                Toggle(L("settings_review_text_selection_menu_lookup_enabled"), isOn: $selectionMenuLookupEnabled)
                Toggle(L("settings_review_text_selection_menu_ai_enabled"), isOn: $selectionMenuAIEnabled)
            } footer: {
                Text(L("settings_review_text_selection_menu_description"))
            }
            .amgiSettingsListRowSurface()

            Section {
                NavigationLink {
                    ReviewSelectionLookupLinkSettingsView()
                } label: {
                    Label(L("settings_review_lookup_link_options"), systemImage: "link")
                        .foregroundStyle(SettingsValueStyle.primary)
                }

                NavigationLink {
                    ReviewSelectionAISettingsView()
                } label: {
                    Label(L("settings_review_ai_settings"), systemImage: "sparkles")
                        .foregroundStyle(SettingsValueStyle.primary)
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_text_selection_menu"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReviewSelectionLookupLinkSettingsView: View {
    @AppStorage(ReviewPreferences.Keys.selectionMenuLookupTemplate) private var lookupTemplate = ""

    var body: some View {
        List {
            Section {
                TextField(
                    "",
                    text: $lookupTemplate,
                    prompt: Text(L("settings_review_lookup_link_template_hint"))
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            } header: {
                Text(L("settings_review_lookup_link_template"))
            } footer: {
                Text(L("settings_review_lookup_link_template_footer"))
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_lookup_link_options"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReviewSelectionAISettingsView: View {
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIEndpoint) private var endpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIModel) private var model = "gpt-4o-mini"
    @AppStorage(ReviewPreferences.Keys.selectionMenuAISystemPrompt) private var systemPrompt = ""
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIGlossary) private var glossary = ""
    @State private var apiKey = KeychainHelper.loadReviewSelectionAIAPIKey() ?? ""

    var body: some View {
        List {
            Section {
                TextField(L("settings_review_ai_endpoint"), text: $endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField(L("settings_review_ai_model"), text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField(L("settings_review_ai_api_key"), text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text(L("settings_review_ai_api_key_footer"))
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_ai_system_prompt")) {
                TextEditor(text: $systemPrompt)
                    .frame(minHeight: 120)
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_ai_glossary")) {
                TextEditor(text: $glossary)
                    .frame(minHeight: 120)
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_ai_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            persistAPIKey()
        }
    }

    private func persistAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.deleteReviewSelectionAIAPIKey()
        } else {
            try? KeychainHelper.saveReviewSelectionAIAPIKey(trimmed)
        }
    }
}

struct ReviewSelectionAISheetView: View {
    let state: ReviewSelectionAIState
    let onClose: () -> Void

    var body: some View {
        List {
            Section(L("review_selection_ai_selected_text")) {
                Text(state.selection)
                    .textSelection(.enabled)
            }
            .amgiSettingsListRowSurface()

            Section(L("review_selection_ai_result")) {
                if state.isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(L("review_selection_ai_loading"))
                            .foregroundStyle(SettingsValueStyle.secondary)
                    }
                } else if let errorMessage = state.errorMessage?.trimmedOrNil {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else {
                    Text(state.response?.trimmedOrNil ?? L("review_selection_ai_empty_response"))
                        .textSelection(.enabled)
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("review_selection_ai_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_done")) {
                    onClose()
                }
            }
        }
    }
}

private extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}