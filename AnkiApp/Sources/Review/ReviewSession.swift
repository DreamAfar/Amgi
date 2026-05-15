import SwiftUI
import AnkiKit
import AnkiClients
import AnkiBackend
import AnkiProto
import Dependencies
import Foundation
import SwiftProtobuf

@Observable @MainActor
final class ReviewSession {
    let deckId: Int64

    @ObservationIgnored @Dependency(\.deckClient) var deckClient
    @ObservationIgnored @Dependency(\.cardClient) var cardClient
    @ObservationIgnored @Dependency(\.noteClient) var noteClient
    @ObservationIgnored @Dependency(\.ankiBackend) var backend

    private(set) var frontHTML: String = ""
    private(set) var backHTML: String = ""
    private(set) var cardCSS: String = ""
    private(set) var showAnswer: Bool = false
    private(set) var autoplayAudio: Bool = true
    private(set) var waitForAudioBeforeAutoAdvance: Bool = false
    private(set) var autoAdvanceQuestionSeconds: Double = 0
    private(set) var autoAdvanceAnswerSeconds: Double = 0
    private(set) var includeQuestionAudioOnAnswerReplay: Bool = true
    private(set) var sessionStats: SessionStats = .init()
    private(set) var remainingCounts: DeckCounts = .zero
    private(set) var isFinished: Bool = false
    private(set) var canUndo: Bool = false
    /// Next interval for each rating button (formatted string)
    private(set) var nextIntervals: [Rating: String] = [:]
    /// Next interval in seconds for each rating button.
    private(set) var nextIntervalSeconds: [Rating: UInt32] = [:]
    private(set) var questionAVTags: [Anki_CardRendering_AVTag] = []
    private(set) var answerAVTags: [Anki_CardRendering_AVTag] = []
    private var reviewStartTime: Date = .now

    /// The raw QueuedCard objects from the Rust backend — preserves scheduling states.
    private var cardQueue: [Anki_Scheduler_QueuedCards.QueuedCard] = []
    private var currentQueuedCard: Anki_Scheduler_QueuedCards.QueuedCard?
    private var autoAdvanceQuestionAction: Anki_DeckConfig_DeckConfig.Config.QuestionAction = .showAnswer
    private var autoAdvanceAnswerAction: Anki_DeckConfig_DeckConfig.Config.AnswerAction = .buryCard
    private var renderedFrontHTML: String = ""
    private var renderedBackHTML: String = ""
    private var typedAnswerState: TypedAnswerState?

    private struct TypedAnswerState {
        let placeholder: String
        let expected: String
        let fontName: String
        let fontSize: UInt32
        let combining: Bool
    }

    /// Public accessor for the current card
    var currentCard: Anki_Scheduler_QueuedCards.QueuedCard? {
        currentQueuedCard
    }

    var requiresTypedAnswerInput: Bool {
        typedAnswerState != nil && !showAnswer
    }

    init(deckId: Int64) {
        self.deckId = deckId
    }

    private func setCurrentDeckForReview() throws {
        var deckReq = Anki_Decks_DeckId()
        deckReq.did = deckId
        try backend.callVoid(
            service: AnkiBackend.Service.decks,
            method: AnkiBackend.DecksMethod.setCurrentDeck,
            request: deckReq
        )
    }

    private func fetchQueuedCardsForCurrentDeck() throws -> Anki_Scheduler_QueuedCards {
        try setCurrentDeckForReview()

        var req = Anki_Scheduler_GetQueuedCardsRequest()
        req.fetchLimit = 200
        return try backend.invoke(
            service: AnkiBackend.Service.scheduler,
            method: AnkiBackend.SchedulerMethod.getQueuedCards,
            request: req
        )
    }

    private func applyQueuedCards(_ response: Anki_Scheduler_QueuedCards) {
        cardQueue = response.cards
        remainingCounts = DeckCounts(
            newCount: Int(response.newCount),
            learnCount: Int(response.learningCount),
            reviewCount: Int(response.reviewCount)
        )
        refreshUndoAvailability()
    }

    func start() {
        do {
            let response = try fetchQueuedCardsForCurrentDeck()

            if let deckConfig = try? deckClient.getDeckConfig(deckId) {
                let cfg = deckConfig.config
                autoplayAudio = !cfg.disableAutoplay
                waitForAudioBeforeAutoAdvance = cfg.waitForAudio
                autoAdvanceQuestionSeconds = Double(cfg.secondsToShowQuestion)
                autoAdvanceAnswerSeconds = Double(cfg.secondsToShowAnswer)
                autoAdvanceQuestionAction = cfg.questionAction
                autoAdvanceAnswerAction = cfg.answerAction
                includeQuestionAudioOnAnswerReplay = !cfg.skipQuestionWhenReplayingAnswer
            } else {
                autoplayAudio = true
                waitForAudioBeforeAutoAdvance = false
                autoAdvanceQuestionSeconds = 0
                autoAdvanceAnswerSeconds = 0
                autoAdvanceQuestionAction = .showAnswer
                autoAdvanceAnswerAction = .buryCard
                includeQuestionAudioOnAnswerReplay = true
            }

            applyQueuedCards(response)

            print("[ReviewSession] Started with \(cardQueue.count) cards, counts: new=\(remainingCounts.newCount) learn=\(remainingCounts.learnCount) review=\(remainingCounts.reviewCount)")
            advanceToNextCard()
        } catch {
            print("[ReviewSession] Start failed: \(error)")
            canUndo = false
            isFinished = true
        }
    }

    /// Refresh the card queue after a card action (suspend, bury, flag, etc.)
    /// and advance to the next card
    func refreshAndAdvance() {
        do {
            let response = try fetchQueuedCardsForCurrentDeck()
            applyQueuedCards(response)
            
            print("[ReviewSession] Queue refreshed after action: \(cardQueue.count) cards remaining")
            advanceToNextCard()
        } catch {
            print("[ReviewSession] Refresh failed: \(error)")
            // Still try to advance to next card even if refresh fails
            advanceToNextCard()
        }
    }

    /// Refresh queue after a card mutation (like flag/edit) while trying to keep current card.
    func refreshAfterCardMutation() async {
        let currentId = currentQueuedCard?.card.id
        let wasShowingAnswer = showAnswer

        do {
            let response = try fetchQueuedCardsForCurrentDeck()
            applyQueuedCards(response)

            if let currentId,
               let retained = cardQueue.first(where: { $0.card.id == currentId }) {
                currentQueuedCard = retained
                renderCurrentCard(retained)
                showAnswer = wasShowingAnswer
            } else {
                advanceToNextCard()
            }
        } catch {
            print("[ReviewSession] Mutation refresh failed: \(error)")
        }
    }

    func refreshAfterUndo() async {
        do {
            let response = try fetchQueuedCardsForCurrentDeck()
            applyQueuedCards(response)
            advanceToNextCard()
        } catch {
            print("[ReviewSession] Undo refresh failed: \(error)")
        }
    }

    func revealAnswer(typedAnswer: String? = nil) {
        if let typedAnswerState {
            backHTML = makeTypedAnswerBackHTML(typedAnswerState: typedAnswerState, typedAnswer: typedAnswer ?? "")
        } else {
            backHTML = strippingTypedAnswerPlaceholders(from: renderedBackHTML)
        }
        showAnswer = true
    }

    var currentAutoAdvanceDelay: Double? {
        let secs = showAnswer ? autoAdvanceAnswerSeconds : autoAdvanceQuestionSeconds
        return secs > 0 ? secs : nil
    }

    func performAutoAdvanceAction() {
        if showAnswer {
            performAutoAdvanceAnswerAction()
        } else {
            performAutoAdvanceQuestionAction()
        }
    }

    private func performAutoAdvanceQuestionAction() {
        switch autoAdvanceQuestionAction {
        case .showAnswer, .showReminder, .UNRECOGNIZED:
            revealAnswer()
        }
    }

    private func performAutoAdvanceAnswerAction() {
        switch autoAdvanceAnswerAction {
        case .answerAgain:
            answer(rating: .again)
        case .answerHard:
            answer(rating: .hard)
        case .answerGood:
            answer(rating: .good)
        case .buryCard:
            guard let cardId = currentQueuedCard?.card.id else { return }
            do {
                try cardClient.bury(cardId)
                refreshAndAdvance()
            } catch {
                print("[ReviewSession] Auto-advance bury failed: \(error)")
                refreshAndAdvance()
            }
        case .showReminder, .UNRECOGNIZED:
            break
        }
    }

    func answer(rating: Rating) {
        guard let queued = currentQueuedCard else { return }

        let timeSpent = UInt32(Date.now.timeIntervalSince(reviewStartTime) * 1000)

        do {
            var answer = Anki_Scheduler_CardAnswer()
            answer.cardID = queued.card.id

            // Pass the scheduling states from the QueuedCard
            answer.currentState = queued.states.current
            switch rating {
            case .again: answer.newState = queued.states.again
            case .hard: answer.newState = queued.states.hard
            case .good: answer.newState = queued.states.good
            case .easy: answer.newState = queued.states.easy
            }
            answer.rating = switch rating {
            case .again: .again
            case .hard: .hard
            case .good: .good
            case .easy: .easy
            }
            answer.answeredAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
            answer.millisecondsTaken = timeSpent

            try backend.callVoid(
                service: AnkiBackend.Service.scheduler,
                method: AnkiBackend.SchedulerMethod.answerCard,
                request: answer
            )

            sessionStats.reviewed += 1
            if rating != .again { sessionStats.correct += 1 }
            sessionStats.totalTimeMs += Int(timeSpent)

            let response = try fetchQueuedCardsForCurrentDeck()
            applyQueuedCards(response)

            advanceToNextCard()
        } catch {
            print("[ReviewSession] Answer failed: \(error)")
            // Skip this card and move to next
            if !cardQueue.isEmpty { cardQueue.removeFirst() }
            refreshUndoAvailability()
            advanceToNextCard()
        }
    }

    private func refreshUndoAvailability() {
        do {
            let status: Anki_Collection_UndoStatus = try backend.invoke(
                service: AnkiBackend.Service.collection,
                method: AnkiBackend.CollectionMethod.getUndoStatus,
                request: Anki_Generic_Empty()
            )
            canUndo = !status.undo.isEmpty
        } catch {
            canUndo = false
            print("[ReviewSession] Fetch undo status failed: \(error)")
        }
    }

    private func advanceToNextCard() {
        guard let next = cardQueue.first else {
            isFinished = true
            currentQueuedCard = nil
            return
        }

        currentQueuedCard = next
        showAnswer = false
        reviewStartTime = .now

        renderCurrentCard(next)

        // Extract next intervals from scheduling states
        let states = next.states
        nextIntervalSeconds = [
            .again: scheduledSecs(states.again),
            .hard: scheduledSecs(states.hard),
            .good: scheduledSecs(states.good),
            .easy: scheduledSecs(states.easy),
        ]
        nextIntervals = [
            .again: formatInterval(nextIntervalSeconds[.again] ?? 0),
            .hard: formatInterval(nextIntervalSeconds[.hard] ?? 0),
            .good: formatInterval(nextIntervalSeconds[.good] ?? 0),
            .easy: formatInterval(nextIntervalSeconds[.easy] ?? 0),
        ]
    }

    private func renderCurrentCard(_ queued: Anki_Scheduler_QueuedCards.QueuedCard) {
        do {
            var renderReq = Anki_CardRendering_RenderExistingCardRequest()
            renderReq.cardID = queued.card.id
            renderReq.browser = false

            let rendered: Anki_CardRendering_RenderCardResponse = try backend.invoke(
                service: AnkiBackend.Service.cardRendering,
                method: AnkiBackend.CardRenderingMethod.renderExistingCard,
                request: renderReq
            )

            let renderedQuestionHTML = renderNodes(rendered.questionNodes)
            let renderedAnswerHTML = renderNodes(rendered.answerNodes)
            let extractedQuestionHTML = extractLatexIfNeeded(in: renderedQuestionHTML, svg: rendered.latexSvg)
            let extractedAnswerHTML = extractLatexIfNeeded(in: renderedAnswerHTML, svg: rendered.latexSvg)
            let questionMedia = Self.normalizeExtractedReviewMedia(
                originalHTML: extractedQuestionHTML,
                media: extractAVTags(from: extractedQuestionHTML, questionSide: true),
                questionSide: true
            )
            let answerMedia = Self.normalizeExtractedReviewMedia(
                originalHTML: extractedAnswerHTML,
                media: extractAVTags(from: extractedAnswerHTML, questionSide: false),
                questionSide: false
            )
            let resolvedQuestionHTML = resolveReviewHTML(
                originalHTML: extractedQuestionHTML,
                extractedHTML: questionMedia.text,
                avTags: questionMedia.tags
            )
            let resolvedAnswerHTML = resolveReviewHTML(
                originalHTML: extractedAnswerHTML,
                extractedHTML: answerMedia.text,
                avTags: answerMedia.tags
            )

            renderedFrontHTML = encodeIriPathsIfNeeded(in: resolvedQuestionHTML)
            renderedBackHTML = encodeIriPathsIfNeeded(in: resolvedAnswerHTML)
            questionAVTags = questionMedia.tags
            answerAVTags = answerMedia.tags

            typedAnswerState = resolveTypedAnswerState(for: queued, frontHTML: renderedFrontHTML)
            frontHTML = makeTypedAnswerFrontHTML(typedAnswerState: typedAnswerState)
            backHTML = renderedBackHTML
            cardCSS = rendered.css
        } catch {
            print("[ReviewSession] Render failed for card \(queued.card.id): \(error)")
            frontHTML = "<p>Error rendering card</p>"
            backHTML = "<p>Error rendering card</p>"
            renderedFrontHTML = frontHTML
            renderedBackHTML = backHTML
            cardCSS = ""
            typedAnswerState = nil
            questionAVTags = []
            answerAVTags = []
        }
    }

    private func extractLatexIfNeeded(in html: String, svg: Bool) -> String {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return html
        }
        if !containsLegacyLatexMarkup(in: html) {
            return html
        }

        do {
            var request = Anki_CardRendering_ExtractLatexRequest()
            request.text = html
            request.svg = svg
            request.expandClozes = false

            let response: Anki_CardRendering_ExtractLatexResponse = try backend.invoke(
                service: AnkiBackend.Service.cardRendering,
                method: AnkiBackend.CardRenderingMethod.extractLatex,
                request: request
            )
            let extracted = response.text
            if extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return html
            }
            return extracted
        } catch {
            print("[ReviewSession] Latex extraction failed: \(error)")
            return html
        }
    }

    private func containsLegacyLatexMarkup(in html: String) -> Bool {
        html.contains("[latex]")
            || html.contains("[/latex]")
            || html.contains("[$]")
            || html.contains("[/$]")
            || html.contains("[$$]")
            || html.contains("[/$$]")
    }

    private func resolveReviewHTML(
        originalHTML: String,
        extractedHTML: String,
        avTags: [Anki_CardRendering_AVTag]
    ) -> String {
        guard Self.shouldUseExtractedAVHTML(
            originalHTML: originalHTML,
            extractedHTML: extractedHTML,
            avTagCount: avTags.count
        ) else {
            if Self.legacyAVDirectiveCount(in: originalHTML) > 0 {
                print("[ReviewSession] Falling back to original AV HTML to keep preview/review parity")
            }
            return originalHTML
        }

        return extractedHTML
    }

    static func shouldUseExtractedAVHTML(
        originalHTML: String,
        extractedHTML: String,
        avTagCount: Int
    ) -> Bool {
        let legacyDirectiveCount = legacyManagedAVDirectiveCount(in: originalHTML)
        guard legacyDirectiveCount > 0 else {
            return extractedAVPlaceholderCount(in: extractedHTML) == avTagCount
        }

        let playPlaceholderCount = extractedAVPlaceholderCount(in: extractedHTML)
        return playPlaceholderCount == legacyDirectiveCount && playPlaceholderCount == avTagCount
    }

    static func legacyAVDirectiveCount(in html: String) -> Int {
        legacyManagedAVDirectiveCount(in: html) + legacyTTSDirectives(in: html).count
    }

    static func legacyManagedAVDirectiveCount(in html: String) -> Int {
        occurrenceCount(of: #"\[sound:[^\]]+\]"#, in: html)
    }

    static func extractedAVPlaceholderCount(in html: String) -> Int {
        occurrenceCount(of: #"\[anki:play:[qa]:\d+\]"#, in: html)
    }

    static func normalizeExtractedReviewMedia(
        originalHTML: String,
        media: (text: String, tags: [Anki_CardRendering_AVTag]),
        questionSide: Bool
    ) -> (text: String, tags: [Anki_CardRendering_AVTag]) {
        let ttsDirectives = legacyTTSDirectives(in: originalHTML)
        guard !ttsDirectives.isEmpty else {
            return media
        }

        var filteredTags: [Anki_CardRendering_AVTag] = []
        var replacements: [Int: String] = [:]
        var ttsIndex = 0
        let side = questionSide ? "q" : "a"

        for (index, tag) in media.tags.enumerated() {
            if let value = tag.value, case .tts = value {
                guard ttsDirectives.indices.contains(ttsIndex) else {
                    print("[ReviewSession] TTS normalization skipped: directive count did not match extracted tag count")
                    return media
                }
                replacements[index] = ttsDirectives[ttsIndex]
                ttsIndex += 1
            } else {
                let normalizedIndex = filteredTags.count
                filteredTags.append(tag)
                replacements[index] = "[anki:play:\(side):\(normalizedIndex)]"
            }
        }

        guard ttsIndex == ttsDirectives.count else {
            print("[ReviewSession] TTS normalization skipped: original HTML had unmatched TTS directives")
            return media
        }

        let placeholderPattern = #"\[anki:play:([qa]):(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: placeholderPattern, options: [.caseInsensitive]) else {
            return (media.text, filteredTags)
        }

        let range = NSRange(media.text.startIndex..., in: media.text)
        let matches = regex.matches(in: media.text, range: range)
        var rebuiltText = media.text

        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: rebuiltText),
                  let indexRange = Range(match.range(at: 2), in: rebuiltText) else {
                continue
            }
            let extractedIndex = Int(rebuiltText[indexRange]) ?? -1
            guard let replacement = replacements[extractedIndex] else {
                continue
            }
            rebuiltText.replaceSubrange(matchRange, with: replacement)
        }

        return (rebuiltText, filteredTags)
    }

    static func legacyTTSDirectives(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[anki:tts([^\]]*)\](.*?)\[/anki:tts\]"#,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let directiveRange = Range(match.range, in: html) else {
                return nil
            }
            return String(html[directiveRange])
        }
    }

    static func occurrenceCount(of pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    private func encodeIriPathsIfNeeded(in html: String) -> String {
        guard !html.isEmpty else {
            return html
        }

        do {
            let response: Anki_Generic_String = try backend.invoke(
                service: AnkiBackend.Service.cardRendering,
                method: AnkiBackend.CardRenderingMethod.encodeIriPaths,
                request: Anki_Generic_String.with { $0.val = html }
            )
            return response.val.isEmpty ? html : response.val
        } catch {
            print("[ReviewSession] encodeIriPaths failed: \(error)")
            return html
        }
    }

    private func extractAVTags(
        from html: String,
        questionSide: Bool
    ) -> (text: String, tags: [Anki_CardRendering_AVTag]) {
        guard !html.isEmpty else {
            return (html, [])
        }

        do {
            var request = Anki_CardRendering_ExtractAvTagsRequest()
            request.text = html
            request.questionSide = questionSide
            let response: Anki_CardRendering_ExtractAvTagsResponse = try backend.invoke(
                service: AnkiBackend.Service.cardRendering,
                method: AnkiBackend.CardRenderingMethod.extractAvTags,
                request: request
            )
            return (response.text, response.avTags)
        } catch {
            print("[ReviewSession] extractAVTags failed: \(error)")
            return (html, [])
        }
    }

    /// Extract the next interval from the scheduling state.
    /// Returns seconds for learning/relearning, days converted to seconds for review.
    private func scheduledSecs(_ state: Anki_Scheduler_SchedulingState) -> UInt32 {
        switch state.kind {
        case .normal(let n):
            return normalScheduledSecs(n)
        case .filtered:
            // Filtered decks — show 0 (can't predict)
            return 0
        case .none:
            return 0
        }
    }

    private func normalScheduledSecs(_ normal: Anki_Scheduler_SchedulingState.Normal) -> UInt32 {
        switch normal.kind {
        case .new: return 0
        case .learning(let s): return s.scheduledSecs
        case .review(let s): return s.scheduledDays * 86400 // days → seconds
        case .relearning(let s): return s.learning.scheduledSecs
        case .none: return 0
        }
    }

    private func formatInterval(_ secs: UInt32) -> String {
        if secs < 60 { return L("card_interval_seconds_short", Int(secs)) }
        let mins = secs / 60
        if mins < 60 { return L("card_interval_minutes_short", Int(mins)) }
        let hours = mins / 60
        if hours < 24 { return L("card_interval_hours_short", Int(hours)) }
        let days = hours / 24
        if days < 30 { return L("card_interval_days_short", Int(days)) }
        let months = days / 30
        if months < 12 { return L("card_interval_months_short", Int(months)) }
        let years = Double(days) / 365.0
        return L("card_interval_years_short", years)
    }

    private func renderNodes(_ nodes: [Anki_CardRendering_RenderedTemplateNode]) -> String {
        nodes.map { node -> String in
            switch node.value {
            case .text(let text): return text
            case .replacement(let r): return r.currentText
            case .none: return ""
            }
        }.joined()
    }

    private func resolveTypedAnswerState(
        for queued: Anki_Scheduler_QueuedCards.QueuedCard,
        frontHTML: String
    ) -> TypedAnswerState? {
        guard let placeholder = firstTypedAnswerPlaceholder(in: frontHTML) else {
            return nil
        }

        do {
            guard let note = try noteClient.fetch(queued.card.noteID) else {
                return TypedAnswerState(
                    placeholder: placeholder.rawToken,
                    expected: "",
                    fontName: "-apple-system",
                    fontSize: 18,
                    combining: true
                )
            }

            var req = Anki_Notetypes_NotetypeId()
            req.ntid = note.mid
            let notetype: Anki_Notetypes_Notetype = try backend.invoke(
                service: AnkiBackend.Service.notetypes,
                method: AnkiBackend.NotetypesMethod.getNotetype,
                request: req
            )

            guard let field = notetype.fields.first(where: { $0.name == placeholder.fieldName }) else {
                return nil
            }

            let fieldIndex = Int(field.ord.val)
            let fieldValues = note.flds.components(separatedBy: "\u{1f}")
            guard fieldValues.indices.contains(fieldIndex) else {
                return nil
            }

            var expected = fieldValues[fieldIndex]
            if let clozeOrdinal = placeholder.clozeOrdinal {
                var extractReq = Anki_CardRendering_ExtractClozeForTypingRequest()
                extractReq.text = expected
                extractReq.ordinal = clozeOrdinal
                let extracted: Anki_Generic_String = try backend.invoke(
                    service: AnkiBackend.Service.cardRendering,
                    method: AnkiBackend.CardRenderingMethod.extractClozeForTyping,
                    request: extractReq
                )
                expected = extracted.val
            }

            return TypedAnswerState(
                placeholder: placeholder.rawToken,
                expected: expected,
                fontName: field.config.fontName.isEmpty ? "-apple-system" : field.config.fontName,
                fontSize: field.config.fontSize == 0 ? 18 : field.config.fontSize,
                combining: placeholder.combining
            )
        } catch {
            print("[ReviewSession] Typed answer resolution failed for card \(queued.card.id): \(error)")
            return nil
        }
    }

    private func makeTypedAnswerFrontHTML(typedAnswerState: TypedAnswerState?) -> String {
        guard let typedAnswerState,
              renderedFrontHTML.contains(typedAnswerState.placeholder)
        else {
            return strippingTypedAnswerPlaceholders(from: renderedFrontHTML)
        }

        if typedAnswerState.expected.isEmpty {
            return renderedFrontHTML.replacingOccurrences(of: typedAnswerState.placeholder, with: "")
        }

        let inputHTML = """
        <center>
        <input type=\"text\" id=\"typeans\" autocapitalize=\"none\" autocomplete=\"off\" autocorrect=\"off\" spellcheck=\"false\" onkeydown=\"return amgiHandleTypeAnswerKey(event);\" style=\"font-family: '\(typedAnswerState.fontName)'; font-size: \(typedAnswerState.fontSize)px;\">
        </center>
        """
        return renderedFrontHTML.replacingOccurrences(of: typedAnswerState.placeholder, with: inputHTML)
    }

    private func makeTypedAnswerBackHTML(typedAnswerState: TypedAnswerState, typedAnswer: String) -> String {
        guard renderedBackHTML.contains(typedAnswerState.placeholder) else {
            return renderedBackHTML
        }

        if typedAnswerState.expected.isEmpty {
            return renderedBackHTML.replacingOccurrences(of: typedAnswerState.placeholder, with: "")
        }

        var compareReq = Anki_CardRendering_CompareAnswerRequest()
        compareReq.expected = typedAnswerState.expected
        compareReq.provided = typedAnswer
        compareReq.combining = typedAnswerState.combining

        do {
            let compared: Anki_Generic_String = try backend.invoke(
                service: AnkiBackend.Service.cardRendering,
                method: AnkiBackend.CardRenderingMethod.compareAnswer,
                request: compareReq
            )
            let comparisonHTML = "<div style=\"font-family: '\(typedAnswerState.fontName)'; font-size: \(typedAnswerState.fontSize)px\">\(compared.val)</div>"
            return renderedBackHTML.replacingOccurrences(of: typedAnswerState.placeholder, with: comparisonHTML)
        } catch {
            print("[ReviewSession] Compare answer failed: \(error)")
            return renderedBackHTML.replacingOccurrences(of: typedAnswerState.placeholder, with: "")
        }
    }

    private func strippingTypedAnswerPlaceholders(from html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[type:.+?\]\]"#) else {
            return html
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    private func firstTypedAnswerPlaceholder(in html: String) -> TypedAnswerPlaceholder? {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[type:(.+?)\]\]"#) else {
            return nil
        }
        let nsRange = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: nsRange),
              let rawRange = Range(match.range(at: 0), in: html),
              let specRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        var spec = String(html[specRange])
        var combining = true
        var clozeOrdinal: UInt32?

        if spec.hasPrefix("cloze:") {
            spec.removeFirst("cloze:".count)
            clozeOrdinal = queuedClozeOrdinal()
        }
        if spec.hasPrefix("nc:") {
            spec.removeFirst("nc:".count)
            combining = false
        }

        guard !spec.isEmpty else { return nil }

        return TypedAnswerPlaceholder(
            rawToken: String(html[rawRange]),
            fieldName: spec,
            combining: combining,
            clozeOrdinal: clozeOrdinal
        )
    }

    private func queuedClozeOrdinal() -> UInt32 {
        (currentQueuedCard?.card.templateIdx ?? 0) + 1
    }

    private struct TypedAnswerPlaceholder {
        let rawToken: String
        let fieldName: String
        let combining: Bool
        let clozeOrdinal: UInt32?
    }
}
