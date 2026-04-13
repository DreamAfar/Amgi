import SwiftUI
import UIKit

struct TemplateSourceEditor: UIViewRepresentable {
    @Binding var text: String

    let fieldNames: [String]
    let insertableTokens: [String]
    let fieldButtonTitle: String
    let doneButtonTitle: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textView.textColor = .label
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.spellCheckingType = .no
        textView.keyboardDismissMode = .interactive
        textView.text = text

        context.coordinator.attach(textView: textView)
        context.coordinator.lastValue = text
        context.coordinator.configureAccessoryView(
            fieldNames: fieldNames,
            insertableTokens: insertableTokens,
            fieldButtonTitle: fieldButtonTitle,
            doneButtonTitle: doneButtonTitle
        )
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text, !context.coordinator.isHandlingProgrammaticChange {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            let maxLocation = min(selectedRange.location, uiView.text.utf16.count)
            uiView.selectedRange = NSRange(location: maxLocation, length: 0)
            context.coordinator.lastValue = text
        }

        context.coordinator.attach(textView: uiView)
        context.coordinator.configureAccessoryView(
            fieldNames: fieldNames,
            insertableTokens: insertableTokens,
            fieldButtonTitle: fieldButtonTitle,
            doneButtonTitle: doneButtonTitle
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        weak var textView: UITextView?
        var lastValue: String = ""
        var isHandlingProgrammaticChange = false

        private var lastFieldNames: [String] = []
        private var lastInsertableTokens: [String] = []
        private var lastFieldButtonTitle = ""
        private var lastDoneButtonTitle = ""

        init(text: Binding<String>) {
            self._text = text
        }

        func attach(textView: UITextView) {
            self.textView = textView
        }

        func textViewDidChange(_ textView: UITextView) {
            lastValue = textView.text
            text = textView.text
        }

        func configureAccessoryView(
            fieldNames: [String],
            insertableTokens: [String],
            fieldButtonTitle: String,
            doneButtonTitle: String
        ) {
            guard
                fieldNames != lastFieldNames
                    || insertableTokens != lastInsertableTokens
                    || fieldButtonTitle != lastFieldButtonTitle
                    || doneButtonTitle != lastDoneButtonTitle
            else {
                return
            }

            lastFieldNames = fieldNames
            lastInsertableTokens = insertableTokens
            lastFieldButtonTitle = fieldButtonTitle
            lastDoneButtonTitle = doneButtonTitle

            textView?.inputAccessoryView = makeAccessoryView(
                fieldNames: fieldNames,
                insertableTokens: insertableTokens,
                fieldButtonTitle: fieldButtonTitle,
                doneButtonTitle: doneButtonTitle
            )
            textView?.reloadInputViews()
        }

        private func makeAccessoryView(
            fieldNames: [String],
            insertableTokens: [String],
            fieldButtonTitle: String,
            doneButtonTitle: String
        ) -> UIView {
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

            let undoButton = makeSymbolButton(systemName: "arrow.uturn.backward") { [weak self] in
                self?.textView?.undoManager?.undo()
            }
            let redoButton = makeSymbolButton(systemName: "arrow.uturn.forward") { [weak self] in
                self?.textView?.undoManager?.redo()
            }
            stackView.addArrangedSubview(undoButton)
            stackView.addArrangedSubview(redoButton)

            if !fieldNames.isEmpty {
                let actions = fieldNames.map { fieldName in
                    UIAction(title: fieldName) { [weak self] _ in
                        self?.insert("{{\(fieldName)}}")
                    }
                }
                let fieldButton = makeTextButton(title: fieldButtonTitle)
                fieldButton.menu = UIMenu(children: actions)
                fieldButton.showsMenuAsPrimaryAction = true
                stackView.addArrangedSubview(fieldButton)
            }

            for token in insertableTokens {
                let button = makeTextButton(title: token) { [weak self] in
                    self?.insert(token)
                }
                stackView.addArrangedSubview(button)
            }

            let doneButton = makeTextButton(title: doneButtonTitle) { [weak self] in
                self?.textView?.resignFirstResponder()
            }
            stackView.addArrangedSubview(doneButton)

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
                stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -16)
            ])

            return container
        }

        private func insert(_ string: String) {
            guard let textView, let range = textView.selectedTextRange else { return }
            isHandlingProgrammaticChange = true
            textView.replace(range, withText: string)
            isHandlingProgrammaticChange = false
            textViewDidChange(textView)
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

        private func makeTextButton(title: String, action: (() -> Void)? = nil) -> UIButton {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle(title, for: .normal)
            button.setTitleColor(.label, for: .normal)
            button.backgroundColor = .tertiarySystemFill
            button.layer.cornerRadius = 10
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            if let action {
                button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            }
            return button
        }
    }
}