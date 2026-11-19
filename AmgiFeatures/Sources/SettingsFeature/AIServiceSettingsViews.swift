//
//  AIServiceSettingsViews.swift
//  SettingsFeature
//

import AppCore
import AppShared
import Dependencies
import Sharing
import SwiftUI
import Theme
import UIKit

// MARK: - Model

/// The services and prompts being edited, kept in step with the store, and
/// connection tests, so the views carry no `@Dependency`.
@Observable
@MainActor
final class AIServicesModel {
    enum TestState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    private(set) var services: [AIServiceProfile] = AIServiceStore.services
    private(set) var customPrompts: [AIPromptPreset] = AIServiceStore.customPrompts
    /// Tests by service id; `nil` is the provider and service in use.
    private(set) var tests: [UUID?: TestState] = [:]

    @ObservationIgnored @Dependency(\.aiAssistantClient) private var aiClient

    func reload() {
        services = AIServiceStore.services
        customPrompts = AIServiceStore.customPrompts
    }

    // MARK: Services

    func service(_ id: UUID) -> AIServiceProfile? {
        services.first { $0.id == id }
    }

    func save(_ service: AIServiceProfile) {
        if let index = services.firstIndex(where: { $0.id == service.id }) {
            guard services[index] != service else { return }
            services[index] = service
        } else {
            services.append(service)
        }
        AIServiceStore.saveServices(services)
        tests[service.id] = .idle
    }

    /// A new, empty service; the first one also becomes the one in use.
    func addService() -> AIServiceProfile {
        let service = AIServiceProfile(name: "", baseURL: "", model: "")
        save(service)
        if services.count == 1 { AIServiceStore.select(service) }
        return service
    }

    func delete(_ id: UUID) {
        services.removeAll { $0.id == id }
        AIServiceStore.saveServices(services)
        AIKeychain.deleteAPIKey(for: id)
        tests[id] = nil
    }

    func test(_ service: AIServiceProfile?) async {
        let key = service?.id
        tests[key] = .testing
        do {
            _ = try await aiClient.testConnection(service)
            tests[key] = .succeeded
        } catch {
            tests[key] = .failed(error.localizedDescription)
        }
    }

    func testState(_ id: UUID?) -> TestState {
        tests[id] ?? .idle
    }

    func resetTest(_ id: UUID?) {
        tests[id] = .idle
    }

    // MARK: Prompts

    func prompts(for purpose: AIPromptPreset.Purpose) -> [AIPromptPreset] {
        (AIPromptPreset.builtIns + customPrompts).filter { $0.purpose == purpose }
    }

    func prompt(_ id: String) -> AIPromptPreset? {
        (AIPromptPreset.builtIns + customPrompts).first { $0.id == id }
    }

    func save(_ prompt: AIPromptPreset) {
        guard !prompt.isBuiltIn else { return }
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            guard customPrompts[index] != prompt else { return }
            customPrompts[index] = prompt
        } else {
            customPrompts.append(prompt)
        }
        AIServiceStore.saveCustomPrompts(customPrompts)
    }

    /// An editable copy of a prompt, added to the user's own.
    func duplicate(_ prompt: AIPromptPreset) -> AIPromptPreset {
        let copy = prompt.duplicate(named: String(localized: "\(prompt.name) Copy", bundle: .module))
        save(copy)
        return copy
    }

    func deletePrompt(_ id: String) {
        customPrompts.removeAll { $0.id == id }
        AIServiceStore.saveCustomPrompts(customPrompts)
    }
}

// MARK: - Service list

/// The services set up, which one is in use, and a way to add one.
struct AIServiceListSection: View {
    let model: AIServicesModel
    @Binding var selectedServiceID: String
    @State private var newService: AIServiceProfile?

    private var inUseID: UUID? {
        let id = UUID(uuidString: selectedServiceID)
        return model.services.contains { $0.id == id } ? id : model.services.first?.id
    }

    var body: some View {
        SettingsSectionHeader(title: String(localized: "Services", bundle: .module))
        SettingsGroup {
            if model.services.count > 1 {
                SettingsPickerRow(
                    title: String(localized: "In use", bundle: .module),
                    systemImage: "checkmark.circle",
                    tone: .review,
                    selection: Binding(
                        get: { inUseID?.uuidString ?? "" },
                        set: { id in
                            selectedServiceID = id
                            model.resetTest(nil)
                        }
                    )
                ) {
                    ForEach(model.services) { service in
                        Text(service.displayName).tag(service.id.uuidString)
                    }
                }
                SettingsSeparator()
            }
            ForEach(model.services) { service in
                SettingsRowLink(
                    title: service.displayName,
                    systemImage: service.id == inUseID ? "checkmark.seal.fill" : "server.rack",
                    tone: service.id == inUseID ? .review : .neutral,
                    detail: service.model.isEmpty ? nil : service.model
                ) {
                    AIServiceEditView(model: model, serviceID: service.id, selectedServiceID: $selectedServiceID)
                }
                SettingsSeparator()
            }
            SettingsButtonRow(
                title: String(localized: "Add Service", bundle: .module),
                systemImage: "plus",
                tone: .accent
            ) {
                newService = model.addService()
            }
        }
        .navigationDestination(item: $newService) { service in
            AIServiceEditView(model: model, serviceID: service.id, selectedServiceID: $selectedServiceID)
        }
        SettingsFootnote(String(localized: "Any service with the OpenAI chat API works: OpenAI, DeepSeek, Qwen, or Ollama on your own computer. Each key is kept in this device's Keychain and isn't synced.", bundle: .module))
    }
}

// MARK: - Service editor

struct AIServiceEditView: View {
    let model: AIServicesModel
    let serviceID: UUID
    @Binding var selectedServiceID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var draft = AIServiceProfile(name: "", baseURL: "", model: "")
    @State private var apiKey = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    private var isInUse: Bool {
        let id = UUID(uuidString: selectedServiceID)
        return id == serviceID || (!model.services.contains { $0.id == id } && model.services.first?.id == serviceID)
    }

    var body: some View {
        SettingsPage {
            SettingsSectionHeader(title: String(localized: "Service", bundle: .module))
            SettingsGroup {
                AISettingsField(title: String(localized: "Name", bundle: .module), text: $draft.name, prompt: String(localized: "Optional", bundle: .module), keyboard: .default)
                SettingsSeparator()
                AISettingsField(title: String(localized: "Address", bundle: .module), text: $draft.baseURL, prompt: "https://api.openai.com/v1", keyboard: .URL)
                SettingsSeparator()
                AISettingsField(title: String(localized: "Model", bundle: .module), text: $draft.model, prompt: "gpt-4o-mini", keyboard: .default)
                SettingsSeparator()
                HStack(spacing: AmgiSpacing.md) {
                    Text("API key", bundle: .module)
                        .amgiFont(.body)
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 96, alignment: .leading)
                    SecureField(String(localized: "Optional for local servers", bundle: .module), text: $apiKey)
                        .amgiFont(.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveKey)
                }
                .padding(.horizontal, AmgiSpacing.lg)
                .frame(minHeight: 44)
            }

            SettingsGroup {
                AITestRow(state: model.testState(serviceID)) {
                    saveKey()
                    model.save(draft)
                    Task { await model.test(draft) }
                }
            }
            if case .failed(let message) = model.testState(serviceID) {
                SettingsFootnote(message)
            }

            SettingsGroup {
                if !isInUse {
                    SettingsButtonRow(
                        title: String(localized: "Use This Service", bundle: .module),
                        systemImage: "checkmark.circle",
                        tone: .review
                    ) {
                        selectedServiceID = serviceID.uuidString
                    }
                    SettingsSeparator()
                }
                SettingsButtonRow(
                    title: String(localized: "Delete Service", bundle: .module),
                    systemImage: "trash",
                    tone: .danger,
                    isDestructive: true
                ) {
                    confirmDelete = true
                }
            }
        }
        .navigationTitle(draft.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: draft) { _, draft in
            guard loaded else { return }
            model.save(draft)
        }
        .onDisappear(perform: saveKey)
        .confirmationDialog(
            String(localized: "Delete this service and its key?", bundle: .module),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Service", bundle: .module), role: .destructive) {
                loaded = false
                model.delete(serviceID)
                dismiss()
            }
        }
    }

    private func load() {
        guard !loaded, let service = model.service(serviceID) else { return }
        draft = service
        apiKey = AIKeychain.apiKey(for: serviceID) ?? ""
        loaded = true
    }

    private func saveKey() {
        guard loaded, model.service(serviceID) != nil else { return }
        AIKeychain.setAPIKey(apiKey, for: serviceID)
    }
}

// MARK: - Prompt list

/// The built-in prompts and the user's own, for both explanations and
/// translations.
struct AIPromptListView: View {
    let model: AIServicesModel

    @Shared(.appStorage(ReviewPreferences.Keys.aiExplainPrompt)) private var explainPromptID: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiTranslatePrompt)) private var translatePromptID: String = ""
    @State private var opened: AIPromptPreset?

    var body: some View {
        SettingsPage {
            section(.explain, title: String(localized: "Explanation Prompts", bundle: .module))
            section(.translate, title: String(localized: "Translation Prompts", bundle: .module))
            SettingsFootnote(String(localized: "The built-in prompts can't be changed, but a copy of one can. In a prompt, {{text}} is the selected text, {{sentence}} the sentence around it (a line with it is left out when there isn't one), and {{language}} the answer language.", bundle: .module))
        }
        .navigationTitle(String(localized: "Prompts", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { prompt in
            AIPromptEditView(model: model, promptID: prompt.id)
        }
        .onAppear { model.reload() }
    }

    @ViewBuilder
    private func section(_ purpose: AIPromptPreset.Purpose, title: String) -> some View {
        let inUse = selectedID(purpose)
        SettingsSectionHeader(title: title)
        SettingsGroup {
            ForEach(model.prompts(for: purpose)) { prompt in
                SettingsRowLink(
                    title: prompt.name,
                    systemImage: prompt.isBuiltIn ? "lock" : "text.quote",
                    tone: prompt.id == inUse ? .review : .neutral,
                    detail: prompt.id == inUse ? String(localized: "In use", bundle: .module) : nil
                ) {
                    AIPromptEditView(model: model, promptID: prompt.id)
                }
                SettingsSeparator()
            }
            SettingsButtonRow(
                title: String(localized: "New Prompt", bundle: .module),
                systemImage: "plus",
                tone: .accent
            ) {
                // Starts from the default, so the placeholders are already there.
                let prompt = AIPromptPreset.defaultPreset(for: purpose)
                    .duplicate(named: String(localized: "My Prompt", bundle: .module))
                model.save(prompt)
                opened = prompt
            }
        }
    }

    private func selectedID(_ purpose: AIPromptPreset.Purpose) -> String {
        let id = purpose == .explain ? explainPromptID : translatePromptID
        return model.prompts(for: purpose).contains { $0.id == id } ? id : AIPromptPreset.defaultPreset(for: purpose).id
    }
}

// MARK: - Prompt editor

struct AIPromptEditView: View {
    let model: AIServicesModel
    @State var promptID: String

    @Shared(.appStorage(ReviewPreferences.Keys.aiExplainPrompt)) private var explainPromptID: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiTranslatePrompt)) private var translatePromptID: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var draft: AIPromptPreset?
    @State private var confirmDelete = false
    @ScaledMetric(relativeTo: .body) private var editorHeight: CGFloat = 140

    init(model: AIServicesModel, promptID: String) {
        self.model = model
        _promptID = State(initialValue: promptID)
    }

    private var isInUse: Bool {
        guard let draft else { return false }
        let id = draft.purpose == .explain ? explainPromptID : translatePromptID
        let current = model.prompts(for: draft.purpose).contains { $0.id == id } ? id : AIPromptPreset.defaultPreset(for: draft.purpose).id
        return current == draft.id
    }

    var body: some View {
        SettingsPage {
            if let draft {
                content(draft)
            }
        }
        .navigationTitle(draft?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: promptID) { load() }
        .onChange(of: draft) { _, draft in
            if let draft { model.save(draft) }
        }
        .confirmationDialog(
            String(localized: "Delete this prompt?", bundle: .module),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Prompt", bundle: .module), role: .destructive) {
                let id = promptID
                draft = nil
                model.deletePrompt(id)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func content(_ prompt: AIPromptPreset) -> some View {
        let editable = !prompt.isBuiltIn
        if editable {
            SettingsGroup {
                AISettingsField(title: String(localized: "Name", bundle: .module), text: binding(\.name), prompt: String(localized: "Prompt name", bundle: .module), keyboard: .default)
            }
        }

        SettingsSectionHeader(title: String(localized: "Instructions", bundle: .module))
        editor(binding(\.instructions), editable: editable)
        SettingsFootnote(String(localized: "Sent as the system message: who the AI should be and how to answer.", bundle: .module))

        SettingsSectionHeader(title: String(localized: "Request", bundle: .module))
        editor(binding(\.prompt), editable: editable)
        if editable {
            HStack(spacing: AmgiSpacing.xs) {
                ForEach(AIPromptPreset.placeholders, id: \.self) { placeholder in
                    Button(placeholder) {
                        draft?.prompt += placeholder
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, AmgiSpacing.lg)
        }
        SettingsFootnote(String(localized: "Sent as your message. {{text}} is the selected text, {{sentence}} the sentence around it, {{language}} the answer language. Follow-up questions keep these instructions and add the earlier answer.", bundle: .module))

        SettingsGroup {
            if !isInUse {
                SettingsButtonRow(
                    title: String(localized: "Use This Prompt", bundle: .module),
                    systemImage: "checkmark.circle",
                    tone: .review
                ) {
                    if prompt.purpose == .explain {
                        $explainPromptID.withLock { $0 = prompt.id }
                    } else {
                        $translatePromptID.withLock { $0 = prompt.id }
                    }
                }
                SettingsSeparator()
            }
            SettingsButtonRow(
                title: editable ? String(localized: "Duplicate", bundle: .module) : String(localized: "Duplicate and Edit", bundle: .module),
                systemImage: "plus.square.on.square",
                tone: .accent
            ) {
                promptID = model.duplicate(prompt).id
            }
            if editable {
                SettingsSeparator()
                SettingsButtonRow(
                    title: String(localized: "Delete Prompt", bundle: .module),
                    systemImage: "trash",
                    tone: .danger,
                    isDestructive: true
                ) {
                    confirmDelete = true
                }
            }
        }
    }

    private func editor(_ text: Binding<String>, editable: Bool) -> some View {
        SettingsGroup {
            Group {
                if editable {
                    TextEditor(text: text)
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    ScrollView {
                        Text(text.wrappedValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
            .amgiFont(.caption)
            .foregroundStyle(editable ? palette.textPrimary : palette.textSecondary)
            .frame(minHeight: editorHeight, maxHeight: editorHeight * 2)
            .padding(.horizontal, AmgiSpacing.md)
            .padding(.vertical, AmgiSpacing.sm)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AIPromptPreset, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { draft?[keyPath: keyPath] = $0 }
        )
    }

    private func load() {
        draft = model.prompt(promptID)
    }
}

// MARK: - Shared rows

struct AISettingsField: View {
    let title: String
    @Binding var text: String
    let prompt: String
    let keyboard: UIKeyboardType

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: AmgiSpacing.md) {
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(palette.textPrimary)
                .frame(width: 96, alignment: .leading)
            TextField(prompt, text: $text)
                .amgiFont(.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, AmgiSpacing.lg)
        .frame(minHeight: 44)
    }
}

/// "Test", with the result beside it.
struct AITestRow: View {
    let state: AIServicesModel.TestState
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Test", bundle: .module)
                    .amgiFont(.body)
                Spacer()
                status
            }
            .padding(.horizontal, AmgiSpacing.lg)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.accent)
        .disabled(state == .testing)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .idle: EmptyView()
        case .testing: ProgressView()
        case .succeeded:
            Label(String(localized: "Working", bundle: .module), systemImage: "checkmark.circle")
                .amgiFont(.caption)
                .foregroundStyle(palette.positive)
        case .failed:
            Label(String(localized: "Failed", bundle: .module), systemImage: "xmark.circle")
                .amgiFont(.caption)
                .foregroundStyle(palette.danger)
        }
    }
}
