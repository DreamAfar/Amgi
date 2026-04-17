import SwiftUI

struct AmgiCardModifier: ViewModifier {
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .padding(AmgiSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(elevated ? Color.amgiSurfaceElevated : Color.amgiSurface)
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

extension View {
    func amgiCard(elevated: Bool = false) -> some View {
        modifier(AmgiCardModifier(elevated: elevated))
    }

    func amgiSectionBackground() -> some View {
        background(Color.amgiBackground)
    }
}