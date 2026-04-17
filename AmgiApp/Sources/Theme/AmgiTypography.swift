import SwiftUI

enum AmgiFont {
    case displayHero       // 34pt semibold, -0.4 tracking
    case sectionHeading    // 24pt semibold, -0.3 tracking
    case cardTitle         // 20pt bold, 0.2 tracking
    case body              // 17pt regular, -0.4 tracking
    case bodyEmphasis      // 17pt semibold, -0.4 tracking
    case caption           // 14pt regular, -0.2 tracking
    case captionBold       // 14pt semibold, -0.2 tracking
    case micro             // 12pt regular, -0.1 tracking

    var font: Font {
        switch self {
        case .displayHero:    .system(size: 34, weight: .semibold)
        case .sectionHeading: .system(size: 24, weight: .semibold)
        case .cardTitle:      .system(size: 20, weight: .bold)
        case .body:           .system(size: 17, weight: .regular)
        case .bodyEmphasis:   .system(size: 17, weight: .semibold)
        case .caption:        .system(size: 14, weight: .regular)
        case .captionBold:    .system(size: 14, weight: .semibold)
        case .micro:          .system(size: 12, weight: .regular)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .displayHero:                    -0.4
        case .sectionHeading:                 -0.3
        case .cardTitle:                       0.2
        case .body, .bodyEmphasis:            -0.4
        case .caption, .captionBold:          -0.2
        case .micro:                          -0.1
        }
    }
}

extension View {
    func amgiFont(_ style: AmgiFont) -> some View {
        self.font(style.font).tracking(style.tracking)
    }
}
