//
//  ReviewCardPreview.swift
//  ReviewFeature
//

package import AppShared
package import SwiftUI

/// The concrete `CardPreviewProviding` the app root injects: the reviewer's
/// own `CardWebView`, so a template preview renders with the same frame
/// HTML, bridge script, media scheme and card CSS as a real review.
///
/// No stored properties, for the reason given on `CardPreviewProviding`.
package struct ReviewCardPreview: CardPreviewProviding {
    package init() {}

    package func preview(_ content: CardPreviewContent) -> AnyView {
        AnyView(
            CardWebView(
                html: content.html,
                cardCSS: content.css,
                // Opening a preview shouldn't start the card's audio; the
                // inline replay buttons still play it on demand.
                autoplayEnabled: false,
                isAnswerSide: content.isAnswerSide,
                cardOrdinal: content.cardOrdinal
            )
        )
    }
}
