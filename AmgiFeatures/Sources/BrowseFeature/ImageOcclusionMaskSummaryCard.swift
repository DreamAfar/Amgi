//
//  ImageOcclusionMaskSummaryCard.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 15.08.2026.
//

#if canImport(UIKit)
import SwiftUI
import UIKit
import Theme
import UI

// MARK: - imageOcclusionPreviewHeight

@MainActor
func imageOcclusionPreviewHeight(for image: UIImage, width: CGFloat) -> CGFloat {
    let ratio = image.size.height / max(image.size.width, 1)
    let idealHeight = width * ratio
    return min(max(idealHeight, 180), 260)
}

// MARK: - ImageOcclusionMaskSummaryCard

struct ImageOcclusionMaskSummaryCard: View {
    @Environment(\.palette) private var palette
    let image: UIImage
    let shapes: [IOShape]
    let action: () -> Void
    @State private var canvasWidth: CGFloat = 0

    private var cardCount: Int { IOCloze.cardCount(shapes) }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.md) {
            IOPreview(image: image, shapes: shapes)
                .frame(height: imageOcclusionPreviewHeight(for: image, width: canvasWidth))
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvasWidth = $0 }
                .clipShape(RoundedRectangle(cornerRadius: AmgiRadius.inset, style: .continuous))
                .allowsHitTesting(false)

            HStack(spacing: AmgiSpacing.md) {
                Text(cardCount == 0 ? "No masks yet" : "\(cardCount) masks", bundle: .module)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: action) {
                    Text("Edit", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(AmgiSpacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: AmgiRadius.pill, style: .continuous))
    }
}

private struct IOPreview: UIViewRepresentable {
    let image: UIImage
    let shapes: [IOShape]

    func makeUIView(context: Context) -> IOPreviewUIView {
        IOPreviewUIView(frame: .zero)
    }

    func updateUIView(_ view: IOPreviewUIView, context: Context) {
        view.image = image
        view.shapes = shapes
    }
}
#endif
