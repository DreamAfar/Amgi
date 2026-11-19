//
//  ReviewSelectionSheet.swift
//  ReviewFeature
//

import AppCore
import AppShared
import Sharing
import SwiftUI
import Theme
import Translation
import UIKit

/// The half-sheet for text selected on a review card: the selection and
/// its sentence on top, then the AI explanation or the translation, and a
/// bar to copy or make a card. Review stays open behind it.
struct ReviewSelectionSheet: View {
    let model: ReviewSelectionModel
    let assist: ReviewSelectionModel.Assist
    let onMakeCard: () -> Void

    @Environment(\.palette) private var palette
    @Shared(.appStorage(ReviewPreferences.Keys.aiExplanationLanguage))
    private var explanationLanguage: String = AIAssistantLanguage.deviceDefault
    @Shared(.appStorage(ReviewPreferences.Keys.translationTargetLanguage))
    private var translationTarget: String = AIAssistantLanguage.deviceDefault
    @Shared(.appStorage(ReviewPreferences.Keys.translationProvider))
    private var translationProviderRaw: String = AITranslationProvider.apple.rawValue
    @Shared(.appStorage(ReviewPreferences.Keys.aiExplainPrompt))
    private var explainPromptID: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiTranslatePrompt))
    private var translatePromptID: String = ""
    @Shared(.appStorage(ReviewPreferences.Keys.aiSelectedService))
    private var selectedServiceID: String = ""

    @State private var tab: ReviewSelectionModel.Tab
    @State private var question = ""
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var selectionTranslation: String?
    @State private var sentenceTranslation: String?
    @State private var translationError: String?

    init(model: ReviewSelectionModel, assist: ReviewSelectionModel.Assist, onMakeCard: @escaping () -> Void) {
        self.model = model
        self.assist = assist
        self.onMakeCard = onMakeCard
        _tab = State(initialValue: assist.tab)
    }

    private var selection: WebSelection { assist.selection }

    /// A sentence worth translating on its own, beside the selection.
    private var separateSentence: String? {
        guard let sentence = selection.sentence, sentence != selection.text else { return nil }
        return sentence
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AmgiSpacing.lg) {
                    header
                    Picker(String(localized: "Show", bundle: .module), selection: $tab) {
                        Text("AI Explanation", bundle: .module).tag(ReviewSelectionModel.Tab.explain)
                        Text("Translation", bundle: .module).tag(ReviewSelectionModel.Tab.translate)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch tab {
                    case .explain: explainContent
                    case .translate: translateContent
                    }
                }
                .padding(AmgiSpacing.lg)
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle(tab == .explain ? String(localized: "AI Explanation", bundle: .module) : String(localized: "Translation", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    aiOptionsMenu
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { model.close() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { start(tab) }
        .onChange(of: tab) { _, newTab in start(newTab) }
        .translationTask(translationConfig) { session in
            await translate(with: session)
        }
    }

    // MARK: - Prompt and service

    private var usesAITranslation: Bool {
        AITranslationProvider(rawValue: translationProviderRaw) == .ai
    }

    /// Which prompt the open tab uses, when it uses one.
    private var activePurpose: AIPromptPreset.Purpose? {
        switch tab {
        case .explain: .explain
        case .translate: usesAITranslation ? .translate : nil
        }
    }

    /// Switches the prompt or the service for this tab without leaving the
    /// sheet, and asks again with it.
    @ViewBuilder
    private var aiOptionsMenu: some View {
        // The store reads user defaults directly; reading the shared values
        // here is what redraws the sheet when a choice changes.
        let _ = (explainPromptID, translatePromptID, selectedServiceID, translationProviderRaw)
        let services = AIAssistantProvider.current == .openAI ? AIServiceStore.services : []
        if activePurpose != nil || services.count > 1 {
            Menu {
                if let purpose = activePurpose {
                    Picker(String(localized: "Prompt", bundle: .module), selection: promptBinding(purpose)) {
                        ForEach(AIServiceStore.prompts(for: purpose)) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .pickerStyle(.inline)
                }
                if services.count > 1 {
                    Picker(String(localized: "Service", bundle: .module), selection: serviceBinding) {
                        ForEach(services) { service in
                            Text(service.displayName).tag(service.id.uuidString)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel(Text("AI Options", bundle: .module))
        }
    }

    private func promptBinding(_ purpose: AIPromptPreset.Purpose) -> Binding<String> {
        Binding(
            get: { AIServiceStore.selectedPrompt(for: purpose).id },
            set: { id in
                if purpose == .explain {
                    $explainPromptID.withLock { $0 = id }
                } else {
                    $translatePromptID.withLock { $0 = id }
                }
                rerun()
            }
        )
    }

    private var serviceBinding: Binding<String> {
        Binding(
            get: { AIServiceStore.selectedService?.id.uuidString ?? "" },
            set: { id in
                $selectedServiceID.withLock { $0 = id }
                rerun()
            }
        )
    }

    /// The open tab's answer again, with the prompt or service just chosen.
    private func rerun() {
        switch tab {
        case .explain:
            model.restartExplanation(language: explanationLanguage)
        case .translate:
            if usesAITranslation { model.translateWithAI(language: translationTarget, force: true) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: AmgiSpacing.sm) {
                Text(selection.text)
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.speak(selection.text)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Speak", bundle: .module))
            }
            if let sentence = separateSentence {
                Text(sentence)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, AmgiSpacing.md)
                    .padding(.vertical, AmgiSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: AmgiRadius.small))
            }
        }
    }

    // MARK: - Explanation

    @ViewBuilder
    private var explainContent: some View {
        answerView(model.explanation, retry: { model.retryExplanation(language: explanationLanguage) })

        ForEach(model.followUps) { exchange in
            VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
                Text(exchange.question)
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                answerView(exchange.answer, retry: nil)
            }
        }

        if model.explanation.text != nil {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AmgiSpacing.xs) {
                    followUpChip(String(localized: "Explain it more simply", bundle: .module))
                    followUpChip(String(localized: "More example sentences", bundle: .module))
                    followUpChip(String(localized: "Similar words and how they differ", bundle: .module))
                }
            }
            HStack(spacing: AmgiSpacing.sm) {
                TextField(String(localized: "Ask a follow-up question", bundle: .module), text: $question)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(sendQuestion)
                Button(action: sendQuestion) {
                    Image(systemName: "arrow.up.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Ask", bundle: .module))
            }
        }

        Text(providerNote)
            .amgiFont(.micro)
            .foregroundStyle(palette.textSecondary)
    }

    @ViewBuilder
    private func answerView(_ answer: ReviewSelectionModel.Answer, retry: (() -> Void)?) -> some View {
        switch answer {
        case .idle, .loading:
            HStack(spacing: AmgiSpacing.sm) {
                ProgressView()
                Text("Thinking…", bundle: .module)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .done(let text):
            Text(text)
                .amgiFont(.body)
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                if let retry {
                    Button(String(localized: "Try Again", bundle: .module), action: retry)
                }
            }
        }
    }

    private func followUpChip(_ text: String) -> some View {
        Button {
            model.ask(text, language: explanationLanguage)
        } label: {
            Text(text)
                .amgiFont(.caption)
                .padding(.horizontal, AmgiSpacing.md)
                .padding(.vertical, AmgiSpacing.xs)
                .overlay(Capsule().strokeBorder(palette.border))
        }
        .buttonStyle(.borderless)
    }

    private func sendQuestion() {
        model.ask(question, language: explanationLanguage)
        question = ""
    }

    private var providerNote: String {
        let prompt = AIServiceStore.selectedPrompt(for: .explain).name
        return switch AIAssistantProvider.current {
        case .apple:
            String(localized: "Explained by Apple's on-device model, with the prompt “\(prompt)”.", bundle: .module)
        case .openAI:
            String(localized: "Explained by \(aiProviderName), with the prompt “\(prompt)”. Only the selection and its sentence were sent.", bundle: .module)
        }
    }

    // MARK: - Translation

    @ViewBuilder
    private var translateContent: some View {
        if usesAITranslation {
            aiTranslateContent
        } else {
            appleTranslateContent
        }
    }

    @ViewBuilder
    private var aiTranslateContent: some View {
        answerView(model.aiTranslation, retry: { model.translateWithAI(language: translationTarget, force: true) })

        Text(String(
            localized: "Translated into \(AIAssistantLanguage.name(for: translationTarget)) by \(aiProviderName), with the prompt “\(AIServiceStore.selectedPrompt(for: .translate).name)”.",
            bundle: .module
        ))
        .amgiFont(.micro)
        .foregroundStyle(palette.textSecondary)
    }

    private var aiProviderName: String {
        switch AIAssistantProvider.current {
        case .apple: String(localized: "Apple's on-device model", bundle: .module)
        case .openAI: AIServiceStore.selectedService?.displayName ?? String(localized: "your AI service", bundle: .module)
        }
    }

    @ViewBuilder
    private var appleTranslateContent: some View {
        if let translationError {
            Label(translationError, systemImage: "exclamationmark.triangle")
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)
        } else if selectionTranslation == nil {
            HStack(spacing: AmgiSpacing.sm) {
                ProgressView()
                Text("Translating…", bundle: .module)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        } else {
            translationBlock(
                title: String(localized: "Selection", bundle: .module),
                text: selectionTranslation ?? ""
            )
            if let sentenceTranslation {
                translationBlock(title: String(localized: "Whole sentence", bundle: .module), text: sentenceTranslation)
            }
        }

        Text("Translated on this device by Apple Translation into \(AIAssistantLanguage.name(for: translationTarget)).", bundle: .module)
            .amgiFont(.micro)
            .foregroundStyle(palette.textSecondary)

        Button {
            tab = .explain
            model.explain(language: explanationLanguage)
            model.ask(String(localized: "Translate the whole sentence naturally and explain the hard parts.", bundle: .module), language: explanationLanguage)
        } label: {
            Label(String(localized: "Ask AI for a natural translation", bundle: .module), systemImage: "sparkles")
        }
        .buttonStyle(.bordered)
    }

    private func translationBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
            Text(title)
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)
            Text(text)
                .amgiFont(.body)
                .foregroundStyle(palette.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: AmgiSpacing.sm) {
            Button {
                UIPasteboard.general.string = copyText
            } label: {
                Label(String(localized: "Copy", bundle: .module), systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button(action: onMakeCard) {
                Label(String(localized: "Make Card", bundle: .module), systemImage: "plus.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, AmgiSpacing.lg)
        .padding(.vertical, AmgiSpacing.sm)
        .background(palette.background)
    }

    private var copyText: String {
        switch tab {
        case .explain:
            ([model.explanation.text] + model.followUps.map(\.answer.text)).compactMap { $0 }.joined(separator: "\n\n")
        case .translate:
            usesAITranslation
                ? model.aiTranslation.text ?? ""
                : [selectionTranslation, sentenceTranslation].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private func start(_ tab: ReviewSelectionModel.Tab) {
        switch tab {
        case .explain:
            model.explain(language: explanationLanguage)
        case .translate:
            if usesAITranslation {
                model.translateWithAI(language: translationTarget)
                return
            }
            guard selectionTranslation == nil, translationConfig == nil else { return }
            translationConfig = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: translationTarget)
            )
        }
    }

    private func translate(with session: TranslationSession) async {
        do {
            var requests = [TranslationSession.Request(sourceText: selection.text, clientIdentifier: "selection")]
            if let sentence = separateSentence {
                requests.append(TranslationSession.Request(sourceText: sentence, clientIdentifier: "sentence"))
            }
            // The session is handed to this view's task and used nowhere else,
            // but the framework doesn't mark it Sendable, so its off-main-actor
            // `translations(from:)` can't be reached from the main actor without this.
            nonisolated(unsafe) let session = session
            let responses = try await session.translations(from: requests)
            for response in responses {
                if response.clientIdentifier == "sentence" {
                    sentenceTranslation = response.targetText
                } else {
                    selectionTranslation = response.targetText
                }
            }
            model.translation = sentenceTranslation ?? selectionTranslation
        } catch {
            translationError = error.localizedDescription
        }
    }
}
