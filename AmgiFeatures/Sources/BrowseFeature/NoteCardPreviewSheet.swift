//
//  NoteCardPreviewSheet.swift
//  BrowseFeature
//

import AnkiKit
import AppShared
import SwiftUI
import Theme
import UI

/// Shows the note being edited as its cards will look — before saving —
/// drawn by the reviewer's own card view through `\.cardPreview`, so the
/// card CSS, media, MathJax and night mode match a real review.
struct NoteCardPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @Environment(\.cardPreview) private var cardPreview

    @State private var model: NoteCardPreviewModel
    @State private var showsBack = false

    init(notetypeID: NotetypeID, fields: [String]) {
        _model = State(initialValue: NoteCardPreviewModel(notetypeID: notetypeID, fields: fields))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(palette.background)
            .navigationTitle(String(localized: "Preview", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                        .amgiToolbarTextButton()
                }
            }
            .task { await model.load() }
            .task(id: model.selected) {
                guard model.selected != nil else { return }
                await model.render()
            }
        }
    }

    private var header: some View {
        HStack(spacing: AmgiSpacing.md) {
            if model.choices.count > 1 {
                Picker(String(localized: "Card", bundle: .module), selection: $model.selected) {
                    ForEach(model.choices) { choice in
                        Text(choice.title).tag(Optional(choice))
                    }
                }
                .pickerStyle(.menu)
            } else if let only = model.choices.first {
                Text(only.title)
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Picker(String(localized: "Side", bundle: .module), selection: $showsBack) {
                Text("Front", bundle: .module).tag(false)
                Text("Back", bundle: .module).tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, AmgiSpacing.lg)
        .padding(.vertical, AmgiSpacing.sm)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            placeholder(message, systemImage: "exclamationmark.triangle")
        case .empty(let text):
            placeholder(text, systemImage: "rectangle.dashed")
        case .rendered(let front, let back, let css):
            if let cardPreview, let choice = model.selected {
                cardPreview.preview(CardPreviewContent(
                    html: showsBack ? back : front,
                    css: css,
                    isAnswerSide: showsBack,
                    cardOrdinal: choice.ordinal
                ))
            } else {
                placeholder(String(localized: "Card preview isn't available here.", bundle: .module), systemImage: "eye.slash")
            }
        }
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        ContentUnavailableView(text, systemImage: systemImage)
    }
}
