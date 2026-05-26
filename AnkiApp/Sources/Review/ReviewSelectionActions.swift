import SwiftUI
import Foundation
import AnkiSync
import AnkiBackend
import AnkiKit
import AnkiClients
import Dependencies
import UIKit

struct ReviewSelectionAIState: Identifiable {
    let id = UUID()
    var originalSelection: String
    var draftSelection: String
    var context: ReviewAIQueryContext
    var activePresetID: String
    var lastAction: ReviewAIQuickAction?
    var isLoading = true
    var response: String?
    var responseHTML: String?
    var errorMessage: String?

    init(
        selection: String,
        context: ReviewAIQueryContext,
        activePresetID: String
    ) {
        self.originalSelection = selection
        self.draftSelection = selection
        self.context = context
        self.activePresetID = activePresetID
    }

    var trimmedSelection: String? {
        draftSelection.trimmedOrNil
    }
}

struct ReviewSelectionLookupPreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var template: String
    var encodeSelection: Bool

    init(
        id: String = UUID().uuidString,
        name: String = "",
        template: String = "",
        encodeSelection: Bool = true
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.encodeSelection = encodeSelection
    }
}

struct ReviewSelectionAIPreset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var endpoint: String
    var model: String
    var systemPrompt: String
    var glossary: String

    init(
        id: String = UUID().uuidString,
        name: String = "",
        endpoint: String = "https://api.openai.com/v1/chat/completions",
        model: String = "gpt-4o-mini",
        systemPrompt: String = "",
        glossary: String = ""
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.model = model
        self.systemPrompt = systemPrompt
        self.glossary = glossary
    }
}

struct ReviewSelectionAIConfig {
    let presetID: String
    let presetName: String
    let endpoint: String
    let model: String
    let systemPrompt: String
    let glossary: String
    let apiKey: String?

    static func load(defaults: UserDefaults = .standard) -> Self {
        ReviewSelectionAIPresetStore.load(defaults: defaults).activeConfig()
    }
}

struct ReviewSelectionLookupPresetStore: Codable, Equatable {
    var presets: [ReviewSelectionLookupPreset]
    var selectedPresetID: String

    static func load(defaults: UserDefaults = .standard) -> Self {
        if let data = defaults.data(forKey: ReviewPreferences.Keys.selectionMenuLookupPresets),
           let value = try? JSONDecoder().decode(Self.self, from: data) {
            return value.normalized()
        }
        let migrated = migratedLegacy(defaults: defaults)
        migrated.persist(defaults: defaults)
        return migrated
    }

    var activePreset: ReviewSelectionLookupPreset {
        let value = normalized()
        return value.presets.first(where: { $0.id == value.selectedPresetID }) ?? value.presets[0]
    }

    func persist(defaults: UserDefaults = .standard) {
        let value = normalized()
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: ReviewPreferences.Keys.selectionMenuLookupPresets)
    }

    mutating func addPreset() {
        let preset = ReviewSelectionLookupPreset()
        presets.append(preset)
        selectedPresetID = preset.id
        self = normalized()
    }

    mutating func update(_ preset: ReviewSelectionLookupPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        self = normalized()
    }

    mutating func removePreset(id: String) {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == id }
        self = normalized()
    }

    private static func migratedLegacy(defaults: UserDefaults) -> Self {
        let preset = ReviewSelectionLookupPreset(
            template: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuLookupTemplate) ?? "",
            encodeSelection: true
        )
        return Self(presets: [preset], selectedPresetID: preset.id)
    }

    private func normalized() -> Self {
        var value = self
        if value.presets.isEmpty {
            let preset = ReviewSelectionLookupPreset()
            value.presets = [preset]
            value.selectedPresetID = preset.id
        } else if value.presets.contains(where: { $0.id == value.selectedPresetID }) == false,
                  let firstPreset = value.presets.first {
            value.selectedPresetID = firstPreset.id
        }
        return value
    }
}

struct ReviewSelectionAIPresetStore: Codable, Equatable {
    var presets: [ReviewSelectionAIPreset]
    var selectedPresetID: String

    static func load(defaults: UserDefaults = .standard) -> Self {
        if let data = defaults.data(forKey: ReviewPreferences.Keys.selectionMenuAIPresets),
           let value = try? JSONDecoder().decode(Self.self, from: data) {
            return value.normalized()
        }
        let migrated = migratedLegacy(defaults: defaults)
        migrated.persist(defaults: defaults)
        return migrated
    }

    var activePreset: ReviewSelectionAIPreset {
        let value = normalized()
        return value.presets.first(where: { $0.id == value.selectedPresetID }) ?? value.presets[0]
    }

    func activeConfig() -> ReviewSelectionAIConfig {
        let preset = activePreset
        return ReviewSelectionAIConfig(
            presetID: preset.id,
            presetName: preset.name.trimmedOrNil ?? "AI",
            endpoint: preset.endpoint,
            model: preset.model,
            systemPrompt: preset.systemPrompt,
            glossary: preset.glossary,
            apiKey: KeychainHelper.loadReviewSelectionAIAPIKey(identifier: preset.id)
                ?? KeychainHelper.loadReviewSelectionAIAPIKey()
        )
    }

    func config(for presetID: String) -> ReviewSelectionAIConfig {
        let preset = presets.first(where: { $0.id == presetID }) ?? activePreset
        return ReviewSelectionAIConfig(
            presetID: preset.id,
            presetName: preset.name.trimmedOrNil ?? "AI",
            endpoint: preset.endpoint,
            model: preset.model,
            systemPrompt: preset.systemPrompt,
            glossary: preset.glossary,
            apiKey: KeychainHelper.loadReviewSelectionAIAPIKey(identifier: preset.id)
                ?? KeychainHelper.loadReviewSelectionAIAPIKey()
        )
    }

    func persist(defaults: UserDefaults = .standard) {
        let value = normalized()
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: ReviewPreferences.Keys.selectionMenuAIPresets)
    }

    mutating func addPreset() {
        let preset = ReviewSelectionAIPreset()
        presets.append(preset)
        selectedPresetID = preset.id
        self = normalized()
    }

    mutating func update(_ preset: ReviewSelectionAIPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        self = normalized()
    }

    mutating func removePreset(id: String) {
        guard presets.count > 1 else { return }
        presets.removeAll { $0.id == id }
        KeychainHelper.deleteReviewSelectionAIAPIKey(identifier: id)
        self = normalized()
    }

    private static func migratedLegacy(defaults: UserDefaults) -> Self {
        let preset = ReviewSelectionAIPreset(
            endpoint: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAIEndpoint)
                ?? "https://api.openai.com/v1/chat/completions",
            model: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAIModel) ?? "gpt-4o-mini",
            systemPrompt: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAISystemPrompt) ?? "",
            glossary: defaults.string(forKey: ReviewPreferences.Keys.selectionMenuAIGlossary) ?? ""
        )
        if let legacyAPIKey = KeychainHelper.loadReviewSelectionAIAPIKey() {
            try? KeychainHelper.saveReviewSelectionAIAPIKey(legacyAPIKey, identifier: preset.id)
        }
        return Self(presets: [preset], selectedPresetID: preset.id)
    }

    private func normalized() -> Self {
        var value = self
        if value.presets.isEmpty {
            let preset = ReviewSelectionAIPreset()
            value.presets = [preset]
            value.selectedPresetID = preset.id
        } else if value.presets.contains(where: { $0.id == value.selectedPresetID }) == false,
                  let firstPreset = value.presets.first {
            value.selectedPresetID = firstPreset.id
        }
        return value
    }
}

enum ReviewSelectionURLBuilder {
    static func resolveTemplate(
        template: String,
        selection: String,
        shouldEncodeSelection: Bool = true
    ) -> String? {
        guard let trimmedTemplate = template.trimmedOrNil else { return nil }
        let encodedSelection = selection.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? selection
        let substitutedSelection = shouldEncodeSelection ? encodedSelection : selection

        return trimmedTemplate
            .replacingOccurrences(of: "{text}", with: substitutedSelection)
            .replacingOccurrences(of: "{text_encoded}", with: encodedSelection)
            .replacingOccurrences(of: "{text_raw}", with: selection)
    }

    static func resolve(
        template: String,
        selection: String,
        shouldEncodeSelection: Bool = true
    ) -> URL? {
        guard let resolved = resolveTemplate(
            template: template,
            selection: selection,
            shouldEncodeSelection: shouldEncodeSelection
        ) else {
            return nil
        }

        let url: URL?
        if shouldEncodeSelection == false, #available(iOS 17.0, *) {
            url = URL(string: resolved, encodingInvalidCharacters: false) ?? URL(string: resolved)
        } else {
            url = URL(string: resolved)
        }

        guard let url, let scheme = url.scheme?.lowercased(), scheme.isEmpty == false else {
            return nil
        }
        return url
    }
}

enum ReviewSelectionAIClient {
    static func generateResponse(
        for selection: String,
        context: ReviewAIQueryContext? = nil,
        quickAction: ReviewAIQuickAction? = nil,
        config: ReviewSelectionAIConfig
    ) async throws -> String {
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
                ChatMessage(role: "user", content: resolvedUserPrompt(
                    selection: selection,
                    context: context,
                    quickAction: quickAction
                ))
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

    private static func resolvedUserPrompt(
        selection: String,
        context: ReviewAIQueryContext?,
        quickAction: ReviewAIQuickAction?
    ) -> String {
        var sections: [String] = []
        if let quickAction {
            sections.append("Task: \(quickAction.promptInstruction)")
        }
        sections.append("Selected text:\n\(selection)")
        if let sentence = context?.sentence?.trimmedOrNil {
            sections.append("Sentence:\n\(sentence)")
        }
        if let source = context?.source?.trimmedOrNil {
            sections.append("Source:\n\(source)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func resolvedSystemPrompt(from config: ReviewSelectionAIConfig) -> String {
        let basePrompt = config.systemPrompt.trimmedOrNil
            ?? "Explain the selected text clearly and concisely in Chinese. Preserve important terms and point out ambiguity when needed."
        guard let glossary = config.glossary.trimmedOrNil else {
            return basePrompt
        }
        return "\(basePrompt)\n\nTerminology constraints:\n\(glossary)"
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

struct ReviewSelectionLookupLinkSettingsView: View {
    @AppStorage(ReviewPreferences.Keys.selectionMenuLookupEnabled) private var selectionMenuLookupEnabled = false
    @State private var store = ReviewSelectionLookupPresetStore.load()

    var body: some View {
        List {
            Section {
                Toggle(L("settings_review_text_selection_menu_lookup_enabled"), isOn: $selectionMenuLookupEnabled)
            } footer: {
                Text(L("settings_review_lookup_settings_footer"))
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_preset_section_current")) {
                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Text(L("settings_review_preset_active"))
                        .foregroundStyle(SettingsValueStyle.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Picker(L("settings_review_preset_active"), selection: selectedPresetBinding) {
                            ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                                Text(presetTitle(preset, index: index))
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(preset.id)
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: activePresetTitle)
                    }
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_preset_section_saved")) {
                ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                    NavigationLink {
                        ReviewSelectionLookupLinkPresetEditorView(
                            preset: presetBinding(for: preset.id),
                            title: presetTitle(preset, index: index)
                        )
                    } label: {
                        presetRow(
                            title: presetTitle(preset, index: index),
                            subtitle: preset.template.trimmedOrNil ?? L("common_none"),
                            isSelected: preset.id == store.selectedPresetID,
                            icon: "link"
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if store.presets.count > 1 {
                            Button(role: .destructive) {
                                store.removePreset(id: preset.id)
                            } label: {
                                Label(L("common_delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_lookup_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.addPreset()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: store) { _, newValue in
            newValue.persist()
        }
    }

    private var selectedPresetBinding: Binding<String> {
        Binding(
            get: { store.selectedPresetID },
            set: { newValue in
                store.selectedPresetID = newValue
            }
        )
    }

    private var activePresetTitle: String {
        let activePreset = store.activePreset
        let index = store.presets.firstIndex(where: { $0.id == activePreset.id }) ?? 0
        return presetTitle(activePreset, index: index)
    }

    private func presetBinding(for presetID: String) -> Binding<ReviewSelectionLookupPreset> {
        Binding(
            get: {
                store.presets.first(where: { $0.id == presetID }) ?? ReviewSelectionLookupPreset(id: presetID)
            },
            set: { newValue in
                store.update(newValue)
            }
        )
    }

    private func presetTitle(_ preset: ReviewSelectionLookupPreset, index: Int) -> String {
        preset.name.trimmedOrNil ?? L("settings_review_preset_name_fallback", index + 1)
    }
}

private struct ReviewSelectionLookupLinkPresetEditorView: View {
    @Binding var preset: ReviewSelectionLookupPreset
    let title: String

    var body: some View {
        List {
            Section {
                TextField(L("settings_review_preset_name"), text: $preset.name)
            }
            .amgiSettingsListRowSurface()

            Section {
                TextField(
                    "",
                    text: $preset.template,
                    prompt: Text(L("settings_review_lookup_link_template_hint"))
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Toggle(L("settings_review_lookup_link_encode_selection"), isOn: $preset.encodeSelection)
            } header: {
                Text(L("settings_review_lookup_link_template"))
            } footer: {
                Text(L("settings_review_lookup_link_template_footer"))
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ReviewAISettingsHomeView: View {
    @AppStorage(ReviewPreferences.Keys.selectionMenuAIEnabled) private var selectionMenuAIEnabled = false
    @State private var favoriteStore = ReviewAIFavoriteStore.load()
    @State private var quickActionStore = ReviewAIQuickActionStore.load()

    var body: some View {
        List {
            Section {
                Toggle(L("settings_review_text_selection_menu_ai_enabled"), isOn: $selectionMenuAIEnabled)
            } footer: {
                Text(L("settings_review_ai_settings_footer"))
            }
            .amgiSettingsListRowSurface()

            Section {
                NavigationLink {
                    ReviewAIPresetManagementView()
                } label: {
                    settingsDestinationRow(
                        title: L("settings_review_ai_presets"),
                        subtitle: L("settings_review_ai_presets_subtitle"),
                        icon: "slider.horizontal.3"
                    )
                }

                NavigationLink {
                    ReviewAIFavoritesView()
                } label: {
                    settingsDestinationRow(
                        title: L("settings_review_ai_favorites"),
                        subtitle: favoriteCountLabel,
                        icon: "star"
                    )
                }

                NavigationLink {
                    ReviewAINoteTemplateSettingsView()
                } label: {
                    settingsDestinationRow(
                        title: L("settings_review_ai_note_template"),
                        subtitle: L("settings_review_ai_note_template_subtitle"),
                        icon: "note.text.badge.plus"
                    )
                }

                NavigationLink {
                    ReviewAIQuickActionsView()
                } label: {
                    settingsDestinationRow(
                        title: L("settings_review_ai_quick_actions"),
                        subtitle: quickActionCountLabel,
                        icon: "bolt"
                    )
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_ai_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            favoriteStore = ReviewAIFavoriteStore.load()
            quickActionStore = ReviewAIQuickActionStore.load()
        }
    }

    private var favoriteCountLabel: String {
        L("settings_review_ai_favorites_count", favoriteStore.items.count)
    }

    private var quickActionCountLabel: String {
        L("settings_review_ai_quick_actions_count", quickActionStore.actions.count)
    }
}

private struct ReviewAIPresetManagementView: View {
    @State private var store = ReviewSelectionAIPresetStore.load()

    var body: some View {
        List {
            Section(L("settings_review_preset_section_current")) {
                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Text(L("settings_review_preset_active"))
                        .foregroundStyle(SettingsValueStyle.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Picker(L("settings_review_preset_active"), selection: selectedPresetBinding) {
                            ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                                Text(presetTitle(preset, index: index))
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(preset.id)
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: activePresetTitle)
                    }
                }
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_preset_section_saved")) {
                ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                    NavigationLink {
                        ReviewAIPresetEditorView(
                            preset: presetBinding(for: preset.id),
                            title: presetTitle(preset, index: index)
                        )
                    } label: {
                        presetRow(
                            title: presetTitle(preset, index: index),
                            subtitle: preset.endpoint.trimmedOrNil ?? L("common_none"),
                            isSelected: preset.id == store.selectedPresetID,
                            icon: "sparkles"
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if store.presets.count > 1 {
                            Button(role: .destructive) {
                                store.removePreset(id: preset.id)
                            } label: {
                                Label(L("common_delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_ai_presets"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.addPreset()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: store) { _, newValue in
            newValue.persist()
        }
    }

    private var selectedPresetBinding: Binding<String> {
        Binding(
            get: { store.selectedPresetID },
            set: { newValue in
                store.selectedPresetID = newValue
            }
        )
    }

    private var activePresetTitle: String {
        let activePreset = store.activePreset
        let index = store.presets.firstIndex(where: { $0.id == activePreset.id }) ?? 0
        return presetTitle(activePreset, index: index)
    }

    private func presetBinding(for presetID: String) -> Binding<ReviewSelectionAIPreset> {
        Binding(
            get: {
                store.presets.first(where: { $0.id == presetID }) ?? ReviewSelectionAIPreset(id: presetID)
            },
            set: { newValue in
                store.update(newValue)
            }
        )
    }

    private func presetTitle(_ preset: ReviewSelectionAIPreset, index: Int) -> String {
        preset.name.trimmedOrNil ?? L("settings_review_preset_name_fallback", index + 1)
    }
}

private struct ReviewAIPresetEditorView: View {
    @Binding var preset: ReviewSelectionAIPreset
    let title: String
    @State private var apiKey: String

    init(preset: Binding<ReviewSelectionAIPreset>, title: String) {
        self._preset = preset
        self.title = title
        self._apiKey = State(initialValue: KeychainHelper.loadReviewSelectionAIAPIKey(identifier: preset.wrappedValue.id) ?? "")
    }

    var body: some View {
        List {
            Section {
                TextField(L("settings_review_preset_name"), text: $preset.name)
            }
            .amgiSettingsListRowSurface()

            Section {
                TextField(L("settings_review_ai_endpoint"), text: $preset.endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField(L("settings_review_ai_model"), text: $preset.model)
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
                placeholderTextEditor(
                    text: $preset.systemPrompt,
                    placeholder: L("settings_review_ai_system_prompt_placeholder"),
                    minHeight: 120
                )
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_ai_glossary")) {
                placeholderTextEditor(
                    text: $preset.glossary,
                    placeholder: L("settings_review_ai_glossary_placeholder"),
                    minHeight: 120
                )
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            persistAPIKey()
        }
    }

    private func persistAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.deleteReviewSelectionAIAPIKey(identifier: preset.id)
        } else {
            try? KeychainHelper.saveReviewSelectionAIAPIKey(trimmed, identifier: preset.id)
        }
    }
}

@MainActor
private func placeholderTextEditor(
    text: Binding<String>,
    placeholder: String,
    minHeight: CGFloat
) -> some View {
    ZStack(alignment: .topLeading) {
        if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(placeholder)
                .foregroundStyle(SettingsValueStyle.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
        }

        TextEditor(text: text)
            .frame(minHeight: minHeight)
    }
}

private struct ReviewAIFavoritesView: View {
    @State private var store = ReviewAIFavoriteStore.load()

    var body: some View {
        List {
            if store.items.isEmpty {
                Section {
                    Text(L("settings_review_ai_favorites_empty"))
                        .foregroundStyle(SettingsValueStyle.secondary)
                }
                .amgiSettingsListRowSurface()
            } else {
                Section {
                    ForEach(store.items) { item in
                        NavigationLink {
                            ReviewAIFavoriteDetailView(item: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.queryText)
                                    .amgiFont(.body)
                                    .foregroundStyle(SettingsValueStyle.primary)
                                    .lineLimit(1)
                                Text(item.summary)
                                    .amgiFont(.caption)
                                    .foregroundStyle(SettingsValueStyle.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.remove(id: item.id)
                                store.persist()
                            } label: {
                                Label(L("common_delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .amgiSettingsListRowSurface()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_ai_favorites"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store = ReviewAIFavoriteStore.load()
        }
    }
}

private struct ReviewAIQuickActionsView: View {
    @State private var store = ReviewAIQuickActionStore.load()

    var body: some View {
        List {
            if store.actions.isEmpty {
                Section {
                    Text(L("settings_review_ai_quick_actions_empty"))
                        .foregroundStyle(SettingsValueStyle.secondary)
                }
                .amgiSettingsListRowSurface()
            } else {
                Section {
                    ForEach(Array(store.actions.enumerated()), id: \.element.id) { index, action in
                        NavigationLink {
                            ReviewAIQuickActionEditorView(
                                action: actionBinding(for: action.id),
                                title: actionTitle(action, index: index)
                            )
                        } label: {
                            settingsDestinationRow(
                                title: actionTitle(action, index: index),
                                subtitle: action.promptInstruction.trimmedOrNil ?? L("common_none"),
                                icon: "bolt"
                            )
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.remove(id: action.id)
                            } label: {
                                Label(L("common_delete"), systemImage: "trash")
                            }
                        }
                    }
                }
                .amgiSettingsListRowSurface()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_ai_quick_actions"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.addAction()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onChange(of: store) { _, newValue in
            newValue.persist()
        }
        .onAppear {
            store = ReviewAIQuickActionStore.load()
        }
    }

    private func actionBinding(for actionID: String) -> Binding<ReviewAIQuickAction> {
        Binding(
            get: {
                store.actions.first(where: { $0.id == actionID })
                    ?? ReviewAIQuickAction(id: actionID, title: "", promptInstruction: "")
            },
            set: { newValue in
                store.update(newValue)
            }
        )
    }

    private func actionTitle(_ action: ReviewAIQuickAction, index: Int) -> String {
        action.title.trimmedOrNil ?? L("settings_review_ai_quick_action_name_fallback", index + 1)
    }
}

private struct ReviewAIQuickActionEditorView: View {
    @Binding var action: ReviewAIQuickAction
    let title: String

    var body: some View {
        List {
            Section {
                TextField(L("settings_review_ai_quick_action_name"), text: $action.title)
            }
            .amgiSettingsListRowSurface()

            Section {
                TextEditor(text: $action.promptInstruction)
                    .frame(minHeight: 160)
            } header: {
                Text(L("settings_review_ai_quick_action_prompt"))
            } footer: {
                Text(L("settings_review_ai_quick_action_prompt_footer"))
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReviewAIFavoriteDetailView: View {
    let item: ReviewAIFavoriteItem
    @State private var pendingAddNoteDraft: ReviewAIAddNoteSheetDraft?

    var body: some View {
        List {
            Section(L("review_selection_ai_selected_text")) {
                Text(item.queryText)
                    .textSelection(.enabled)
            }
            .amgiSettingsListRowSurface()

            if let sentence = item.sentence?.trimmedOrNil {
                Section(L("review_selection_ai_sentence")) {
                    Text(sentence)
                        .textSelection(.enabled)
                }
                .amgiSettingsListRowSurface()
            }

            if let source = item.source?.trimmedOrNil {
                Section(L("review_selection_ai_source")) {
                    Text(source)
                        .textSelection(.enabled)
                }
                .amgiSettingsListRowSurface()
            }

            Section(L("review_selection_ai_result")) {
                Text(item.responseText)
                    .textSelection(.enabled)
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(item.presetName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = item.responseText
                } label: {
                    Image(systemName: "doc.on.doc")
                }

                Button {
                    let template = ReviewAINoteTemplateStore.load().template
                    pendingAddNoteDraft = ReviewAIAddNoteSheetDraft(
                        draft: template.makeDraft(
                            context: item.context,
                            answer: item.responseText
                        )
                    )
                } label: {
                    Image(systemName: "note.text.badge.plus")
                }
            }
        }
        .sheet(item: $pendingAddNoteDraft) { sheetDraft in
            AddNoteView(
                onSave: {
                    pendingAddNoteDraft = nil
                },
                draft: sheetDraft.draft
            )
        }
    }
}

private struct ReviewAINoteTemplateSettingsView: View {
    @Dependency(\.ankiBackend) private var backend
    @Dependency(\.deckClient) private var deckClient

    @State private var store = ReviewAINoteTemplateStore.load()
    @State private var decks: [DeckInfo] = []
    @State private var notetypeNames: [(id: Int64, name: String)] = []
    @State private var availableFields: [String] = []

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Text(L("add_note_section_deck"))
                        .foregroundStyle(SettingsValueStyle.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Picker(L("add_note_section_deck"), selection: selectedDeckBinding) {
                            Text(L("settings_reader_not_set"))
                                .foregroundStyle(SettingsValueStyle.highlight)
                                .tag(0)
                            ForEach(decks) { deck in
                                Text(deck.name)
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(Int(deck.id))
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: selectedDeckLabel)
                    }
                }

                HStack(alignment: .top, spacing: AmgiSpacing.md) {
                    Text(L("add_note_type_label"))
                        .foregroundStyle(SettingsValueStyle.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Menu {
                        Picker(L("add_note_type_label"), selection: selectedNotetypeBinding) {
                            Text(L("settings_reader_not_set"))
                                .foregroundStyle(SettingsValueStyle.highlight)
                                .tag(0)
                            ForEach(notetypeNames, id: \.id) { item in
                                Text(item.name)
                                    .foregroundStyle(SettingsValueStyle.highlight)
                                    .tag(Int(item.id))
                            }
                        }
                    } label: {
                        SettingsOptionCapsuleLabel(title: selectedNotetypeLabel)
                    }
                }
            } footer: {
                Text(L("settings_review_ai_note_template_footer"))
            }
            .amgiSettingsListRowSurface()

            Section {
                VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
                    Text(L("settings_review_ai_note_template_selection_format"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ReviewAISelectionFormatFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(ReviewAINoteSelectionFormat.allCases) { format in
                            let binding = selectionFormatBinding(for: format)
                            Button {
                                binding.wrappedValue.toggle()
                            } label: {
                                ReviewAISelectionFormatCapsule(
                                    title: format.title,
                                    isSelected: binding.wrappedValue
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(format.title)
                            .accessibilityAddTraits(binding.wrappedValue ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }

                ForEach(availableFields, id: \.self) { fieldName in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fieldName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField(L("common_none"), text: templateMappingBinding(for: fieldName))
                                .submitLabel(.done)
                            Menu {
                                Button("-") {
                                    templateMappingBinding(for: fieldName).wrappedValue = ""
                                }
                                Divider()
                                ForEach(ReviewAINoteTemplateToken.allCases) { token in
                                    Button(token.title) {
                                        insertToken(token.rawValue, into: fieldName)
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(L("io_section_tags"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(L("common_none"), text: tagsBinding)
                        .submitLabel(.done)
                }
            } header: {
                Text(L("settings_review_ai_note_template_fields"))
            } footer: {
                Text(L("settings_review_ai_note_template_selection_format_footer") + "\n" + L("settings_review_ai_note_template_supported_fields"))
            }
            .amgiSettingsListRowSurface()
        }
        .scrollContentBackground(.hidden)
        .background(Color.amgiBackground)
        .navigationTitle(L("settings_review_ai_note_template"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .onChange(of: store) { _, newValue in
            newValue.persist()
        }
    }

    private var selectedDeckBinding: Binding<Int> {
        Binding(
            get: { store.template.deckID.map(Int.init) ?? 0 },
            set: { newValue in
                store.template.deckID = newValue == 0 ? nil : Int64(newValue)
            }
        )
    }

    private var selectedNotetypeBinding: Binding<Int> {
        Binding(
            get: { store.template.notetypeID.map(Int.init) ?? 0 },
            set: { newValue in
                store.template.notetypeID = newValue == 0 ? nil : Int64(newValue)
                loadTemplateFields(for: store.template.notetypeID)
            }
        )
    }

    private var selectedDeckLabel: String {
        guard let deckID = store.template.deckID,
              let deck = decks.first(where: { $0.id == deckID }) else {
            return L("settings_reader_not_set")
        }
        return deck.name
    }

    private var selectedNotetypeLabel: String {
        guard let notetypeID = store.template.notetypeID,
              let entry = notetypeNames.first(where: { $0.id == notetypeID }) else {
            return L("settings_reader_not_set")
        }
        return entry.name
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { store.template.tags },
            set: { newValue in
                store.template.tags = newValue
            }
        )
    }

    private func selectionFormatBinding(
        for format: ReviewAINoteSelectionFormat
    ) -> Binding<Bool> {
        Binding(
            get: { store.template.selectionFormats.contains(format) },
            set: { isEnabled in
                if isEnabled {
                    if store.template.selectionFormats.contains(format) == false {
                        store.template.selectionFormats.append(format)
                    }
                } else {
                    store.template.selectionFormats.removeAll { $0 == format }
                }
                store.template.selectionFormats = ReviewAINoteSelectionFormat.allCases.filter {
                    store.template.selectionFormats.contains($0)
                }
            }
        )
    }

    private func templateMappingBinding(for fieldName: String) -> Binding<String> {
        Binding(
            get: { store.template.fieldMappings[fieldName] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    store.template.fieldMappings.removeValue(forKey: fieldName)
                } else {
                    store.template.fieldMappings[fieldName] = newValue
                }
            }
        )
    }

    private func insertToken(_ token: String, into fieldName: String) {
        let current = store.template.fieldMappings[fieldName] ?? ""
        if current.isEmpty {
            store.template.fieldMappings[fieldName] = token
        } else if current.contains(token) == false {
            store.template.fieldMappings[fieldName] = current + " " + token
        }
    }

    private func loadData() async {
        decks = (try? deckClient.fetchNamesOnly()) ?? []
        do {
            notetypeNames = try loadStandardNotetypeEntries(backend: backend)
        } catch {
            notetypeNames = []
        }
        loadTemplateFields(for: store.template.notetypeID)
    }

    private func loadTemplateFields(for notetypeID: Int64?) {
        guard let notetypeID else {
            availableFields = []
            store.template.clearInvalidFields(validFields: [])
            return
        }

        do {
            let notetype = try fetchNotetype(backend: backend, id: notetypeID)
            availableFields = notetype.fields.map(\.name)
            store.template.clearInvalidFields(validFields: availableFields)
        } catch {
            availableFields = []
            store.template.clearInvalidFields(validFields: [])
        }
    }
}

private struct ReviewAISelectionFormatCapsule: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .amgiFont(.captionBold)
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white : SettingsValueStyle.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.amgiAccent : Color.amgiSurfaceElevated,
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(
                    isSelected ? Color.amgiAccent.opacity(0.16) : Color.amgiBorder.opacity(0.28),
                    lineWidth: 1
                )
        )
        .contentShape(Capsule())
    }
}

private struct ReviewAISelectionFormatFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

@MainActor
private func settingsDestinationRow(title: String, subtitle: String, icon: String) -> some View {
    HStack(spacing: AmgiSpacing.sm) {
        Image(systemName: icon)
            .foregroundStyle(SettingsValueStyle.secondary)
            .frame(width: 18)

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(SettingsValueStyle.primary)
            Text(subtitle)
                .amgiFont(.caption)
                .foregroundStyle(SettingsValueStyle.secondary)
                .lineLimit(1)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
}

@MainActor
private func presetRow(title: String, subtitle: String, isSelected: Bool, icon: String) -> some View {
    HStack(spacing: AmgiSpacing.sm) {
        Image(systemName: icon)
            .foregroundStyle(SettingsValueStyle.secondary)
            .frame(width: 18)

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(SettingsValueStyle.primary)
            Text(subtitle)
                .amgiFont(.caption)
                .foregroundStyle(SettingsValueStyle.secondary)
                .lineLimit(1)
        }

        Spacer()

        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.amgiAccent)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
}

struct ReviewSelectionAISheetView: View {
    @Dependency(\.ankiBackend) private var backend
    @Binding var state: ReviewSelectionAIState
    @State private var resultContentHeight: CGFloat = 0
    let presets: [ReviewSelectionAIPreset]
    let quickActions: [ReviewAIQuickAction]
    let isFavorited: Bool
    let onClose: () -> Void
    let onSubmit: (ReviewAIQuickAction?) -> Void
    let onToggleFavorite: () -> Void
    let onAddNote: () -> Void

    init(
        state: Binding<ReviewSelectionAIState>,
        presets: [ReviewSelectionAIPreset],
        quickActions: [ReviewAIQuickAction],
        isFavorited: Bool,
        onClose: @escaping () -> Void,
        onSubmit: @escaping (ReviewAIQuickAction?) -> Void,
        onToggleFavorite: @escaping () -> Void,
        onAddNote: @escaping () -> Void
    ) {
        self._state = state
        self.presets = presets
        self.quickActions = quickActions
        self.isFavorited = isFavorited
        self.onClose = onClose
        self.onSubmit = onSubmit
        self.onToggleFavorite = onToggleFavorite
        self.onAddNote = onAddNote
    }

    private var resultPanelMaximumHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.46, 280), 420)
    }

    private var presetPickerMaximumWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.68, 320)
    }

    private var resultPanelMinimumHeight: CGFloat {
        min(220, resultPanelMaximumHeight)
    }

    private var resultPanelMeasuredHeight: CGFloat {
        resultContentHeight + 24
    }

    private var resultPanelHeight: CGFloat {
        min(max(resultPanelMeasuredHeight, resultPanelMinimumHeight), resultPanelMaximumHeight)
    }

    private var resultPanelNeedsScroll: Bool {
        resultPanelMeasuredHeight > resultPanelMaximumHeight
    }

    var body: some View {
        contentView
            .background(Color.amgiBackground)
            .navigationTitle(L("review_selection_ai_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_done")) {
                        onClose()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        onAddNote()
                    } label: {
                        Image(systemName: "note.text.badge.plus")
                    }
                    .disabled(canAddNote == false)
                    .accessibilityLabel(L("review_selection_ai_add_note"))

                    Button {
                        onToggleFavorite()
                    } label: {
                        Image(systemName: isFavorited ? "star.fill" : "star")
                    }
                    .accessibilityLabel(isFavorited ? L("review_selection_ai_unfavorite") : L("review_selection_ai_favorite"))
                }
            }
            .onAppear {
                renderResponseHTMLIfNeeded()
            }
            .onChange(of: state.activePresetID) { _, _ in
                onSubmit(nil)
            }
            .onChange(of: state.response) { _, _ in
                renderResponseHTMLIfNeeded()
            }
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AmgiSpacing.md) {
                presetPickerRow
                selectionEditorSection
                resultSection
                quickActionsSection
                contextSection
            }
            .padding()
        }
    }

    private var presetPickerRow: some View {
        HStack(spacing: AmgiSpacing.sm) {
            Menu {
                ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                    let title = preset.name.trimmedOrNil ?? L("settings_review_preset_name_fallback", index + 1)
                    Button {
                        state.activePresetID = preset.id
                    } label: {
                        if preset.id == state.activePresetID {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            } label: {
                HStack(spacing: AmgiSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(AmgiFont.micro.font)
                        .foregroundStyle(SettingsValueStyle.secondary)
                    Text(selectedPresetTitle)
                        .amgiFont(.body)
                        .foregroundStyle(SettingsValueStyle.highlight)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AmgiFont.micro.font)
                        .foregroundStyle(SettingsValueStyle.secondary)
                }
                .amgiCapsuleControl(backgroundColor: Color.amgiMenuSurface)
            }
            .frame(maxWidth: presetPickerMaximumWidth, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 0)

            Button {
                onSubmit(nil)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel(L("review_selection_ai_retry"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionEditorSection: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
            Text(L("review_selection_ai_selected_text"))
                .amgiFont(.bodyEmphasis)
                .foregroundStyle(SettingsValueStyle.primary)
            TextEditor(text: $state.draftSelection)
                .frame(minHeight: 92)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
            HStack(spacing: AmgiSpacing.sm) {
                Text(L("review_selection_ai_result"))
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(SettingsValueStyle.primary)

                Spacer(minLength: 0)

                Button(L("review_selection_ai_copy")) {
                    UIPasteboard.general.string = state.response?.trimmedOrNil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(canCopyResponse == false)
            }

            resultPanelContent
            .padding(12)
            .frame(
                maxWidth: .infinity,
                minHeight: resultPanelHeight,
                maxHeight: resultPanelHeight,
                alignment: .topLeading
            )
            .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resultPanelContent: some View {
        ScrollView(.vertical, showsIndicators: resultPanelNeedsScroll) {
            measuredResultContent
        }
        .scrollDisabled(resultPanelNeedsScroll == false)
    }

    private var measuredResultContent: some View {
        resultContent
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ReviewSelectionAIResultHeightPreferenceKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(ReviewSelectionAIResultHeightPreferenceKey.self) { newHeight in
                guard abs(resultContentHeight - newHeight) > 0.5 else { return }
                resultContentHeight = newHeight
            }
    }

    @ViewBuilder
    private var resultContent: some View {
        if state.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text(L("review_selection_ai_loading"))
                    .foregroundStyle(SettingsValueStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let errorMessage = state.errorMessage?.trimmedOrNil {
            Text(errorMessage)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else if let responseHTML = state.responseHTML?.trimmedOrNil {
            NoteFieldHTMLPreview(html: responseHTML)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Text(state.response?.trimmedOrNil ?? L("review_selection_ai_empty_response"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var quickActionsSection: some View {
        if quickActions.isEmpty == false {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AmgiSpacing.xs) {
                    ForEach(quickActions) { action in
                        Button(action.title) {
                            onSubmit(action)
                        }
                        .foregroundStyle(SettingsValueStyle.secondary)
                        .amgiCapsuleControl(backgroundColor: Color.amgiMenuSurface, horizontalPadding: 10, verticalPadding: 6)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var contextSection: some View {
        if state.context.sentence?.trimmedOrNil != nil || state.context.source?.trimmedOrNil != nil {
            DisclosureGroup(L("review_selection_ai_more_context")) {
                VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
                    if let sentence = state.context.sentence?.trimmedOrNil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("review_selection_ai_sentence"))
                                .amgiFont(.caption)
                                .foregroundStyle(SettingsValueStyle.secondary)
                            Text(sentence)
                                .textSelection(.enabled)
                        }
                    }
                    if let source = state.context.source?.trimmedOrNil {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("review_selection_ai_source"))
                                .amgiFont(.caption)
                                .foregroundStyle(SettingsValueStyle.secondary)
                            Text(source)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, AmgiSpacing.xs)
            }
            .padding(12)
            .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedPresetTitle: String {
        if let index = presets.firstIndex(where: { $0.id == state.activePresetID }) {
            return presets[index].name.trimmedOrNil ?? L("settings_review_preset_name_fallback", index + 1)
        }
        return L("settings_review_ai_settings")
    }

    private var canAddNote: Bool {
        state.trimmedSelection != nil && state.response?.trimmedOrNil != nil
    }

    private var canCopyResponse: Bool {
        state.response?.trimmedOrNil != nil
    }

    private func renderResponseHTMLIfNeeded() {
        guard state.isLoading == false,
              state.errorMessage?.trimmedOrNil == nil,
              let response = state.response?.trimmedOrNil else {
            if state.responseHTML != nil {
                state.responseHTML = nil
            }
            return
        }

        let renderedHTML = ReviewAIFlow.renderResponseHTML(markdown: response, backend: backend)
        if state.responseHTML != renderedHTML {
            state.responseHTML = renderedHTML
        }
    }
}

extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ReviewSelectionAIResultHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
