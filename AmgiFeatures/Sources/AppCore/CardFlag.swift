//
//  CardFlag.swift
//  AppCore
//
//  Created by Vladimir Gusev on 08.08.2026.
//

public import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Anki packs the flag into the low three bits of a card's `flags` field.
public enum CardFlag {
    /// `0` is "no flag"; 1–7 are the seven colours, in Anki's order.
    public static let all: [UInt32] = [0, 1, 2, 3, 4, 5, 6, 7]

    public static func name(_ value: UInt32) -> String {
        switch value & 0b111 {
        case 1: return String(localized: "Red", bundle: .module)
        case 2: return String(localized: "Orange", bundle: .module)
        case 3: return String(localized: "Green", bundle: .module)
        case 4: return String(localized: "Blue", bundle: .module)
        case 5: return String(localized: "Pink", bundle: .module)
        case 6: return String(localized: "Turquoise", bundle: .module)
        case 7: return String(localized: "Purple", bundle: .module)
        default: return String(localized: "No Flag", bundle: .module)
        }
    }

    /// Anki's own flag colours (`ts/lib/sass/_vars.scss`), lighter in
    /// dark mode as there. SwiftUI's `.pink` is a pinkish red that read as
    /// a second red flag; Anki's pink is a fuchsia.
    public static func color(_ value: UInt32) -> Color {
        switch value & 0b111 {
        case 1: return adaptive(light: 0xEF4444, dark: 0xF87171)
        case 2: return adaptive(light: 0xFB923C, dark: 0xFDBA74)
        case 3: return adaptive(light: 0x4ADE80, dark: 0x86EFAC)
        case 4: return adaptive(light: 0x3B82F6, dark: 0x60A5FA)
        case 5: return adaptive(light: 0xE879F9, dark: 0xF0ABFC)
        case 6: return adaptive(light: 0x2DD4BF, dark: 0x5EEAD4)
        case 7: return adaptive(light: 0xA855F7, dark: 0xC084FC)
        default: return .secondary
        }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        let light = UIColor(rgb(light)), dark = UIColor(rgb(dark))
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
        #elseif os(macOS)
        let light = NSColor(rgb(light)), dark = NSColor(rgb(dark))
        return Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
        #else
        // watchOS is always dark.
        return rgb(dark)
        #endif
    }

    public static func symbol(_ value: UInt32) -> String {
        value & 0b111 == 0 ? "flag.slash.fill" : "flag.fill"
    }
}
