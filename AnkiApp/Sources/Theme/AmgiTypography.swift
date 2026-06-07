import SwiftUI

enum AmgiFont {
    case displayHero       // largeTitle semibold, system tracking
    case sectionHeading    // title2 semibold, system tracking
    case cardTitle         // title3 bold, system tracking
    case body              // body regular, system tracking (Dynamic Type)
    case bodyEmphasis      // body semibold, system tracking (Dynamic Type)
    case caption           // caption regular, system tracking (Dynamic Type)
    case captionBold       // caption semibold, system tracking (Dynamic Type)
    case micro             // caption2 regular, system tracking (Dynamic Type)

    var font: Font {
        switch self {
        case .displayHero:    .largeTitle.weight(.semibold)
        case .sectionHeading: .title2.weight(.semibold)
        case .cardTitle:      .title3.weight(.bold)
        case .body:           .body
        case .bodyEmphasis:   .body.weight(.semibold)
        case .caption:        .caption
        case .captionBold:    .caption.weight(.semibold)
        case .micro:          .caption2
        }
    }
}

extension View {
    func amgiFont(_ style: AmgiFont) -> some View {
        self.font(style.font)
    }
}