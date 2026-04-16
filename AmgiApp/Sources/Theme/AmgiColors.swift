import SwiftUI

extension Color {
    // MARK: - Backgrounds
    static let amgiBackground = Color(
        light: Color(red: 0.96, green: 0.96, blue: 0.97),   // #F5F5F7
        dark: Color(red: 0, green: 0, blue: 0)                // #000000
    )
    static let amgiSurface = Color(
        light: .white,                                         // #FFFFFF
        dark: Color(red: 0.11, green: 0.11, blue: 0.12)       // #1C1C1E
    )
    static let amgiSurfaceElevated = Color(
        light: .white,                                         // #FFFFFF
        dark: Color(red: 0.165, green: 0.165, blue: 0.176)    // #2A2A2D
    )

    // MARK: - Text
    static let amgiTextPrimary = Color(
        light: Color(red: 0.114, green: 0.114, blue: 0.122),  // #1D1D1F
        dark: .white
    )
    static let amgiTextSecondary = Color(
        light: .black.opacity(0.8),
        dark: .white.opacity(0.8)
    )
    static let amgiTextTertiary = Color(
        light: .black.opacity(0.48),
        dark: .white.opacity(0.48)
    )

    // MARK: - Interactive
    static let amgiAccent = Color(
        light: Color(red: 0, green: 0.443, blue: 0.89),       // #0071E3
        dark: Color(red: 0.161, green: 0.592, blue: 1.0)      // #2997FF
    )
    static let amgiLink = Color(
        light: Color(red: 0, green: 0.4, blue: 0.8),          // #0066CC
        dark: Color(red: 0.161, green: 0.592, blue: 1.0)      // #2997FF
    )
}

// MARK: - Adaptive Color Initializer

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}

// MARK: - Shadow

extension View {
    func amgiShadow() -> some View {
        self.shadow(color: .black.opacity(0.22), radius: 15, x: 3, y: 5)
    }
}
