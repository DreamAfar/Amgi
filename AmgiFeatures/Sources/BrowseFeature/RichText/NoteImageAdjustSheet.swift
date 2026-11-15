//
//  NoteImageAdjustSheet.swift
//  BrowseFeature
//

#if canImport(UIKit)
import Foundation
import SwiftUI
import Theme
import UIKit

/// Shown after an image is picked and before it goes into the note: crop
/// it, cap its resolution, and choose how hard to compress it. The footer
/// shows the size the result will actually have, so the trade-off is
/// visible before inserting.
struct NoteImageAdjustSheet: View {
    let candidate: NoteImageCandidate
    let onInsert: (NoteImageOutput) -> Void
    let onCancel: () -> Void

    @Environment(\.palette) private var palette
    @State private var settings: NoteImageSettings
    @State private var result: NoteImageOutput?
    @State private var isPreparing = false

    init(
        candidate: NoteImageCandidate,
        onInsert: @escaping (NoteImageOutput) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.candidate = candidate
        self.onInsert = onInsert
        self.onCancel = onCancel
        _settings = State(initialValue: NoteImageSettings.suggested(for: candidate))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NoteImageCropView(image: candidate.image, crop: $settings.crop)
                    .padding(AmgiSpacing.lg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
            }
            .background(palette.background)
            .navigationTitle(String(localized: "Adjust Image", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Insert", bundle: .module)) { insert() }
                        .disabled(isPreparing)
                }
            }
            // Re-encode a moment after the settings settle, so dragging the
            // crop doesn't encode on every frame.
            .task(id: settings) {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let output = await Self.prepare(candidate, settings)
                guard !Task.isCancelled else { return }
                result = output
            }
        }
        .interactiveDismissDisabled()
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.md) {
            option(String(localized: "Resolution", bundle: .module)) {
                Picker(String(localized: "Resolution", bundle: .module), selection: $settings.size) {
                    ForEach(NoteImageSettings.Size.allCases, id: \.self) { size in
                        Text(Self.title(for: size)).tag(size)
                    }
                }
            }
            option(String(localized: "Quality", bundle: .module)) {
                Picker(String(localized: "Quality", bundle: .module), selection: $settings.quality) {
                    ForEach(NoteImageSettings.Quality.allCases, id: \.self) { quality in
                        Text(Self.title(for: quality)).tag(quality)
                    }
                }
            }

            HStack {
                Text(summary)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
                Spacer()
                if settings.isCropped {
                    Button(String(localized: "Reset Crop", bundle: .module)) {
                        settings.crop = NoteImageCropGeometry.unit
                    }
                    .amgiFont(.caption)
                }
            }
        }
        .padding(AmgiSpacing.lg)
        .background(palette.surface)
    }

    private func option(_ title: String, @ViewBuilder picker: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
            Text(title)
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)
            picker()
                .pickerStyle(.segmented)
                .labelsHidden()
        }
    }

    /// "1920 × 1440 · 412 KB" once encoded; the dimensions alone until then.
    private var summary: String {
        let size = result?.pixelSize ?? NoteImageProcessor.outputPixelSize(for: candidate, settings: settings)
        let dimensions = "\(Int(size.width)) × \(Int(size.height))"
        guard let result else { return dimensions }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(result.data.count), countStyle: .file)
        return "\(dimensions) · \(bytes)"
    }

    private func insert() {
        isPreparing = true
        Task {
            let output = await Self.prepare(candidate, settings)
            isPreparing = false
            if let output { onInsert(output) }
        }
    }

    private static func prepare(_ candidate: NoteImageCandidate, _ settings: NoteImageSettings) async -> NoteImageOutput? {
        await Task.detached(priority: .userInitiated) {
            NoteImageProcessor.output(for: candidate, settings: settings)
        }.value
    }

    private static func title(for size: NoteImageSettings.Size) -> String {
        switch size {
        case .original: String(localized: "Original", bundle: .module)
        case .large, .medium, .small: "\(size.rawValue)"
        }
    }

    private static func title(for quality: NoteImageSettings.Quality) -> String {
        switch quality {
        case .original: String(localized: "Original", bundle: .module)
        case .high: String(localized: "High", bundle: .module)
        case .medium: String(localized: "Medium", bundle: .module)
        case .low: String(localized: "Low", bundle: .module)
        }
    }
}
#endif
