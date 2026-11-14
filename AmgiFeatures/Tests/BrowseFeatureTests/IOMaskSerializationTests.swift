//
//  IOMaskSerializationTests.swift
//  BrowseFeatureTests
//

import CoreGraphics
import Testing
@testable import BrowseFeature

@Suite("Image-occlusion serialization")
struct IOMaskSerializationTests {
    private func rect(_ left: CGFloat, ordinal: Int? = nil) -> IOMask {
        let mask = IOMask.rect(left: left, top: 0.1, width: 0.2, height: 0.2, extras: [:])
        return ordinal.map { mask.applyingSerializationOrdinal($0) } ?? mask
    }

    private func ordinals(_ text: String) -> [Int] {
        text.split(separator: "\n").compactMap { line in
            guard let start = line.range(of: "{{c"), let end = line.range(of: "::") else { return nil }
            return Int(line[start.upperBound..<end.lowerBound])
        }
    }

    @Test("new masks are numbered in order")
    func numbersNewMasks() {
        #expect(ordinals(IOMask.occlusionsText([rect(0.1), rect(0.4), rect(0.7)])) == [1, 2, 3])
    }

    @Test("a new mask never joins an existing group")
    func newMaskSkipsUsedOrdinals() {
        // Draw three, group the last two: the group takes c1.
        let text = IOMask.occlusionsText([rect(0.1), rect(0.4, ordinal: 1), rect(0.7, ordinal: 1)])
        #expect(ordinals(text) == [2, 1, 1])
    }

    @Test("a mask added to a loaded note is numbered after the existing cards")
    func addedMaskOnLoadedNote() {
        // c1 was deleted in this edit; reusing it would inherit its history.
        let text = IOMask.occlusionsText([rect(0.1, ordinal: 2), rect(0.4, ordinal: 3), rect(0.7)])
        #expect(ordinals(text) == [2, 3, 4])
    }

    @Test("a deleted highest card stays reserved")
    func reservedThroughLoadedMax() {
        // Loaded c1…c3, deleted c3, drew a new mask.
        let text = IOMask.occlusionsText([rect(0.1, ordinal: 1), rect(0.4, ordinal: 2), rect(0.7)], reservedThrough: 3)
        #expect(ordinals(text) == [1, 2, 4])
    }

    @Test("numbers use Anki's four-decimal format")
    func ankiNumberFormat() {
        #expect(ioNumber(0.25) == ".25")
        #expect(ioNumber(0.12346) == ".1235")
        #expect(ioNumber(0) == ".0000")
        #expect(ioNumber(1) == "1.")
        let text = IOMask.rect(left: 0.1, top: 0.25, width: 0.5, height: 0.12346, extras: [:]).occlusionText(ordinal: 1)
        #expect(text == "{{c1::image-occlusion:rect:left=.1:top=.25:width=.5:height=.1235}}")
    }
}
