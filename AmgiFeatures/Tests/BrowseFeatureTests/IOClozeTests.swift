//
//  IOClozeTests.swift
//  BrowseFeatureTests
//
//  The occlusion field has to read and write exactly what Anki's editor
//  does (ts/routes/image-occlusion/shapes), or notes edited here would
//  change shape, lose groups or move cards when opened on the desktop.
//

import AnkiKit
import CoreGraphics
import Foundation
import Testing
@testable import BrowseFeature

@Suite("Image occlusion cloze format")
struct IOClozeTests {
    private func rect(_ left: CGFloat, ordinal: Int? = nil, group: UUID? = nil) -> IOShape {
        IOShape(kind: .rect(width: 0.2, height: 0.1), left: left, top: 0.1, ordinal: ordinal, group: group)
    }

    private func ordinals(_ text: String) -> [Int] {
        text.components(separatedBy: "<br>").compactMap { cloze in
            guard let start = cloze.range(of: "{{c"), let end = cloze.range(of: "::") else { return nil }
            return Int(cloze[start.upperBound..<end.lowerBound])
        }
    }

    @Test("numbers use floatToDisplay")
    func numberFormat() {
        #expect(IOFormat.number(0.25) == ".25")
        #expect(IOFormat.number(0.12346) == ".1235")
        #expect(IOFormat.number(0) == ".0000")
        #expect(IOFormat.number(1) == "1.")
    }

    @Test("angles are stored in ten-thousandths of a turn and read back")
    func angleRoundTrip() {
        #expect(IOFormat.storedAngle(0) == nil)
        #expect(IOFormat.storedAngle(90) == 2500)
        #expect(IOFormat.storedAngle(-36) == -1000)
        #expect(IOFormat.degrees(fromStored: "2500") == 90)
    }

    @Test("a rectangle is written in Anki's key order with a trailing <br>")
    func rectangleCloze() {
        let shape = IOShape(kind: .rect(width: 0.5, height: 0.12346), left: 0.1, top: 0.25, angle: 90)
        #expect(
            IOCloze.cloze(for: shape, ordinal: 1, occludeInactive: true)
                == "{{c1::image-occlusion:rect:left=.1:top=.25:angle=2500:width=.5:height=.1235:oi=1}}<br>"
        )
    }

    @Test("default fills are left out, others written")
    func fills() {
        var shape = rect(0.1)
        shape.fill = IOStyle.maskFill
        #expect(!IOCloze.cloze(for: shape, ordinal: 1, occludeInactive: false).contains("fill="))
        shape.fill = "#ff0000"
        #expect(IOCloze.cloze(for: shape, ordinal: 1, occludeInactive: false).contains(":fill=#ff0000"))
    }

    @Test("colons and backslashes in text are escaped")
    func escaping() {
        let label = IOShape(kind: .text("a:b\\c", scale: 1, fontSize: 0.05), left: 0, top: 0)
        #expect(IOCloze.cloze(for: label, ordinal: 0, occludeInactive: false).contains(":text=a\\:b\\\\c:"))
    }

    @Test("a lone text label is ordinal 0 and makes no card")
    func textLabels() {
        let label = IOShape(kind: .text("Heart", scale: 1, fontSize: 0.05), left: 0.5, top: 0.5)
        let shapes = [rect(0.1), label]
        #expect(ordinals(IOCloze.occlusions(shapes, occludeInactive: false)) == [1, 0])
        #expect(IOCloze.cardCount(shapes) == 1)
    }

    @Test("new shapes fill gaps first, then count up")
    func ordinalAssignment() {
        let shapes = [rect(0.1, ordinal: 1), rect(0.2, ordinal: 3), rect(0.3), rect(0.4)]
        #expect(ordinals(IOCloze.occlusions(shapes, occludeInactive: false)) == [1, 3, 2, 4])
    }

    @Test("a group is written as one ordinal, gathered where its first member is")
    func groups() {
        let group = UUID()
        let shapes = [rect(0.1, group: group), rect(0.2), rect(0.3, group: group)]
        #expect(ordinals(IOCloze.occlusions(shapes, occludeInactive: false)) == [1, 1, 2])
        #expect(IOCloze.cardCount(shapes) == 2)
    }

    @Test("an occlusion with several shapes loads as one group")
    func readsGroups() {
        func shapeData(_ left: String) -> ImageOcclusionShapeData {
            ImageOcclusionShapeData(kind: "rect", properties: [
                .init(name: "left", value: left), .init(name: "top", value: ".1"),
                .init(name: "width", value: ".2"), .init(name: "height", value: ".1"),
            ])
        }
        let shapes = IOCloze.shapes(from: [
            ImageOcclusionData(ordinal: 1, shapes: [shapeData(".1"), shapeData(".4")]),
            ImageOcclusionData(ordinal: 2, shapes: [shapeData(".7")]),
        ])
        #expect(shapes.count == 3)
        #expect(shapes[0].group != nil && shapes[0].group == shapes[1].group)
        #expect(shapes[2].group == nil)
        #expect(shapes.map(\.ordinal) == [1, 1, 2])
        #expect(ordinals(IOCloze.occlusions(shapes, occludeInactive: false)) == [1, 1, 2])
    }

    @Test("reading keeps angle, fill, text and unknown properties")
    func readsProperties() throws {
        let label = try #require(IOCloze.shape(from: ImageOcclusionShapeData(kind: "text", properties: [
            .init(name: "left", value: ".2"), .init(name: "top", value: ".3"),
            .init(name: "angle", value: "2500"), .init(name: "text", value: "E=mc2"),
            .init(name: "scale", value: "1.5"), .init(name: "fs", value: ".04"),
            .init(name: "fill", value: "#ff0000"), .init(name: "future", value: "x"),
        ]), ordinal: 0))
        #expect(label.kind == .text("E=mc2", scale: 1.5, fontSize: 0.04))
        #expect(label.angle == 90)
        #expect(label.fill == "#ff0000")
        #expect(label.extras == ["future": "x"])
        #expect(IOCloze.cloze(for: label, ordinal: 0, occludeInactive: false).contains(":future=x"))
    }
}
