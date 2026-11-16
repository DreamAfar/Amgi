//
//  AIAssistantSettingsView.swift
//  SettingsFeature
//

import AppCore
import AppShared
import Dependencies
import Sharing
import SwiftUI
import Theme
import UIKit

/// Runs the connection test, so the view carries no `@Dependency`.
@Observable
@MainActor
final class AIAssistantSettingsModel {
    enum TestState: Equatable {
        case idle
        case testing
        case succeeded
        case failed(String)
    }

    private(set) var testState: TestState = .idle
    var apiKey: String = AIKeychain.apiKey ?? ""

    @ObservationIgnored @Dependency(\.aiAssistantClient) private var aiClient

    func saveKey() {
        AIKeychain.setAPIKey(apiKey)
    }

    func test() async {
        saveKey()
        testState = .testing
        do {
            _ = try await aiClient.testConnection()
            testState = .succeeded
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }

    func resetTest() {
        testState = .idle
    }
}

/// Where AI explanations come from, and which languages explanations and
/// translations use, for the text-selection actions in review.
struct AIAssistantSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.selectionActionsEnabled))
    private var selectionActionsEnabled: Bool = true
    @Shared(.appStorage(ReviewPreferences.Keys.aiProvider))
    private var providerRaw: String = AIAssistantProvider.apple.rawValue
    @Shared(.appStorage(ReviewPreferences.Keys.aiBaseURL))
    private var baseURL: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiModel))
    private var modelName: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiExplanationLanguage))
    private var explanationLanguage: String = AIAssistantLanguage.deviceDefault
    @Shared(.appStorage(ReviewPreferences.Keys.translationTargetLanguage))
    private var translationTarget: String = AIAssistantLanguage.deviceDefault

    @State private var model = AIAssistantSettingsModel()
    @Environment(\.palette) private var palette

    private var provider: AIAssistantProvider {
        AIAssistantProvider(rawValue: providerRaw) ?? .apple
    }

    var body: some View {
        SettingsPage {
            Group {
                SettingsGroup {
                    SettingsToggleRow(
                        title: String(localized: "Actions for selected text", bundle: .module),
                        systemImage: "text.cursor",
                        tone: .accent,
                        isOn: Binding($selectionActionsEnabled)
                    )
                }
                SettingsFootnote(String(localized: "Adds AI Explain, Translate, Speak and Make Card to the menu that appears when you select text on a card.", bundle: .module))
            }

            Group {
                SettingsSectionHeader(title: String(localized: "AI Explanations", bundle: .module))
                SettingsGroup {
                    SettingsPickerRow(
                        title: String(localized: "Provider", bundle: .module),
                        systemImage: "sparkles",
                        tone: .info,
                        selection: Binding(
                            get: { providerRaw },
                            set: { value in
                                $providerRaw.withLock { $0 = value }
                                model.resetTest()
                            }
                        )
                    ) {
                        Text("Apple on-device model", bundle: .module).tag(AIAssistantProvider.apple.rawValue)
                        Text("OpenAI-compatible service", bundle: .module).tag(AIAssistantProvider.openAI.rawValue)
                    }
                    SettingsSeparator()
                    SettingsPickerRow(
                        title: String(localized: "Explanation language", bundle: .module),
                        systemImage: "character.bubble",
                        tone: .info,
                        selection: Binding($explanationLanguage)
                    ) {
                        ForEach(AIAssistantLanguage.codes, id: \.self) { code in
                            Text(AIAssistantLanguage.name(for: code)).tag(code)
                        }
                    }
                }
                if provider == .apple {
                    SettingsFootnote(String(localized: "Runs on this device and works offline. Needs a device with Apple Intelligence turned on (iOS 26 or later).", bundle: .module))
                }
            }

            if provider == .openAI {
                Group {
                    SettingsSectionHeader(title: String(localized: "Service", bundle: .module))
                    SettingsGroup {
                        field(String(localized: "Address", bundle: .module), text: Binding($baseURL), prompt: "https://api.openai.com/v1", keyboard: .URL)
                        SettingsSeparator()
                        field(String(localized: "Model", bundle: .module), text: Binding($modelName), prompt: "gpt-4o-mini", keyboard: .default)
                        SettingsSeparator()
                        HStack(spacing: AmgiSpacing.md) {
                            Text("API key", bundle: .module)
                                .amgiFont(.body)
                                .foregroundStyle(palette.textPrimary)
                                .frame(width: 96, alignment: .leading)
                            SecureField(String(localized: "Optional for local servers", bundle: .module), text: $model.apiKey)
                                .amgiFont(.body)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { model.saveKey() }
                        }
                        .padding(.horizontal, AmgiSpacing.lg)
                        .frame(minHeight: 44)
                    }
                    SettingsFootnote(String(localized: "Any service with the OpenAI chat API works: OpenAI, DeepSeek, Qwen, or Ollama on your own computer. The key is kept in this device's Keychain and isn't synced.", bundle: .module))
                }
            }

            Group {
                SettingsGroup {
                    Button {
                        Task { await model.test() }
                    } label: {
                        HStack {
                            Text("Test", bundle: .module)
                                .amgiFont(.body)
                            Spacer()
                            testStatus
                        }
                        .padding(.horizontal, AmgiSpacing.lg)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.accent)
                    .disabled(model.testState == .testing)
                }
                if case .failed(let message) = model.testState {
                    SettingsFootnote(message)
                }
            }

            Group {
                SettingsSectionHeader(title: String(localized: "Translation", bundle: .module))
                SettingsGroup {
                    SettingsPickerRow(
                        title: String(localized: "Translate into", bundle: .module),
                        systemImage: "translate",
                        tone: .link,
                        selection: Binding($translationTarget)
                    ) {
                        ForEach(AIAssistantLanguage.codes, id: \.self) { code in
                            Text(AIAssistantLanguage.name(for: code)).tag(code)
                        }
                    }
                    SettingsSeparator()
                    SettingsRowLink(
                        title: String(localized: "Vocabulary Card Template", bundle: .module),
                        systemImage: "rectangle.and.pencil.and.ellipsis",
                        tone: .review
                    ) {
                        LookupNoteTemplateView()
                    }
                }
                SettingsFootnote(String(localized: "Translations use Apple Translation on this device; the first time, it may ask to download the language. Make Card fills the vocabulary card template, including its AI explanation and translation fields. Only the selected text and its sentence are ever sent to an AI service.", bundle: .module))
            }
        }
        .navigationTitle(String(localized: "AI and Translation", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onDisappear { model.saveKey() }
    }

    @ViewBuilder
    private var testStatus: some View {
        switch model.testState {
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

    private func field(_ title: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: AmgiSpacing.md) {
            Text(title)
                .amgiFont(.body)
                .foregroundStyle(palette.textPrimary)
                .frame(width: 96, alignment: .leading)
            TextField(prompt, text: text)
                .amgiFont(.body)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { model.resetTest() }
        }
        .padding(.horizontal, AmgiSpacing.lg)
        .frame(minHeight: 44)
    }
}
