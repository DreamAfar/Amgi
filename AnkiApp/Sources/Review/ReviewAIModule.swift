import Foundation
import AnkiKit

enum ReviewAIFlowError: Error, Equatable, Sendable {
    case message(String)

    var message: String {
        switch self {
        case let .message(value):
            return value
        }
    }
}

struct ReviewAIQueryContext: Codable, Equatable, Hashable, Sendable {
    var selectedText: String
    var sentence: String?
    var source: String?

    init(
        selectedText: String,
        sentence: String? = nil,
        source: String? = nil
    ) {
        self.selectedText = selectedText
        self.sentence = sentence?.trimmedOrNil
        self.source = source?.trimmedOrNil
    }
}

enum ReviewAIQuickAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case explain
    case translate
    case example
    case grammar
    case simplify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explain:
            return L("review_selection_ai_action_explain")
        case .translate:
            return L("review_selection_ai_action_translate")
        case .example:
            return L("review_selection_ai_action_example")
        case .grammar:
            return L("review_selection_ai_action_grammar")
        case .simplify:
            return L("review_selection_ai_action_simplify")
        }
    }

    var promptInstruction: String {
        switch self {
        case .explain:
            return "Explain the selected text clearly in Chinese, keeping key terms."
        case .translate:
            return "Translate the selected text into concise natural Chinese."
        case .example:
            return "Provide short example sentences and explain how the selected text is used."
        case .grammar:
            return "Break down the grammar and structure of the selected text in Chinese."
        case .simplify:
            return "Rewrite the answer in a simpler and more concise Chinese explanation."
        }
    }
}

struct ReviewAIFavoriteItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var createdAt: Date
    var presetID: String
    var presetName: String
    var queryText: String
    var responseText: String
    var sentence: String?
    var source: String?

    init(
        id: String = UUID().uuidString,
        createdAt: Date = .now,
        presetID: String,
        presetName: String,
        queryText: String,
        responseText: String,
        sentence: String? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.presetID = presetID
        self.presetName = presetName
        self.queryText = queryText
        self.responseText = responseText
        self.sentence = sentence?.trimmedOrNil
        self.source = source?.trimmedOrNil
    }

    var summary: String {
        responseText.trimmedOrNil ?? queryText
    }

    func matches(queryText: String, responseText: String, presetID: String) -> Bool {
        self.queryText == queryText && self.responseText == responseText && self.presetID == presetID
    }

    var context: ReviewAIQueryContext {
        ReviewAIQueryContext(
            selectedText: queryText,
            sentence: sentence,
            source: source
        )
    }
}

struct ReviewAIFavoriteStore: Codable, Equatable, Sendable {
    var items: [ReviewAIFavoriteItem]

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: ReviewPreferences.Keys.aiFavorites),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(items: [])
        }
        return value
    }

    func persist(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: ReviewPreferences.Keys.aiFavorites)
    }

    func contains(queryText: String, responseText: String, presetID: String) -> Bool {
        items.contains(where: { $0.matches(queryText: queryText, responseText: responseText, presetID: presetID) })
    }

    func favoriteID(queryText: String, responseText: String, presetID: String) -> String? {
        items.first(where: { $0.matches(queryText: queryText, responseText: responseText, presetID: presetID) })?.id
    }

    mutating func upsert(_ item: ReviewAIFavoriteItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        items.sort { $0.createdAt > $1.createdAt }
    }

    mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }
}

enum ReviewAINoteTemplateToken: String, CaseIterable, Identifiable, Sendable {
    case selection = "{selection}"
    case sentence = "{sentence}"
    case source = "{source}"
    case answer = "{answer}"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selection:
            return L("review_selection_ai_note_token_selection")
        case .sentence:
            return L("review_selection_ai_note_token_sentence")
        case .source:
            return L("review_selection_ai_note_token_source")
        case .answer:
            return L("review_selection_ai_note_token_answer")
        }
    }
}

struct ReviewAINoteTemplate: Codable, Equatable, Sendable {
    var deckID: Int64?
    var notetypeID: Int64?
    var fieldMappings: [String: String]
    var tags: String

    static let empty = Self()

    init(
        deckID: Int64? = nil,
        notetypeID: Int64? = nil,
        fieldMappings: [String: String] = [:],
        tags: String = "ai review-ai"
    ) {
        self.deckID = deckID
        self.notetypeID = notetypeID
        self.fieldMappings = fieldMappings
        self.tags = tags
    }

    mutating func clearInvalidFields(validFields: [String]) {
        let validFieldSet = Set(validFields)
        fieldMappings = fieldMappings.filter { validFieldSet.contains($0.key) }
    }

    func makeDraft(
        context: ReviewAIQueryContext,
        answer: String,
        fallbackDeckID: Int64? = nil
    ) -> AddNoteDraft {
        var resolvedFieldValues: [String: String] = [:]

        for (fieldName, template) in fieldMappings {
            let resolved = Self.resolve(template: template, context: context, answer: answer)
            if let trimmed = resolved.trimmedOrNil {
                resolvedFieldValues[fieldName] = trimmed
            }
        }

        if resolvedFieldValues.isEmpty {
            let selectedText = context.selectedText
            let resolvedSentence = context.sentence?.trimmedOrNil ?? selectedText
            let resolvedSource = context.source?.trimmedOrNil ?? ""

            resolvedFieldValues = [
                "Front": selectedText,
                "Text": selectedText,
                "Expression": selectedText,
                "Sentence": resolvedSentence,
                "Back": answer,
                "Meaning": answer,
                "Extra": answer,
                "Source": resolvedSource
            ]
        }

        return AddNoteDraft(
            deckID: deckID ?? fallbackDeckID,
            notetypeID: notetypeID,
            fieldValues: resolvedFieldValues,
            tags: tags.split(whereSeparator: \.isWhitespace).map(String.init)
        )
    }

    static func resolve(
        template: String,
        context: ReviewAIQueryContext,
        answer: String
    ) -> String {
        template
            .replacingOccurrences(of: ReviewAINoteTemplateToken.selection.rawValue, with: context.selectedText)
            .replacingOccurrences(of: ReviewAINoteTemplateToken.sentence.rawValue, with: context.sentence ?? "")
            .replacingOccurrences(of: ReviewAINoteTemplateToken.source.rawValue, with: context.source ?? "")
            .replacingOccurrences(of: ReviewAINoteTemplateToken.answer.rawValue, with: answer)
    }
}

struct ReviewAINoteTemplateStore: Codable, Equatable, Sendable {
    var template: ReviewAINoteTemplate

    static func load(defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: ReviewPreferences.Keys.aiNoteTemplate),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(template: .empty)
        }
        return value
    }

    func persist(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: ReviewPreferences.Keys.aiNoteTemplate)
    }
}

struct ReviewAIAddNoteSheetDraft: Identifiable, Equatable, Sendable {
    let id = UUID()
    let draft: AddNoteDraft
}

enum ReviewAIFlow {
    static func activeConfig(for presetID: String?) -> ReviewSelectionAIConfig {
        let store = ReviewSelectionAIPresetStore.load()
        guard let presetID = presetID?.trimmedOrNil else {
            return store.activeConfig()
        }
        return store.config(for: presetID)
    }

    static func validationError(for config: ReviewSelectionAIConfig) -> String? {
        if config.endpoint.trimmedOrNil == nil {
            return L("review_selection_ai_missing_endpoint")
        }
        if config.model.trimmedOrNil == nil {
            return L("review_selection_ai_missing_model")
        }
        return nil
    }

    static func makeInitialState(
        selection: String,
        context: ReviewAIQueryContext
    ) -> ReviewSelectionAIState {
        let config = activeConfig(for: nil)
        return ReviewSelectionAIState(
            selection: selection,
            context: context,
            activePresetID: config.presetID
        )
    }

    static func makeInitialStateIfConfigured(
        selection: String,
        context: ReviewAIQueryContext
    ) -> Result<ReviewSelectionAIState, ReviewAIFlowError> {
        let config = activeConfig(for: nil)
        if let error = validationError(for: config) {
            return .failure(.message(error))
        }
        return .success(
            ReviewSelectionAIState(
                selection: selection,
                context: context,
                activePresetID: config.presetID
            )
        )
    }

    static func prepareSubmission(
        state: ReviewSelectionAIState,
        quickAction: ReviewAIQuickAction?
    ) -> Result<(state: ReviewSelectionAIState, selection: String, config: ReviewSelectionAIConfig), ReviewAIFlowError> {
        guard let selection = state.trimmedSelection else {
            return .failure(.message(L("review_selection_ai_empty_selection")))
        }

        let config = activeConfig(for: state.activePresetID)
        if let error = validationError(for: config) {
            return .failure(.message(error))
        }

        var nextState = state
        nextState.isLoading = true
        nextState.errorMessage = nil
        nextState.lastAction = quickAction
        nextState.context.selectedText = selection
        return .success((nextState, selection, config))
    }

    static func requestResponse(
        selection: String,
        context: ReviewAIQueryContext,
        quickAction: ReviewAIQuickAction?,
        presetID: String
    ) async throws -> String {
        try await ReviewSelectionAIClient.generateResponse(
            for: selection,
            context: context,
            quickAction: quickAction,
            config: activeConfig(for: presetID)
        )
    }

    static func favoriteItem(for state: ReviewSelectionAIState) -> ReviewAIFavoriteItem? {
        guard let queryText = state.trimmedSelection,
              let responseText = state.response?.trimmedOrNil else {
            return nil
        }

        let config = activeConfig(for: state.activePresetID)
        return ReviewAIFavoriteItem(
            id: ReviewAIFavoriteStore.load().favoriteID(
                queryText: queryText,
                responseText: responseText,
                presetID: config.presetID
            ) ?? UUID().uuidString,
            presetID: config.presetID,
            presetName: config.presetName,
            queryText: queryText,
            responseText: responseText,
            sentence: state.context.sentence,
            source: state.context.source
        )
    }

    static func makeAddNoteDraft(
        for state: ReviewSelectionAIState,
        fallbackDeckID: Int64? = nil
    ) -> ReviewAIAddNoteSheetDraft? {
        guard let response = state.response?.trimmedOrNil,
              let selection = state.trimmedSelection else {
            return nil
        }

        let template = ReviewAINoteTemplateStore.load().template
        return ReviewAIAddNoteSheetDraft(
            draft: template.makeDraft(
                context: ReviewAIQueryContext(
                    selectedText: selection,
                    sentence: state.context.sentence,
                    source: state.context.source
                ),
                answer: response,
                fallbackDeckID: fallbackDeckID
            )
        )
    }

    static func isFavorited(_ item: ReviewAIFavoriteItem?) -> Bool {
        guard let item else { return false }
        return ReviewAIFavoriteStore.load().items.contains(where: { $0.id == item.id })
    }

    static func toggleFavorite(_ item: ReviewAIFavoriteItem?) {
        guard let item else { return }
        var store = ReviewAIFavoriteStore.load()
        if store.items.contains(where: { $0.id == item.id }) {
            store.remove(id: item.id)
        } else {
            store.upsert(item)
        }
        store.persist()
    }
}
