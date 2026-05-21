import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NoteImageOptimizationRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let originalByteCount: Int
    let suggestedFilename: String
    let confirmTitle: String
    let onConfirm: (NoteOptimizedImageResult) -> Void
    let onCancel: () -> Void
}

struct NoteOptimizedImageResult {
    let data: Data
    let filename: String
    let contentType: UTType
    let pixelSize: CGSize
    let fileSize: Int
}

struct NoteImageOptimizationSheet: View {
    let request: NoteImageOptimizationRequest

    @Environment(\.dismiss) private var dismiss
    @AppStorage("image_optimizer_custom_max_dimension") private var storedCustomMaxDimension = 640

    @State private var cropAspect: CropAspectPreset = .original
    @State private var maxDimension: Int = 1600
    @State private var selectedResolutionOption: ResolutionOption = .preset(1600)
    @State private var compressionQuality: Double = 0.82
    @State private var zoom: CGFloat = 1
    @State private var zoomAnchor: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragAnchor: CGSize = .zero
    @State private var outputPreview: NoteOptimizedImageResult?
    @State private var previewContainerSize: CGSize = .zero
    @State private var showCustomDimensionPrompt = false
    @State private var customDimensionText = ""
    @State private var customDimensionErrorMessage: String?
    @State private var showCustomDimensionError = false

    private var image: UIImage {
        request.image.amgiNormalizedOrientation()
    }

    private var originalPixelSize: CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private var originalLongestSide: Int {
        Int(max(originalPixelSize.width, originalPixelSize.height).rounded())
    }

    private let resolutionPresets = [0, 2048, 1600, 1280, 1024, 768]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    previewSection
                    infoSection
                    controlsSection
                }
                .padding(12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L("image_optimizer_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common_cancel")) {
                        request.onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.confirmTitle) {
                        guard let outputPreview else { return }
                        request.onConfirm(outputPreview)
                        dismiss()
                    }
                    .disabled(outputPreview == nil)
                }
            }
            .alert(L("image_optimizer_resolution_custom_title"), isPresented: $showCustomDimensionPrompt) {
                TextField(L("image_optimizer_resolution_custom_placeholder"), text: $customDimensionText)
                    .keyboardType(.numberPad)
                Button(L("common_cancel"), role: .cancel) {}
                Button(L("common_save")) {
                    applyCustomDimension()
                }
            } message: {
                Text(L("image_optimizer_resolution_custom_message", originalLongestSide))
            }
            .alert(L("common_error"), isPresented: $showCustomDimensionError) {
                Button(L("common_ok"), role: .cancel) {}
            } message: {
                Text(customDimensionErrorMessage ?? L("common_unknown_error"))
            }
            .onAppear {
                configureInitialResolutionSelection()
                refreshOutputPreview()
            }
            .onChange(of: cropAspect) {
                resetCropIfNeeded()
            }
            .onChange(of: maxDimension) {
                refreshOutputPreview()
            }
            .onChange(of: compressionQuality) {
                refreshOutputPreview()
            }
            .onChange(of: zoom) {
                refreshOutputPreview()
            }
            .onChange(of: offset) {
                refreshOutputPreview()
            }
            .onChange(of: previewContainerSize) {
                resetCropIfNeeded()
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("image_optimizer_crop_title"))
                .font(.headline)

            GeometryReader { geometry in
                let containerSize = geometry.size
                let cropRect = cropRect(in: containerSize)
                let resolvedOffset = boundedOffset(offset, cropRect: cropRect)
                let displaySize = displayedImageSize(for: cropRect, zoom: zoom)

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.secondarySystemBackground),
                                    Color(.systemBackground),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Color.black.opacity(0.16)

                    Image(uiImage: image)
                        .resizable()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(
                            x: cropRect.midX + resolvedOffset.width,
                            y: cropRect.midY + resolvedOffset.height
                        )
                        .gesture(dragGesture(for: cropRect))
                        .simultaneousGesture(magnificationGesture(for: cropRect))

                    CropMaskShape(cropRect: cropRect)
                        .fill(
                            Color.black.opacity(0.46),
                            style: FillStyle(eoFill: true)
                        )
                        .allowsHitTesting(false)

                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.94), lineWidth: 2)
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

                    VStack {
                        Spacer()
                        Text(L("image_optimizer_crop_hint"))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.28), in: Capsule())
                            .padding(.bottom, 14)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onAppear {
                    previewContainerSize = containerSize
                }
                .onChange(of: containerSize) {
                    previewContainerSize = containerSize
                }
            }
            .frame(height: 260)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var infoSection: some View {
        HStack(spacing: 10) {
            compactInfoChip(
                title: L("image_optimizer_original_title"),
                pixelSize: originalPixelSize,
                byteCount: request.originalByteCount
            )
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            compactInfoChip(
                title: L("image_optimizer_output_title"),
                pixelSize: outputPreview?.pixelSize ?? originalPixelSize,
                byteCount: outputPreview?.fileSize ?? request.originalByteCount,
                emphasizesValue: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func compactInfoChip(
        title: String,
        pixelSize: CGSize,
        byteCount: Int,
        emphasizesValue: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
                .font(.subheadline.weight(emphasizesValue ? .bold : .semibold))
            Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("image_optimizer_aspect_title"))
                    .font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CropAspectPreset.allCases) { preset in
                            Button {
                                cropAspect = preset
                            } label: {
                                Text(preset.localizedTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        cropAspect == preset
                                            ? Color.accentColor
                                            : Color(.tertiarySystemFill),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(cropAspect == preset ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("image_optimizer_resolution_title"))
                        .font(.subheadline.weight(.semibold))
                    Text(L("image_optimizer_resolution_original_longest_fmt", originalLongestSide))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(L("image_optimizer_resolution_no_upscale_hint"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(resolutionPresets, id: \.self) { value in
                        resolutionOptionButton(for: value)
                    }
                    customResolutionButton
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("image_optimizer_quality_title"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(compressionQuality * 100))%")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $compressionQuality, in: 0.45...0.95, step: 0.05)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func maxDimensionLabel(for value: Int) -> String {
        if value == 0 {
            return L("image_optimizer_resolution_original")
        }
        return "\(value)px"
    }

    private func resolutionOptionButton(for value: Int) -> some View {
        let option: ResolutionOption = value == 0 ? .original : .preset(value)
        let isSelected = selectedResolutionOption == option
        let isEnabled = isResolutionOptionEnabled(option)

        return Button {
            guard isEnabled else { return }
            selectedResolutionOption = option
            maxDimension = value
        } label: {
            Text(maxDimensionLabel(for: value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(resolutionButtonTextColor(isSelected: isSelected, isEnabled: isEnabled))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(resolutionButtonBackground(isSelected: isSelected, isEnabled: isEnabled))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var customResolutionButton: some View {
        let isSelected = selectedResolutionOption == .custom
        let customLabelValue = isSelected ? maxDimension : storedCustomMaxDimension

        return Button {
            customDimensionText = "\(max(1, min(storedCustomMaxDimension, max(originalLongestSide, 1))))"
            showCustomDimensionPrompt = true
        } label: {
            VStack(spacing: 4) {
                Text(L("image_optimizer_resolution_custom"))
                    .font(.subheadline.weight(.semibold))
                Text("\(customLabelValue)px")
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(resolutionButtonBackground(isSelected: isSelected, isEnabled: true))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func resolutionButtonBackground(isSelected: Bool, isEnabled: Bool) -> Color {
        if isSelected {
            return .accentColor
        }
        return isEnabled ? Color(.tertiarySystemFill) : Color(.quaternarySystemFill)
    }

    private func resolutionButtonTextColor(isSelected: Bool, isEnabled: Bool) -> Color {
        if isSelected {
            return .white
        }
        return isEnabled ? .primary : .secondary
    }

    private func isResolutionOptionEnabled(_ option: ResolutionOption) -> Bool {
        switch option {
        case .original:
            return true
        case .preset(let value):
            return value <= originalLongestSide
        case .custom:
            return true
        }
    }

    private func configureInitialResolutionSelection() {
        if case .custom = selectedResolutionOption {
            maxDimension = min(max(storedCustomMaxDimension, 1), max(originalLongestSide, 1))
            return
        }

        if maxDimension == 0 {
            selectedResolutionOption = .original
        } else if maxDimension > originalLongestSide {
            maxDimension = 0
            selectedResolutionOption = .original
        } else {
            selectedResolutionOption = .preset(maxDimension)
        }
    }

    private func applyCustomDimension() {
        let trimmed = customDimensionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0, value <= originalLongestSide else {
            customDimensionErrorMessage = L("image_optimizer_resolution_custom_invalid", originalLongestSide)
            showCustomDimensionError = true
            return
        }

        storedCustomMaxDimension = value
        selectedResolutionOption = .custom
        maxDimension = value
    }

    private func dragGesture(for cropRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: dragAnchor.width + value.translation.width,
                    height: dragAnchor.height + value.translation.height
                )
                offset = boundedOffset(proposed, cropRect: cropRect)
            }
            .onEnded { _ in
                dragAnchor = offset
            }
    }

    private func magnificationGesture(for cropRect: CGRect) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = min(max(zoomAnchor * value.magnification, 1), 4)
                zoom = proposed
                offset = boundedOffset(offset, cropRect: cropRect, zoom: proposed)
            }
            .onEnded { _ in
                zoomAnchor = zoom
            }
    }

    private func cropRect(in containerSize: CGSize) -> CGRect {
        let availableWidth = max(containerSize.width - 24, 1)
        let availableHeight = max(containerSize.height - 24, 1)
        let aspect = cropAspect.resolvedAspect(for: image.size)

        var width = availableWidth
        var height = width / aspect
        if height > availableHeight {
            height = availableHeight
            width = height * aspect
        }

        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func displayedImageSize(for cropRect: CGRect, zoom: CGFloat) -> CGSize {
        let imageSize = image.size
        let fillScale = max(cropRect.width / max(imageSize.width, 1), cropRect.height / max(imageSize.height, 1))
        return CGSize(
            width: imageSize.width * fillScale * zoom,
            height: imageSize.height * fillScale * zoom
        )
    }

    private func boundedOffset(_ proposed: CGSize, cropRect: CGRect, zoom: CGFloat? = nil) -> CGSize {
        let effectiveZoom = zoom ?? self.zoom
        let displaySize = displayedImageSize(for: cropRect, zoom: effectiveZoom)
        let maxX = max((displaySize.width - cropRect.width) / 2, 0)
        let maxY = max((displaySize.height - cropRect.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func resetCropIfNeeded() {
        zoom = 1
        zoomAnchor = 1
        offset = .zero
        dragAnchor = .zero
        refreshOutputPreview()
    }

    private func refreshOutputPreview() {
        guard previewContainerSize != .zero else { return }
        outputPreview = generateOutput()
    }

    private func generateOutput() -> NoteOptimizedImageResult? {
        let cropRect = cropRect(in: previewContainerSize)
        let imageRect = imagePixelCropRect(for: cropRect)
        guard let croppedImage = image.amgiCropped(to: imageRect) else { return nil }
        let resizedImage = croppedImage.amgiResized(maxDimension: maxDimension)
        guard let data = resizedImage.jpegData(compressionQuality: compressionQuality) else {
            return nil
        }

        return NoteOptimizedImageResult(
            data: data,
            filename: request.suggestedFilename.amgiOptimizedJPEGFilename(),
            contentType: .jpeg,
            pixelSize: CGSize(
                width: resizedImage.size.width * resizedImage.scale,
                height: resizedImage.size.height * resizedImage.scale
            ),
            fileSize: data.count
        )
    }

    private func imagePixelCropRect(for cropRect: CGRect) -> CGRect {
        let imageSize = image.size
        let fillScale = max(cropRect.width / max(imageSize.width, 1), cropRect.height / max(imageSize.height, 1)) * zoom
        let displaySize = CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
        let imageOrigin = CGPoint(
            x: cropRect.midX - displaySize.width / 2 + offset.width,
            y: cropRect.midY - displaySize.height / 2 + offset.height
        )

        let visibleX = max(0, (cropRect.minX - imageOrigin.x) / fillScale)
        let visibleY = max(0, (cropRect.minY - imageOrigin.y) / fillScale)
        let visibleWidth = min(imageSize.width - visibleX, cropRect.width / fillScale)
        let visibleHeight = min(imageSize.height - visibleY, cropRect.height / fillScale)

        return CGRect(
            x: visibleX * image.scale,
            y: visibleY * image.scale,
            width: visibleWidth * image.scale,
            height: visibleHeight * image.scale
        ).integral
    }
}

private enum ResolutionOption: Hashable {
    case original
    case preset(Int)
    case custom
}

private enum CropAspectPreset: String, CaseIterable, Identifiable {
    case original
    case square
    case standard4x3
    case widescreen16x9

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .original:
            return L("image_optimizer_aspect_original")
        case .square:
            return L("image_optimizer_aspect_square")
        case .standard4x3:
            return "4:3"
        case .widescreen16x9:
            return "16:9"
        }
    }

    func resolvedAspect(for imageSize: CGSize) -> CGFloat {
        switch self {
        case .original:
            return max(imageSize.width / max(imageSize.height, 1), 0.01)
        case .square:
            return 1
        case .standard4x3:
            return 4.0 / 3.0
        case .widescreen16x9:
            return 16.0 / 9.0
        }
    }
}

private struct CropMaskShape: Shape {
    let cropRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: 24, height: 24))
        path.addRoundedRect(in: cropRect, cornerSize: CGSize(width: 18, height: 18))
        return path
    }
}

private extension UIImage {
    func amgiNormalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func amgiCropped(to rect: CGRect) -> UIImage? {
        guard let cgImage else { return nil }
        let bounded = CGRect(
            x: max(0, rect.origin.x),
            y: max(0, rect.origin.y),
            width: min(rect.width, CGFloat(cgImage.width) - max(0, rect.origin.x)),
            height: min(rect.height, CGFloat(cgImage.height) - max(0, rect.origin.y))
        )
        guard bounded.width > 0, bounded.height > 0,
              let cropped = cgImage.cropping(to: bounded) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    func amgiResized(maxDimension: Int) -> UIImage {
        guard maxDimension > 0 else { return self }

        let pixelWidth = size.width * scale
        let pixelHeight = size.height * scale
        let longestSide = max(pixelWidth, pixelHeight)
        guard longestSide > CGFloat(maxDimension) else { return self }

        let resizeScale = CGFloat(maxDimension) / longestSide
        let targetSize = CGSize(
            width: floor(size.width * resizeScale),
            height: floor(size.height * resizeScale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.systemBackground.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private extension String {
    func amgiOptimizedJPEGFilename() -> String {
        let url = URL(fileURLWithPath: self)
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? "image.jpg" : "\(base)-optimized.jpg"
    }
}
