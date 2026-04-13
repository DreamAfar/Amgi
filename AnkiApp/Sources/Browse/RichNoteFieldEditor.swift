import SwiftUI
import UIKit

/// A plain-text field editor for Anki note fields.
///
/// Anki stores field values as HTML fragments. This editor strips HTML tags for
/// display/editing and writes back plain text on change. This avoids the crash-
/// prone `NSAttributedString` HTML parsing path.
struct RichNoteFieldEditor: UIViewRepresentable {
    @Binding var htmlText: String

    private let commonSymbols = ["(", ")", ".", ",", ":", "#"]
    private let doneButtonTitle = L("common_done")

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
        context.coordinator.attach(textView: textView)
        textView.inputAccessoryView = makeInputToolbar(for: textView, coordinator: context.coordinator)

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

    private func makeInputToolbar(for textView: UITextView, coordinator: Coordinator) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 56))
        container.backgroundColor = .secondarySystemBackground

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = .separator
        container.addSubview(divider)

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        container.addSubview(scrollView)

        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        scrollView.addSubview(stackView)

        stackView.addArrangedSubview(
            makeSymbolButton(systemName: "arrow.uturn.backward") {
                textView.undoManager?.undo()
            }
        )
        stackView.addArrangedSubview(
            makeSymbolButton(systemName: "arrow.uturn.forward") {
                textView.undoManager?.redo()
            }
        )

        for symbol in commonSymbols {
            stackView.addArrangedSubview(
                makeTextButton(title: symbol) {
                    coordinator.insert(symbol)
                }
            )
        }

        stackView.addArrangedSubview(
            makeTextButton(title: doneButtonTitle) {
                textView.resignFirstResponder()
            }
        )

        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: container.topAnchor),
            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -16),
        ])

        return container
    }

    private func makeSymbolButton(systemName: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeTextButton(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = 10
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var htmlText: String
        weak var textView: UITextView?
        var lastRenderedValue: String = ""
        var lastPlainText: String = ""
        var isEditing = false

        init(htmlText: Binding<String>) {
            self._htmlText = htmlText
        }

        func attach(textView: UITextView) {
            self.textView = textView
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

        func insert(_ string: String) {
            guard let textView, let range = textView.selectedTextRange else { return }
            textView.replace(range, withText: string)
            commit(textView.text ?? "")
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
