//
//  ReviewInputMappingTests.swift
//  AppCoreTests
//

import Testing
@testable import AppCore

@Suite struct ReviewInputMappingTests {
    @Test func storedMapRoundTrips() {
        let map = ReviewInputMap.defaultKeyboard
        #expect(ReviewInputMap(json: map.json, default: ReviewInputMap()) == map)
    }

    /// Nothing stored yet, or something unreadable, means the defaults.
    @Test func emptyOrBadStorageFallsBack() {
        #expect(ReviewInputMap(json: "", default: .defaultGamepad) == .defaultGamepad)
        #expect(ReviewInputMap(json: "{not json", default: .defaultGamepad) == .defaultGamepad)
    }

    /// Clearing an input removes it, so a cleared map stays cleared rather
    /// than falling back to a default for that input.
    @Test func settingNoneRemovesTheInput() {
        var map = ReviewInputMap.defaultGamepad
        map.set(.none, for: ReviewGamepadButton.a.id, side: .answer)
        #expect(map.answer[ReviewGamepadButton.a.id] == nil)
        #expect(map.action(for: ReviewGamepadButton.a.id, side: .answer) == .none)
        #expect(map.action(for: ReviewGamepadButton.a.id, side: .question) == .showAnswer)
    }

    @Test func chordIDRoundTrips() {
        let chord = ReviewKeyChord(key: ReviewKeyChord.letter("z"), modifiers: [.command, .shift])
        #expect(ReviewKeyChord(id: chord.id) == chord)
        #expect(ReviewKeyChord(id: "nonsense") == nil)
        #expect(chord.title == "⇧⌘Z")
    }

    @Test func keyNamesFollowHIDUsages() {
        #expect(ReviewKeyChord.keyName(ReviewKeyChord.letter("a")) == "A")
        #expect(ReviewKeyChord.keyName(ReviewKeyChord.digit(1)) == "1")
        #expect(ReviewKeyChord.keyName(ReviewKeyChord.digit(0)) == "0")
        #expect(ReviewKeyChord.keyName(0x52) == "↑")
    }

    /// Anki's desktop keys: Space reveals, then grades Good; 1–4 grade.
    @Test func keyboardDefaultsMatchAnki() {
        let map = ReviewInputMap.defaultKeyboard
        let space = ReviewKeyChord(key: ReviewKeyChord.space).id
        #expect(map.action(for: space, side: .question) == .showAnswer)
        #expect(map.action(for: space, side: .answer) == .good)
        #expect(map.action(for: ReviewKeyChord(key: ReviewKeyChord.digit(1)).id, side: .answer) == .again)
        #expect(map.action(for: ReviewKeyChord(key: ReviewKeyChord.digit(1), modifiers: .control).id, side: .answer) == .flag1)
    }

    /// AnkiMobile's tap layout: anywhere reveals; then left is Again, right
    /// is Good and the middle column does nothing.
    @Test func ankiMobileGestureDefaults() {
        let map = ReviewInputMap.ankiMobileGestures
        for zone in ReviewGesture.zones {
            #expect(map.action(for: ReviewGesture.tap(zone: zone).id, side: .question) == .showAnswer)
        }
        #expect(map.action(for: ReviewGesture.tap(zone: 3).id, side: .answer) == .again)
        #expect(map.action(for: ReviewGesture.tap(zone: 4).id, side: .answer) == .none)
        #expect(map.action(for: ReviewGesture.tap(zone: 5).id, side: .answer) == .good)
    }

    /// Gestures start off, so updating doesn't make taps start answering.
    @Test func gesturesStartEmpty() {
        #expect(ReviewInputMap.defaultGestures == ReviewInputMap())
    }
}
