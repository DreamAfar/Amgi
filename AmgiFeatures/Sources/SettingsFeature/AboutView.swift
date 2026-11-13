//
//  AboutView.swift
//  SettingsFeature
//
//  Created by Vladimir Gusev on 28.04.2026.
//

import SwiftUI
import Theme

struct AboutView: View {
    private var appVersion: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        SettingsPage {
            SettingsSectionHeader(title: "Amgi")
            SettingsGroup {
                SettingsValueRow(
                    title: String(localized: "Version", bundle: .module),
                    value: appVersion,
                    systemImage: "number",
                    tone: .info
                )
                SettingsSeparator()
                SettingsValueRow(
                    title: String(localized: "Korean origin", bundle: .module),
                    value: String(localized: "암기 — memorization", bundle: .module),
                    systemImage: "character.book.closed",
                    tone: .mature
                )
            }

            SettingsSectionHeader(title: String(localized: "Acknowledgements", bundle: .module))
            SettingsGroup {
                SettingsValueRow(
                    title: String(localized: "Anki engine", bundle: .module),
                    value: "ankitects/anki",
                    systemImage: "shippingbox",
                    tone: .accent
                )
                SettingsSeparator()
                SettingsValueRow(
                    title: String(localized: "Community", bundle: .module),
                    value: String(localized: "DreamAfar — fork contributor", bundle: .module),
                    systemImage: "person.2",
                    tone: .learning
                )
            }
            SettingsFootnote(String(localized: "Amgi uses the official Anki Rust backend. The backend code is licensed under AGPL-3.0 and remains the work of its authors.", bundle: .module))
        }
        .navigationTitle(String(localized: "About", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG

// MARK: - Preview

#Preview {
    NavigationStack { AboutView() }
}
#endif
