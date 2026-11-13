//
//  CardPreview.swift
//  AppShared
//

public import SwiftUI

/// One side of a rendered card, as the backend returns it: the side's HTML,
/// the notetype CSS, and the template ordinal the card's `.cardN` class
/// comes from.
public struct CardPreviewContent: Equatable, Sendable {
    public let html: String
    public let css: String
    public let isAnswerSide: Bool
    public let cardOrdinal: UInt32

    public init(html: String, css: String, isAnswerSide: Bool, cardOrdinal: UInt32) {
        self.html = html
        self.css = css
        self.isAnswerSide = isAnswerSide
        self.cardOrdinal = cardOrdinal
    }
}

/// Draws a card exactly as the reviewer does, for features that must not
/// import `ReviewFeature`.
///
/// `TemplatesFeature` previews unsaved templates, but `ReviewFeature` already
/// imports `TemplatesFeature` to open the editor from a card, so the reverse
/// import would be a cycle. The app root supplies the reviewer's card view
/// here instead — the same arrangement as `\.lookupPopup`, with the same
/// rule: conformers keep no stored properties so the environment value
/// compares equal across body evaluations.
@MainActor
public protocol CardPreviewProviding {
    func preview(_ content: CardPreviewContent) -> AnyView
}

public extension EnvironmentValues {
    /// `nil` means no provider (a preview canvas, a test host): the template
    /// preview falls back to a plain message instead of failing.
    @Entry var cardPreview: (any CardPreviewProviding)? = nil
}
