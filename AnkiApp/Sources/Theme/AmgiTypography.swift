import SwiftUI

enum AmgiFont {
    case displayHero
    case sectionHeading
    case cardTitle
    case body
    case bodyEmphasis
    case caption
    case captionBold
    case micro

    var font: Font {
        switch self {
        case .displayHero:
            return .system(size: 32, weight: .bold, design: .rounded)
        case .sectionHeading:
            return .system(size: 18, weight: .semibold, design: .default)
        case .cardTitle:
            return .system(size: 16, weight: .semibold, design: .default)
        case .body:
            return .system(size: 15, weight: .regular, design: .default)
        case .bodyEmphasis:
            return .system(size: 15, weight: .medium, design: .default)
        case .caption:
            return .system(size: 13, weight: .regular, design: .default)
        case .captionBold:
            return .system(size: 13, weight: .semibold, design: .default)
        case .micro:
            return .system(size: 11, weight: .medium, design: .default)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .displayHero:
            return -0.4
        case .sectionHeading:
            return -0.3
        case .cardTitle:
            return 0.2
        case .body, .bodyEmphasis:
            return 0
        case .caption, .captionBold:
            return 0.1
        case .micro:
            return 0.2
        }
    }
}

extension View {
    func amgiFont(_ style: AmgiFont) -> some View {
        font(style.font)
            .tracking(style.tracking)
    }
}