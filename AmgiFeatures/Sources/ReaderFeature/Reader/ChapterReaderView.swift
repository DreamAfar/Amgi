//
//  ChapterReaderView.swift
//  ReaderFeature
//
//  Created by Vladimir Gusev on 05.05.2026.
//

import Reader
import Theme
import AppCore
import AppShared
import AnkiClients
import AnkiKit
import BrowseFeature
import Sharing
import SwiftUI
import WebKit


/// Renders a chapter's HTML content in a WKWebView and tracks vertical
/// scroll progress as a 0..1 fraction of the document. The current
/// progress is captured into a binding on every scroll-end and persisted
/// when the view dismisses.
///
/// First-pass scope: read-only. No tap-to-lookup, no font/theme controls,
/// no pagination. Those layer on later via the ReaderPreferences keys
/// already declared in the Settings module.
struct ChapterReaderView: View {
    let book: ReaderBook
    let chapter: ReaderChapter
    let progress: ReaderProgressCoordinator

    @State private var scrollProgress: Double = 0
    @State private var didRestoreInitialProgress = false
    @State private var initialRestoreProgress: Double?
    /// The dictionary popup, when open. Stored rather than derived from a
    /// query string: a sheet item rebuilt on every render gets a new
    /// identity each time, and the reader re-renders on every scroll, so
    /// the popup could close or reopen by itself.
    @State private var lookup: LookupQuery?
    @State private var noteDraft: ReaderNoteDraft?
    @State private var hint: String?
    @State private var hintTask: Task<Void, Never>?
    @Shared(.appStorage(ReaderPreferences.Keys.lookupNoteTemplate))
    private var serializedNoteTemplate: String = ""

    @Shared(.appStorage(ReaderPreferences.Keys.fontSize))
    private var fontSize: Double = 17
    @Shared(.appStorage(ReaderPreferences.Keys.lineHeight))
    private var lineHeight: Double = 1.5
    @Shared(.appStorage(ReaderPreferences.Keys.horizontalPadding))
    private var horizontalPadding: Double = 18
    @Shared(.appStorage(ReaderPreferences.Keys.verticalPadding))
    private var verticalPadding: Double = 16
    @Shared(.appStorage(ReaderPreferences.Keys.justifyText))
    private var justifyText: Bool = false
    @Shared(.appStorage(ReaderPreferences.Keys.themeMode))
    private var themeModeRaw: String = "system"
    @Shared(.appStorage(ReaderPreferences.Keys.selectedFont))
    private var selectedFontRaw: String = ReaderFontOption.defaultValue

    @Shared(.appStorage(ReaderPreferences.Keys.customTextColor))
    private var customTextColorHex: String = "#1F2A26"

    @Shared(.appStorage(ReaderPreferences.Keys.customBackgroundColor))
    private var customBackgroundColorHex: String = "#FAF7F2"
    @Shared(.appStorage(ReaderPreferences.Keys.showTitle))
    private var showTitle: Bool = true
    @Shared(.appStorage(ReaderPreferences.Keys.showPercentage))
    private var showPercentage: Bool = true
    @Shared(.appStorage(ReaderPreferences.Keys.tapLookup))
    private var tapLookup: Bool = true

    @Shared(.appStorage(ReaderPreferences.Keys.characterSpacing))
    private var characterSpacing: Double = 0
    @Shared(.appStorage(ReaderPreferences.Keys.avoidPageBreak))
    private var avoidPageBreak: Bool = true
    @Shared(.appStorage(ReaderPreferences.Keys.hideFurigana))
    private var hideFurigana: Bool = false
    @Shared(.appStorage(ReaderPreferences.Keys.customHintColor))
    private var customHintColorHex: String = "#777777"

    @Shared(.appStorage(ReaderPreferences.Keys.showProgressTop))
    private var showProgressTop: Bool = false
    @Shared(.appStorage(ReaderPreferences.Keys.verticalLayout))
    private var verticalLayout: Bool = false
    @Shared(.appStorage(ReaderPreferences.Keys.popupDebugInfoEnabled))
    private var debugInfoEnabled: Bool = false

    @State private var lastTapPhrase: String?
    /// Whether the open lookup came from a tap in the text — only then is
    /// there a tapped span to highlight.
    @State private var lookupFromTap = false
    @State private var lookupHighlight = LookupHighlight()
    @Shared(.appStorage(ReaderPreferences.Keys.dictionaryScanLength))
    private var dictionaryScanLength: Int = 16

    /// The wrapped chapter HTML, rebuilt only when the chapter or a
    /// typography preference changes.
    ///
    /// `scrollViewDidScroll` writes `scrollProgress`, and a `@State` write
    /// invalidates unconditionally — so `body` re-runs at scroll-event rate.
    /// Building this in `body` meant interpolating the whole chapter into a
    /// template string (and running `prefersLatinWordLayout`'s two
    /// whole-document regexes) on every scrolled frame, then having
    /// `updateUIView` compare the result against the last one with a
    /// full-string `!=`.
    @State private var renderedHTML: String = ""

    @Environment(\.palette) private var palette

    /// Every input `wrappedHTML` reads. Keys the rebuild task, so a
    /// preference change re-renders and a scroll does not.
    private var renderInputs: ChapterRenderInputs {
        ChapterRenderInputs(
            chapterID: chapter.id,
            fontSize: fontSize,
            lineHeight: lineHeight,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            justifyText: justifyText,
            themeModeRaw: themeModeRaw,
            selectedFontRaw: selectedFontRaw,
            customTextColorHex: customTextColorHex,
            customBackgroundColorHex: customBackgroundColorHex,
            characterSpacing: characterSpacing,
            avoidPageBreak: avoidPageBreak,
            hideFurigana: hideFurigana,
            customHintColorHex: customHintColorHex,
            verticalLayout: verticalLayout,
            language: book.language
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            ChapterWebView(
                html: renderedHTML,
                initialProgress: didRestoreInitialProgress ? nil : initialRestoreProgress,
                progress: $scrollProgress,
                onTapLookup: tapLookup
                    ? { phrase in
                        lastTapPhrase = phrase
                        lookupFromTap = true
                        lookup = LookupQuery(text: phrase)
                    }
                    : nil,
                onSelectionForNote: { makeCard(from: $0) },
                onLookupSelection: { text in
                    lookupFromTap = false
                    lookup = LookupQuery(text: text)
                },
                scanLength: dictionaryScanLength,
                lookupHighlight: lookupHighlight
            )
            if showProgressTop {
                ProgressView(value: scrollProgress)
                    .progressViewStyle(.linear)
                    .tint(palette.accent)
                    .frame(height: 2)
                    .scaleEffect(x: 1, y: 0.6, anchor: .top)
                    .ignoresSafeArea(edges: .horizontal)
            }
            if showPercentage {
                Text("\(Int(scrollProgress * 100))%")
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
                    .accessibilityLabel(String(localized: "Reading progress", bundle: .module))
            }
            if debugInfoEnabled {
                debugOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(showTitle ? chapter.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    requestSelectionForNote()
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel(String(localized: "Make note from selection", bundle: .module))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    lookupFromTap = false
                    lookup = LookupQuery(text: "")
                } label: {
                    Image(systemName: "character.book.closed")
                }
                .accessibilityLabel(String(localized: "Look up word", bundle: .module))
            }
        }
        .sheet(item: $lookup, onDismiss: { lookupHighlight.clear() }) { wrapped in
            LookupPopupView(
                initialQuery: wrapped.text,
                languageHint: book.language,
                onMatched: lookupFromTap ? { lookupHighlight.show(matched: $0) } : nil
            ) {
                lookup = nil
            }
        }
        .sheet(item: $noteDraft) { wrapped in
            AddNoteView(initialDraft: wrapped.draft) {
                noteDraft = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let hint {
                Text(hint)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AmgiSpacing.lg)
                    .padding(.vertical, AmgiSpacing.sm)
                    .background(palette.surfaceElevated, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.border))
                    .padding(.horizontal, AmgiSpacing.lg)
                    .padding(.bottom, AmgiSpacing.xxl)
                    .transition(AmgiMotion.slide(from: .bottom))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(AmgiMotion.quick, value: hint)
        .onAppear {
            didRestoreInitialProgress = false
        }
        .task(id: renderInputs) {
            let inputs = renderInputs
            let content = chapter.content
            renderedHTML = await Task.detached {
                ChapterReaderView.wrappedHTML(content, inputs: inputs)
            }.value
        }
        .task(id: chapter.id) {
            guard let saved = await progress.resolved(bookID: book.id),
                  saved.chapterID == chapter.id else { return }
            initialRestoreProgress = saved.progress
        }
        .onDisappear {
            // Persist whatever the user reached. Save unconditionally —
            // even 0% writes are cheap and keep the chapterID stable so
            // the bookshelf "Resume" hint stays accurate. The coordinator
            // also fires-and-forgets a sync write to the Anki collection.
            progress.save(bookID: book.id, chapterID: chapter.id, progress: scrollProgress)
        }
    }

    /// Bottom-left HUD shown only when `popupDebugInfoEnabled` is on.
    /// Useful when triaging tap-lookup misfires or font/layout issues
    /// without spinning up a debug build. Hit-testing is disabled at the
    /// call site so the overlay never swallows reader taps.
    private var debugOverlay: some View {
        let fontTitle = ReaderCustomFonts.font(forSelection: selectedFontRaw)?.displayName
            ?? ReaderFontOption.resolved(selectedFontRaw).title
        let latin = Self.prefersLatinWordLayout(chapter.content, language: book.language)
        let layout = verticalLayout ? "vertical" : (latin ? "latin" : "cjk")
        let phrase = (lastTapPhrase ?? "—").prefix(40)
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(scrollProgress * 100))% · font: \(fontTitle)", bundle: .module)
            Text("layout: \(layout) · lang: \(book.language ?? "?")", bundle: .module)
            Text("last tap: \(phrase)", bundle: .module)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(6)
        .background(palette.textPrimary.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(.white)
    }
}

extension ChapterReaderView {
    /// Opens Add Note filled from the vocabulary card template: the
    /// selection as the word, its sentence (selection in bold) as the
    /// example, the book as the source. Without a selection, says how to
    /// make one instead of doing nothing.
    func makeCard(from selection: WebSelection?) {
        guard let selection else {
            showHint(String(localized: "Select some text first (touch and hold), then tap + — or choose Make Card in the menu that appears.", bundle: .module))
            return
        }
        let template = serializedNoteTemplate.isEmpty
            ? ReaderLookupNoteTemplate.empty
            : ReaderLookupNoteTemplate.decode(from: serializedNoteTemplate)
        let draft = template.makeDraft(
            payload: ReaderLookupNotePayload(term: selection.text, sentence: selection.sentenceHTML, source: book.title),
            fallbackDeckID: nil,
            sourceDescription: book.title
        )
        noteDraft = ReaderNoteDraft(draft: draft)
    }

    private func showHint(_ text: String) {
        hint = text
        hintTask?.cancel()
        hintTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            hint = nil
        }
    }

    /// Toolbar "+" handler: ask the WebView for the user's current
    /// selection. The WebView responds via the `onSelectionForNote`
    /// callback, which opens Add Note (or a hint when nothing is selected).
    func requestSelectionForNote() {
        NotificationCenter.default.post(
            name: .amgiReaderRequestSelection,
            object: nil
        )
    }

    /// Decides whether `book.language` (or, as a fallback, the chapter
    /// content) is Latin-script-dominant. Drives `overflow-wrap` and
    /// `hyphens` rules — Latin text wraps on word boundaries and hyphenates,
    /// CJK wraps anywhere.
    nonisolated static func prefersLatinWordLayout(_ content: String, language: String?) -> Bool {
        if let hint = language?.lowercased() {
            if hint.hasPrefix("en") || hint.hasPrefix("de") || hint.hasPrefix("fr") ||
               hint.hasPrefix("es") || hint.hasPrefix("it") || hint.hasPrefix("pt") ||
               hint.hasPrefix("ru") || hint == "eng" {
                return true
            }
            if hint.hasPrefix("ja") || hint.hasPrefix("ko") || hint.hasPrefix("zh") ||
               hint == "jpn" || hint == "kor" || hint == "chi" {
                return false
            }
        }
        let plain = content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&[A-Za-z0-9#]+;", with: " ", options: .regularExpression)
        let latin = plain.unicodeScalars.lazy.filter {
            CharacterSet.letters.contains($0) && $0.value < 128
        }.count
        let cjk = plain.unicodeScalars.lazy.filter {
            (0x3040...0x30FF).contains(Int($0.value)) ||  // Japanese kana
            (0x3400...0x9FFF).contains(Int($0.value)) ||  // CJK ideographs
            (0xAC00...0xD7AF).contains(Int($0.value))     // Hangul
        }.count
        return latin >= 40 && latin > cjk * 2
    }

    /// Wrap the raw note HTML in a tiny shell that gives us a readable
    /// default style and a known body width. Without a viewport meta
    /// tag, WKWebView can pick wildly different scales depending on the
    /// content and progress math gets noisy.
    ///
    /// CSS pulls in user prefs: font size, line height, padding, justify,
    /// theme. Theme `system` defers to the OS via prefers-color-scheme;
    /// fixed modes hardcode foreground/background. Sepia matches Anki
    /// desktop's reader-tone (#f4ecd8 / #5b4636).
    /// Pure and `static` so the caller can run it off the main actor. The
    /// body is a whole-chapter string interpolation plus two full-document
    /// regex passes; it used to run on the main thread on chapter open and
    /// on every typography-preference change.
    nonisolated static func wrappedHTML(_ content: String, inputs: ChapterRenderInputs) -> String {
        let mode = ReaderThemeMode(rawValue: inputs.themeModeRaw) ?? .system
        let theme = themeCSS(for: mode, customTextColorHex: inputs.customTextColorHex, customBackgroundColorHex: inputs.customBackgroundColorHex)
        let builtInFamily = ReaderFontOption.resolved(inputs.selectedFontRaw).cssFontFamily
        let customFont = ReaderCustomFonts.css(
            forSelection: inputs.selectedFontRaw,
            fallback: ReaderFontOption.system.cssFontFamily
        )
        let fontFamily = customFont?.family ?? builtInFamily
        let fontFaceRule = customFont?.fontFace ?? ""
        let letterSpacingEm = String(format: "%.3f", inputs.characterSpacing / 100)
        let pageBreakRule = inputs.avoidPageBreak
            ? "p { break-inside: avoid; -webkit-column-break-inside: avoid; }"
            : ""
        let hintColor = ReaderThemeColor.cssHex(inputs.customHintColorHex, default: "#777777")
        let rubyRule = inputs.hideFurigana
            ? "ruby rt { display: none; }"
            : "ruby rt { color: \(hintColor); font-size: 0.55em; }"

        // Latin-dominant text wants word-boundary wrapping + hyphenation;
        // CJK wants `overflow-wrap: anywhere`. Vertical mode ignores
        // alignment (`text-align: start` is the only sensible value).
        let latinLayout = prefersLatinWordLayout(content, language: inputs.language)
        let wrappingRule = latinLayout
            ? "overflow-wrap: break-word; word-break: normal;"
            : "overflow-wrap: anywhere;"
        let hyphenRule = latinLayout ? "hyphens: auto; -webkit-hyphens: auto;" : ""
        let alignment = inputs.verticalLayout
            ? "start"
            : (inputs.justifyText && !latinLayout ? "justify" : (inputs.justifyText ? "justify" : "left"))
        let writingMode = inputs.verticalLayout ? "vertical-rl" : "horizontal-tb"
        let bodyWidthRule = inputs.verticalLayout
            ? "width: max-content; min-width: 100%;"
            : "max-width: 100%;"

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <style>
        :root { color-scheme: light dark; }
        html, body {
          margin: 0;
          -webkit-text-size-adjust: 100%;
          text-size-adjust: 100%;
          \(wrappingRule)
        }
        body {
          font-family: \(fontFamily);
          font-size: \(Int(inputs.fontSize))px;
          line-height: \(String(format: "%.2f", inputs.lineHeight));
          letter-spacing: \(letterSpacingEm)em;
          padding: \(Int(inputs.verticalPadding))px \(Int(inputs.horizontalPadding))px \(Int(inputs.verticalPadding) + 48)px \(Int(inputs.horizontalPadding))px;
          text-align: \(alignment);
          writing-mode: \(writingMode);
          text-orientation: mixed;
          \(bodyWidthRule)
          \(hyphenRule)
          \(theme)
        }
        \(fontFaceRule)
        p { margin: 0 0 1em 0; }
        \(pageBreakRule)
        \(rubyRule)
        ::highlight(amgi-reader-selection) {
          background-color: rgba(160, 160, 160, 0.4);
          color: inherit;
        }
        img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>\(content)</body>
        </html>
        """
    }

    /// CSS palette per theme mode. `system` defers to the OS via the
    /// `-apple-system-*` semantic colors; `eyeCare` is a low-contrast
    /// dark-on-cream palette tuned for long sessions; `sepia` matches
    /// Anki desktop; `custom` stays system until the user wires up the
    /// custom-color preference UI in a follow-up chunk.
    nonisolated static func themeCSS(
        for mode: ReaderThemeMode,
        customTextColorHex: String,
        customBackgroundColorHex: String
    ) -> String {
        switch mode {
        case .system:
            return "color: -apple-system-label; background: -apple-system-systemBackground;"
        case .custom:
            let text = ReaderThemeColor.cssHex(customTextColorHex, default: "#1F2A26")
            let bg = ReaderThemeColor.cssHex(customBackgroundColorHex, default: "#FAF7F2")
            return "color: \(text); background: \(bg);"
        case .eyeCare:
            return "color: #1f2a26; background: #e8f0e3;"
        case .sepia:
            return "color: #5b4636; background: #f4ecd8;"
        }
    }
}

extension Notification.Name {
    /// Toolbar → WebView ping that asks for the user's current text
    /// selection. The coordinator answers via `onSelectionForNote`.
    static let amgiReaderRequestSelection = Notification.Name("amgiReaderRequestSelection")
}

/// The full input set `ChapterReaderView.wrappedHTML` reads, so the rebuild
/// can be keyed on it. Deliberately excludes `scrollProgress` and the chapter
/// body itself — the chapter is identified by `chapterID`, and progress
/// doesn't affect the rendered HTML.
/// Internal rather than private: `ChapterWebView` moved to its own file and
/// `wrappedHTML` takes this as a parameter, and `private` is file-scoped.
struct ChapterRenderInputs: Equatable, Sendable {
    let chapterID: Int64
    let fontSize: Double
    let lineHeight: Double
    let horizontalPadding: Double
    let verticalPadding: Double
    let justifyText: Bool
    let themeModeRaw: String
    let selectedFontRaw: String
    let customTextColorHex: String
    let customBackgroundColorHex: String
    let characterSpacing: Double
    let avoidPageBreak: Bool
    let hideFurigana: Bool
    let customHintColorHex: String
    let verticalLayout: Bool
    let language: String?
}

/// Wrapper so an empty-string query is still presentable via .sheet(item:);
/// `.sheet(item:)` requires `Identifiable` and treats nil as "dismissed".
private struct LookupQuery: Identifiable {
    let id = UUID()
    let text: String
}

private struct ReaderNoteDraft: Identifiable {
    let id = UUID()
    let draft: AddNoteDraft
}
