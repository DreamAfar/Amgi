//
//  ReviewSettingsView.swift
//  SettingsFeature
//
//  Created by Vladimir Gusev on 02.05.2026.
//

import SwiftUI
import AppCore
import Theme
import Sharing
import ReviewCore
import ReviewFeature

struct ReviewSettingsView: View {
    @Shared(.appStorage(ReviewPreferences.Keys.openLinksExternally))
    private var openLinksExternally: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.cardContentAlignment))
    private var cardContentAlignment: String = CardWebViewContentAlignment.center.rawValue

    @Shared(.appStorage(ReviewPreferences.Keys.autoMatchCardBackground))
    private var autoMatchCardBackground: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showRemainingDays))
    private var showRemainingDays: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.showNextReviewTime))
    private var showNextReviewTime: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.playAudioInSilentMode))
    private var playAudioInSilentMode: Bool = false

    @Shared(.appStorage(ReviewPreferences.Keys.ankiDroidJSEnabled))
    private var ankiDroidJSEnabled: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.ankiDroidJSAllowsCardChanges))
    private var ankiDroidJSAllowsCardChanges: Bool = false

    @Shared(.appStorage(ReviewPreferences.Keys.ankiDroidJSAllowsSearch))
    private var ankiDroidJSAllowsSearch: Bool = false

    var body: some View {
        SettingsPage {
            cardDisplaySection
            answerButtonsSection
            audioSection
            cardScriptsSection
        }
        .navigationTitle(String(localized: "Review", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardDisplaySection: some View {
        Group {
            SettingsSectionHeader(title: String(localized: "Card Display", bundle: .module))
            SettingsGroup {
                SettingsToggleRow(
                    title: String(localized: "Match toolbar to card background", bundle: .module),
                    systemImage: "paintbrush",
                    tone: .mature,
                    isOn: Binding($autoMatchCardBackground)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: String(localized: "Open links externally", bundle: .module),
                    systemImage: "arrow.up.right.square",
                    tone: .accent,
                    isOn: Binding($openLinksExternally)
                )
                SettingsSeparator()
                SettingsPickerRow(
                    title: String(localized: "Content alignment", bundle: .module),
                    systemImage: "arrow.up.and.down.text.horizontal",
                    tone: .link,
                    selection: Binding($cardContentAlignment)
                ) {
                    Text("Center", bundle: .module).tag(CardWebViewContentAlignment.center.rawValue)
                    Text("Top", bundle: .module).tag(CardWebViewContentAlignment.top.rawValue)
                }
            }
        }
    }

    private var answerButtonsSection: some View {
        Group {
            SettingsSectionHeader(title: String(localized: "Answer Buttons", bundle: .module))
            SettingsGroup {
                SettingsToggleRow(
                    title: String(localized: "Show remaining counts", bundle: .module),
                    systemImage: "number",
                    tone: .review,
                    isOn: Binding($showRemainingDays)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: String(localized: "Show next review time", bundle: .module),
                    systemImage: "clock",
                    tone: .info,
                    isOn: Binding($showNextReviewTime)
                )
            }
        }
    }

    private var audioSection: some View {
        Group {
            SettingsSectionHeader(title: String(localized: "Audio", bundle: .module))
            SettingsGroup {
                SettingsToggleRow(
                    title: String(localized: "Play audio in silent mode", bundle: .module),
                    systemImage: "speaker.wave.2",
                    tone: .learning,
                    isOn: Binding($playAudioInSilentMode)
                )
            }
        }
    }

    private var cardScriptsSection: some View {
        Group {
            SettingsSectionHeader(title: String(localized: "Card Scripts", bundle: .module))
            SettingsGroup {
                SettingsToggleRow(
                    title: String(localized: "AnkiDroid JavaScript API", bundle: .module),
                    systemImage: "curlybraces",
                    tone: .info,
                    isOn: Binding($ankiDroidJSEnabled)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: String(localized: "Allow changes to cards", bundle: .module),
                    systemImage: "exclamationmark.shield",
                    tone: .danger,
                    isOn: Binding($ankiDroidJSAllowsCardChanges)
                )
                .disabled(!ankiDroidJSEnabled)
                SettingsSeparator()
                SettingsToggleRow(
                    title: String(localized: "Allow searching the collection", bundle: .module),
                    systemImage: "magnifyingglass",
                    tone: .danger,
                    isOn: Binding($ankiDroidJSAllowsSearch)
                )
                .disabled(!ankiDroidJSEnabled)
            }
            SettingsFootnote(String(localized: "Lets card templates written for AnkiDroid read the card's details, show the answer, answer, flag and mark. Changes to cards — bury, suspend, set due date, reset, edit tags — run only when allowed, since any shared deck's template could use them. Searching lets a card's script read the notes a search finds, from any deck.", bundle: .module))
        }
    }
}

#if DEBUG

#Preview {
    NavigationStack {
        ReviewSettingsView()
    }
}
#endif
