//
//  IOEditorModel.swift
//  BrowseFeature
//
//  Document and tool state for the image-occlusion editor. The tools and
//  their rules follow Anki's mask editor (ts/routes/image-occlusion/tools):
//  draw tools stay active after a shape, groups share one ordinal, ungroup
//  frees every member's ordinal, undo restores whole snapshots, and the
//  first undo while a polygon is half drawn just drops that polygon.
//

#if canImport(UIKit)
import UIKit

enum IOTool: CaseIterable, Equatable {
    case select, rectangle, ellipse, polygon, text, fill
}

enum IOAlignment: CaseIterable {
    case left, horizontalCenter, right, top, verticalCenter, bottom
}

/// Text the editor needs the user to type: a new label, or an existing one.
enum IOTextRequest: Identifiable, Equatable {
    case insert(at: CGPoint)
    case edit(id: UUID, text: String)

    var id: String {
        switch self {
        case .insert(let point): return "insert-\(point.x)-\(point.y)"
        case .edit(let id, _): return "edit-\(id.uuidString)"
        }
    }

    var initialText: String {
        if case .edit(_, let text) = self { return text }
        return ""
    }
}

@Observable
@MainActor
final class IOEditorModel {
    /// The image in points; shapes are stored as fractions of it.
    let imageSize: CGSize

    private(set) var shapes: [IOShape]
    var occludeInactive: Bool
    private(set) var currentTool: IOTool = .rectangle
    /// Switching tools drops a half-drawn polygon, and the tools that act on
    /// taps (polygon, text, fill) start with nothing selected.
    var tool: IOTool {
        get { currentTool }
        set {
            guard newValue != currentTool else { return }
            currentTool = newValue
            cancelPolygon()
            if newValue == .polygon || newValue == .fill || newValue == .text { selection = [] }
        }
    }

    private(set) var selection: Set<UUID> = []
    /// Colour the fill tool paints with.
    var fillColor: String = IOStyle.maskFill
    /// Anki's "translucent" toggle: masks drawn at 40 % so the image shows through.
    var translucent = false
    /// Text the user has to type before the editor can continue.
    var textRequest: IOTextRequest?

    /// Points of the polygon being drawn, in image pixels.
    private(set) var draftPolygon: [CGPoint] = []
    /// A rectangle or ellipse while its first drag is still going.
    private(set) var draftShape: IOShape?
    /// Rubber-band selection while dragging over empty canvas.
    private(set) var marquee: CGRect?

    private let initialShapes: [IOShape]
    private let initialOccludeInactive: Bool
    @ObservationIgnored private var history: [[IOShape]]
    private var historyIndex = 0

    private enum Drag {
        case move(start: CGPoint, originals: [UUID: IOShape])
        case resize(IOHandle, start: IOShape)
        case rotate(startAngle: CGFloat, start: IOShape)
        case draw(start: CGPoint)
        case marquee(start: CGPoint)
    }
    @ObservationIgnored private var drag: Drag?

    init(imageSize: CGSize, shapes: [IOShape], occludeInactive: Bool) {
        self.imageSize = imageSize
        self.shapes = shapes
        self.occludeInactive = occludeInactive
        initialShapes = shapes
        initialOccludeInactive = occludeInactive
        history = [shapes]
        // Anki opens an existing note on the select tool and a new one on rectangles.
        if !shapes.isEmpty { currentTool = .select }
    }

    // MARK: - Derived state

    var hasChanges: Bool { shapes != initialShapes || occludeInactive != initialOccludeInactive }
    var canUndo: Bool { !draftPolygon.isEmpty || historyIndex > 0 }
    var canRedo: Bool { historyIndex < history.count - 1 }
    var cardCount: Int { IOCloze.cardCount(shapes) }

    var selectedShapes: [IOShape] { shapes.filter { selection.contains($0.id) } }

    /// The one shape handles can act on: a single selected shape outside a group.
    var editableShape: IOShape? {
        let selected = selectedShapes
        guard selected.count == 1, selected[0].group == nil else { return nil }
        return selected[0]
    }

    var canGroup: Bool { IOCloze.units(of: selectedShapes).count >= 2 }
    var canUngroup: Bool { selectedShapes.contains { $0.group != nil } }

    /// Axis-aligned bounds of the selection, in image pixels.
    var selectionBounds: CGRect? {
        let rects = selectedShapes.map { $0.box(in: imageSize).boundingRect }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    // MARK: - History

    private func commit() {
        guard shapes != history[historyIndex] else { return }
        history.removeSubrange((historyIndex + 1)...)
        history.append(shapes)
        historyIndex += 1
    }

    func undo() {
        if !draftPolygon.isEmpty {
            cancelPolygon()
            return
        }
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        restore(history[historyIndex])
    }

    func redo() {
        cancelPolygon()
        guard canRedo else { return }
        historyIndex += 1
        restore(history[historyIndex])
    }

    private func restore(_ snapshot: [IOShape]) {
        shapes = snapshot
        let ids = Set(snapshot.map(\.id))
        selection = selection.intersection(ids)
    }

    // MARK: - Selection

    /// Topmost shape under `point`.
    func shape(at point: CGPoint, tolerance: CGFloat) -> IOShape? {
        shapes.last { $0.contains(point, tolerance: tolerance, in: imageSize) }
    }

    /// Selecting a grouped shape selects its whole group, as fabric does.
    private func unitIDs(of shape: IOShape) -> Set<UUID> {
        guard let group = shape.group else { return [shape.id] }
        return Set(shapes.filter { $0.group == group }.map(\.id))
    }

    func select(_ shape: IOShape?) {
        selection = shape.map(unitIDs(of:)) ?? []
    }

    func selectAll() {
        tool = .select
        selection = Set(shapes.map(\.id))
    }

    func clearSelection() {
        selection = []
    }

    // MARK: - Taps

    func tap(at point: CGPoint, tolerance: CGFloat) {
        switch tool {
        case .select:
            select(shape(at: point, tolerance: tolerance))
        case .rectangle, .ellipse:
            // A tap draws nothing; it can still pick a shape to adjust.
            select(shape(at: point, tolerance: tolerance))
        case .polygon:
            addPolygonPoint(point, closeRadius: tolerance * 1.5)
        case .text:
            if let hit = shape(at: point, tolerance: tolerance), case .text(let text, _, _) = hit.kind {
                select(hit)
                textRequest = .edit(id: hit.id, text: text)
            } else if isInsideImage(point) {
                textRequest = .insert(at: point)
            }
        case .fill:
            guard let hit = shape(at: point, tolerance: tolerance), hit.effectiveFill != fillColor else { return }
            update(hit.id) { $0.fill = fillColor }
            commit()
        }
    }

    /// Double tap on a label edits its text, whatever the tool.
    func doubleTap(at point: CGPoint, tolerance: CGFloat) {
        guard let hit = shape(at: point, tolerance: tolerance), case .text(let text, _, _) = hit.kind else { return }
        select(hit)
        textRequest = .edit(id: hit.id, text: text)
    }

    private func isInsideImage(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: imageSize).contains(point)
    }

    // MARK: - Drags

    /// Handle under `point` on the single editable shape, if any.
    func handle(at point: CGPoint, tolerance: CGFloat, knobOffset: CGFloat) -> IOHandle? {
        guard let target = editableShape else { return nil }
        let box = target.box(in: imageSize)
        return target.handles.first { handle in
            let position = handle.localPosition(in: box.size, knobOffset: knobOffset).applying(box.transform)
            return hypot(position.x - point.x, position.y - point.y) <= tolerance
        }
    }

    func dragBegan(at point: CGPoint, tolerance: CGFloat, knobOffset: CGFloat) {
        switch tool {
        case .select, .rectangle, .ellipse:
            if let grabbed = handle(at: point, tolerance: tolerance, knobOffset: knobOffset), let target = editableShape {
                if grabbed == .rotate {
                    let center = target.box(in: imageSize).center
                    drag = .rotate(startAngle: atan2(point.y - center.y, point.x - center.x), start: target)
                } else {
                    drag = .resize(grabbed, start: target)
                }
                return
            }
            if let hit = shape(at: point, tolerance: tolerance) {
                if !selection.contains(hit.id) { select(hit) }
                let originals = Dictionary(uniqueKeysWithValues: selectedShapes.map { ($0.id, $0) })
                drag = .move(start: point, originals: originals)
                return
            }
            if tool == .select {
                selection = []
                drag = .marquee(start: point)
                marquee = CGRect(origin: point, size: .zero)
            } else if isInsideImage(point) {
                selection = []
                drag = .draw(start: point)
            }
        case .polygon, .text, .fill:
            drag = nil
        }
    }

    func dragChanged(to point: CGPoint) {
        switch drag {
        case .move(let start, let originals):
            var delta = CGVector(dx: point.x - start.x, dy: point.y - start.y)
            delta = clampedMove(delta, for: Array(originals.values))
            for (id, original) in originals {
                update(id) { $0 = original.moved(by: delta, in: imageSize) }
            }
        case .resize(let handle, let start):
            update(start.id) { $0 = start.resized(handle, to: point, in: imageSize) }
        case .rotate(let startAngle, let start):
            let center = start.box(in: imageSize).center
            let current = atan2(point.y - center.y, point.x - center.x)
            let startDegrees = start.angle
            let rawDegrees = startDegrees + (current - startAngle) * 180 / .pi
            let snapped = ioSnappedDegrees(IOShape.normalizedDegrees(rawDegrees))
            let delta = (snapped - startDegrees) * .pi / 180
            update(start.id) { $0 = start.rotated(by: delta, in: imageSize) }
        case .draw(let start):
            draftShape = drawnShape(from: start, to: clampedToImage(point))
        case .marquee(let start):
            let rect = CGRect(
                x: min(start.x, point.x), y: min(start.y, point.y),
                width: abs(point.x - start.x), height: abs(point.y - start.y)
            )
            marquee = rect
            let hits = shapes.filter { $0.box(in: imageSize).boundingRect.intersects(rect) }
            selection = hits.reduce(into: Set<UUID>()) { $0.formUnion(unitIDs(of: $1)) }
        case nil:
            break
        }
    }

    func dragEnded(at point: CGPoint) {
        dragChanged(to: point)
        if case .draw? = drag, let shape = draftShape {
            let box = shape.box(in: imageSize)
            if box.size.width >= IOStyle.minimumSize, box.size.height >= IOStyle.minimumSize {
                shapes.append(shape)
                selection = [shape.id]
            }
        }
        draftShape = nil
        marquee = nil
        drag = nil
        commit()
    }

    func dragCancelled() {
        drag = nil
        draftShape = nil
        marquee = nil
        restore(history[historyIndex])
    }

    private func drawnShape(from start: CGPoint, to end: CGPoint) -> IOShape {
        let minX = min(start.x, end.x), minY = min(start.y, end.y)
        let width = abs(end.x - start.x), height = abs(end.y - start.y)
        let kind: IOShape.Kind = tool == .ellipse
            ? .ellipse(rx: width / 2 / imageSize.width, ry: height / 2 / imageSize.height)
            : .rect(width: width / imageSize.width, height: height / imageSize.height)
        return IOShape(kind: kind, left: minX / imageSize.width, top: minY / imageSize.height)
    }

    private func clampedToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), imageSize.width), y: min(max(point.y, 0), imageSize.height))
    }

    /// `makeShapesRemainInCanvas`: a selection that fits stays inside the image.
    private func clampedMove(_ delta: CGVector, for originals: [IOShape]) -> CGVector {
        let rects = originals.map { $0.box(in: imageSize).boundingRect }
        guard var bounds = rects.first else { return delta }
        for rect in rects.dropFirst() { bounds = bounds.union(rect) }
        guard bounds.width <= imageSize.width, bounds.height <= imageSize.height else { return delta }
        let dx = min(max(delta.dx, -bounds.minX), imageSize.width - bounds.maxX)
        let dy = min(max(delta.dy, -bounds.minY), imageSize.height - bounds.maxY)
        return CGVector(dx: dx, dy: dy)
    }

    // MARK: - Polygon

    private func addPolygonPoint(_ point: CGPoint, closeRadius: CGFloat) {
        guard isInsideImage(point) else { return }
        if draftPolygon.count >= 3, let first = draftPolygon.first,
           hypot(first.x - point.x, first.y - point.y) <= closeRadius {
            finishPolygon()
            return
        }
        draftPolygon.append(point)
    }

    var canFinishPolygon: Bool { draftPolygon.count >= 3 }

    func finishPolygon() {
        guard canFinishPolygon else { return }
        let points = draftPolygon.map { CGPoint(x: $0.x / imageSize.width, y: $0.y / imageSize.height) }
        draftPolygon = []
        let shape = IOShape(kind: .polygon(points: points), left: 0, top: 0)
        let box = shape.box(in: imageSize)
        guard box.size.width > IOStyle.minimumSize, box.size.height > IOStyle.minimumSize else { return }
        shapes.append(shape)
        selection = [shape.id]
        commit()
    }

    func cancelPolygon() {
        draftPolygon = []
    }

    // MARK: - Text

    func submitText(_ text: String, for request: IOTextRequest) {
        textRequest = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch request {
        case .insert(let point):
            guard !trimmed.isEmpty else { return }
            let shape = IOShape(
                kind: .text(text, scale: 1, fontSize: IOStyle.defaultFontSize),
                left: point.x / imageSize.width,
                top: point.y / imageSize.height
            )
            shapes.append(shape)
            selection = [shape.id]
        case .edit(let id, _):
            if trimmed.isEmpty {
                shapes.removeAll { $0.id == id }
                selection.remove(id)
            } else {
                update(id) { shape in
                    if case .text(_, let scale, let fontSize) = shape.kind {
                        shape.kind = .text(text, scale: scale, fontSize: fontSize)
                    }
                }
            }
        }
        commit()
    }

    // MARK: - Selection actions

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        shapes.removeAll { selection.contains($0.id) }
        selection = []
        commit()
    }

    /// `duplicateItem`: copies 10 px down and right, with fresh ordinals.
    func duplicateSelection() {
        let originals = selectedShapes
        guard !originals.isEmpty else { return }
        var groupMap: [UUID: UUID] = [:]
        let copies = originals.map { original -> IOShape in
            var copy = original.moved(by: CGVector(dx: 10, dy: 10), in: imageSize)
            copy.id = UUID()
            copy.ordinal = nil
            if let group = original.group {
                let mapped = groupMap[group] ?? UUID()
                groupMap[group] = mapped
                copy.group = mapped
            }
            return copy
        }
        shapes += copies
        selection = Set(copies.map(\.id))
        commit()
    }

    /// `groupShapes`: one group, taking the lowest ordinal among its members.
    func groupSelection() {
        guard canGroup else { return }
        let group = UUID()
        let ordinal = selectedShapes.compactMap(\.ordinal).min()
        for id in selection {
            update(id) { $0.group = group; $0.ordinal = ordinal }
        }
        commit()
    }

    /// `unGroupShapes`: members leave the group and lose their ordinal.
    func ungroupSelection() {
        guard canUngroup else { return }
        for shape in selectedShapes where shape.group != nil {
            update(shape.id) { $0.group = nil; $0.ordinal = nil }
        }
        commit()
    }

    func applyFillToSelection() {
        guard !selection.isEmpty else { return }
        for id in selection { update(id) { $0.fill = fillColor } }
        commit()
    }

    /// One shape lines up with the image edge or centre; several line up
    /// with the outermost of them (`tool-aligns.ts`). Groups move as one.
    func align(_ alignment: IOAlignment) {
        let units = IOCloze.units(of: selectedShapes)
        guard !units.isEmpty else { return }
        let bounds = units.map { unit in
            unit.shapes.map { $0.box(in: imageSize).boundingRect }.reduce(CGRect.null) { $0.union($1) }
        }
        let image = CGRect(origin: .zero, size: imageSize)
        let all = bounds.reduce(CGRect.null) { $0.union($1) }
        let reference = units.count == 1 ? image : all

        for (unit, rect) in zip(units, bounds) {
            var delta = CGVector.zero
            switch alignment {
            case .left: delta.dx = reference.minX - rect.minX
            case .horizontalCenter: delta.dx = reference.midX - rect.midX
            case .right: delta.dx = reference.maxX - rect.maxX
            case .top: delta.dy = reference.minY - rect.minY
            case .verticalCenter: delta.dy = reference.midY - rect.midY
            case .bottom: delta.dy = reference.maxY - rect.maxY
            }
            for shape in unit.shapes {
                update(shape.id) { $0 = shape.moved(by: delta, in: imageSize) }
            }
        }
        commit()
    }

    // MARK: - Helpers

    private func update(_ id: UUID, _ change: (inout IOShape) -> Void) {
        guard let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        change(&shapes[index])
    }
}
#endif
