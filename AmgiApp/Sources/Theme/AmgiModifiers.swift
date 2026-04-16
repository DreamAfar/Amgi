import SwiftUI

// MARK: - Card Modifier

struct AmgiCardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(AmgiSpacing.lg)
            .background(
                elevated ? Color.amgiSurfaceElevated : Color.amgiSurface,
                in: RoundedRectangle(cornerRadius: 12)
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

extension View {
    func amgiCard(elevated: Bool = false) -> some View {
        modifier(AmgiCardModifier(elevated: elevated))
    }
}

// MARK: - Section Background

extension View {
    func amgiSectionBackground() -> some View {
        self.background(Color.amgiBackground)
    }
}

// MARK: - Button Styles

struct AmgiPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .amgiFont(.body)
            .foregroundStyle(.white)
            .padding(.vertical, AmgiSpacing.sm)
            .padding(.horizontal, 20)
            .background(Color.amgiAccent, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

struct AmgiSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .amgiFont(.body)
            .foregroundStyle(Color.amgiAccent)
            .padding(.vertical, AmgiSpacing.sm)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .stroke(Color.amgiAccent, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
