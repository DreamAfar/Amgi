import SwiftUI
import UIKit

extension Color {
    static let amgiBackground = Color(light: .systemGroupedBackground, dark: .black)
    static let amgiSurface = Color(light: .secondarySystemGroupedBackground, dark: .secondarySystemBackground)
    static let amgiSurfaceElevated = Color(light: .systemBackground, dark: UIColor(red: 0.14, green: 0.15, blue: 0.18, alpha: 1.0))

    static let amgiTextPrimary = Color(light: .label, dark: .white)
    static let amgiTextSecondary = Color(light: .secondaryLabel, dark: UIColor(white: 0.82, alpha: 1.0))
    static let amgiTextTertiary = Color(light: .tertiaryLabel, dark: UIColor(white: 0.66, alpha: 1.0))

    static let amgiAccent = Color(light: UIColor(red: 0.10, green: 0.45, blue: 0.88, alpha: 1.0), dark: UIColor(red: 0.35, green: 0.68, blue: 1.00, alpha: 1.0))
    static let amgiLink = Color(light: UIColor(red: 0.02, green: 0.39, blue: 0.84, alpha: 1.0), dark: UIColor(red: 0.48, green: 0.78, blue: 1.00, alpha: 1.0))

    static let amgiPositive = Color(light: .systemGreen, dark: UIColor(red: 0.39, green: 0.86, blue: 0.54, alpha: 1.0))
    static let amgiWarning = Color(light: .systemOrange, dark: UIColor(red: 1.00, green: 0.72, blue: 0.29, alpha: 1.0))
    static let amgiDanger = Color(light: .systemRed, dark: UIColor(red: 1.00, green: 0.48, blue: 0.48, alpha: 1.0))
    static let amgiInfo = Color(light: .systemCyan, dark: UIColor(red: 0.44, green: 0.84, blue: 0.95, alpha: 1.0))

    init(light: UIColor, dark: UIColor) {
        self.init(
            uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }
}

extension View {
    func amgiShadow() -> some View {
        shadow(color: Color.black.opacity(0.22), radius: 15, x: 3, y: 5)
    }
}