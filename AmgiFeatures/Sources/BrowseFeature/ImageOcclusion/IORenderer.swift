//
//  IORenderer.swift
//  BrowseFeature
//
//  Draws masks the way Anki's editor shows them: mask yellow (or the
//  shape's own fill) with a thin dark outline that stays one point wide at
//  any zoom, and text labels as black Arial on a white box.
//

#if canImport(UIKit)
import Theme
import UIKit

enum IORenderer {
    static let borderColor = UIColor(amgiHex: IOStyle.border) ?? .darkGray

    /// Draws `shapes` into the current UIKit context. `transform` maps image
    /// points to the view; `scale` is its zoom, used to keep outlines thin.
    static func draw(
        _ shapes: [IOShape],
        imageSize: CGSize,
        transform: CGAffineTransform,
        scale: CGFloat,
        translucent: Bool,
        in context: CGContext
    ) {
        for shape in shapes {
            draw(shape, imageSize: imageSize, transform: transform, scale: scale, translucent: translucent, in: context)
        }
    }

    static func draw(
        _ shape: IOShape,
        imageSize: CGSize,
        transform: CGAffineTransform,
        scale: CGFloat,
        translucent: Bool,
        in context: CGContext
    ) {
        let alpha: CGFloat = translucent ? 0.4 : 1
        let fill = (UIColor(amgiHex: shape.effectiveFill) ?? .yellow).withAlphaComponent(alpha)
        let lineWidth = 1 / max(scale, 0.0001)

        context.saveGState()
        context.concatenate(transform)
        defer { context.restoreGState() }

        switch shape.kind {
        case .polygon:
            let points = shape.pixelPoints(in: imageSize)
            guard let first = points.first else { return }
            context.beginPath()
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.closePath()
            fillAndStroke(context, fill: fill, lineWidth: lineWidth, alpha: alpha)
        case .rect:
            let box = shape.box(in: imageSize)
            context.concatenate(box.transform)
            context.addRect(CGRect(origin: .zero, size: box.size))
            fillAndStroke(context, fill: fill, lineWidth: lineWidth, alpha: alpha)
        case .ellipse:
            let box = shape.box(in: imageSize)
            context.concatenate(box.transform)
            context.addEllipse(in: CGRect(origin: .zero, size: box.size))
            fillAndStroke(context, fill: fill, lineWidth: lineWidth, alpha: alpha)
        case .text(let text, let labelScale, _):
            let box = shape.box(in: imageSize)
            let pixelSize = shape.fontPixelSize(in: imageSize)
            context.concatenate(box.transform)
            context.scaleBy(x: labelScale, y: labelScale)
            let unscaled = IOTextMetrics.unscaledSize(text: text, pixelSize: pixelSize)
            context.setFillColor((UIColor(amgiHex: IOStyle.textBackground) ?? .white).withAlphaComponent(alpha).cgColor)
            context.fill(CGRect(origin: .zero, size: unscaled))
            let font = IOTextMetrics.font(pixelSize: pixelSize)
            let lineHeight = IOTextMetrics.lineHeight(pixelSize: pixelSize)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fill]
            UIGraphicsPushContext(context)
            for (index, line) in IOTextMetrics.lines(text).enumerated() {
                (line as NSString).draw(at: CGPoint(x: 0, y: CGFloat(index) * lineHeight), withAttributes: attributes)
            }
            UIGraphicsPopContext()
        }
    }

    private static func fillAndStroke(_ context: CGContext, fill: UIColor, lineWidth: CGFloat, alpha: CGFloat) {
        guard let path = context.path else { return }
        context.setFillColor(fill.cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(borderColor.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }
}

/// Non-interactive preview of an occlusion document: the image aspect-fit
/// with its masks on top. Used by the add/edit forms.
final class IOPreviewUIView: UIView {
    var image: UIImage? { didSet { setNeedsDisplay() } }
    var shapes: [IOShape] = [] { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        guard let image, let context = UIGraphicsGetCurrentContext(),
              image.size.width > 0, image.size.height > 0 else { return }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        image.draw(in: CGRect(origin: origin, size: size))
        let transform = CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
        IORenderer.draw(shapes, imageSize: image.size, transform: transform, scale: scale, translucent: false, in: context)
    }
}
#endif
