import SwiftUI
import UIKit
import AmgiTheme

// MARK: - Dynamic theme-aware colors

/// Dynamic colors that respect both the current Theme (vivid/muted/legacy)
/// and the system color scheme (light/dark).
///
/// Uses `UIColor` dynamic provider so that colors auto-update when
/// the user switches themes or the system toggles Dark Mode.
extension Color {
    static var amgiBackground: Color { palette(\.background) }
    static var amgiSurface: Color { palette(\.surface) }
    static var amgiSurfaceElevated: Color { palette(\.surfaceElevated) }
    static var amgiBorder: Color { palette(\.border) }
    static var amgiTextPrimary: Color { palette(\.textPrimary) }
    static var amgiTextSecondary: Color { palette(\.textSecondary) }
    static var amgiTextTertiary: Color { palette(\.textTertiary) }
    static var amgiAccent: Color { palette(\.accent) }
    static var amgiLink: Color { palette(\.link) }
    static var amgiPositive: Color { palette(\.positive) }
    static var amgiWarning: Color { palette(\.warning) }
    static var amgiDanger: Color { palette(\.danger) }
    static var amgiInfo: Color { palette(\.info) }

    /// Accent surface with theme-aware tint.
    static var amgiAccentSurface: Color {
        amgiAccent.opacity(0.12)
    }

    /// Menu capsule / picker background (same as surface).
    static var amgiMenuSurface: Color { palette(\.surface) }

    private static func palette(_ keyPath: KeyPath<Palette, Color>) -> Color {
        Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            let palette = Palette.resolve(
                theme: ThemeManager.shared.theme,
                scheme: scheme
            )
            return UIColor(palette[keyPath: keyPath])
        })
    }
}
