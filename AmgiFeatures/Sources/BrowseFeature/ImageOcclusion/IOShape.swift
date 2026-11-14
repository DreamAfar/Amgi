//
//  IOShape.swift
//  BrowseFeature
//
//  The image-occlusion document, shaped like Anki's own editor
//  (ts/routes/image-occlusion/shapes): positions are fractions of the image
//  size, `angle` is in degrees around the shape's left/top corner, and each
//  shape knows how to write itself as a cloze.
//

import AnkiKit
import CoreGraphics
import Foundation

/// Anki's editor defaults (ts/routes/image-occlusion/tools/lib.ts).
enum IOStyle {
    static let maskFill = "#ffeba2"
    static let border = "#212121"
    static let textColor = "#000000"
    static let textBackground = "#ffffff"
    static let textFontName = "ArialMT"
    /// Padding around a text label, in unscaled font pixels.
    static let textPadding: CGFloat = 5
    /// Anki's 40 px default on a canvas about 800 px tall.
    static let defaultFontSize: CGFloat = 0.05
    /// Shapes smaller than this many image pixels are discarded, as in Anki.
    static let minimumSize: CGFloat = 5
}

struct IOShape: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case rect(width: CGFloat, height: CGFloat)
        case ellipse(rx: CGFloat, ry: CGFloat)
        /// Absolute, normalized points. Polygons never keep an angle: like
        /// Anki, every move, resize or rotation is baked into the points.
        case polygon(points: [CGPoint])
        /// `fontSize` is a fraction of the image height; nil means Anki's default.
        case text(String, scale: CGFloat, fontSize: CGFloat?)
    }

    var id = UUID()
    var kind: Kind
    var left: CGFloat
    var top: CGFloat
    /// Degrees, clockwise, around (left, top). Always 0 for polygons.
    var angle: CGFloat = 0
    /// nil means the default for the kind (mask yellow, or black text).
    var fill: String?
    /// The cloze ordinal this shape already has. nil until it is saved.
    var ordinal: Int?
    /// Shapes sharing a group are one occlusion and one card.
    var group: UUID?
    /// Properties this editor doesn't know, written back untouched.
    var extras: [String: String] = [:]

    var isText: Bool {
        if case .text = kind { return true }
        return false
    }

    var effectiveFill: String {
        fill ?? (isText ? IOStyle.textColor : IOStyle.maskFill)
    }
}

// MARK: - Anki number formats

enum IOFormat {
    /// `floatToDisplay`: four decimals, leading and trailing zeros stripped.
    static func number(_ value: CGFloat) -> String {
        let double = Double(value)
        guard !double.isNaN, double != 0 else { return ".0000" }
        var text = String(format: "%.4f", double)
        while text.hasPrefix("0") { text.removeFirst() }
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    private static let angleSteps: Double = 10_000

    /// `angleToStored`: degrees as 1/10000ths of a turn. nil for no rotation.
    static func storedAngle(_ degrees: CGFloat) -> Int? {
        let wrapped = Double(degrees).truncatingRemainder(dividingBy: 360)
        guard !wrapped.isNaN else { return nil }
        let stored = Int((wrapped / 360 * angleSteps).rounded())
        return stored == 0 ? nil : stored
    }

    /// `storedToAngle`.
    static func degrees(fromStored text: String?) -> CGFloat {
        guard let text, let value = Double(text) else { return 0 }
        return CGFloat(value.truncatingRemainder(dividingBy: angleSteps) / angleSteps * 360)
    }

    /// `addKeyValue`: backslashes and colons are escaped inside values.
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ":", with: "\\:")
    }
}

// MARK: - Reading a note

enum IOCloze {
    /// `extractShapesFromClozedField`: every shape of an occlusion with more
    /// than one shape joins one group.
    static func shapes(from occlusions: [ImageOcclusionData]) -> [IOShape] {
        var result: [IOShape] = []
        for occlusion in occlusions {
            let built = occlusion.shapes.compactMap { shape(from: $0, ordinal: occlusion.ordinal) }
            if built.count > 1, occlusion.ordinal != 0 {
                let group = UUID()
                result += built.map { var shape = $0; shape.group = group; return shape }
            } else {
                result += built
            }
        }
        return result
    }

    static func shape(from data: ImageOcclusionShapeData, ordinal: Int) -> IOShape? {
        var props: [String: String] = [:]
        for property in data.properties { props[property.name] = property.value }

        func number(_ key: String) -> CGFloat? {
            props[key].flatMap { Double($0) }.map { CGFloat($0) }
        }
        let left = number("left") ?? 0
        let top = number("top") ?? 0
        let angle = IOFormat.degrees(fromStored: props["angle"])
        let kind: IOShape.Kind
        var known: Set<String> = ["left", "top", "angle", "fill", "oi"]

        switch data.kind {
        case "rect":
            kind = .rect(width: number("width") ?? 0, height: number("height") ?? 0)
            known.formUnion(["width", "height"])
        case "ellipse":
            kind = .ellipse(rx: number("rx") ?? 0, ry: number("ry") ?? 0)
            known.formUnion(["rx", "ry"])
        case "polygon":
            let points = (props["points"] ?? "").split(separator: " ").compactMap { pair -> CGPoint? in
                let parts = pair.split(separator: ",")
                guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
                return CGPoint(x: x, y: y)
            }
            guard points.count >= 3 else { return nil }
            kind = .polygon(points: points)
            known.insert("points")
        case "text":
            kind = .text(props["text"] ?? "", scale: number("scale") ?? 1, fontSize: number("fs"))
            known.formUnion(["text", "scale", "fs"])
        default:
            return nil
        }

        return IOShape(
            kind: kind,
            left: left,
            top: top,
            angle: data.kind == "polygon" ? 0 : angle,
            fill: props["fill"],
            ordinal: ordinal,
            extras: props.filter { !known.contains($0.key) }
        )
    }
}

// MARK: - Writing a note

extension IOCloze {
    /// A shape, or a group of shapes, that becomes one cloze.
    struct Unit {
        var shapes: [IOShape]
        var isTextLabel: Bool { shapes.count == 1 && shapes[0].isText }
        var ordinal: Int? { shapes.first?.ordinal }
    }

    /// Shapes in drawing order, with each group gathered where its first
    /// member sits.
    static func units(of shapes: [IOShape]) -> [Unit] {
        var units: [Unit] = []
        var groupIndex: [UUID: Int] = [:]
        for shape in shapes {
            if let group = shape.group {
                if let index = groupIndex[group] {
                    units[index].shapes.append(shape)
                } else {
                    groupIndex[group] = units.count
                    units.append(Unit(shapes: [shape]))
                }
            } else {
                units.append(Unit(shapes: [shape]))
            }
        }
        return units
    }

    /// How many cards the shapes make: every unit except a lone text label.
    static func cardCount(_ shapes: [IOShape]) -> Int {
        units(of: shapes).filter { !$0.isTextLabel }.count
    }

    /// `exportShapesToClozeDeletions`. Existing ordinals stay; a lone text
    /// label gets 0 (it is shown on every card, never asked); anything else
    /// new takes the lowest unused ordinal, then counts up from the highest.
    static func occlusions(_ shapes: [IOShape], occludeInactive: Bool) -> String {
        let units = Self.units(of: shapes)
        let existing = units.compactMap(\.ordinal)
        let maxOrdinal = max(existing.max() ?? 0, 0)
        var missing = maxOrdinal > 0 ? (1...maxOrdinal).filter { !existing.contains($0) } : []
        var next = maxOrdinal + 1

        var text = ""
        for unit in units {
            let ordinal: Int
            if let existingOrdinal = unit.ordinal {
                ordinal = existingOrdinal
            } else if unit.isTextLabel {
                ordinal = 0
            } else if !missing.isEmpty {
                ordinal = missing.removeFirst()
            } else {
                ordinal = next
                next += 1
            }
            for shape in unit.shapes {
                text += cloze(for: shape, ordinal: ordinal, occludeInactive: occludeInactive)
            }
        }
        return text
    }

    static func cloze(for shape: IOShape, ordinal: Int, occludeInactive: Bool) -> String {
        var pairs: [(String, String)] = []
        let type: String
        let defaultFill: String

        switch shape.kind {
        case .polygon(let points):
            let minX = points.map(\.x).min() ?? 0
            let minY = points.map(\.y).min() ?? 0
            pairs = [("left", IOFormat.number(minX)), ("top", IOFormat.number(minY))]
        default:
            pairs = [("left", IOFormat.number(shape.left)), ("top", IOFormat.number(shape.top))]
            if let angle = IOFormat.storedAngle(shape.angle) {
                pairs.append(("angle", String(angle)))
            }
        }

        switch shape.kind {
        case .rect(let width, let height):
            type = "rect"
            defaultFill = IOStyle.maskFill
            pairs += [("width", IOFormat.number(width)), ("height", IOFormat.number(height))]
        case .ellipse(let rx, let ry):
            type = "ellipse"
            defaultFill = IOStyle.maskFill
            pairs += [("rx", IOFormat.number(rx)), ("ry", IOFormat.number(ry))]
        case .polygon(let points):
            type = "polygon"
            defaultFill = IOStyle.maskFill
            pairs.append(("points", points.map { "\(IOFormat.number($0.x)),\(IOFormat.number($0.y))" }.joined(separator: " ")))
        case .text(let string, let scale, let fontSize):
            type = "text"
            defaultFill = IOStyle.textColor
            pairs += [
                ("text", string),
                ("scale", IOFormat.number(scale)),
                ("fs", IOFormat.number(fontSize ?? IOStyle.defaultFontSize)),
            ]
        }
        if let fill = shape.fill, fill.lowercased() != defaultFill {
            pairs.append(("fill", fill))
        }
        for key in shape.extras.keys.sorted() {
            pairs.append((key, shape.extras[key] ?? ""))
        }
        if occludeInactive {
            pairs.append(("oi", "1"))
        }

        let body = pairs.map { ":\($0.0)=\(IOFormat.escape($0.1))" }.joined()
        return "{{c\(ordinal)::image-occlusion:\(type)\(body)}}<br>"
    }
}
