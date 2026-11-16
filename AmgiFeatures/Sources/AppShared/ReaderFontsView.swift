//
//  ReaderFontsView.swift
//  AppShared
//

import SwiftUI
import Theme
import UniformTypeIdentifiers

/// Lists, imports and deletes the readers' custom fonts. Reached from the
/// font settings of both readers, so a font imported in one shows up in the
/// other.
@Observable
@MainActor
public final class ReaderFontsModel {
    public private(set) var fonts: [ReaderCustomFont] = []
    var errorMessage: String?

    public init() {}

    public func reload() {
        fonts = ReaderCustomFonts.all()
        fonts.forEach(ReaderCustomFonts.registerForPreview)
    }

    func importFonts(from urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            do {
                try ReaderCustomFonts.importFont(from: url)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        reload()
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    func delete(_ font: ReaderCustomFont) {
        do {
            try ReaderCustomFonts.delete(font)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }
}

public struct ReaderFontsView: View {
    @State private var model = ReaderFontsModel()
    @State private var isImporting = false
    @State private var pendingDelete: ReaderCustomFont?

    @Environment(\.palette) private var palette

    public init() {}

    /// Font files CoreText can read. WOFF has no system type on every OS
    /// version, so it's matched by extension.
    private static let importTypes: [UTType] = [.font]
        + ["woff", "woff2"].compactMap { UTType(filenameExtension: $0) }

    public var body: some View {
        List {
            if model.fonts.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Custom Fonts", bundle: .module), systemImage: "textformat")
                } description: {
                    Text("Import TrueType, OpenType or WOFF fonts to read books in them.", bundle: .module)
                } actions: {
                    Button(String(localized: "Import Font", bundle: .module)) { isImporting = true }
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.fonts) { font in
                        row(font)
                            .swipeActions {
                                Button(String(localized: "Delete", bundle: .module), role: .destructive) {
                                    pendingDelete = font
                                }
                            }
                            .contextMenu {
                                Button(String(localized: "Delete", bundle: .module), systemImage: "trash", role: .destructive) {
                                    pendingDelete = font
                                }
                            }
                    }
                } footer: {
                    Text("Fonts stay on this device and are available in both readers. A book set in a deleted font goes back to the default.", bundle: .module)
                }
            }
        }
        .navigationTitle(String(localized: "Custom Fonts", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label(String(localized: "Import Font", bundle: .module), systemImage: "plus")
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.importTypes, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.importFonts(from: urls) }
        }
        .confirmationDialog(
            String(localized: "Delete Font?", bundle: .module),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { font in
            Button(String(localized: "Delete “\(font.displayName)”", bundle: .module), role: .destructive) {
                model.delete(font)
            }
        }
        .alert(
            String(localized: "Couldn't Import Font", bundle: .module),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button(String(localized: "OK", bundle: .module), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear { model.reload() }
    }

    private func row(_ font: ReaderCustomFont) -> some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
            Text(font.displayName)
                .amgiFont(.bodyEmphasis)
                .foregroundStyle(palette.textPrimary)
            // The sample in the font itself, so fonts can be told apart.
            Text(verbatim: "Aa Bb 永 あア 가나")
                .font(.custom(font.postScriptName, size: 20, relativeTo: .title3))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text(verbatim: "\(font.fileName) · \(ByteCountFormatter.string(fromByteCount: font.fileSize, countStyle: .file))")
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, AmgiSpacing.xxs)
        .accessibilityElement(children: .combine)
    }
}
