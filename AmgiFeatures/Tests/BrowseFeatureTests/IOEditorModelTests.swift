//
//  IOEditorModelTests.swift
//  BrowseFeatureTests
//

import CoreGraphics
import Foundation
import Testing
@testable import BrowseFeature

@Suite("Image occlusion editor")
@MainActor
struct IOEditorModelTests {
    private let size = CGSize(width: 1000, height: 500)

    private func rect(_ left: CGFloat, top: CGFloat = 0.1, ordinal: Int? = nil) -> IOShape {
        IOShape(kind: .rect(width: 0.1, height: 0.2), left: left, top: top, ordinal: ordinal)
    }

    private func model(_ shapes: [IOShape] = []) -> IOEditorModel {
        IOEditorModel(imageSize: size, shapes: shapes, occludeInactive: true)
    }

    private func close(_ a: CGPoint, _ b: CGPoint, within tolerance: CGFloat = 0.01) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    // MARK: Geometry

    @Test("rotating turns a shape around its centre, not its stored corner")
    func rotationKeepsCentre() {
        let shape = rect(0.4)
        let before = shape.box(in: size).center
        let turned = shape.rotated(by: .pi / 2, in: size)
        #expect(close(turned.box(in: size).center, before))
        #expect(abs(turned.angle - 90) < 0.0001)
        // The stored corner moves so that Anki, which turns around it,
        // draws the same picture.
        #expect(turned.left != shape.left)
    }

    @Test("rotating a polygon bakes the turn into its points")
    func polygonRotation() {
        let triangle = IOShape(kind: .polygon(points: [
            CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.3, y: 0.1), CGPoint(x: 0.2, y: 0.3),
        ]), left: 0, top: 0)
        let turned = triangle.rotated(by: .pi, in: size)
        #expect(turned.angle == 0)
        #expect(close(turned.box(in: size).center, triangle.box(in: size).center))
    }

    @Test("resizing a rotated rectangle keeps the opposite corner in place")
    func resizeKeepsAnchor() {
        let shape = rect(0.4).rotated(by: .pi / 6, in: size)
        let box = shape.box(in: size)
        let anchor = box.corners[0]
        let target = CGPoint(x: box.corners[2].x + 40, y: box.corners[2].y + 30)
        let resized = shape.resized(.bottomRight, to: target, in: size)
        #expect(close(resized.box(in: size).corners[0], anchor))
        #expect(resized.angle == shape.angle)
    }

    @Test("text resizes uniformly from a corner")
    func textScalesUniformly() {
        let label = IOShape(kind: .text("Hi", scale: 1, fontSize: 0.05), left: 0.1, top: 0.1)
        let box = label.box(in: size)
        let resized = label.resized(.bottomRight, to: CGPoint(x: box.corners[2].x + box.size.width, y: box.corners[2].y), in: size)
        guard case .text(_, let scale, _) = resized.kind else { Issue.record("not text"); return }
        #expect(abs(scale - 2) < 0.01)
        #expect(close(resized.box(in: size).corners[0], box.corners[0]))
    }

    // MARK: Drawing

    @Test("dragging with the rectangle tool draws and selects a mask")
    func drawRectangle() {
        let model = model()
        model.dragBegan(at: CGPoint(x: 100, y: 100), tolerance: 10, knobOffset: 30)
        model.dragEnded(at: CGPoint(x: 300, y: 200))
        #expect(model.shapes.count == 1)
        #expect(model.selection == [model.shapes[0].id])
        #expect(model.shapes[0].kind == .rect(width: 0.2, height: 0.2))
    }

    @Test("a drag shorter than 5 px draws nothing")
    func tinyDrawIsDropped() {
        let model = model()
        model.dragBegan(at: CGPoint(x: 100, y: 100), tolerance: 10, knobOffset: 30)
        model.dragEnded(at: CGPoint(x: 102, y: 150))
        #expect(model.shapes.isEmpty)
        #expect(!model.canUndo)
    }

    @Test("tapping the first point closes a polygon")
    func polygonCloses() {
        let model = model()
        model.tool = .polygon
        for point in [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 200, y: 300), CGPoint(x: 101, y: 101)] {
            model.tap(at: point, tolerance: 10)
        }
        #expect(model.draftPolygon.isEmpty)
        guard case .polygon(let points) = model.shapes.first?.kind else { Issue.record("no polygon"); return }
        #expect(points.count == 3)
    }

    @Test("the first undo drops a half-drawn polygon, as in Anki")
    func undoDropsDraftPolygon() {
        let model = model([rect(0.1)])
        model.tool = .polygon
        model.tap(at: CGPoint(x: 500, y: 100), tolerance: 10)
        #expect(model.canUndo)
        model.undo()
        #expect(model.draftPolygon.isEmpty)
        #expect(model.shapes.count == 1)
    }

    // MARK: Editing

    @Test("moving keeps a selection inside the image")
    func moveIsClamped() {
        let model = model([rect(0.1)])
        model.tool = .select
        model.dragBegan(at: CGPoint(x: 150, y: 100), tolerance: 10, knobOffset: 30)
        model.dragEnded(at: CGPoint(x: -500, y: 100))
        #expect(model.shapes[0].left == 0)
    }

    @Test("grouping shares the lowest ordinal; ungrouping clears it")
    func groupAndUngroup() {
        let model = model([rect(0.1, ordinal: 4), rect(0.5, ordinal: 2)])
        model.selectAll()
        model.groupSelection()
        #expect(model.shapes.map(\.ordinal) == [2, 2])
        #expect(model.shapes[0].group != nil && model.shapes[0].group == model.shapes[1].group)
        #expect(IOCloze.cardCount(model.shapes) == 1)

        model.ungroupSelection()
        #expect(model.shapes.allSatisfy { $0.group == nil && $0.ordinal == nil })
    }

    @Test("tapping one member selects the whole group")
    func groupSelection() {
        let model = model([rect(0.1), rect(0.5)])
        model.selectAll()
        model.groupSelection()
        model.clearSelection()
        model.tool = .select
        model.tap(at: CGPoint(x: 150, y: 100), tolerance: 5)
        #expect(model.selection.count == 2)
    }

    @Test("duplicate offsets by 10 px and starts without an ordinal")
    func duplicate() {
        let model = model([rect(0.1, ordinal: 1)])
        model.select(model.shapes[0])
        model.duplicateSelection()
        #expect(model.shapes.count == 2)
        #expect(abs(model.shapes[1].left - 0.11) < 0.0001)
        #expect(model.shapes[1].ordinal == nil)
        #expect(model.selection == [model.shapes[1].id])
    }

    @Test("a single shape aligns to the image edge")
    func alignSingle() {
        let model = model([rect(0.4)])
        model.select(model.shapes[0])
        model.align(.right)
        #expect(abs(model.shapes[0].left - 0.9) < 0.0001)
    }

    @Test("several shapes align to the outermost of them")
    func alignSeveral() {
        let model = model([rect(0.2, top: 0.1), rect(0.6, top: 0.5)])
        model.selectAll()
        model.align(.top)
        #expect(model.shapes.allSatisfy { abs($0.top - 0.1) < 0.0001 })
    }

    @Test("undo and redo step through whole snapshots")
    func undoRedo() {
        let model = model([rect(0.1)])
        model.select(model.shapes[0])
        model.deleteSelection()
        #expect(model.shapes.isEmpty)
        model.undo()
        #expect(model.shapes.count == 1)
        model.redo()
        #expect(model.shapes.isEmpty)
    }

    @Test("the fill tool paints the tapped mask")
    func fillTool() {
        let model = model([rect(0.1)])
        model.tool = .fill
        model.fillColor = "#ff0000"
        model.tap(at: CGPoint(x: 150, y: 100), tolerance: 5)
        #expect(model.shapes[0].fill == "#ff0000")
    }

    @Test("a new label is ordinal-free text that makes no card")
    func textLabel() {
        let model = model()
        model.tool = .text
        model.tap(at: CGPoint(x: 100, y: 100), tolerance: 5)
        guard let request = model.textRequest else {
            Issue.record("no text request")
            return
        }
        model.submitText("Aorta", for: request)
        #expect(model.shapes.count == 1)
        #expect(model.cardCount == 0)
    }
}
