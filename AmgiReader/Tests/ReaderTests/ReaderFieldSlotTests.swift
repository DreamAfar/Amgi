//
//  ReaderFieldSlotTests.swift
//  ReaderTests
//

import Reader
import Testing

struct ReaderFieldSlotTests {
    @Test func matchesExactEnglishNames() {
        let guess = ReaderFieldSlot.guessMapping(fieldNames: [
            "Book ID", "Book Title", "Cover", "Chapter Title", "Chapter Order", "Content", "Language",
        ])
        #expect(guess == [
            .bookID: "Book ID",
            .bookTitle: "Book Title",
            .bookCover: "Cover",
            .chapterTitle: "Chapter Title",
            .chapterOrder: "Chapter Order",
            .content: "Content",
            .language: "Language",
        ])
    }

    @Test func matchesChineseNames() {
        let guess = ReaderFieldSlot.guessMapping(fieldNames: ["书名", "章节", "序号", "正文"])
        #expect(guess[.bookTitle] == "书名")
        #expect(guess[.chapterTitle] == "章节")
        #expect(guess[.chapterOrder] == "序号")
        #expect(guess[.content] == "正文")
        #expect(guess[.bookID] == nil)
    }

    @Test func chapterNumberIsTheOrderNotTheTitle() {
        let guess = ReaderFieldSlot.guessMapping(fieldNames: ["Chapter Number", "Chapter Name", "Text"])
        #expect(guess[.chapterOrder] == "Chapter Number")
        #expect(guess[.chapterTitle] == "Chapter Name")
        #expect(guess[.content] == "Text")
    }

    @Test func usesEachFieldOnce() {
        let guess = ReaderFieldSlot.guessMapping(fieldNames: ["Title"])
        #expect(guess == [.bookTitle: "Title"])
    }

    @Test func leavesUnrelatedFieldsUnmapped() {
        #expect(ReaderFieldSlot.guessMapping(fieldNames: ["Front", "Back"]).isEmpty)
    }

    @Test func onlyCoverAndLanguageAreOptional() {
        #expect(ReaderFieldSlot.allCases.filter(\.isOptional) == [.bookCover, .language])
    }
}
