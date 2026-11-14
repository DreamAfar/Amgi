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

    @Shared(.appStorage(ReviewPreferences.Keys.lookupPopupEnabled))
    private var lookupEnabled: Bool = ReviewPreferences.lookupPopupDefault

    @Shared(.appStorage(ReviewPreferences.Keys.lookupPopupFrontEnabled))
    private var lookupOnFront: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.lookupPopupBackEnabled))
    private var lookupOnBack: Bool = true

    @Shared(.appStorage(ReviewPreferences.Keys.playAudioInSilentMode))
    private var playAudioInSilentMode: Bool = false

    var body: some View {
        SettingsPage {
            cardDisplaySection
            lookupSection
            answerButtonsSection
            audioSection
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

    private var lookupSection: some View {
        Group {
            SettingsSectionHeader(title: String(localized: "Dictionary Lookup", bundle: .module))
            SettingsGroup {
                SettingsToggleRow(
                    title: String(localized: "Tap word to look up", bundle: .module),
                    systemImage: "hand.tap",
                    tone: .info,
                    isOn: Binding($lookupEnabled)
                )
                SettingsSeparator()
                SettingsToggleRow(
                    title: String(localized: "On the front", bundle: .module),
                    systemImage: "rectangle.portrait",
                    tone: .neutral,
                    isOn: Binding($lookupOnFront)
                )
                .disabled(!lookupEnabled)
                SettingsSeparator()
                SettingsToggleRow(
                    title: String(localized: "On the back", bundle: .module),
                    systemImage: "rectangle.portrait.on.rectangle.portrait",
                    tone: .neutral,
                    isOn: Binding($lookupOnBack)
                )
                .disabled(!lookupEnabled)
            }
            SettingsFootnote(String(localized: "Applies to review cards only; the Reader has its own switch. Lookup stays off while a card asks you to type the answer.", bundle: .module))
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
}

#if DEBUG

#Preview {
    NavigationStack {
        ReviewSettingsView()
    }
}
#endif
