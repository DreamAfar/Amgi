//
//  IOGeometry.swift
//  BrowseFeature
//
//  Shape geometry in image pixels. Anki stores a rotated shape by its
//  left/top corner and an angle around that corner (fabric's default origin),
//  but its editor turns shapes around their centre. Every transform here
//  works from a snapshot of the shape taken when the gesture began, so a drag
//  never accumulates rounding.
//

#if canImport(UIKit)
import UIKit

/// A shape's unrotated box, placed with its top-left corner at `origin` and
/// turned by `angle` radians around that corner.
struct IOBox: Equatable {
    var origin: CGPoint
    var size: CGSize
    var angle: CGFloat

    var transform: CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: angle)
    }

    var center: CGPoint {
        CGPoint(x: size.width / 2, y: size.height / 2).applying(transform)
    }

    var corners: [CGPoint] {
        [
            CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
            CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height),
        ].map { $0.applying(transform) }
    }

    /// Axis-aligned bounds of the rotated box.
    var boundingRect: CGRect {
        let points = corners
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    func toLocal(_ point: CGPoint) -> CGPoint {
        point.applying(transform.inverted())
    }
}

/// Selection handles, as fabric draws them: four corners, four edges, and
/// the rotation knob above the top edge.
enum IOHandle: CaseIterable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, rotate

    var isCorner: Bool { [.topLeft, .topRight, .bottomRight, .bottomLeft].contains(self) }
    var movesMinX: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var movesMaxX: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var movesMinY: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesMaxY: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }

    /// Position in the box's own coordinates. `knobOffset` is how far above
    /// the top edge the rotation knob sits.
    func localPosition(in size: CGSize, knobOffset: CGFloat) -> CGPoint {
        let w = size.width, h = size.height
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: w / 2, y: 0)
        case .topRight: return CGPoint(x: w, y: 0)
        case .right: return CGPoint(x: w, y: h / 2)
        case .bottomRight: return CGPoint(x: w, y: h)
        case .bottom: return CGPoint(x: w / 2, y: h)
        case .bottomLeft: return CGPoint(x: 0, y: h)
        case .left: return CGPoint(x: 0, y: h / 2)
        case .rotate: return CGPoint(x: w / 2, y: -knobOffset)
        }
    }
}

// MARK: - Text metrics

/// Text labels are measured the way Anki's reviewer draws them: Arial, a
/// line height of 1.5 × the height of "M", and a 5 px pad, all multiplied by
/// the label's scale.
enum IOTextMetrics {
    static func font(pixelSize: CGFloat) -> UIFont {
        UIFont(name: IOStyle.textFontName, size: pixelSize) ?? .systemFont(ofSize: pixelSize)
    }

    static func lineHeight(pixelSize: CGFloat) -> CGFloat {
        1.5 * font(pixelSize: pixelSize).capHeight
    }

    static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// Unscaled box: widest line plus padding, by line count × line height plus padding.
    static func unscaledSize(text: String, pixelSize: CGFloat) -> CGSize {
        let font = Self.font(pixelSize: pixelSize)
        let lines = Self.lines(text)
        let width = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return CGSize(
            width: width + IOStyle.textPadding,
            height: CGFloat(lines.count) * lineHeight(pixelSize: pixelSize) + IOStyle.textPadding
        )
    }
}

// MARK: - Shape geometry

extension IOShape {
    func fontPixelSize(in image: CGSize) -> CGFloat {
        guard case .text(_, _, let fontSize) = kind else { return 0 }
        return (fontSize ?? IOStyle.defaultFontSize) * image.height
    }

    func box(in image: CGSize) -> IOBox {
        let radians = angle * .pi / 180
        let origin = CGPoint(x: left * image.width, y: top * image.height)
        switch kind {
        case .rect(let width, let height):
            return IOBox(origin: origin, size: CGSize(width: width * image.width, height: height * image.height), angle: radians)
        case .ellipse(let rx, let ry):
            return IOBox(origin: origin, size: CGSize(width: 2 * rx * image.width, height: 2 * ry * image.height), angle: radians)
        case .text(let text, let scale, _):
            let unscaled = IOTextMetrics.unscaledSize(text: text, pixelSize: fontPixelSize(in: image))
            return IOBox(origin: origin, size: CGSize(width: unscaled.width * scale, height: unscaled.height * scale), angle: radians)
        case .polygon(let points):
            let pixels = points.map { CGPoint(x: $0.x * image.width, y: $0.y * image.height) }
            let xs = pixels.map(\.x), ys = pixels.map(\.y)
            let minX = xs.min() ?? 0, minY = ys.min() ?? 0
            return IOBox(
                origin: CGPoint(x: minX, y: minY),
                size: CGSize(width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY),
                angle: 0
            )
        }
    }

    func pixelPoints(in image: CGSize) -> [CGPoint] {
        guard case .polygon(let points) = kind else { return [] }
        return points.map { CGPoint(x: $0.x * image.width, y: $0.y * image.height) }
    }

    /// Handles a single selected shape offers. Text keeps its aspect ratio,
    /// so it only gets corners (Anki hides the edge controls on text).
    var handles: [IOHandle] {
        if isText { return [.topLeft, .topRight, .bottomRight, .bottomLeft, .rotate] }
        return IOHandle.allCases
    }

    // MARK: Hit testing

    func contains(_ point: CGPoint, tolerance: CGFloat, in image: CGSize) -> Bool {
        switch kind {
        case .polygon:
            let points = pixelPoints(in: image)
            if Self.polygon(points, contains: point) { return true }
            return Self.distance(from: point, toPolygon: points) <= tolerance
        case .ellipse:
            let box = self.box(in: image)
            let local = box.toLocal(point)
            let rx = box.size.width / 2 + tolerance, ry = box.size.height / 2 + tolerance
            guard rx > 0, ry > 0 else { return false }
            let dx = (local.x - box.size.width / 2) / rx, dy = (local.y - box.size.height / 2) / ry
            return dx * dx + dy * dy <= 1
        case .rect, .text:
            let box = self.box(in: image)
            let local = box.toLocal(point)
            return local.x >= -tolerance && local.x <= box.size.width + tolerance
                && local.y >= -tolerance && local.y <= box.size.height + tolerance
        }
    }

    static func polygon(_ points: [CGPoint], contains point: CGPoint) -> Bool {
        guard points.count >= 3 else { return false }
        var inside = false
        var j = points.count - 1
        for i in points.indices {
            let a = points[i], b = points[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func distance(from point: CGPoint, toPolygon points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return .infinity }
        var best = CGFloat.infinity
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let lengthSquared = ab.x * ab.x + ab.y * ab.y
            let t = lengthSquared == 0 ? 0 : max(0, min(1, ((point.x - a.x) * ab.x + (point.y - a.y) * ab.y) / lengthSquared))
            let closest = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
            best = min(best, hypot(point.x - closest.x, point.y - closest.y))
        }
        return best
    }

    // MARK: Transforms (from a snapshot)

    func moved(by delta: CGVector, in image: CGSize) -> IOShape {
        var shape = self
        let dx = delta.dx / image.width, dy = delta.dy / image.height
        if case .polygon(let points) = kind {
            shape.kind = .polygon(points: points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        } else {
            shape.left += dx
            shape.top += dy
        }
        return shape
    }

    /// Turns the shape by `delta` radians around the centre of its box.
    /// Boxes keep their centre and get a new corner + angle; polygons have
    /// the rotation baked into their points.
    func rotated(by delta: CGFloat, in image: CGSize) -> IOShape {
        var shape = self
        let box = self.box(in: image)
        let center = box.center
        if case .polygon = kind {
            let turn = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: delta)
                .translatedBy(x: -center.x, y: -center.y)
            let points = pixelPoints(in: image).map { $0.applying(turn) }
            shape.kind = .polygon(points: points.map { CGPoint(x: $0.x / image.width, y: $0.y / image.height) })
            return shape
        }
        let newAngle = box.angle + delta
        let half = CGPoint(x: box.size.width / 2, y: box.size.height / 2)
            .applying(CGAffineTransform(rotationAngle: newAngle))
        shape.left = (center.x - half.x) / image.width
        shape.top = (center.y - half.y) / image.height
        shape.angle = Self.normalizedDegrees(newAngle * 180 / .pi)
        return shape
    }

    static func normalizedDegrees(_ degrees: CGFloat) -> CGFloat {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value <= -180 { value += 360 }
        return abs(value) < 0.0001 ? 0 : value
    }

    /// Drags `handle` to `point`, keeping the opposite side (or corner)
    /// fixed in the shape's own rotated frame.
    func resized(_ handle: IOHandle, to point: CGPoint, in image: CGSize) -> IOShape {
        guard handle != .rotate else { return self }
        let box = self.box(in: image)
        let local = box.toLocal(point)
        let w = box.size.width, h = box.size.height
        let minimum = IOStyle.minimumSize
        var shape = self

        if case .text(let text, let scale, let fontSize) = kind {
            guard handle.isCorner, w > 0, h > 0 else { return self }
            let anchor = CGPoint(x: handle.movesMinX ? w : 0, y: handle.movesMinY ? h : 0)
            let factor = max(abs(local.x - anchor.x) / w, abs(local.y - anchor.y) / h, minimum / min(w, h))
            let newW = w * factor, newH = h * factor
            let newMin = CGPoint(x: handle.movesMinX ? anchor.x - newW : 0, y: handle.movesMinY ? anchor.y - newH : 0)
            let origin = newMin.applying(box.transform)
            shape.kind = .text(text, scale: scale * factor, fontSize: fontSize)
            shape.left = origin.x / image.width
            shape.top = origin.y / image.height
            return shape
        }

        var minX: CGFloat = 0, minY: CGFloat = 0, maxX = w, maxY = h
        if handle.movesMinX { minX = min(local.x, maxX - minimum) }
        if handle.movesMaxX { maxX = max(local.x, minX + minimum) }
        if handle.movesMinY { minY = min(local.y, maxY - minimum) }
        if handle.movesMaxY { maxY = max(local.y, minY + minimum) }
        let newSize = CGSize(width: maxX - minX, height: maxY - minY)
        let origin = CGPoint(x: minX, y: minY).applying(box.transform)

        switch kind {
        case .rect:
            shape.kind = .rect(width: newSize.width / image.width, height: newSize.height / image.height)
            shape.left = origin.x / image.width
            shape.top = origin.y / image.height
        case .ellipse:
            shape.kind = .ellipse(rx: newSize.width / 2 / image.width, ry: newSize.height / 2 / image.height)
            shape.left = origin.x / image.width
            shape.top = origin.y / image.height
        case .polygon:
            let sx = w > 0 ? newSize.width / w : 1
            let sy = h > 0 ? newSize.height / h : 1
            let points = pixelPoints(in: image).map { point in
                CGPoint(
                    x: (origin.x + (point.x - box.origin.x) * sx) / image.width,
                    y: (origin.y + (point.y - box.origin.y) * sy) / image.height
                )
            }
            shape.kind = .polygon(points: points)
        case .text:
            break
        }
        return shape
    }
}

/// Snaps a rotation to the nearest quarter turn within 3°, the threshold
/// Anki's editor uses for its snap to 0°.
func ioSnappedDegrees(_ degrees: CGFloat) -> CGFloat {
    let nearest = (degrees / 90).rounded() * 90
    return abs(degrees - nearest) <= 3 ? nearest : degrees
}
#endif
