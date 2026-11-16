//
//  LookupResultList.swift
//  ReaderFeature
//
//  Created by Vladimir Gusev on 13.06.2026.
//

import Reader
import SwiftUI
import Theme

/// The plain list of dictionary entries shared by the root lookup popup and
/// every pushed child pane. Both used to inline an identical
/// list of `LookupEntryView`s; this is that body, parameterised by the
/// per-entry callbacks each caller supplies.
struct LookupResultList: View {
    let result: DictionaryLookupResult
    let styling: LookupEntryStyling
    let audioTemplate: String
    let audioPlaybackMode: LookupAudioPlaybackMode
    let collapsedDictionaries: Set<String>
    let onSetCollapsed: (String, Bool) -> Void
    let languageHint: String?
    let onMakeNote: (DictionaryLookupEntry) -> Void
    let onLookupRequested: (String) -> Void

    var body: some View {
        // A scroll view and stack rather than a `List`: entries are tall and
        // their height arrives late, from the web views inside them. A List
        // sizes its rows as collection-view cells and didn't always pick the
        // new height up, so entries were drawn over one another until the
        // next scroll or tap. A stack lays its rows out again on any change.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(result.entries) { entry in
                    LookupEntryView(
                        entry: entry,
                        dictionaryStyles: result.dictionaryStyles,
                        audioTemplate: audioTemplate,
                        audioPlaybackMode: audioPlaybackMode,
                        styling: styling,
                        collapsedDictionaries: collapsedDictionaries,
                        onSetCollapsed: onSetCollapsed,
                        languageHint: languageHint,
                        onMakeNote: { onMakeNote(entry) },
                        onLookupRequested: onLookupRequested
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AmgiSpacing.lg)
                    .padding(.vertical, AmgiSpacing.sm)
                    Divider()
                        .padding(.leading, AmgiSpacing.lg)
                }
                ForEach(result.kanji) { kanji in
                    LookupKanjiView(kanji: kanji, styling: styling)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AmgiSpacing.lg)
                        .padding(.vertical, AmgiSpacing.sm)
                    Divider()
                        .padding(.leading, AmgiSpacing.lg)
                }
            }
        }
    }
}

/// One kanji with its readings and meanings, per kanji dictionary.
struct LookupKanjiView: View {
    let kanji: DictionaryLookupKanji
    let styling: LookupEntryStyling

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: AmgiSpacing.md) {
            Text(kanji.character)
                .amgiFont(.displayHero)
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
                ForEach(Array(kanji.entries.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                        Text(entry.dictionary)
                            .font(.system(size: styling.dictionaryNameFontSize))
                            .foregroundStyle(palette.textSecondary)
                        if !entry.onyomi.isEmpty {
                            reading(String(localized: "On reading", bundle: .module), entry.onyomi)
                        }
                        if !entry.kunyomi.isEmpty {
                            reading(String(localized: "Kun reading", bundle: .module), entry.kunyomi)
                        }
                        if !entry.meanings.isEmpty {
                            Text(entry.meanings.joined(separator: "; "))
                                .font(.system(size: styling.contentFontSize))
                                .foregroundStyle(palette.textPrimary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func reading(_ label: String, _ values: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AmgiSpacing.sm) {
            Text(label)
                .amgiFont(.micro)
                .foregroundStyle(palette.textSecondary)
            Text(values.joined(separator: "、"))
                .font(.system(size: styling.contentFontSize))
                .foregroundStyle(palette.textPrimary)
        }
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Result list") {
    LookupResultList(
        result: DictionaryLookupResult(
            query: "勉強",
            entries: [
                DictionaryLookupEntry(
                    term: "勉強",
                    reading: "べんきょう",
                    glossaries: ["study; diligence"],
                    frequency: "1023",
                    pitch: "[0]"
                ),
                DictionaryLookupEntry(
                    term: "勉強会",
                    reading: "べんきょうかい",
                    glossaries: ["study group; study meeting"],
                    frequency: "8841"
                ),
            ]
        ),
        styling: LookupEntryStyling(),
        audioTemplate: "",
        audioPlaybackMode: .interrupt,
        collapsedDictionaries: [],
        onSetCollapsed: { _, _ in },
        languageHint: "ja",
        onMakeNote: { _ in },
        onLookupRequested: { _ in }
    )
}
#endif
