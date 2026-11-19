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

/// Where AI explanations come from, and which languages explanations and
/// translations use, for the text-selection actions in review.
struct AIAssistantSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.selectionActionsEnabled))
    private var selectionActionsEnabled: Bool = true
    @Shared(.appStorage(ReviewPreferences.Keys.aiProvider))
    private var providerRaw: String = AIAssistantProvider.apple.rawValue
    @Shared(.appStorage(ReviewPreferences.Keys.aiSelectedService))
    private var selectedServiceID: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiExplainPrompt))
    private var explainPromptID: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiTranslatePrompt))
    private var translatePromptID: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.translationProvider))
    private var translationProviderRaw: String = AITranslationProvider.apple.rawValue
    @Shared(.appStorage(ReviewPreferences.Keys.aiExplanationLanguage))
    private var explanationLanguage: String = AIAssistantLanguage.deviceDefault
    @Shared(.appStorage(ReviewPreferences.Keys.translationTargetLanguage))
    private var translationTarget: String = AIAssistantLanguage.deviceDefault

    @State private var model = AIServicesModel()
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
                        title: String(localized: "Model source", bundle: .module),
                        systemImage: "sparkles",
                        tone: .info,
                        selection: Binding(
                            get: { providerRaw },
                            set: { value in
                                $providerRaw.withLock { $0 = value }
                                model.resetTest(nil)
                            }
                        )
                    ) {
                        Text("On-device (Apple)", bundle: .module).tag(AIAssistantProvider.apple.rawValue)
                        Text("API service", bundle: .module).tag(AIAssistantProvider.openAI.rawValue)
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
                    SettingsSeparator()
                    promptPicker(.explain)
                    SettingsSeparator()
                    SettingsRowLink(
                        title: String(localized: "Prompts", bundle: .module),
                        systemImage: "text.quote",
                        tone: .info,
                        detail: "\(model.prompts(for: .explain).count + model.prompts(for: .translate).count)"
                    ) {
                        AIPromptListView(model: model)
                    }
                }
                if provider == .apple {
                    SettingsFootnote(String(localized: "Runs on this device and works offline. Needs a device with Apple Intelligence turned on (iOS 26 or later).", bundle: .module))
                }
            }

            if provider == .openAI {
                AIServiceListSection(model: model, selectedServiceID: Binding($selectedServiceID))
            }

            Group {
                SettingsGroup {
                    AITestRow(state: model.testState(nil)) {
                        Task { await model.test(nil) }
                    }
                }
                if case .failed(let message) = model.testState(nil) {
                    SettingsFootnote(message)
                }
            }

            Group {
                SettingsSectionHeader(title: String(localized: "Translation", bundle: .module))
                SettingsGroup {
                    SettingsPickerRow(
                        title: String(localized: "Translate with", bundle: .module),
                        systemImage: "globe",
                        tone: .link,
                        selection: Binding($translationProviderRaw)
                    ) {
                        Text("Apple Translation", bundle: .module).tag(AITranslationProvider.apple.rawValue)
                        Text("AI", bundle: .module).tag(AITranslationProvider.ai.rawValue)
                    }
                    SettingsSeparator()
                    if translationProviderRaw == AITranslationProvider.ai.rawValue {
                        promptPicker(.translate)
                        SettingsSeparator()
                    }
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
                SettingsFootnote(String(localized: "Apple Translation runs on this device; the first time, it may ask to download the language. AI translates with the explanation provider above and the translation prompt. Make Card fills the vocabulary card template, including its AI explanation and translation fields. Only the selected text and its sentence are ever sent to an AI service.", bundle: .module))
            }
        }
        .navigationTitle(String(localized: "AI and Translation", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { model.reload() }
    }

    /// The prompt in use for explanations or translations.
    private func promptPicker(_ purpose: AIPromptPreset.Purpose) -> some View {
        let stored = purpose == .explain ? $explainPromptID : $translatePromptID
        let prompts = model.prompts(for: purpose)
        return SettingsPickerRow(
            title: purpose == .explain
                ? String(localized: "Explanation prompt", bundle: .module)
                : String(localized: "Translation prompt", bundle: .module),
            systemImage: "text.bubble",
            tone: purpose == .explain ? .info : .link,
            selection: Binding(
                get: {
                    let id = stored.wrappedValue
                    return prompts.contains { $0.id == id } ? id : AIPromptPreset.defaultPreset(for: purpose).id
                },
                set: { id in stored.withLock { $0 = id } }
            )
        ) {
            ForEach(prompts) { prompt in
                Text(prompt.name).tag(prompt.id)
            }
        }
    }
}
