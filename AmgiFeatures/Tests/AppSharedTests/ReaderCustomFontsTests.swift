//
//  ReaderCustomFontsTests.swift
//  AppSharedTests
//

import Foundation
import Testing
@testable import AppShared

@Suite("Reader custom fonts")
struct ReaderCustomFontsTests {

    @Test func onlyPlainFileNamesResolve() {
        #expect(ReaderCustomFonts.isPlainFileName("Noto Serif.ttf"))
        #expect(!ReaderCustomFonts.isPlainFileName("../secret.ttf"))
        #expect(!ReaderCustomFonts.isPlainFileName("a/b.ttf"))
        #expect(!ReaderCustomFonts.isPlainFileName(".hidden.ttf"))
        #expect(!ReaderCustomFonts.isPlainFileName(""))
        #expect(ReaderCustomFonts.fileURL(forRequest: URL(string: "amgi-reader-font://fonts/..%2F..%2Fsecret")!) == nil)
    }

    @Test func builtInSelectionsHaveNoCustomCSS() {
        #expect(ReaderCustomFonts.css(forSelection: "system", fallback: "serif") == nil)
        #expect(ReaderCustomFonts.css(forSelection: "custom:missing-font.ttf", fallback: "serif") == nil)
    }

    @Test func familyNamesAreCSSSafe() {
        #expect(ReaderCustomFonts.cssFamilyName(forFileName: "My \"Font\" 2.otf") == "AmgiReaderFont-My__Font__2_otf")
    }

    @Test func mimeTypesFollowTheExtension() {
        #expect(ReaderCustomFonts.mimeType(forFileName: "a.OTF") == "font/otf")
        #expect(ReaderCustomFonts.mimeType(forFileName: "a.ttc") == "font/collection")
        #expect(ReaderCustomFonts.mimeType(forFileName: "a.woff2") == "font/woff2")
        #expect(ReaderCustomFonts.mimeType(forFileName: "a.ttf") == "font/ttf")
    }

    @Test func aFileThatIsntAFontIsRefused() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-font-\(UUID().uuidString).ttf")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(throws: ReaderCustomFonts.ImportError.self) {
            try ReaderCustomFonts.importFont(from: file)
        }
    }
}
