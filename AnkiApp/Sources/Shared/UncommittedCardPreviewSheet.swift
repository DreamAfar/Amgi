import SwiftUI
import AnkiBackend
import AnkiProto
import AnkiKit
import Dependencies

struct UncommittedCardPreviewSheet: View {
    @Dependency(\.ankiBackend) var backend
    @Environment(\.dismiss) private var dismiss

    let title: String
    let emptyMessage: String
    let notetype: Anki_Notetypes_Notetype
    let allowsTemplateSelection: Bool
    let loadPreviewNote: () async throws -> Anki_Notes_Note

    @State private var selectedTemplateIndex: Int
    @State private var previewSide: CardPreviewSide = .front
    @State private var previewNote: Anki_Notes_Note?
    @State private var renderedFrontHTML = ""
    @State private var renderedBackHTML = ""
    @State private var isLoading = false
    @State private var isEmptyCard = false
    @State private var errorMessage: String?

    init(
        title: String,
        emptyMessage: String,
        notetype: Anki_Notetypes_Notetype,
        initialTemplateIndex: Int = 0,
        allowsTemplateSelection: Bool = true,
        loadPreviewNote: @escaping () async throws -> Anki_Notes_Note
    ) {
        self.title = title
        self.emptyMessage = emptyMessage
        self.notetype = notetype
        self.allowsTemplateSelection = allowsTemplateSelection
        self.loadPreviewNote = loadPreviewNote
        let normalizedIndex = notetype.templates.indices.contains(initialTemplateIndex) ? initialTemplateIndex : 0
        _selectedTemplateIndex = State(initialValue: normalizedIndex)
    }

    private var currentTemplateName: String {
        guard notetype.templates.indices.contains(selectedTemplateIndex) else {
            return L("deck_template_preview_no_template")
        }
        return notetype.templates[selectedTemplateIndex].name
    }

    private var currentCardOrdinal: UInt32 {
        guard notetype.templates.indices.contains(selectedTemplateIndex) else { return 0 }
        return notetype.templates[selectedTemplateIndex].ord.val
    }

    private var currentHTML: String {
        previewSide == .front ? renderedFrontHTML : renderedBackHTML
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
                    HStack(spacing: 12) {
                        Text(currentTemplateName)
                            .amgiFont(.bodyEmphasis)
                            .foregroundStyle(Color.amgiTextSecondary)

                        Spacer()

                        if allowsTemplateSelection && notetype.templates.count > 1 {
                            Menu {
                                ForEach(Array(notetype.templates.enumerated()), id: \.offset) { index, template in
                                    Button {
                                        selectedTemplateIndex = index
                                    } label: {
                                        if selectedTemplateIndex == index {
                                            Label(template.name, systemImage: "checkmark")
                                        } else {
                                            Text(template.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(AmgiFont.caption.font)
                                        .foregroundStyle(Color.amgiTextSecondary)
                                }
                                .amgiCapsuleControl(horizontalPadding: 12, verticalPadding: 8)
                            }
                        }
                    }

                    Picker(L("deck_template_preview_side"), selection: $previewSide) {
                        ForEach(CardPreviewSide.allCases, id: \.self) { side in
                            Text(side.label).tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                }
                .padding()

                Group {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        VStack(spacing: AmgiSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(Color.amgiWarning)
                            Text(errorMessage)
                                .amgiFont(.body)
                                .foregroundStyle(Color.amgiTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if isEmptyCard {
                        VStack(spacing: AmgiSpacing.sm) {
                            Image(systemName: "rectangle.slash")
                                .font(.title2)
                                .foregroundStyle(Color.amgiTextTertiary)
                            Text(emptyMessage)
                                .amgiFont(.body)
                                .foregroundStyle(Color.amgiTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else {
                        CardWebView(
                            html: currentHTML,
                            autoplayEnabled: false,
                            isAnswerSide: previewSide == .back,
                            cardOrdinal: currentCardOrdinal,
                            openLinksExternally: false,
                            contentAlignment: .top
                        )
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .stroke(Color.amgiBorder.opacity(0.8), lineWidth: 1)
                }
            }
            .background(Color.amgiSurfaceElevated)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_done")) { dismiss() }
                        .amgiToolbarTextButton()
                }
            }
            .task {
                await loadAndRenderPreview()
            }
            .onChange(of: selectedTemplateIndex) {
                Task { await renderPreview() }
            }
        }
    }

    @MainActor
    private func loadAndRenderPreview() async {
        do {
            previewNote = try await loadPreviewNote()
            await renderPreview()
        } catch {
            isLoading = false
            isEmptyCard = false
            renderedFrontHTML = ""
            renderedBackHTML = ""
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func renderPreview() async {
        guard notetype.templates.indices.contains(selectedTemplateIndex) else {
            isLoading = false
            isEmptyCard = false
            errorMessage = L("deck_template_preview_no_template")
            renderedFrontHTML = ""
            renderedBackHTML = ""
            return
        }

        guard let previewNote else {
            await loadAndRenderPreview()
            return
        }

        isLoading = true
        defer { isLoading = false }

        let backend = self.backend
        let template = notetype.templates[selectedTemplateIndex]
        let notetypeCSS = notetype.config.css

        do {
            let rendered: (frontHTML: String, backHTML: String, isEmpty: Bool) = try await Task.detached(priority: .userInitiated) {
                func extractLatexIfNeeded(
                    backend: AnkiBackend,
                    html: String,
                    svg: Bool
                ) -> String {
                    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return html
                    }

                    var request = Anki_CardRendering_ExtractLatexRequest()
                    request.text = html
                    request.svg = svg
                    request.expandClozes = false

                    do {
                        let response: Anki_CardRendering_ExtractLatexResponse = try backend.invoke(
                            service: AnkiBackend.Service.cardRendering,
                            method: AnkiBackend.CardRenderingMethod.extractLatex,
                            request: request
                        )
                        let extracted = response.text
                        if extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return html
                        }
                        return extracted
                    } catch {
                        print("[UncommittedCardPreviewSheet] Latex extraction failed: \(error)")
                        return html
                    }
                }

                var request = Anki_CardRendering_RenderUncommittedCardRequest()
                request.note = previewNote
                request.cardOrd = template.ord.val
                request.template = template
                request.fillEmpty = false
                request.partialRender = false
                let response: Anki_CardRendering_RenderCardResponse = try backend.invoke(
                    service: AnkiBackend.Service.cardRendering,
                    method: AnkiBackend.CardRenderingMethod.renderUncommittedCard,
                    request: request
                )

                return (
                    frontHTML: extractLatexIfNeeded(
                        backend: backend,
                        html: renderCardPreviewNodes(response.questionNodes),
                        svg: response.latexSvg
                    ),
                    backHTML: extractLatexIfNeeded(
                        backend: backend,
                        html: renderCardPreviewNodes(response.answerNodes),
                        svg: response.latexSvg
                    ),
                    isEmpty: response.isEmpty
                )
            }.value

            let cssTag = notetypeCSS.isEmpty ? "" : "<style>\(notetypeCSS)</style>"
            renderedFrontHTML = cssTag + rendered.frontHTML
            renderedBackHTML = cssTag + rendered.backHTML
            isEmptyCard = rendered.isEmpty
                || (renderedFrontHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && renderedBackHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            errorMessage = nil
        } catch {
            isEmptyCard = false
            renderedFrontHTML = ""
            renderedBackHTML = ""
            errorMessage = error.localizedDescription
        }
    }
}

private enum CardPreviewSide: CaseIterable {
    case front
    case back

    var label: String {
        switch self {
        case .front:
            return L("deck_template_preview_front")
        case .back:
            return L("deck_template_preview_back")
        }
    }
}

func buildCardPreviewNote(
    from note: NoteRecord,
    fieldValues: [String]? = nil,
    tags: String? = nil
) -> Anki_Notes_Note {
    var preview = Anki_Notes_Note()
    preview.id = note.id
    preview.guid = note.guid
    preview.notetypeID = note.mid
    preview.mtimeSecs = UInt32(clamping: note.mod)
    preview.usn = note.usn
    preview.tags = (tags ?? note.tags)
        .split(whereSeparator: { $0.isWhitespace })
        .map(String.init)
    preview.fields = fieldValues
        ?? note.flds.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
    return preview
}

func makeEmptyCardPreviewNote(notetypeId: Int64, fieldCount: Int) -> Anki_Notes_Note {
    var preview = Anki_Notes_Note()
    preview.notetypeID = notetypeId
    preview.usn = -1
    preview.fields = Array(repeating: "", count: max(fieldCount, 0))
    return preview
}

private func renderCardPreviewNodes(_ nodes: [Anki_CardRendering_RenderedTemplateNode]) -> String {
    nodes.map { node in
        switch node.value {
        case .text(let text):
            return text
        case .replacement(let replacement):
            return replacement.currentText
        case .none:
            return ""
        }
    }.joined()
}