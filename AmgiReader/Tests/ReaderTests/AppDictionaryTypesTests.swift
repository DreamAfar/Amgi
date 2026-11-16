//
//  AppDictionaryTypesTests.swift
//  ReaderTests
//

import Foundation
import Reader
import Testing

struct AppDictionaryTypesTests {
    @Test func aConfigSavedBeforeKanjiDictionariesStillLoads() throws {
        let saved = Data(#"""
        {"termDictionaries":[{"fileName":"JMdict","isEnabled":true,"order":0}],
         "frequencyDictionaries":[],"pitchDictionaries":[]}
        """#.utf8)
        let config = try JSONDecoder().decode(AppDictionaryConfig.self, from: saved)
        #expect(config.termDictionaries.map(\.fileName) == ["JMdict"])
        #expect(config.kanjiDictionaries.isEmpty)
    }

    @Test func readsTheIndexTheOldEngineWrote() throws {
        let stored = Data(#"""
        {"title":"JMdict","format":3,"revision":"2026-01-01","isUpdatable":true,
         "indexUrl":"https://example.com/index.json","downloadUrl":"https://example.com/jmdict.zip"}
        """#.utf8)
        let index = try JSONDecoder().decode(AppDictionaryIndex.self, from: stored)
        #expect(index == AppDictionaryIndex(
            title: "JMdict", format: 3, revision: "2026-01-01", isUpdatable: true,
            indexURL: "https://example.com/index.json", downloadURL: "https://example.com/jmdict.zip"
        ))
    }

    @Test func readsTheImportSummaryTheNewEngineWrites() throws {
        let stored = Data(#"""
        {"title":"明鏡","revision":"1","sequenced":false,"version":3,"importDate":1760000000,
         "counts":{"terms":{"total":10}},"styles":"","indexUrl":null}
        """#.utf8)
        let index = try JSONDecoder().decode(AppDictionaryIndex.self, from: stored)
        #expect(index == AppDictionaryIndex(title: "明鏡", format: 3, revision: "1"))
    }

    @Test func aLibraryFlagsDictionariesFromTheOldEngine() {
        let current = AppDictionaryInfo(fileName: "a", index: AppDictionaryIndex(title: "A"))
        let outdated = AppDictionaryInfo(fileName: "b", index: AppDictionaryIndex(title: "B"), needsReimport: true)
        #expect(!AppDictionaryLibraryState(termDictionaries: [current]).needsReimport)
        #expect(AppDictionaryLibraryState(termDictionaries: [current], kanjiDictionaries: [outdated]).needsReimport)
        #expect(AppDictionaryLibraryState(kanjiDictionaries: [outdated]).dictionaries(of: .kanji) == [outdated])
    }

    @Test func pitchShowsNumbersThenPatternsThenTranscriptions() {
        let pitch = DictionaryLookupPitch(dictionary: "NHK", positions: [0, 2], patterns: ["LHHL"], transcriptions: ["sɯ̥kʲi"])
        #expect(pitch.displayValues == ["0", "2", "LHHL", "sɯ̥kʲi"])
    }
}
