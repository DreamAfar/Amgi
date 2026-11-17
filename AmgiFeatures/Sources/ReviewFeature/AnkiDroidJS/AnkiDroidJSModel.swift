//
//  AnkiDroidJSModel.swift
//  ReviewFeature
//

import AnkiClients
import AnkiKit
import Dependencies
import AppCore
import Foundation
import OSLog
import ReviewCore
import Sharing

/// Answers the AnkiDroid-compatible card API during review. Owns the
/// card, note, tag and deck clients so the views carry no `@Dependency`.
///
/// Answering, flagging and marking work like the reviewer's own buttons.
/// Calls that bury, suspend, reschedule, reset or retag (`changesCard`)
/// only run when the user has allowed them in Settings, since any shared
/// deck's template could otherwise rewrite the user's schedule.
@Observable
@MainActor
final class AnkiDroidJSModel {
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let isLong: Bool
    }

    private(set) var toast: Toast?
    /// Set by `ankiSearchCard`; the review screen shows the browser for it.
    var browseRequest: AnkiDroidJSBrowseRequest?
    var isEnabled = true
    var allowsCardChanges = false

    @ObservationIgnored private let speech = AnkiDroidJSSpeech()
    /// Flag and mark changes made through the API, since the session's copy
    /// of the card and note isn't re-read until the next card.
    @ObservationIgnored private var flags: [CardID: UInt32] = [:]
    @ObservationIgnored private var marks: [NoteID: Bool] = [:]
    @ObservationIgnored private var deckNames: [DeckID: String]?
    /// One notice per problem per review, not one per call.
    @ObservationIgnored private var notices: Set<String> = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    @ObservationIgnored @Dependency(\.cardClient) private var cardClient
    @ObservationIgnored @Dependency(\.noteClient) private var noteClient
    @ObservationIgnored @Dependency(\.tagClient) private var tagClient
    @ObservationIgnored @Dependency(\.deckClient) private var deckClient
    @ObservationIgnored @Dependency(\.notetypesClient) private var notetypesClient

    /// Whether a script may read the notes a search finds. Read here rather
    /// than passed down like the other two switches: only this model uses it.
    @ObservationIgnored
    @Shared(.appStorage(ReviewPreferences.Keys.ankiDroidJSAllowsSearch))
    private var allowsSearch: Bool = false

    private static let markedTag = "marked"

    /// The JSON text to answer `request` with, or nil for an endpoint
    /// AnkiDroid doesn't have — the shim then rejects the promise, as
    /// AnkiDroid does.
    func handle(
        _ request: AnkiDroidJSRequest,
        session: ReviewSession,
        isNightMode: Bool,
        onFlagChange: (UInt32) -> Void = { _ in }
    ) async -> String? {
        guard isEnabled else { return AnkiDroidJSResult.unavailable }

        switch AnkiDroidJSContract.status(version: request.version, developer: request.developer) {
        case .valid:
            break
        case .missingContact:
            notice("contract", String(localized: "This card uses the AnkiDroid JavaScript API without a version and developer contact, so its script features are off.", bundle: .module))
            return AnkiDroidJSResult.unavailable
        case .unsupportedVersion:
            notice("version", String(localized: "This card asks for AnkiDroid JavaScript API \(request.version); Amgi supports \(AnkiDroidJSContract.version). Contact the deck's developer: \(request.developer)", bundle: .module))
            return AnkiDroidJSResult.unavailable
        }

        if request.endpoint == "init" { return AnkiDroidJSResult.success(true) }
        guard let card = session.currentCard else { return AnkiDroidJSResult.unavailable }

        if request.changesCard, !allowsCardChanges {
            notice("changes", String(localized: "This card's script tried to change the card. Allow it in Settings › Review › Card Scripts.", bundle: .module))
            return AnkiDroidJSResult.failure(false)
        }

        if let value = AnkiDroidJSCardField.value(for: request.endpoint, card: card) {
            return AnkiDroidJSResult.success(value)
        }

        do {
            return try await perform(request, card: card, session: session, isNightMode: isNightMode, onFlagChange: onFlagChange)
        } catch {
            Log.review.error("\(request.endpoint, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return AnkiDroidJSResult.failure(false)
        }
    }

    /// Stops script speech when the review ends.
    func stop() {
        _ = speech.stop()
        toastTask?.cancel()
    }

    // MARK: - Calls

    private func perform(
        _ request: AnkiDroidJSRequest,
        card: CardRecord,
        session: ReviewSession,
        isNightMode: Bool,
        onFlagChange: (UInt32) -> Void
    ) async throws -> String? {
        switch request.endpoint {
        // Session state
        case "newCardCount": return AnkiDroidJSResult.success(session.remainingCounts.newCount)
        case "lrnCardCount": return AnkiDroidJSResult.success(session.remainingCounts.learnCount)
        case "revCardCount": return AnkiDroidJSResult.success(session.remainingCounts.reviewCount)
        case "nextTime1", "nextTime2", "nextTime3", "nextTime4":
            let label = request.rating.flatMap { session.nextIntervals[$0] } ?? ""
            return AnkiDroidJSResult.success(label)
        case "deckName": return AnkiDroidJSResult.success(await deckName(for: card.did, fallback: session.deckName))
        case "isDisplayingAnswer": return AnkiDroidJSResult.success(session.showAnswer)
        case "isInNightMode": return AnkiDroidJSResult.success(isNightMode)
        case "isInFullscreen": return AnkiDroidJSResult.success(false)
        case "isTopbarShown": return AnkiDroidJSResult.success(true)
        case "ttsFieldModifierIsAvailable": return AnkiDroidJSResult.success(false)
        case "cardFlag": return AnkiDroidJSResult.success(Int(flag(of: card)))
        case "cardMark": return AnkiDroidJSResult.success(isMarked(card.nid, session: session))

        // Reviewer actions
        case "showAnswer":
            session.revealAnswer()
            return AnkiDroidJSResult.success(true)
        case "answerEase1", "answerEase2", "answerEase3", "answerEase4":
            // As AnkiDroid's flipOrAnswerCard: on the question side an
            // answer button shows the answer first.
            guard let rating = request.rating else { return AnkiDroidJSResult.failure(false) }
            if session.showAnswer {
                session.answer(rating: rating)
            } else {
                session.revealAnswer()
            }
            return AnkiDroidJSResult.success(true)
        case "toggleFlag":
            guard let value = AnkiDroidJSFlag.toggled(current: flag(of: card), name: request.data) else {
                notice("flag", String(localized: "This card's script asked for an unknown flag.", bundle: .module))
                return AnkiDroidJSResult.failure(false)
            }
            try await cardClient.flag(card.id, value)
            flags[card.id] = value
            onFlagChange(value)
            return AnkiDroidJSResult.success(true)
        case "markCard":
            let marked = isMarked(card.nid, session: session)
            if marked {
                try await tagClient.removeTagFromNotes(Self.markedTag, [card.nid])
            } else {
                try await tagClient.addTagToNotes(Self.markedTag, [card.nid])
            }
            marks[card.nid] = !marked
            return AnkiDroidJSResult.success(true)
        case "showToast":
            let payload = request.jsonObject
            let text = (payload?["text"] as? String) ?? ""
            show((text.removingPercentEncoding ?? text), isLong: !((payload?["shortLength"] as? Bool) ?? true))
            return AnkiDroidJSResult.success(true)

        // Changes to the card (gated by `allowsCardChanges`)
        case "buryCard":
            try await cardClient.bury(card.id)
            session.requeueAfterCardRemoval()
            return AnkiDroidJSResult.success(true)
        case "suspendCard":
            try await cardClient.suspend(card.id)
            session.requeueAfterCardRemoval()
            return AnkiDroidJSResult.success(true)
        case "buryNote":
            for sibling in try await cardClient.fetchByNote(card.nid) { try await cardClient.bury(sibling.id) }
            session.requeueAfterCardRemoval()
            return AnkiDroidJSResult.success(true)
        case "suspendNote":
            for sibling in try await cardClient.fetchByNote(card.nid) { try await cardClient.suspend(sibling.id) }
            session.requeueAfterCardRemoval()
            return AnkiDroidJSResult.success(true)
        case "setCardDue":
            guard let days = Int(request.data.trimmingCharacters(in: .whitespaces)), (0...9999).contains(days) else {
                return AnkiDroidJSResult.failure(false)
            }
            try await cardClient.setDueDate(card.id, String(days))
            session.requeueAfterCardRemoval()
            return AnkiDroidJSResult.success(true)
        case "resetProgress":
            try await cardClient.resetToNew(card.id)
            session.requeueAfterCardRemoval()
            return AnkiDroidJSResult.success(true)
        case "getNoteTags":
            let tags = try await noteClient.fetch(card.nid).map { Self.tags(in: $0.tags) } ?? []
            return AnkiDroidJSResult.success(Self.jsonArray(tags))
        case "setNoteTags":
            guard let tags = (request.jsonObject?["tags"] as? [String])?.map({ $0.trimmingCharacters(in: .whitespaces) }),
                  !tags.contains(where: { $0.contains(where: \.isWhitespace) }),
                  var note = try await noteClient.fetch(card.nid) else {
                return AnkiDroidJSResult.failure(false)
            }
            let kept = tags.filter { !$0.isEmpty }
            note.tags = kept.isEmpty ? "" : " " + kept.joined(separator: " ") + " "
            try await noteClient.save(note)
            marks[card.nid] = kept.contains { $0.caseInsensitiveCompare(Self.markedTag) == .orderedSame }
            return AnkiDroidJSResult.success(true)
        case "addTagToNote":
            // Only the card's own note: AnkiDroid asks a separate permission
            // to touch any other.
            let payload = request.jsonObject
            guard let noteID = (payload?["noteId"] as? NSNumber)?.int64Value, noteID == card.nid.rawValue,
                  let tag = (payload?["tag"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !tag.isEmpty, !tag.contains(where: \.isWhitespace) else {
                return AnkiDroidJSResult.failure(false)
            }
            try await tagClient.addTagToNotes(tag, [card.nid])
            if tag.caseInsensitiveCompare(Self.markedTag) == .orderedSame { marks[card.nid] = true }
            return AnkiDroidJSResult.success(true)

        // Search
        case "searchCard":
            let query = request.data.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return AnkiDroidJSResult.failure(false) }
            browseRequest = AnkiDroidJSBrowseRequest(query: query)
            return AnkiDroidJSResult.success(true)
        case "searchCardWithCallback":
            guard allowsSearch else {
                notice("search", String(localized: "This card's script tried to search your collection. Allow it in Settings › Review › Card Scripts.", bundle: .module))
                return AnkiDroidJSResult.failure(false)
            }
            let results = try await searchResults(for: request.data)
            return AnkiDroidJSResult.search(results: results)

        // Speech
        case "ttsSpeak":
            let payload = request.jsonObject
            let text = (payload?["text"] as? String) ?? ""
            let queueMode = (payload?["queueMode"] as? NSNumber)?.intValue ?? 0
            return AnkiDroidJSResult.success(speech.speak(text, queueMode: queueMode))
        case "ttsStop": return AnkiDroidJSResult.success(speech.stop())
        case "ttsIsSpeaking": return AnkiDroidJSResult.success(speech.isSpeaking)
        case "ttsSetLanguage": return AnkiDroidJSResult.success(speech.setLanguage(request.data))
        case "ttsSetPitch":
            guard let value = Float(request.data) else { return AnkiDroidJSResult.failure(false) }
            return AnkiDroidJSResult.success(speech.setPitch(value))
        case "ttsSetSpeechRate":
            guard let value = Float(request.data) else { return AnkiDroidJSResult.failure(false) }
            return AnkiDroidJSResult.success(speech.setSpeechRate(value))

        // Part of AnkiDroid's API but tied to its own screens, or not
        // available on iOS: they answer "not done" rather than reject, so
        // a card that calls them keeps running.
        case "eta", "isActiveNetworkMetered", "addTagToCard",
             "setFullscreenButtonsAndMenu", "setFullscreenButtonsOnly", "setFullscreenAllGone",
             "enableHorizontalScrollbar", "enableVerticalScrollbar",
             "showNavigationDrawer", "showOptionsMenu", "sttSetLanguage", "sttStart", "sttStop":
            return AnkiDroidJSResult.failure(request.endpoint == "eta" ? -1 : false)

        default:
            return nil
        }
    }

    // MARK: - Search

    /// Every card of the notes `query` finds, as AnkiDroid's hook gets them.
    private func searchResults(for query: String) async throws -> [[String: Any]] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let notes = try await noteClient.searchAll(query, AnkiDroidJSSearchResult.noteLimit)
        var fieldNames: [NotetypeID: [String]] = [:]
        var results: [[String: Any]] = []
        for note in notes.prefix(AnkiDroidJSSearchResult.noteLimit) {
            if fieldNames[note.mid] == nil {
                fieldNames[note.mid] = try await notetypesClient.get(note.mid).fields.map(\.name)
            }
            for card in try await cardClient.fetchByNote(note.id) {
                results.append(
                    AnkiDroidJSSearchResult.entry(cardID: card.id, note: note, fieldNames: fieldNames[note.mid] ?? [])
                )
            }
        }
        return results
    }

    // MARK: - State

    private func flag(of card: CardRecord) -> UInt32 {
        flags[card.id] ?? UInt32(max(0, card.flags)) & 0b111
    }

    private func isMarked(_ noteID: NoteID, session: ReviewSession) -> Bool {
        if let marked = marks[noteID] { return marked }
        guard let note = session.currentNote, note.id == noteID else { return false }
        return Self.tags(in: note.tags).contains { $0.caseInsensitiveCompare(Self.markedTag) == .orderedSame }
    }

    /// The deck's own name without its parents, as AnkiDroid returns it.
    private func deckName(for deckID: DeckID, fallback: String) async -> String {
        if deckNames == nil {
            let decks = (try? await deckClient.fetchAll()) ?? []
            deckNames = Dictionary(decks.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        }
        return Self.baseName(deckNames?[deckID] ?? fallback)
    }

    // MARK: - Notices

    private func notice(_ key: String, _ text: String) {
        guard notices.insert(key).inserted else { return }
        show(text, isLong: true)
    }

    private func show(_ text: String, isLong: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let toast = Toast(text: trimmed, isLong: isLong)
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: isLong ? .milliseconds(3500) : .seconds(2))
            guard !Task.isCancelled, self?.toast == toast else { return }
            self?.toast = nil
        }
    }

    // MARK: - Helpers

    static func tags(in field: String) -> [String] {
        field.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func baseName(_ deckName: String) -> String {
        deckName.components(separatedBy: "::").last ?? deckName
    }

    /// AnkiDroid returns the note's tags as a JSON array *string* inside the
    /// result, so a card parses it a second time.
    static func jsonArray(_ strings: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: strings, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}
