import AnkiBackend
import AnkiProto
import Foundation

enum DeckDeletionMaintenance {
    static func resetHeatmapSelectionIfNeeded(
        deletedDeckID: Int64,
        userDefaults: UserDefaults = .standard
    ) {
        let scopeRaw = userDefaults.string(forKey: DeckListHeatmapSettings.scopeKey)
            ?? DeckListHeatmapScope.allDecks.rawValue
        let scope = DeckListHeatmapScope(rawValue: scopeRaw) ?? .allDecks
        let selectedDeckID = userDefaults.integer(forKey: DeckListHeatmapSettings.selectedDeckIDKey)

        guard scope == .selectedDeck, Int64(selectedDeckID) == deletedDeckID else { return }

        userDefaults.set(DeckListHeatmapScope.allDecks.rawValue, forKey: DeckListHeatmapSettings.scopeKey)
        userDefaults.set(
            DeckListHeatmapSettings.defaultSelectedDeckID,
            forKey: DeckListHeatmapSettings.selectedDeckIDKey
        )
    }

    static func cleanupUnusedMedia(using backend: AnkiBackend) throws {
        let response: Anki_Media_CheckMediaResponse = try backend.invoke(
            service: AnkiBackend.Service.media,
            method: AnkiBackend.MediaMethod.checkMedia
        )

        if !response.unused.isEmpty {
            var request = Anki_Media_TrashMediaFilesRequest()
            request.fnames = response.unused
            try backend.callVoid(
                service: AnkiBackend.Service.media,
                method: AnkiBackend.MediaMethod.trashMediaFiles,
                request: request
            )
        }

        if response.haveTrash || !response.unused.isEmpty {
            try backend.callVoid(
                service: AnkiBackend.Service.media,
                method: AnkiBackend.MediaMethod.emptyTrash
            )
        }
    }
}