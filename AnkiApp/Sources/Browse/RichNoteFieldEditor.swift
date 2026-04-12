import SwiftUI
import UIKit

/// A plain-text field editor for Anki note fields.
///
/// Anki stores field values as HTML fragments. This editor strips HTML tags for
/// display/editing and writes back plain text on change. This avoids the crash-
/// prone `NSAttributedString` HTML parsing path.
struct RichNoteFieldEditor: UIViewRepresentable {
    @Binding var htmlText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(htmlText: $htmlText)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.layer.cornerRadius = 0
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textColor = .label
        textView.inputAccessoryView = makeDoneToolbar(for: textView)

        textView.text = Coordinator.plainText(from: htmlText)
        context.coordinator.lastRenderedValue = htmlText
        context.coordinator.lastPlainText = textView.text ?? ""
        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = min(max(32, fit.height), 160)
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard !context.coordinator.isEditing else { return }
        guard htmlText != context.coordinator.lastRenderedValue else { return }

        let plain = Coordinator.plainText(from: htmlText)
        if uiView.text != plain {
            let selected = uiView.selectedRange
            uiView.text = plain
            let maxLoc = max(0, min(selected.location, plain.utf16.count))
            uiView.selectedRange = NSRange(location: maxLoc, length: 0)
        }
        context.coordinator.lastRenderedValue = htmlText
        context.coordinator.lastPlainText = plain
    }

    // MARK: - Toolbar

    private func makeDoneToolbar(for textView: UITextView) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(
                systemItem: .done,
                primaryAction: UIAction { [weak textView] _ in
                    textView?.resignFirstResponder()
                }
            ),
        ]
        toolbar.sizeToFit()
        return toolbar
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var htmlText: String
        var lastRenderedValue: String = ""
        var lastPlainText: String = ""
        var isEditing = false

        init(htmlText: Binding<String>) {
            self._htmlText = htmlText
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            commit(textView.text ?? "")
        }

        func textViewDidChange(_ textView: UITextView) {
            commit(textView.text ?? "")
        }

        private func commit(_ plain: String) {
            lastPlainText = plain
            lastRenderedValue = plain
            htmlText = plain
        }

        // MARK: - HTML strip

        /// Strips HTML tags and decodes common entities to produce editable plain text.
        static func plainText(from html: String) -> String {
            guard !html.isEmpty else { return "" }
            guard isLikelyHTML(html) else { return html }

            var result = ""
            result.reserveCapacity(html.count)
            var inTag = false
            for ch in html.unicodeScalars {
                switch ch {
                case "<": inTag = true
                case ">": inTag = false
                default:
                    if !inTag { result.unicodeScalars.append(ch) }
                }
            }

            result = result
                .replacingOccurrences(of: "&amp;",  with: "&")
                .replacingOccurrences(of: "&lt;",   with: "<")
                .replacingOccurrences(of: "&gt;",   with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;",  with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " ")

            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func isLikelyHTML(_ text: String) -> Bool {
            text.contains("<") && text.contains(">")
        }
    }
}
