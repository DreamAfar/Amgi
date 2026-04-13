import SwiftUI
import UIKit

struct TemplateSourceEditor: UIViewRepresentable {
    @Binding var text: String

    let fieldNames: [String]
    let insertableTokens: [String]
    let fieldButtonTitle: String
    let doneButtonTitle: String
    let searchQuery: String

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
        context.coordinator.applySearch(searchQuery, in: textView)
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
        context.coordinator.applySearch(searchQuery, in: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        weak var textView: UITextView?
        var lastValue: String = ""
        var isHandlingProgrammaticChange = false
        private var lastSearchKey = ""

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

        func applySearch(_ query: String, in textView: UITextView) {
            let key = "\(query)|\(textView.text ?? "")"
            guard key != lastSearchKey else { return }
            lastSearchKey = key

            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let nsText = textView.text as NSString? ?? ""
            let range = nsText.range(of: trimmed, options: [.caseInsensitive])
            guard range.location != NSNotFound else { return }

            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
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
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 50))
            toolbar.backgroundColor = .secondarySystemBackground
            toolbar.barTintColor = .secondarySystemBackground
            toolbar.tintColor = .label

            var items: [UIBarButtonItem] = [
                UIBarButtonItem(
                    customView: makeToolbarIconButton(systemName: "arrow.uturn.backward") { [weak self] in
                        self?.textView?.undoManager?.undo()
                    }
                ),
                fixedSpaceItem(8),
                UIBarButtonItem(
                    customView: makeToolbarIconButton(systemName: "arrow.uturn.forward") { [weak self] in
                        self?.textView?.undoManager?.redo()
                    }
                )
            ]

            if !fieldNames.isEmpty {
                let fieldActions = fieldNames.map { fieldName in
                    UIAction(title: fieldName) { [weak self] _ in
                        self?.insert("{{\(fieldName)}}")
                    }
                }
                items.append(fixedSpaceItem(8))
                items.append(
                    UIBarButtonItem(
                        customView: makeToolbarMenuButton(
                            title: fieldButtonTitle,
                            menu: UIMenu(children: fieldActions)
                        )
                    )
                )
            }

            if !insertableTokens.isEmpty {
                let tokenActions = insertableTokens.map { token in
                    UIAction(title: token) { [weak self] _ in
                        self?.insert(token)
                    }
                }
                items.append(fixedSpaceItem(8))
                items.append(
                    UIBarButtonItem(
                        customView: makeToolbarMenuButton(
                            title: L("card_template_insert_short"),
                            menu: UIMenu(children: tokenActions)
                        )
                    )
                )
            }

            items.append(.flexibleSpace())
            items.append(
                UIBarButtonItem(
                    customView: makeToolbarActionButton(title: doneButtonTitle) { [weak self] in
                        self?.textView?.resignFirstResponder()
                    }
                )
            )

            toolbar.items = items
            toolbar.sizeToFit()
            return toolbar
        }

        private func insert(_ string: String) {
            guard let textView, let range = textView.selectedTextRange else { return }
            isHandlingProgrammaticChange = true
            textView.replace(range, withText: string)
            isHandlingProgrammaticChange = false
            textViewDidChange(textView)
        }

        private func makeToolbarIconButton(systemName: String, action: @escaping () -> Void) -> UIButton {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setImage(UIImage(systemName: systemName), for: .normal)
            button.tintColor = .label
            var configuration = UIButton.Configuration.bordered()
            configuration.buttonSize = .small
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
            button.configuration = configuration
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            return button
        }

        private func makeToolbarMenuButton(title: String, menu: UIMenu) -> UIButton {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            var configuration = UIButton.Configuration.bordered()
            configuration.buttonSize = .small
            configuration.title = title
            configuration.image = UIImage(systemName: "chevron.down")
            configuration.imagePlacement = .trailing
            configuration.imagePadding = 6
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
            button.configuration = configuration
            button.menu = menu
            button.showsMenuAsPrimaryAction = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            return button
        }

        private func makeToolbarActionButton(title: String, action: @escaping () -> Void) -> UIButton {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            var configuration = UIButton.Configuration.borderedTinted()
            configuration.buttonSize = .small
            configuration.title = title
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            button.configuration = configuration
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            return button
        }

        private func fixedSpaceItem(_ width: CGFloat) -> UIBarButtonItem {
            let item = UIBarButtonItem(systemItem: .fixedSpace)
            item.width = width
            return item
        }
    }
}