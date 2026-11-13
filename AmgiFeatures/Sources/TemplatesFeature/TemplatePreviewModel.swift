//
//  TemplatePreviewModel.swift
//  TemplatesFeature
//

import AnkiKit
import AnkiServices
import Dependencies
import Foundation

/// Renders an unsaved template through the backend for the preview sheet.
/// Owns the rendering service so the sheet carries no `@Dependency`, the
/// same split `TemplateEditorModel` makes for the editor.
@Observable
@MainActor
final class TemplatePreviewModel {
    enum State: Equatable {
        case loading
        case failed(String)
        /// The template renders nothing for this note on either side.
        case empty
        case rendered(front: String, back: String, css: String)
    }

    private(set) var state: State = .loading
    var templateIndex: Int

    let notetype: Notetype
    @ObservationIgnored private let loadSampleFields: () async throws -> [String]
    @ObservationIgnored private var sampleFields: [String]?
    @ObservationIgnored @Dependency(\.cardRenderingService) private var cardRenderingService

    init(notetype: Notetype, templateIndex: Int, loadSampleFields: @escaping () async throws -> [String]) {
        self.notetype = notetype
        self.templateIndex = notetype.templates.indices.contains(templateIndex) ? templateIndex : 0
        self.loadSampleFields = loadSampleFields
    }

    var templateName: String {
        guard notetype.templates.indices.contains(templateIndex) else {
            return String(localized: "No template selected.", bundle: .module)
        }
        return notetype.templates[templateIndex].name
    }

    /// The ordinal the backend's `.cardN` class uses. A template added in
    /// this editing session has no ordinal yet; its position stands in.
    var cardOrdinal: UInt32 {
        guard notetype.templates.indices.contains(templateIndex) else { return 0 }
        return UInt32(clamping: notetype.templates[templateIndex].ord ?? templateIndex)
    }

    func render() async {
        guard notetype.templates.indices.contains(templateIndex) else {
            state = .failed(String(localized: "No template selected.", bundle: .module))
            return
        }
        state = .loading
        do {
            let fields: [String]
            if let sampleFields {
                fields = sampleFields
            } else {
                fields = try await loadSampleFields()
                sampleFields = fields
            }
            let service = cardRenderingService
            let notetype = self.notetype
            let index = templateIndex
            let rendered = try await Task.detached(priority: .userInitiated) {
                try service.renderUncommittedCard(notetype, index, fields)
            }.value
            // The user may have switched templates while this rendered.
            guard index == templateIndex else { return }
            state = Self.state(for: rendered)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated static func state(for rendered: RenderedCard) -> State {
        let blank = { (html: String) in html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if blank(rendered.frontHTML) && blank(rendered.backHTML) { return .empty }
        return .rendered(front: rendered.frontHTML, back: rendered.backHTML, css: rendered.cardCSS)
    }
}
