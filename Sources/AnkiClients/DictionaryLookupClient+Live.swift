import CHoshiDicts
public import AnkiBackend
import Foundation
public import Dependencies

private enum DictionaryLookupRuntimeError: LocalizedError {
    case importFailed([String])
    case dictionaryNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .importFailed(files):
            if files.isEmpty {
                return "Failed to import dictionary archive."
            }
            return "Failed to import: \(files.joined(separator: ", "))."
        case let .dictionaryNotFound(dictionaryID):
            return "Dictionary not found: \(dictionaryID)"
        }
    }
}

private struct SyncedDictionaryConfig: Codable {
    var updatedAt: Date
    var config: AppDictionaryConfig
}

private struct TimestampedDictionaryConfig {
    var config: AppDictionaryConfig
    var updatedAt: Date
}

public enum DictionaryLookupConfigMigration {
    private static let configFileName = "config.json"
    private static let collectionConfigKey = "amgi.reader.dictionaryConfig"
    private static let legacyMirroredConfigFileName = "amgi_reader_dictionary_config.json"

    public static func migrateLegacyMirroredConfigIfNeeded(backend: AnkiBackend) throws {
        let profileID = sanitizedProfileID()
        let local = try loadLocalConfig(profileID: profileID)
        let collection = try loadCollectionConfig(backend: backend)
        let legacyMirrored = try loadLegacyMirroredConfig(profileID: profileID)

        let resolved: TimestampedDictionaryConfig?
        switch (local, collection, legacyMirrored) {
        case let (local?, collection?, legacyMirrored?):
            resolved = [local, collection, legacyMirrored].max(by: { $0.updatedAt < $1.updatedAt })
        case let (local?, collection?, nil):
            resolved = local.updatedAt >= collection.updatedAt ? local : collection
        case let (local?, nil, legacyMirrored?):
            resolved = local.updatedAt >= legacyMirrored.updatedAt ? local : legacyMirrored
        case let (nil, collection?, legacyMirrored?):
            resolved = collection.updatedAt >= legacyMirrored.updatedAt ? collection : legacyMirrored
        case let (local?, nil, nil):
            resolved = local
        case let (nil, collection?, nil):
            resolved = collection
        case let (nil, nil, legacyMirrored?):
            resolved = legacyMirrored
        case (nil, nil, nil):
            resolved = nil
        }

        guard let resolved else {
            return
        }

        if local?.config != resolved.config || local?.updatedAt != resolved.updatedAt {
            try writeLocalConfig(resolved.config, updatedAt: resolved.updatedAt, profileID: profileID)
        }

        if collection?.config != resolved.config || collection?.updatedAt != resolved.updatedAt {
            try writeCollectionConfig(resolved.config, updatedAt: resolved.updatedAt, backend: backend)
        }

        if legacyMirrored != nil {
            try removeLegacyMirroredConfig(profileID: profileID)
        }
    }

    private static func sanitizedProfileID() -> String {
        let fallback = "default"
        let rawProfileID = UserDefaults.standard.string(forKey: "selectedUser") ?? fallback
        let trimmed = rawProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func loadCollectionConfig(backend: AnkiBackend) throws -> TimestampedDictionaryConfig? {
        guard let synced: SyncedDictionaryConfig = try backend.getConfigJSONValue(for: collectionConfigKey) else {
            return nil
        }

        return TimestampedDictionaryConfig(config: synced.config, updatedAt: synced.updatedAt)
    }

    private static func loadLocalConfig(profileID: String) throws -> TimestampedDictionaryConfig? {
        let configURL = try configURL(profileID: profileID)
        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(AppDictionaryConfig.self, from: data)
        let updatedAt = try configURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return TimestampedDictionaryConfig(config: config, updatedAt: updatedAt)
    }

    private static func loadLegacyMirroredConfig(profileID: String) throws -> TimestampedDictionaryConfig? {
        let configURL = try legacyMirroredConfigURL(profileID: profileID)
        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: configURL)
        let synced = try JSONDecoder().decode(SyncedDictionaryConfig.self, from: data)
        return TimestampedDictionaryConfig(config: synced.config, updatedAt: synced.updatedAt)
    }

    private static func writeLocalConfig(
        _ config: AppDictionaryConfig,
        updatedAt: Date,
        profileID: String
    ) throws {
        let configURL = try configURL(profileID: profileID)
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: updatedAt],
            ofItemAtPath: configURL.path(percentEncoded: false)
        )
    }

    private static func writeCollectionConfig(
        _ config: AppDictionaryConfig,
        updatedAt: Date,
        backend: AnkiBackend
    ) throws {
        let synced = SyncedDictionaryConfig(updatedAt: updatedAt, config: config)
        try backend.setConfigJSONValue(synced, for: collectionConfigKey)
    }

    private static func rootDirectory(profileID: String) throws -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let directory = baseDirectory
            .appendingPathComponent("ReaderDictionaries", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func configURL(profileID: String) throws -> URL {
        try rootDirectory(profileID: profileID).appendingPathComponent(configFileName)
    }

    private static func legacyMirroredConfigURL(profileID: String) throws -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        let mediaDirectory = baseDirectory
            .appendingPathComponent("AnkiCollection", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: mediaDirectory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        }
        return mediaDirectory.appendingPathComponent(legacyMirroredConfigFileName)
    }

    private static func removeLegacyMirroredConfig(profileID: String) throws {
        let configURL = try legacyMirroredConfigURL(profileID: profileID)
        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: configURL)
        }
    }
}

private actor DictionaryLookupRuntime {
    private struct ManagedDictionary {
        var info: AppDictionaryInfo
        var path: URL
    }

    private struct RecommendedArchive {
        var metadataURL: String
        var kind: AppDictionaryKind
    }

    private static let configFileName = "config.json"
    private static let collectionConfigKey = "amgi.reader.dictionaryConfig"
    private static let legacyMirroredConfigFileName = "amgi_reader_dictionary_config.json"
    private static let recommendedArchives: [RecommendedArchive] = [
        RecommendedArchive(
            metadataURL: "https://github.com/yomidevs/jmdict-yomitan/releases/latest/download/JMdict_english.json",
            kind: .term
        ),
        RecommendedArchive(
            metadataURL: "https://api.jiten.moe/api/frequency-list/index",
            kind: .frequency
        ),
    ]

    private let backend: AnkiBackend
    private var activeProfileID: String?
    private var termDictionaries: [ManagedDictionary] = []
    private var frequencyDictionaries: [ManagedDictionary] = []
    private var pitchDictionaries: [ManagedDictionary] = []
    private var dictQuery: DictionaryQuery?
    private var deinflector: Deinflector?
    private var lookupEngine: Lookup?

    init(backend: AnkiBackend) {
        self.backend = backend
    }

    func lookup(_ text: String, maxResults: Int, scanLength: Int) throws -> DictionaryLookupResult {
        try ensureLoaded()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return DictionaryLookupResult(query: text, entries: [], isPlaceholder: false)
        }

        guard termDictionaries.contains(where: { $0.info.isEnabled }) else {
            return DictionaryLookupResult(query: trimmed, entries: [], isPlaceholder: true)
        }

        let resolvedMaxResults = max(1, maxResults)
        let resolvedScanLength = max(1, scanLength)
        let rawResults = Array(lookupEngine?.lookup(std.string(trimmed), Int32(resolvedMaxResults), resolvedScanLength) ?? [])
        let styles = loadStyles()
        return DictionaryLookupResult(
            query: trimmed,
            entries: rawResults.map(Self.makeEntry),
            isPlaceholder: false,
            dictionaryStyles: styles
        )
    }

    func loadStyles() -> [String: String] {
        Array(dictQuery?.get_styles() ?? [])
            .reduce(into: [String: String]()) { result, style in
                result[String(style.dict_name)] = String(style.styles)
            }
    }

    func mediaFile(dictionary: String, mediaPath: String) throws -> Data {
        try ensureLoaded()
        guard let dictQuery else {
            return Data()
        }
        let bytes = dictQuery.get_media_file(std.string(dictionary), std.string(mediaPath))
        return Data(bytes.map { UInt8(bitPattern: $0) })
    }

    func loadState() throws -> AppDictionaryLibraryState {
        try ensureLoaded()
        return libraryState()
    }

    func importArchives(_ urls: [URL], kind: AppDictionaryKind) throws -> AppDictionaryLibraryState {
        try ensureLoaded()

        var failedFiles: [String] = []
        var didImport = false
        for url in urls {
            do {
                try importArchive(at: url, kind: kind, requiresSecurityScope: true)
                didImport = true
            } catch {
                failedFiles.append(url.lastPathComponent)
            }
        }

        guard didImport else {
            throw DictionaryLookupRuntimeError.importFailed(failedFiles)
        }

        try reloadState(for: currentProfileID())
        return libraryState()
    }

    func importRecommended() async throws -> AppDictionaryLibraryState {
        try ensureLoaded()

        var temporaryFiles: [URL] = []
        defer {
            for file in temporaryFiles {
                try? FileManager.default.removeItem(at: file)
            }
        }

        for archive in Self.recommendedArchives {
            let metadataURL = URL(string: archive.metadataURL)!
            let (data, _) = try await URLSession.shared.data(from: metadataURL)
            let remoteIndex = try JSONDecoder().decode(AppDictionaryIndex.self, from: data)
            let downloadURL = URL(string: remoteIndex.downloadURL)!
            let (temporaryFile, _) = try await URLSession.shared.download(from: downloadURL)
            temporaryFiles.append(temporaryFile)
            try importArchive(at: temporaryFile, kind: archive.kind, requiresSecurityScope: false)
        }

        try reloadState(for: currentProfileID())
        return libraryState()
    }

    func setEnabled(kind: AppDictionaryKind, dictionaryID: String, enabled: Bool) throws -> AppDictionaryLibraryState {
        try ensureLoaded()

        switch kind {
        case .term:
            guard let index = termDictionaries.firstIndex(where: { $0.info.id == dictionaryID }) else {
                throw DictionaryLookupRuntimeError.dictionaryNotFound(dictionaryID)
            }
            termDictionaries[index].info.isEnabled = enabled
        case .frequency:
            guard let index = frequencyDictionaries.firstIndex(where: { $0.info.id == dictionaryID }) else {
                throw DictionaryLookupRuntimeError.dictionaryNotFound(dictionaryID)
            }
            frequencyDictionaries[index].info.isEnabled = enabled
        case .pitch:
            guard let index = pitchDictionaries.firstIndex(where: { $0.info.id == dictionaryID }) else {
                throw DictionaryLookupRuntimeError.dictionaryNotFound(dictionaryID)
            }
            pitchDictionaries[index].info.isEnabled = enabled
        }

        try persistAndRebuild()
        return libraryState()
    }

    func delete(kind: AppDictionaryKind, dictionaryID: String) throws -> AppDictionaryLibraryState {
        try ensureLoaded()

        switch kind {
        case .term:
            guard let index = termDictionaries.firstIndex(where: { $0.info.id == dictionaryID }) else {
                throw DictionaryLookupRuntimeError.dictionaryNotFound(dictionaryID)
            }
            try? FileManager.default.removeItem(at: termDictionaries[index].path)
            termDictionaries.remove(at: index)
            termDictionaries = normalized(termDictionaries)
        case .frequency:
            guard let index = frequencyDictionaries.firstIndex(where: { $0.info.id == dictionaryID }) else {
                throw DictionaryLookupRuntimeError.dictionaryNotFound(dictionaryID)
            }
            try? FileManager.default.removeItem(at: frequencyDictionaries[index].path)
            frequencyDictionaries.remove(at: index)
            frequencyDictionaries = normalized(frequencyDictionaries)
        case .pitch:
            guard let index = pitchDictionaries.firstIndex(where: { $0.info.id == dictionaryID }) else {
                throw DictionaryLookupRuntimeError.dictionaryNotFound(dictionaryID)
            }
            try? FileManager.default.removeItem(at: pitchDictionaries[index].path)
            pitchDictionaries.remove(at: index)
            pitchDictionaries = normalized(pitchDictionaries)
        }

        try persistAndRebuild()
        return libraryState()
    }

    private func ensureLoaded() throws {
        let profileID = currentProfileID()
        if activeProfileID != profileID {
            try reloadState(for: profileID)
        }
    }

    private func reloadState(for profileID: String) throws {
        let storedTerm = try dictionariesFromStorage(kind: .term, profileID: profileID)
        let storedFrequency = try dictionariesFromStorage(kind: .frequency, profileID: profileID)
        let storedPitch = try dictionariesFromStorage(kind: .pitch, profileID: profileID)
        let config = try loadConfig(profileID: profileID) ?? AppDictionaryConfig()

        termDictionaries = collectDictionaries(stored: storedTerm, configured: config.termDictionaries)
        frequencyDictionaries = collectDictionaries(stored: storedFrequency, configured: config.frequencyDictionaries)
        pitchDictionaries = collectDictionaries(stored: storedPitch, configured: config.pitchDictionaries)

        activeProfileID = profileID
        try persistAndRebuild()
    }

    private func persistAndRebuild() throws {
        guard let profileID = activeProfileID else { return }
        try saveConfig(profileID: profileID)
        rebuildLookupQuery()
    }

    private func rebuildLookupQuery() {
        deinflector = Deinflector()
        dictQuery = DictionaryQuery()

        for dictionary in termDictionaries where dictionary.info.isEnabled {
            dictQuery?.add_term_dict(std.string(dictionary.path.path(percentEncoded: false)))
        }

        for dictionary in frequencyDictionaries where dictionary.info.isEnabled {
            dictQuery?.add_freq_dict(std.string(dictionary.path.path(percentEncoded: false)))
        }

        for dictionary in pitchDictionaries where dictionary.info.isEnabled {
            dictQuery?.add_pitch_dict(std.string(dictionary.path.path(percentEncoded: false)))
        }

        if dictQuery != nil, deinflector != nil {
            lookupEngine = Lookup(&dictQuery!, &deinflector!)
        } else {
            lookupEngine = nil
        }
    }

    private func importArchive(at url: URL, kind: AppDictionaryKind, requiresSecurityScope: Bool) throws {
        let startedAccess = requiresSecurityScope ? url.startAccessingSecurityScopedResource() : false
        if requiresSecurityScope && !startedAccess {
            throw DictionaryLookupRuntimeError.importFailed([url.lastPathComponent])
        }

        defer {
            if startedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let outputDirectory = try dictionaryDirectory(for: kind, profileID: currentProfileID())
        let importResult = dictionary_importer.import(
            std.string(url.path(percentEncoded: false)),
            std.string(outputDirectory.path(percentEncoded: false)),
            false
        )

        guard importResult.success else {
            throw DictionaryLookupRuntimeError.importFailed([url.lastPathComponent])
        }
    }

    private func libraryState() -> AppDictionaryLibraryState {
        AppDictionaryLibraryState(
            termDictionaries: termDictionaries.map(\.info),
            frequencyDictionaries: frequencyDictionaries.map(\.info),
            pitchDictionaries: pitchDictionaries.map(\.info)
        )
    }

    private func collectDictionaries(
        stored: [ManagedDictionary],
        configured: [AppDictionaryConfig.Entry]
    ) -> [ManagedDictionary] {
        var result: [ManagedDictionary] = []

        for entry in configured.sorted(by: { $0.order < $1.order }) {
            guard let storedDictionary = stored.first(where: { $0.info.fileName == entry.fileName }) else {
                continue
            }
            var dictionary = storedDictionary
            dictionary.info.isEnabled = entry.isEnabled
            dictionary.info.order = entry.order
            result.append(dictionary)
        }

        let existingFileNames = Set(result.map(\.info.fileName))
        for storedDictionary in stored where !existingFileNames.contains(storedDictionary.info.fileName) {
            var dictionary = storedDictionary
            dictionary.info.isEnabled = true
            dictionary.info.order = result.count
            result.append(dictionary)
        }

        return normalized(result)
    }

    private func normalized(_ dictionaries: [ManagedDictionary]) -> [ManagedDictionary] {
        dictionaries.enumerated().map { index, dictionary in
            var dictionary = dictionary
            dictionary.info.order = index
            return dictionary
        }
    }

    private func dictionariesFromStorage(kind: AppDictionaryKind, profileID: String) throws -> [ManagedDictionary] {
        let directory = try dictionaryDirectory(for: kind, profileID: profileID)

        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }

            let indexURL = url.appendingPathComponent("index.json")
            guard let data = try? Data(contentsOf: indexURL),
                  let index = try? JSONDecoder().decode(AppDictionaryIndex.self, from: data) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }

            return ManagedDictionary(
                info: AppDictionaryInfo(fileName: url.lastPathComponent, index: index),
                path: url
            )
        }
        .sorted { $0.info.title.localizedCaseInsensitiveCompare($1.info.title) == .orderedAscending }
    }

    private func loadConfig(profileID: String) throws -> AppDictionaryConfig? {
        let local = try loadLocalConfig(profileID: profileID)
        let collection = try loadCollectionConfig()
        let legacyMirrored = try loadLegacyMirroredConfig(profileID: profileID)

        let resolved: TimestampedDictionaryConfig?
        switch (local, collection, legacyMirrored) {
        case let (local?, collection?, legacyMirrored?):
            resolved = [local, collection, legacyMirrored].max(by: { $0.updatedAt < $1.updatedAt })
        case let (local?, collection?, nil):
            resolved = local.updatedAt >= collection.updatedAt ? local : collection
        case let (local?, nil, legacyMirrored?):
            resolved = local.updatedAt >= legacyMirrored.updatedAt ? local : legacyMirrored
        case let (nil, collection?, legacyMirrored?):
            resolved = collection.updatedAt >= legacyMirrored.updatedAt ? collection : legacyMirrored
        case let (local?, nil, nil):
            resolved = local
        case let (nil, collection?, nil):
            resolved = collection
        case let (nil, nil, legacyMirrored?):
            resolved = legacyMirrored
        case (nil, nil, nil):
            resolved = nil
        }

        guard let resolved else {
            return nil
        }

        if local?.config != resolved.config || local?.updatedAt != resolved.updatedAt {
            try writeLocalConfig(resolved.config, updatedAt: resolved.updatedAt, profileID: profileID)
        }

        if collection?.config != resolved.config || collection?.updatedAt != resolved.updatedAt {
            try writeCollectionConfig(resolved.config, updatedAt: resolved.updatedAt)
        }

        if legacyMirrored != nil {
            try removeLegacyMirroredConfig(profileID: profileID)
        }

        return resolved.config
    }

    private func saveConfig(profileID: String) throws {
        let config = AppDictionaryConfig(
            termDictionaries: termDictionaries.map {
                AppDictionaryConfig.Entry(
                    fileName: $0.info.fileName,
                    isEnabled: $0.info.isEnabled,
                    order: $0.info.order
                )
            },
            frequencyDictionaries: frequencyDictionaries.map {
                AppDictionaryConfig.Entry(
                    fileName: $0.info.fileName,
                    isEnabled: $0.info.isEnabled,
                    order: $0.info.order
                )
            },
            pitchDictionaries: pitchDictionaries.map {
                AppDictionaryConfig.Entry(
                    fileName: $0.info.fileName,
                    isEnabled: $0.info.isEnabled,
                    order: $0.info.order
                )
            }
        )

        let updatedAt = Date()
        try writeLocalConfig(config, updatedAt: updatedAt, profileID: profileID)
        try writeCollectionConfig(config, updatedAt: updatedAt)
        try removeLegacyMirroredConfig(profileID: profileID)
    }

    private func loadLocalConfig(profileID: String) throws -> TimestampedDictionaryConfig? {
        let configURL = try configURL(profileID: profileID)
        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(AppDictionaryConfig.self, from: data)
        let updatedAt = try configURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return TimestampedDictionaryConfig(config: config, updatedAt: updatedAt)
    }

    private func loadCollectionConfig() throws -> TimestampedDictionaryConfig? {
        guard let synced: SyncedDictionaryConfig = try backend.getConfigJSONValue(for: Self.collectionConfigKey) else {
            return nil
        }

        return TimestampedDictionaryConfig(config: synced.config, updatedAt: synced.updatedAt)
    }

    private func loadLegacyMirroredConfig(profileID: String) throws -> TimestampedDictionaryConfig? {
        let configURL = try legacyMirroredConfigURL(profileID: profileID)
        guard FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: configURL)
        let synced = try JSONDecoder().decode(SyncedDictionaryConfig.self, from: data)
        return TimestampedDictionaryConfig(config: synced.config, updatedAt: synced.updatedAt)
    }

    private func writeLocalConfig(
        _ config: AppDictionaryConfig,
        updatedAt: Date,
        profileID: String
    ) throws {
        let configURL = try configURL(profileID: profileID)
        let data = try JSONEncoder().encode(config)
        try data.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: updatedAt],
            ofItemAtPath: configURL.path(percentEncoded: false)
        )
    }

    private func writeCollectionConfig(
        _ config: AppDictionaryConfig,
        updatedAt: Date
    ) throws {
        let synced = SyncedDictionaryConfig(updatedAt: updatedAt, config: config)
        try backend.setConfigJSONValue(synced, for: Self.collectionConfigKey)
    }

    private func configURL(profileID: String) throws -> URL {
        try rootDirectory(profileID: profileID).appendingPathComponent(Self.configFileName)
    }

    private func legacyMirroredConfigURL(profileID: String) throws -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let mediaDirectory = baseDirectory
            .appendingPathComponent("AnkiCollection", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent("media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: mediaDirectory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        }
        return mediaDirectory.appendingPathComponent(Self.legacyMirroredConfigFileName)
    }

    private func removeLegacyMirroredConfig(profileID: String) throws {
        let configURL = try legacyMirroredConfigURL(profileID: profileID)
        if FileManager.default.fileExists(atPath: configURL.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: configURL)
        }
    }

    private func dictionaryDirectory(for kind: AppDictionaryKind, profileID: String) throws -> URL {
        let directory = try rootDirectory(profileID: profileID).appendingPathComponent(kind.storageDirectoryName)
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func rootDirectory(profileID: String) throws -> URL {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = baseDirectory
            .appendingPathComponent("ReaderDictionaries", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func currentProfileID() -> String {
        let selectedUser = UserDefaults.standard.string(forKey: "amgi.selectedUser") ?? "default"
        return Self.sanitizedUserFolderName(selectedUser)
    }

    private static func sanitizedUserFolderName(_ user: String) -> String {
        let trimmed = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "default" }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = trimmed.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        let folder = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return folder.isEmpty ? "default" : folder
    }

    private static func makeEntry(from result: LookupResult) -> DictionaryLookupEntry {
        let glossaries = Array(result.term.glossaries).flatMap { glossary in
            glossaryLines(dictName: String(glossary.dict_name), rawGlossary: String(glossary.glossary))
        }

        let structuredGlossaries = Array(result.term.glossaries).map { glossary in
            DictionaryLookupGlossary(
                dictionary: String(glossary.dict_name),
                content: String(glossary.glossary),
                definitions: flattenGlossary(String(glossary.glossary)),
                definitionTags: String(glossary.definition_tags).nilIfEmpty,
                termTags: String(glossary.term_tags).nilIfEmpty
            )
        }

        let structuredFrequencies = Array(result.term.frequencies).map { entry in
            DictionaryLookupFrequency(
                dictionary: String(entry.dict_name),
                frequencies: Array(entry.frequencies).map { frequency in
                    let displayValue = String(frequency.display_value)
                    return DictionaryLookupFrequencyValue(
                        value: Int(frequency.value),
                        displayValue: displayValue.nilIfEmpty
                    )
                }
            )
        }

        let structuredPitches = Array(result.term.pitches).map { entry in
            let positions = Array(entry.pitch_positions)
                .map(Int.init)
                .reduce(into: [Int]()) { output, position in
                    if output.contains(position) == false {
                        output.append(position)
                    }
                }

            return DictionaryLookupPitch(
                dictionary: String(entry.dict_name),
                positions: positions
            )
        }

        let frequency = Array(result.term.frequencies)
            .compactMap { entry -> String? in
                let values = Array(entry.frequencies).map { frequency -> String in
                    let displayValue = String(frequency.display_value)
                    return displayValue.isEmpty ? String(frequency.value) : displayValue
                }
                .filter { !$0.isEmpty }

                guard !values.isEmpty else { return nil }
                let dictName = String(entry.dict_name)
                return dictName.isEmpty ? values.joined(separator: ", ") : "\(dictName): \(values.joined(separator: ", "))"
            }
            .joined(separator: "  ")

        let pitch = Array(result.term.pitches)
            .compactMap { entry -> String? in
                let positions = entry.pitch_positions.map { String($0) }
                guard !positions.isEmpty else { return nil }
                let dictName = String(entry.dict_name)
                return dictName.isEmpty ? positions.joined(separator: ", ") : "\(dictName): \(positions.joined(separator: ", "))"
            }
            .joined(separator: "  ")

        let trace = Array(result.trace.reversed())
            .map {
                DictionaryLookupDeinflectionStep(
                    name: String($0.name),
                    description: String($0.description).nilIfEmpty
                )
            }
        let traceText = trace
            .map(\.name)
            .filter { !$0.isEmpty }
            .joined(separator: " -> ")
        let matched = String(result.matched)
        let source = traceText.isEmpty ? matched : "\(matched) • \(traceText)"
        let rules = String(result.term.rules)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.isEmpty == false }

        return DictionaryLookupEntry(
            term: String(result.term.expression),
            reading: String(result.term.reading).nilIfEmpty,
            matched: matched.nilIfEmpty,
            rules: rules,
            deinflectionTrace: trace,
            structuredGlossaries: structuredGlossaries,
            structuredFrequencies: structuredFrequencies,
            structuredPitches: structuredPitches,
            glossaries: glossaries,
            frequency: frequency.nilIfEmpty,
            pitch: pitch.nilIfEmpty,
            source: source.nilIfEmpty
        )
    }

    private static func glossaryLines(dictName: String, rawGlossary: String) -> [String] {
        let flattened = flattenGlossary(rawGlossary)
        guard !flattened.isEmpty else {
            return dictName.isEmpty ? [] : [dictName]
        }

        guard !dictName.isEmpty else {
            return flattened
        }

        if let first = flattened.first {
            return ["\(dictName): \(first)"] + flattened.dropFirst()
        }
        return [dictName]
    }

    private static func flattenGlossary(_ rawGlossary: String) -> [String] {
        guard let data = rawGlossary.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return [rawGlossary]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return flattenGlossary(json)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func flattenGlossary(_ value: Any) -> [String] {
        switch value {
        case let string as String:
            return [string]
        case let number as NSNumber:
            return [number.stringValue]
        case let array as [Any]:
            return array.flatMap(flattenGlossary)
        case let dictionary as [String: Any]:
            if let text = dictionary["text"] {
                return flattenGlossary(text)
            }
            if let content = dictionary["content"] {
                return flattenGlossary(content)
            }
            if let value = dictionary["value"] {
                return flattenGlossary(value)
            }
            if let title = dictionary["title"] as? String {
                return [title]
            }
            return dictionary.values.flatMap(flattenGlossary)
        default:
            return []
        }
    }
}

private extension AppDictionaryKind {
    var storageDirectoryName: String {
        switch self {
        case .term:
            return "Term"
        case .frequency:
            return "Frequency"
        case .pitch:
            return "Pitch"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension DictionaryLookupClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        let runtime = DictionaryLookupRuntime(backend: backend)
        return Self(
            lookup: { text, maxResults, scanLength in
                try await runtime.lookup(text, maxResults: maxResults, scanLength: scanLength)
            },
            loadStyles: {
                try await runtime.loadStyles()
            },
            mediaFile: { dictionary, mediaPath in
                try await runtime.mediaFile(dictionary: dictionary, mediaPath: mediaPath)
            },
            loadState: {
                try await runtime.loadState()
            },
            importArchives: { urls, kind in
                try await runtime.importArchives(urls, kind: kind)
            },
            importRecommended: {
                try await runtime.importRecommended()
            },
            setEnabled: { kind, dictionaryID, enabled in
                try await runtime.setEnabled(kind: kind, dictionaryID: dictionaryID, enabled: enabled)
            },
            delete: { kind, dictionaryID in
                try await runtime.delete(kind: kind, dictionaryID: dictionaryID)
            }
        )
    }()
}
