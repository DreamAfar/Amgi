//
//  NoteSoundTagsTests.swift
//  BrowseFeatureTests
//

import Testing
@testable import BrowseFeature

@Suite("Note sound tags")
struct NoteSoundTagsTests {
    @Test("finds each [sound:] reference once, in order")
    func findsReferences() {
        let field = "猫 [sound:neko.mp3]<br>[sound: inu.mp3 ] text [sound:neko.mp3] [sound:]"
        #expect(NoteSoundTags.filenames(in: field) == ["neko.mp3", "inu.mp3"])
    }

    @Test("an unterminated tag is ignored")
    func unterminated() {
        #expect(NoteSoundTags.filenames(in: "[sound:broken.mp3").isEmpty)
    }

    @Test("appending separates the new reference with a space")
    func appending() {
        #expect(NoteSoundTags.appending("a.m4a", to: "") == "[sound:a.m4a]")
        #expect(NoteSoundTags.appending("a.m4a", to: "word") == "word [sound:a.m4a]")
    }
}
