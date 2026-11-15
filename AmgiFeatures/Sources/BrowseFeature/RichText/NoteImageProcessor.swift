//
//  NoteImageProcessor.swift
//  BrowseFeature
//

#if canImport(UIKit)
import CryptoKit
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// An image picked for a note field, before it is cropped, resized and
/// compressed.
struct NoteImageCandidate: Identifiable, @unchecked Sendable {
    let id = UUID()
    /// Decoded, with its orientation applied when drawn.
    let image: UIImage
    /// The file as picked — kept so an untouched image can be stored
    /// byte for byte.
    let originalData: Data
    /// The picked file's extension when it's a format every Anki client
    /// shows (jpg, png, gif, webp, svg); nil otherwise (HEIC from the
    /// camera, TIFF, …), in which case the image is always re-encoded.
    let passthroughExtension: String?

    /// Size in pixels, orientation applied.
    var pixelSize: CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    init?(data: Data) {
        guard let image = UIImage(data: data) else { return nil }
        self.image = image
        self.originalData = data
        self.passthroughExtension = NoteImageProcessor.passthroughExtension(for: data)
    }
}

/// How a picked image is prepared for the note.
struct NoteImageSettings: Equatable, Sendable {
    /// The kept part of the image as a unit rectangle (0…1 on both axes).
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var size = Size.large
    var quality = Quality.high

    /// Cap on the longer edge, in pixels.
    enum Size: Int, CaseIterable, Sendable {
        case original = 0
        case large = 1920
        case medium = 1280
        case small = 800

        var maxDimension: CGFloat? { self == .original ? nil : CGFloat(rawValue) }
    }

    enum Quality: CaseIterable, Sendable {
        /// Keep the picked file's own encoding wherever possible.
        case original
        case high
        case medium
        case low

        var jpegQuality: CGFloat {
            switch self {
            case .original: 0.95
            case .high: 0.88
            case .medium: 0.72
            case .low: 0.5
            }
        }
    }

    /// Photos are capped and recompressed by default — a camera shot is
    /// several megabytes that every sync then carries. Screenshots and
    /// graphics (PNG, GIF, WebP) keep their encoding, since recompressing
    /// them as JPEG smears text and drops animation.
    static func suggested(for candidate: NoteImageCandidate) -> NoteImageSettings {
        var settings = NoteImageSettings()
        if let kept = candidate.passthroughExtension, kept != "jpg" {
            settings.quality = .original
        }
        return settings
    }

    var isCropped: Bool {
        crop.minX > 0.001 || crop.minY > 0.001 || crop.width < 0.999 || crop.height < 0.999
    }
}

/// The encoded image, ready to store in the media folder.
struct NoteImageOutput: Sendable {
    let data: Data
    let fileExtension: String
    let pixelSize: CGSize

    /// Named after the content's hash, like Anki's pasted images, so the
    /// same image inserted twice is stored once.
    var filename: String {
        let digest = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "paste-\(digest).\(fileExtension)"
    }
}

enum NoteImageProcessor {
    /// Formats stored as picked. Everything else is converted, because not
    /// every Anki client can show it.
    private static let passthroughTypes: [UTType: String] = [
        .jpeg: "jpg", .png: "png", .gif: "gif", .webP: "webp", .svg: "svg",
    ]

    static func passthroughExtension(for data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier) else { return nil }
        return passthroughTypes[type]
    }

    /// The crop in pixels: the unit rectangle scaled to the image, snapped
    /// to whole pixels and kept inside it.
    static func pixelCrop(_ crop: CGRect, in pixelSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: pixelSize)
        let scaled = CGRect(
            x: crop.minX * pixelSize.width,
            y: crop.minY * pixelSize.height,
            width: crop.width * pixelSize.width,
            height: crop.height * pixelSize.height
        ).integral.intersection(bounds)
        return scaled.isNull || scaled.isEmpty ? bounds : scaled
    }

    /// `size` scaled down so its longer edge is at most `maxDimension`.
    /// Never scales up.
    static func fitted(_ size: CGSize, maxDimension: CGFloat?) -> CGSize {
        let longest = max(size.width, size.height)
        guard let maxDimension, longest > maxDimension, longest > 0 else {
            return CGSize(width: size.width.rounded(), height: size.height.rounded())
        }
        let scale = maxDimension / longest
        return CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
    }

    /// The size the output will have, without rendering it.
    static func outputPixelSize(for candidate: NoteImageCandidate, settings: NoteImageSettings) -> CGSize {
        fitted(pixelCrop(settings.crop, in: candidate.pixelSize).size, maxDimension: settings.size.maxDimension)
    }

    /// Whether the picked file can be stored as it is: nothing about it is
    /// being changed, and it's in a format every client shows.
    static func keepsOriginalFile(_ candidate: NoteImageCandidate, settings: NoteImageSettings) -> Bool {
        guard candidate.passthroughExtension != nil, settings.quality == .original, !settings.isCropped else {
            return false
        }
        return outputPixelSize(for: candidate, settings: settings) == fitted(candidate.pixelSize, maxDimension: nil)
    }

    /// Crops, resizes and encodes. Images with transparency stay PNG;
    /// everything else becomes JPEG at the chosen quality. Safe to call
    /// off the main thread.
    static func output(for candidate: NoteImageCandidate, settings: NoteImageSettings) -> NoteImageOutput? {
        if keepsOriginalFile(candidate, settings: settings), let fileExtension = candidate.passthroughExtension {
            return NoteImageOutput(
                data: candidate.originalData, fileExtension: fileExtension, pixelSize: candidate.pixelSize
            )
        }

        let crop = pixelCrop(settings.crop, in: candidate.pixelSize)
        let target = fitted(crop.size, maxDimension: settings.size.maxDimension)
        let scale = target.width / crop.width
        let hasAlpha = candidate.passthroughExtension == "png" && Self.hasAlpha(candidate.image)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !hasAlpha
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // Draw the whole image scaled, shifted so the crop's corner
            // lands on the origin; drawing through UIImage applies the
            // photo's orientation.
            candidate.image.draw(in: CGRect(
                x: -crop.minX * scale,
                y: -crop.minY * scale,
                width: candidate.pixelSize.width * scale,
                height: candidate.pixelSize.height * scale
            ))
        }

        if hasAlpha, let data = rendered.pngData() {
            return NoteImageOutput(data: data, fileExtension: "png", pixelSize: target)
        }
        guard let data = rendered.jpegData(compressionQuality: settings.quality.jpegQuality) else { return nil }
        return NoteImageOutput(data: data, fileExtension: "jpg", pixelSize: target)
    }

    private static func hasAlpha(_ image: UIImage) -> Bool {
        guard let alpha = image.cgImage?.alphaInfo else { return false }
        switch alpha {
        case .first, .last, .premultipliedFirst, .premultipliedLast: return true
        default: return false
        }
    }
}

/// Geometry of the crop overlay, in unit coordinates so it's independent
/// of how large the image is drawn.
enum NoteImageCropGeometry {
    enum Corner: CaseIterable, Sendable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// Where an image of `imageSize` sits when fitted inside `container`.
    static func fittedFrame(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// `rect` moved by `delta`, stopped at the image's edges.
    static func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        var result = rect
        result.origin.x = min(max(rect.minX + delta.width, 0), 1 - rect.width)
        result.origin.y = min(max(rect.minY + delta.height, 0), 1 - rect.height)
        return result
    }

    /// `rect` with one corner dragged by `delta`; the opposite corner stays
    /// put. The dragged corner stops at the image's edges and `minSize`
    /// short of the opposite corner.
    static func resized(_ rect: CGRect, corner: Corner, by delta: CGSize, minSize: CGSize) -> CGRect {
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch corner {
        case .topLeading, .bottomLeading:
            minX = min(max(minX + delta.width, 0), maxX - minSize.width)
        case .topTrailing, .bottomTrailing:
            maxX = max(min(maxX + delta.width, 1), minX + minSize.width)
        }
        switch corner {
        case .topLeading, .topTrailing:
            minY = min(max(minY + delta.height, 0), maxY - minSize.height)
        case .bottomLeading, .bottomTrailing:
            maxY = max(min(maxY + delta.height, 1), minY + minSize.height)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func point(of corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeading: CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
#endif
