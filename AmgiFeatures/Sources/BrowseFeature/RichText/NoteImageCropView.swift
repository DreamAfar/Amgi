//
//  NoteImageCropView.swift
//  BrowseFeature
//

#if canImport(UIKit)
import Foundation
import SwiftUI
import Theme
import UIKit

/// The image with a crop rectangle over it: drag inside to move it, drag a
/// corner to resize. The part outside the rectangle is dimmed. `crop` is a
/// unit rectangle, so it doesn't depend on the size the image is shown at.
struct NoteImageCropView: View {
    let image: UIImage
    @Binding var crop: CGRect

    @Environment(\.palette) private var palette
    /// The crop when the current drag began; drags apply to this, so the
    /// rectangle tracks the finger rather than accumulating error.
    @State private var dragOrigin: CGRect?

    private static let handleSize: CGFloat = 22
    private static let handleHitSize: CGFloat = 44
    /// Smallest crop, in points on screen, so the handles never overlap.
    private static let minimumSide: CGFloat = 48

    var body: some View {
        GeometryReader { proxy in
            let frame = NoteImageCropGeometry.fittedFrame(imageSize: image.size, in: proxy.size)
            let selection = CGRect(
                x: frame.minX + crop.minX * frame.width,
                y: frame.minY + crop.minY * frame.height,
                width: crop.width * frame.width,
                height: crop.height * frame.height
            )

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .accessibilityHidden(true)

                // Everything of the image outside the selection.
                Path { path in
                    path.addRect(frame)
                    path.addRect(selection)
                }
                .fill(palette.background.opacity(0.65), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(palette.accent, lineWidth: 2)
                    .contentShape(Rectangle())
                    .frame(width: selection.width, height: selection.height)
                    .offset(x: selection.minX, y: selection.minY)
                    .gesture(drag(in: frame) { origin, delta in
                        NoteImageCropGeometry.moved(origin, by: delta)
                    })
                    .accessibilityLabel(Text("Crop area", bundle: .module))

                ForEach(NoteImageCropGeometry.Corner.allCases, id: \.self) { corner in
                    let point = NoteImageCropGeometry.point(of: corner, in: selection)
                    Circle()
                        .fill(palette.accent)
                        .frame(width: Self.handleSize, height: Self.handleSize)
                        .frame(width: Self.handleHitSize, height: Self.handleHitSize)
                        .contentShape(Rectangle())
                        .offset(x: point.x - Self.handleHitSize / 2, y: point.y - Self.handleHitSize / 2)
                        .gesture(drag(in: frame) { origin, delta in
                            NoteImageCropGeometry.resized(
                                origin,
                                corner: corner,
                                by: delta,
                                minSize: CGSize(
                                    width: min(Self.minimumSide / max(frame.width, 1), 1),
                                    height: min(Self.minimumSide / max(frame.height, 1), 1)
                                )
                            )
                        })
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// A drag whose translation, converted to unit coordinates of the
    /// displayed image, is applied to the crop as it was when the drag began.
    private func drag(
        in frame: CGRect,
        apply: @escaping (_ origin: CGRect, _ delta: CGSize) -> CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard frame.width > 0, frame.height > 0 else { return }
                let origin = dragOrigin ?? crop
                if dragOrigin == nil { dragOrigin = origin }
                crop = apply(origin, CGSize(
                    width: value.translation.width / frame.width,
                    height: value.translation.height / frame.height
                ))
            }
            .onEnded { _ in dragOrigin = nil }
    }
}
#endif
