import SwiftUI

enum AmgiStatusTone {
    case accent
    case positive
    case warning
    case danger
    case info
    case neutral

    fileprivate var foregroundColor: Color {
        switch self {
        case .accent:
            return Color.amgiAccent
        case .positive:
            return Color.amgiPositive
        case .warning:
            return Color.amgiWarning
        case .danger:
            return Color.amgiDanger
        case .info:
            return Color.amgiInfo
        case .neutral:
            return Color.amgiTextSecondary
        }
    }

    fileprivate var backgroundColor: Color {
        switch self {
        case .accent:
            return Color.amgiAccent.opacity(0.12)
        case .positive:
            return Color.amgiPositive.opacity(0.14)
        case .warning:
            return Color.amgiWarning.opacity(0.16)
        case .danger:
            return Color.amgiDanger.opacity(0.14)
        case .info:
            return Color.amgiInfo.opacity(0.14)
        case .neutral:
            return Color.amgiSurface
        }
    }

    fileprivate var borderColor: Color {
        switch self {
        case .neutral:
            return Color.amgiBorder.opacity(0.32)
        default:
            return foregroundColor.opacity(0.28)
        }
    }
}

struct AmgiCardModifier: ViewModifier {
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(AmgiSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(elevated ? Color.amgiSurfaceElevated : Color.amgiSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.amgiBorder.opacity(elevated ? 0.32 : 0.18), lineWidth: 1)
            )
            .modifier(ConditionalShadow(enabled: elevated))
    }
}

private struct ConditionalShadow: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.amgiShadow()
        } else {
            content
        }
    }
}

struct AmgiPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .amgiFont(.bodyEmphasis)
            .foregroundStyle(Color.white)
            .padding(.horizontal, AmgiSpacing.lg)
            .padding(.vertical, AmgiSpacing.sm)
            .background(Color.amgiAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct AmgiSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .amgiFont(.bodyEmphasis)
            .foregroundStyle(Color.amgiAccent)
            .padding(.horizontal, AmgiSpacing.lg)
            .padding(.vertical, AmgiSpacing.sm)
            .background(
                Capsule()
                    .stroke(Color.amgiAccent.opacity(configuration.isPressed ? 0.55 : 0.85), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct AmgiStatusMessageView: View {
    let title: String
    let message: String
    let systemImage: String
    let tone: AmgiStatusTone

    var body: some View {
        VStack(spacing: AmgiSpacing.md) {
            Label(title, systemImage: systemImage)
                .amgiStatusBadge(tone, horizontalPadding: 12, verticalPadding: 8)

            Text(message)
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .amgiStatusPanel(tone, elevated: true)
        .padding(.horizontal, AmgiSpacing.lg)
    }
}

extension View {
    func amgiCard(elevated: Bool = false) -> some View {
        modifier(AmgiCardModifier(elevated: elevated))
    }

    func amgiToolbarIconButton(size: CGFloat = 32) -> some View {
        frame(width: size, height: size)
            .foregroundStyle(Color.amgiTextPrimary)
            .background(Color.amgiSurfaceElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.amgiBorder.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func amgiToolbarTextButton(tone: AmgiStatusTone = .accent) -> some View {
        amgiFont(.captionBold)
            .foregroundStyle(tone.foregroundColor)
    }

    func amgiCapsuleControl(horizontalPadding: CGFloat = 10, verticalPadding: CGFloat = 6) -> some View {
        padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Color.amgiSurfaceElevated)
            .overlay(
                Capsule()
                    .stroke(Color.amgiBorder.opacity(0.28), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    func amgiStatusBadge(_ tone: AmgiStatusTone, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 4) -> some View {
        amgiFont(.captionBold)
            .foregroundStyle(tone.foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.backgroundColor)
            .overlay(
                Capsule()
                    .stroke(tone.borderColor, lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    func amgiStatusPanel(_ tone: AmgiStatusTone, elevated: Bool = false) -> some View {
        padding(AmgiSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.amgiSurfaceElevated)
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tone.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tone.borderColor, lineWidth: 1)
            )
            .modifier(ConditionalShadow(enabled: elevated))
    }

    func amgiSegmentedPicker() -> some View {
        pickerStyle(.segmented)
            .tint(Color.amgiAccent)
    }

    func amgiSectionBackground() -> some View {
        background(Color.amgiBackground)
    }
}