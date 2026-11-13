//
//  TemplatePreviewSheet.swift
//  TemplatesFeature
//
//  Created by Vladimir Gusev on 14.05.2026.
//

import SwiftUI
import AppShared
import Theme
import UI
import AnkiKit

/// Preview sheet for uncommitted (unsaved) card templates. The backend
/// renders the edited template against a real note; the card is then drawn
/// by the reviewer's own card view, supplied through `\.cardPreview`, so the
/// preview matches what a review shows — HTML, card CSS, media and night mode.
struct TemplatePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    let title: String
    let emptyMessage: String

    @State private var model: TemplatePreviewModel
    @State private var side: CardPreviewSide = .front

    init(
        title: String,
        emptyMessage: String,
        notetype: Notetype,
        initialTemplateIndex: Int = 0,
        loadSampleFields: @escaping () async throws -> [String]
    ) {
        self.title = title
        self.emptyMessage = emptyMessage
        _model = State(initialValue: TemplatePreviewModel(
            notetype: notetype,
            templateIndex: initialTemplateIndex,
            loadSampleFields: loadSampleFields
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TemplatePreviewHeader(
                    templateName: model.templateName,
                    templates: model.notetype.templates.map(\.name),
                    templateIndex: $model.templateIndex,
                    side: $side
                )
                TemplatePreviewBody(
                    state: model.state,
                    side: side,
                    cardOrdinal: model.cardOrdinal,
                    emptyMessage: emptyMessage
                )
            }
            .background(palette.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                        .amgiToolbarTextButton()
                }
            }
            .task(id: model.templateIndex) { await model.render() }
        }
    }
}

enum CardPreviewSide: CaseIterable {
    case front
    case back

    var label: String {
        switch self {
        case .front: String(localized: "Front", bundle: .module)
        case .back: String(localized: "Back", bundle: .module)
        }
    }
}

struct TemplatePreviewHeader: View {
    let templateName: String
    let templates: [String]
    @Binding var templateIndex: Int
    @Binding var side: CardPreviewSide

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            if templates.count > 1 {
                // A notetype with several card types (Basic and reversed,
                // cloze-free multi-card types) previews each one in place.
                Picker(String(localized: "Card type", bundle: .module), selection: $templateIndex) {
                    ForEach(templates.indices, id: \.self) { index in
                        Text(templates[index]).tag(index)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Text(templateName)
                    .amgiFont(.bodyEmphasis)
                    .foregroundStyle(palette.textSecondary)
            }

            Picker(String(localized: "Side", bundle: .module), selection: $side) {
                ForEach(CardPreviewSide.allCases, id: \.self) { side in
                    Text(side.label).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

struct TemplatePreviewBody: View {
    let state: TemplatePreviewModel.State
    let side: CardPreviewSide
    let cardOrdinal: UInt32
    let emptyMessage: String

    @Environment(\.palette) private var palette
    @Environment(\.cardPreview) private var cardPreview

    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            placeholder(systemImage: "exclamationmark.triangle", text: message, tint: palette.warning)
        case .empty:
            placeholder(systemImage: "rectangle.slash", text: emptyMessage, tint: palette.textTertiary)
        case .rendered(let front, let back, let css):
            if let cardPreview {
                cardPreview.preview(CardPreviewContent(
                    html: side == .front ? front : back,
                    css: css,
                    isAnswerSide: side == .back,
                    cardOrdinal: cardOrdinal
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder(
                    systemImage: "rectangle.on.rectangle.slash",
                    text: String(localized: "Card preview isn't available here.", bundle: .module),
                    tint: palette.textTertiary
                )
            }
        }
    }

    private func placeholder(systemImage: String, text: String, tint: Color) -> some View {
        VStack(spacing: AmgiSpacing.sm) {
            Image(systemName: systemImage)
                .amgiFont(.sectionHeading)
                .foregroundStyle(tint)
            Text(text)
                .amgiFont(.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
