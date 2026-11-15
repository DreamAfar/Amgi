//
//  RichNoteFieldEditor.swift
//  BrowseFeature
//
//  Created by Vladimir Gusev on 28.04.2026.
//

import Foundation
import SwiftUI
import Theme

#if canImport(UIKit)
import UIKit
import WebKit

/// A note field editor that edits the field's HTML as rich text.
///
/// Anki stores field values as HTML fragments. The field is edited in a
/// small web page (`RichFieldPage`) whose editable element holds that HTML
/// directly, so formatting, images and markup from other Anki clients show
/// as they will on the card and survive an edit untouched — the previous
/// plain-text editor stripped every tag from a field as soon as it was
/// focused. A field is only written back when it is actually edited.
///
/// The view sizes itself to its content and has no background of its own,
/// so it sits in a form row the way the plain text view did.
struct RichNoteFieldEditor: View {
    @Binding var htmlText: String

    @Environment(\.palette) private var palette
    @Environment(NoteImageInsertionModel.self) private var imageModel: NoteImageInsertionModel?
    @State private var contentHeight: CGFloat = RichNoteFieldEditor.minHeight

    fileprivate static let minHeight: CGFloat = 32
    /// Past this the field scrolls inside itself rather than growing, so a
    /// long field doesn't push the others off the screen.
    fileprivate static let maxHeight: CGFloat = 280

    var body: some View {
        RichFieldWebView(
            htmlText: $htmlText,
            contentHeight: $contentHeight,
            textColor: UIColor(palette.textPrimary),
            caretColor: UIColor(palette.accent),
            toolbarColors: ToolbarColors(
                background: UIColor(palette.surfaceElevated),
                border: UIColor(palette.border)
            ),
            imageModel: imageModel
        )
        .frame(height: min(max(contentHeight, Self.minHeight), Self.maxHeight))
    }
}

/// Colors of the keyboard toolbar, taken from the palette.
private struct ToolbarColors {
    let background: UIColor
    let border: UIColor
}

private struct RichFieldWebView: UIViewRepresentable {
    @Binding var htmlText: String
    @Binding var contentHeight: CGFloat
    let textColor: UIColor
    let caretColor: UIColor
    let toolbarColors: ToolbarColors
    let imageModel: NoteImageInsertionModel?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            htmlText: $htmlText,
            contentHeight: $contentHeight,
            caretColor: caretColor,
            toolbarColors: toolbarColors
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let coordinator = context.coordinator
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(coordinator.mediaScheme, forURLScheme: NoteMediaScheme.scheme)
        configuration.userContentController.add(coordinator, name: RichFieldPage.messageHandler)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false

        coordinator.attach(webView)
        coordinator.imageModel = imageModel
        coordinator.show(htmlText)
        coordinator.setColors(text: textColor, accent: caretColor, in: webView.traitCollection)
        webView.loadHTMLString(
            RichFieldPage.html(
                textColor: Coordinator.css(textColor, in: webView.traitCollection),
                caretColor: Coordinator.css(caretColor, in: webView.traitCollection)
            ),
            baseURL: NoteMediaScheme.baseURL
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.htmlText = $htmlText
        coordinator.contentHeight = $contentHeight
        coordinator.imageModel = imageModel
        coordinator.show(htmlText)
        coordinator.setColors(text: textColor, accent: caretColor, in: webView.traitCollection)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RichFieldPage.messageHandler)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var htmlText: Binding<String>
        var contentHeight: Binding<CGFloat>
        var imageModel: NoteImageInsertionModel?
        let mediaScheme = NoteMediaScheme()

        private weak var webView: WKWebView?
        private let caretColor: UIColor
        private let toolbarColors: ToolbarColors
        private var toolbar: RichTextToolbar?
        private var isReady = false
        /// The HTML the page holds, as last sent to it or reported by it.
        /// Comparing against this is what keeps the two directions from
        /// echoing: a change the page reported isn't pushed back at it
        /// (which would reset the caret), and a value the app set isn't
        /// reported as an edit.
        private var shownHTML = ""
        private var shownColors = ""

        init(
            htmlText: Binding<String>,
            contentHeight: Binding<CGFloat>,
            caretColor: UIColor,
            toolbarColors: ToolbarColors
        ) {
            self.htmlText = htmlText
            self.contentHeight = contentHeight
            self.caretColor = caretColor
            self.toolbarColors = toolbarColors
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            // Built on first use: a note can have dozens of fields, and
            // only the one being edited needs its toolbar.
            WebViewInputAccessory.install(on: webView) { [weak self] in
                self?.makeToolbarIfNeeded()
            }
        }

        // MARK: App → page

        func show(_ html: String) {
            guard html != shownHTML else { return }
            shownHTML = html
            if isReady { run("amgi.set(\(RichTextCommand.literal(html)))") }
        }

        func setColors(text: UIColor, accent: UIColor, in traits: UITraitCollection) {
            let textCSS = Self.css(text, in: traits)
            let accentCSS = Self.css(accent, in: traits)
            let key = textCSS + accentCSS
            guard key != shownColors else { return }
            shownColors = key
            if isReady {
                run("amgi.setColors(\(RichTextCommand.literal(textCSS)), \(RichTextCommand.literal(accentCSS)))")
            }
        }

        func perform(_ command: RichTextCommand) {
            run(command.script)
        }

        private func run(_ script: String) {
            webView?.evaluateJavaScript(script) { _, _ in }
        }

        // MARK: Page → app

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let name = body["name"] as? String else { return }
            switch name {
            case "ready":
                isReady = true
                if !shownHTML.isEmpty {
                    run("amgi.set(\(RichTextCommand.literal(shownHTML)))")
                }
            case "change":
                guard let html = body["html"] as? String else { return }
                let stored = NoteFieldHTML.normalizedForStorage(html)
                shownHTML = stored
                if htmlText.wrappedValue != stored { htmlText.wrappedValue = stored }
            case "height":
                guard let height = (body["height"] as? NSNumber).map({ CGFloat(truncating: $0) }), height > 0 else { return }
                if abs(contentHeight.wrappedValue - height) > 0.5 { contentHeight.wrappedValue = height }
                webView?.scrollView.isScrollEnabled = height > RichNoteFieldEditor.maxHeight
            case "state":
                toolbar?.apply(RichTextFormatting(message: body))
            case "focus":
                revealInEnclosingScrollView()
            default:
                break
            }
        }

        // MARK: Toolbar

        private func makeToolbarIfNeeded() -> UIView {
            if let toolbar { return toolbar }
            let toolbar = RichTextToolbar(
                accent: caretColor,
                background: toolbarColors.background,
                border: toolbarColors.border,
                showsImages: imageModel != nil
            )
            toolbar.onCommand = { [weak self] in self?.perform($0) }
            toolbar.onDismiss = { [weak self] in
                self?.run("amgi.blur()")
                self?.webView?.endEditing(true)
            }
            toolbar.onImage = { [weak self] source in
                guard let self, let imageModel = self.imageModel else { return }
                self.webView?.endEditing(true)
                // The page remembers where the caret was, so the image
                // lands there once the picker and the adjust sheet are done.
                imageModel.request(source) { [weak self] filename in
                    self?.perform(.insertImage(filename: filename))
                }
            }
            self.toolbar = toolbar
            return toolbar
        }

        /// WebKit scrolls its own content to the caret but not the form
        /// around it, so a field low on the screen would stay under the
        /// keyboard. Once the keyboard is up, bring the field into view.
        private func revealInEnclosingScrollView() {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let webView = self?.webView else { return }
                var ancestor = webView.superview
                while let view = ancestor, !(view is UIScrollView) { ancestor = view.superview }
                guard let scrollView = ancestor as? UIScrollView else { return }
                let rect = webView.convert(webView.bounds, to: scrollView).insetBy(dx: 0, dy: -12)
                scrollView.scrollRectToVisible(rect, animated: true)
            }
        }

        /// A color as CSS `rgba()`, resolved for the given appearance.
        static func css(_ color: UIColor, in traits: UITraitCollection) -> String {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
            return "rgba(\(channel(red)), \(channel(green)), \(channel(blue)), \(Double(alpha)))"
        }
    }
}

#else

struct RichNoteFieldEditor: View {
    @Binding var htmlText: String

    var body: some View {
        TextEditor(text: $htmlText)
            .scrollContentBackground(.hidden)
    }
}

#endif

/// Storage-form fixes for field HTML coming out of the editor.
enum NoteFieldHTML {
    /// Rewrites `<anki-mathjax>` elements — the desktop editor's in-editor
    /// form of an equation — to the `\(…\)` / `\[…\]` delimiters fields
    /// store.
    static func normalizedForStorage(_ text: String) -> String {
        guard text.localizedCaseInsensitiveContains("anki-mathjax") else { return text }
        let pattern = #"<anki-mathjax(?:[^>]*?block=\"(.*?)\")?[^>]*?>(.*?)</anki-mathjax>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return text
        }

        let source = text as NSString
        var output = ""
        output.reserveCapacity(source.length)
        var currentLocation = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let fullRange = match.range(at: 0)
            output += source.substring(with: NSRange(location: currentLocation, length: fullRange.location - currentLocation))

            let blockValue: String? = {
                let range = match.range(at: 1)
                guard range.location != NSNotFound else { return nil }
                return source.substring(with: range)
            }()

            let innerText: String = {
                let range = match.range(at: 2)
                guard range.location != NSNotFound else { return "" }
                return source.substring(with: range)
            }()

            let trimmed = trimMathJaxBreaks(in: innerText)
            if let blockValue, !blockValue.isEmpty, blockValue.caseInsensitiveCompare("false") != .orderedSame {
                output += #"\["# + trimmed + #"\]"#
            } else {
                output += #"\("# + trimmed + #"\)"#
            }

            currentLocation = fullRange.location + fullRange.length
        }

        output += source.substring(from: currentLocation)
        return output
    }

    private static func trimMathJaxBreaks(in text: String) -> String {
        text
            .replacingOccurrences(
                of: #"<br[ ]*/?>"#,
                with: "\n",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: #"^\n*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n*$"#, with: "", options: .regularExpression)
    }
}
