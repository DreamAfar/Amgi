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
    @State private var store = ReviewSelectionLookupPresetStore.load()

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
        .navigationTitle(L("settings_review_lookup_link_options"))
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

private struct ReviewSelectionAISettingsView: View {
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
                        ReviewSelectionAIPresetEditorView(
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
        .navigationTitle(L("settings_review_ai_settings"))
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

private struct ReviewSelectionAIPresetEditorView: View {
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
                TextEditor(text: $preset.systemPrompt)
                    .frame(minHeight: 120)
            }
            .amgiSettingsListRowSurface()

            Section(L("settings_review_ai_glossary")) {
                TextEditor(text: $preset.glossary)
                    .frame(minHeight: 120)
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

extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
