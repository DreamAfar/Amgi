//
//  IOCanvasView.swift
//  BrowseFeature
//
//  The editing surface. The image sits in a zooming scroll view; masks,
//  handles and drafts are drawn by an overlay above it at screen resolution,
//  so a large photo never needs a full-size drawing layer. One finger draws
//  or edits; two fingers pan and pinch, as in Anki's touch handling.
//

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Lets the SwiftUI toolbar drive the canvas zoom.
@MainActor
final class IOCanvasController {
    fileprivate weak var canvas: IOCanvasUIView?

    func zoomIn() { canvas?.zoom(by: 1.5) }
    func zoomOut() { canvas?.zoom(by: 1 / 1.5) }
    func zoomToFit() { canvas?.zoomToFit(animated: true) }
}

struct IOCanvasView: UIViewRepresentable {
    let image: UIImage
    let model: IOEditorModel
    let controller: IOCanvasController
    let accent: UIColor

    func makeUIView(context: Context) -> IOCanvasUIView {
        let view = IOCanvasUIView(image: image, model: model)
        controller.canvas = view
        return view
    }

    func updateUIView(_ view: IOCanvasUIView, context: Context) {
        // Reading these registers them with SwiftUI's observation, so any
        // change to the document or the drafts redraws the overlay.
        _ = model.shapes
        _ = model.selection
        _ = model.draftPolygon
        _ = model.draftShape
        _ = model.marquee
        _ = model.translucent
        _ = model.currentTool
        view.accent = accent
        view.redraw()
    }
}

final class IOCanvasUIView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let imageView: UIImageView
    private let overlay = IOOverlayView()
    private let model: IOEditorModel
    private var fittedBounds: CGSize = .zero
    private var lastTap: (time: TimeInterval, point: CGPoint)?

    var accent: UIColor = .tintColor {
        didSet { overlay.accent = accent }
    }

    /// Touch slop, in image points at the current zoom.
    private var tolerance: CGFloat { 22 / scrollView.zoomScale }
    private var knobOffset: CGFloat { 32 / scrollView.zoomScale }

    init(image: UIImage, model: IOEditorModel) {
        self.model = model
        imageView = UIImageView(image: image)
        super.init(frame: .zero)

        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.addSubview(imageView)
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.contentSize = image.size
        // One finger belongs to the tools; panning and pinching take two.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        addSubview(scrollView)

        overlay.model = model
        overlay.isUserInteractionEnabled = false
        overlay.isOpaque = false
        addSubview(overlay)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        scrollView.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        scrollView.addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        overlay.frame = bounds
        if bounds.size != fittedBounds, bounds.width > 0, bounds.height > 0 {
            fittedBounds = bounds.size
            zoomToFit(animated: false)
        }
        redraw()
    }

    // MARK: Zoom

    private var fitScale: CGFloat {
        let size = imageView.bounds.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return min(bounds.width / size.width, bounds.height / size.height)
    }

    func zoomToFit(animated: Bool) {
        scrollView.minimumZoomScale = fitScale
        scrollView.maximumZoomScale = fitScale * 8
        scrollView.setZoomScale(fitScale, animated: animated)
        centerImage()
    }

    func zoom(by factor: CGFloat) {
        let target = min(max(scrollView.zoomScale * factor, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        let center = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
        let focus = scrollView.convert(center, to: imageView)
        let width = scrollView.bounds.width / target, height = scrollView.bounds.height / target
        scrollView.zoom(to: CGRect(x: focus.x - width / 2, y: focus.y - height / 2, width: width, height: height), animated: true)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        redraw()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        redraw()
    }

    /// Keeps a zoomed-out image centred instead of pinned to the top left.
    private func centerImage() {
        let content = imageView.frame.size
        let horizontal = max(0, (scrollView.bounds.width - content.width) / 2)
        let vertical = max(0, (scrollView.bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func redraw() {
        overlay.imageToView = imageToOverlayTransform
        overlay.zoom = scrollView.zoomScale
        overlay.knobOffset = knobOffset
        overlay.setNeedsDisplay()
    }

    private var imageToOverlayTransform: CGAffineTransform {
        let origin = imageView.convert(CGPoint.zero, to: overlay)
        let scale = scrollView.zoomScale
        return CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
    }

    // MARK: Gestures

    /// Lets a pinch or two-finger pan start while a one-finger drag is
    /// under way; `handlePan` then abandons the drag.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        other === scrollView.pinchGestureRecognizer || other === scrollView.panGestureRecognizer
    }

    private var isZoomGestureActive: Bool {
        let states: [UIGestureRecognizer.State] = [.began, .changed]
        return states.contains(scrollView.pinchGestureRecognizer?.state ?? .possible)
            || states.contains(scrollView.panGestureRecognizer.state)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: imageView)
        let now = Date.timeIntervalSinceReferenceDate
        if let lastTap, now - lastTap.time < 0.35, hypot(lastTap.point.x - point.x, lastTap.point.y - point.y) < tolerance {
            self.lastTap = nil
            model.doubleTap(at: point, tolerance: tolerance)
            return
        }
        lastTap = (now, point)
        model.tap(at: point, tolerance: tolerance)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: imageView)
        switch gesture.state {
        case .began:
            let translation = gesture.translation(in: imageView)
            let start = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            model.dragBegan(at: start, tolerance: tolerance, knobOffset: knobOffset)
            model.dragChanged(to: point)
        case .changed:
            // A second finger means the user is zooming, not drawing: drop
            // the half-made shape or move, as Anki does on pinch.
            if gesture.numberOfTouches > 1 || isZoomGestureActive {
                gesture.isEnabled = false
                gesture.isEnabled = true
                return
            }
            model.dragChanged(to: point)
        case .ended:
            model.dragEnded(at: point)
        case .cancelled, .failed:
            model.dragCancelled()
        default:
            break
        }
    }
}

// MARK: - Overlay

/// Draws the document, the drafts and the selection chrome at screen
/// resolution on top of the zoomed image.
final class IOOverlayView: UIView {
    weak var model: IOEditorModel?
    var imageToView: CGAffineTransform = .identity
    var zoom: CGFloat = 1
    var knobOffset: CGFloat = 32
    var accent: UIColor = .tintColor

    override func draw(_ rect: CGRect) {
        guard let model, let context = UIGraphicsGetCurrentContext() else { return }
        let size = model.imageSize

        IORenderer.draw(model.shapes, imageSize: size, transform: imageToView, scale: zoom, translucent: model.translucent, in: context)
        if let draft = model.draftShape {
            IORenderer.draw(draft, imageSize: size, transform: imageToView, scale: zoom, translucent: true, in: context)
        }
        drawDraftPolygon(model.draftPolygon, in: context)
        drawSelection(model, in: context)
        if let marquee = model.marquee {
            let rect = marquee.applying(imageToView)
            context.setFillColor(accent.withAlphaComponent(0.12).cgColor)
            context.fill(rect)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(1)
            context.stroke(rect)
        }
    }

    private func drawDraftPolygon(_ points: [CGPoint], in context: CGContext) {
        guard !points.isEmpty else { return }
        let viewPoints = points.map { $0.applying(imageToView) }
        context.saveGState()
        if viewPoints.count >= 3 {
            context.beginPath()
            context.addLines(between: viewPoints)
            context.closePath()
            context.setFillColor(UIColor.gray.withAlphaComponent(0.3).cgColor)
            context.fillPath()
        }
        context.beginPath()
        context.addLines(between: viewPoints)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(2)
        context.strokePath()
        for (index, point) in viewPoints.enumerated() {
            let dot = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
            context.setFillColor(UIColor.white.cgColor)
            context.fillEllipse(in: dot)
            // The first point is the one to tap to close the shape.
            context.setStrokeColor(index == 0 ? UIColor.systemRed.cgColor : UIColor.darkGray.cgColor)
            context.setLineWidth(index == 0 ? 2.5 : 1.5)
            context.strokeEllipse(in: dot)
        }
        context.restoreGState()
    }

    private func drawSelection(_ model: IOEditorModel, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(1.5)

        if let shape = model.editableShape {
            let box = shape.box(in: model.imageSize)
            let toView = box.transform.concatenating(imageToView)
            let outline = CGRect(origin: .zero, size: box.size)
            let corners = [
                CGPoint(x: outline.minX, y: outline.minY), CGPoint(x: outline.maxX, y: outline.minY),
                CGPoint(x: outline.maxX, y: outline.maxY), CGPoint(x: outline.minX, y: outline.maxY),
            ].map { $0.applying(toView) }
            context.beginPath()
            context.addLines(between: corners + [corners[0]])
            context.strokePath()

            let topCenter = CGPoint(x: box.size.width / 2, y: 0).applying(toView)
            let knob = IOHandle.rotate.localPosition(in: box.size, knobOffset: knobOffset).applying(toView)
            context.beginPath()
            context.move(to: topCenter)
            context.addLine(to: knob)
            context.strokePath()

            for handle in shape.handles {
                let center = handle.localPosition(in: box.size, knobOffset: knobOffset).applying(toView)
                let radius: CGFloat = handle == .rotate ? 8 : 6
                let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: dot)
                context.strokeEllipse(in: dot)
            }
        } else if let bounds = model.selectionBounds {
            // Groups and multiple shapes move together; Anki offers no
            // rotation for them, so there are no handles here either.
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(bounds.applying(imageToView).insetBy(dx: -4, dy: -4))
        }
    }
}
#endif
