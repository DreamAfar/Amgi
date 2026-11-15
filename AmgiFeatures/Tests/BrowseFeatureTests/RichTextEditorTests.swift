//
//  RichTextEditorTests.swift
//  BrowseFeatureTests
//

import CoreGraphics
import Foundation
import Testing
@testable import BrowseFeature

@Suite("Rich text commands")
struct RichTextCommandTests {

    @Test func togglesRunTheBrowserCommand() {
        #expect(RichTextCommand.bold.script == #"amgi.exec("bold")"#)
        #expect(RichTextCommand.strikethrough.script == #"amgi.exec("strikeThrough")"#)
        #expect(RichTextCommand.subscriptText.script == #"amgi.exec("subscript")"#)
        #expect(RichTextCommand.numberedList.script == #"amgi.exec("insertOrderedList")"#)
        #expect(RichTextCommand.align(.center).script == #"amgi.exec("justifyCenter")"#)
        #expect(RichTextCommand.clearFormatting.script == #"amgi.exec("removeFormat")"#)
    }

    @Test func colorsCarryTheirValue() {
        #expect(RichTextCommand.textColor("#e53935").script == ##"amgi.exec("foreColor", "#e53935")"##)
        #expect(RichTextCommand.highlight(nil).script == #"amgi.exec("hiliteColor", "transparent")"#)
    }

    @Test func mathWrapsWithAnkiDelimiters() {
        #expect(RichTextCommand.math(.inline).script == #"amgi.wrap("\\(", "\\)")"#)
        #expect(RichTextCommand.math(.block).script == #"amgi.wrap("\\[", "\\]")"#)
        #expect(RichTextCommand.math(.chemistry).script == #"amgi.wrap("\\(\\ce{", "}\\)")"#)
    }

    @Test func literalsCannotBreakOutOfTheScript() {
        let script = RichTextCommand.insertImage(filename: "a\"); alert(1); (\".jpg").script
        #expect(script == #"amgi.insertImage("a\"); alert(1); (\".jpg")"#)
        #expect(RichTextCommand.literal("line\nbreak") == #""line\nbreak""#)
    }

    @Test func formattingReadsThePageState() {
        let formatting = RichTextFormatting(message: [
            "name": "state", "bold": true, "strike": true, "sup": true, "ol": true, "align": "right",
        ])
        #expect(formatting.bold)
        #expect(!formatting.italic)
        #expect(formatting.strikethrough)
        #expect(formatting.superscriptText)
        #expect(formatting.numberedList)
        #expect(formatting.alignment == .right)
        #expect(RichTextFormatting(message: [:]) == RichTextFormatting())
    }

    @Test func thePageTakesItsColors() {
        let page = RichFieldPage.html(textColor: "rgba(1, 2, 3, 1.0)", caretColor: "rgba(4, 5, 6, 1.0)")
        #expect(page.contains("color: rgba(1, 2, 3, 1.0)"))
        #expect(page.contains("caret-color: rgba(4, 5, 6, 1.0)"))
        #expect(!page.contains("__COLOR__"))
        #expect(!page.contains("__ACCENT__"))
    }

    @Test func mathJaxElementsAreStoredAsDelimiters() {
        #expect(NoteFieldHTML.normalizedForStorage("<b>x</b>") == "<b>x</b>")
        #expect(
            NoteFieldHTML.normalizedForStorage(#"a <anki-mathjax>x^2</anki-mathjax> b"#) == #"a \(x^2\) b"#
        )
        #expect(
            NoteFieldHTML.normalizedForStorage(#"<anki-mathjax block="true">x<br>y</anki-mathjax>"#) == "\\[x\ny\\]"
        )
    }
}

#if canImport(UIKit)
@Suite("Note image geometry")
struct NoteImageGeometryTests {

    @Test func fittedNeverScalesUp() {
        #expect(NoteImageProcessor.fitted(CGSize(width: 800, height: 600), maxDimension: 1920) == CGSize(width: 800, height: 600))
        #expect(NoteImageProcessor.fitted(CGSize(width: 800, height: 600), maxDimension: nil) == CGSize(width: 800, height: 600))
    }

    @Test func fittedCapsTheLongerEdge() {
        #expect(NoteImageProcessor.fitted(CGSize(width: 4000, height: 3000), maxDimension: 1920) == CGSize(width: 1920, height: 1440))
        #expect(NoteImageProcessor.fitted(CGSize(width: 3000, height: 4000), maxDimension: 800) == CGSize(width: 600, height: 800))
    }

    @Test func pixelCropScalesAndStaysInside() {
        let size = CGSize(width: 1000, height: 500)
        #expect(
            NoteImageProcessor.pixelCrop(CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5), in: size)
                == CGRect(x: 250, y: 250, width: 500, height: 250)
        )
        #expect(NoteImageProcessor.pixelCrop(CGRect(x: 0, y: 0, width: 1, height: 1), in: size) == CGRect(origin: .zero, size: size))
        #expect(NoteImageProcessor.pixelCrop(CGRect(x: 2, y: 2, width: 1, height: 1), in: size) == CGRect(origin: .zero, size: size))
    }

    @Test func settingsKnowWhenTheyCrop() {
        var settings = NoteImageSettings()
        #expect(!settings.isCropped)
        settings.crop = CGRect(x: 0.1, y: 0, width: 0.9, height: 1)
        #expect(settings.isCropped)
    }

    @Test func imageIsFittedAndCentred() {
        let frame = NoteImageCropGeometry.fittedFrame(
            imageSize: CGSize(width: 200, height: 100), in: CGSize(width: 100, height: 100)
        )
        #expect(frame == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func movingStopsAtTheEdges() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        #expect(NoteImageCropGeometry.moved(rect, by: CGSize(width: 1, height: -1)) == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    @Test func resizingKeepsTheOppositeCornerAndAMinimum() {
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let minSize = CGSize(width: 0.125, height: 0.125)

        let grown = NoteImageCropGeometry.resized(rect, corner: .bottomTrailing, by: CGSize(width: 1, height: 1), minSize: minSize)
        #expect(grown == CGRect(x: 0.25, y: 0.25, width: 0.75, height: 0.75))

        let squeezed = NoteImageCropGeometry.resized(rect, corner: .topLeading, by: CGSize(width: 1, height: 1), minSize: minSize)
        #expect(squeezed == CGRect(x: 0.625, y: 0.625, width: 0.125, height: 0.125))
    }

    @Test func mediaRequestsResolveToAFlatFilename() {
        #expect(NoteMediaScheme.filename(in: URL(string: "amgi-note-media://media/paste-1.jpg")!) == "paste-1.jpg")
        #expect(NoteMediaScheme.filename(in: URL(string: "amgi-note-media://media/a%20b.png")!) == "a b.png")
        #expect(NoteMediaScheme.filename(in: URL(string: "amgi-note-media://media/x/../../secret.txt")!) == "secret.txt")
        #expect(NoteMediaScheme.filename(in: URL(string: "amgi-note-media://media/")!) == nil)
    }
}
#endif
