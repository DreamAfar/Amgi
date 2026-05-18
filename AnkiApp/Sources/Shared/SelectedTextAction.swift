import UIKit
import WebKit

enum SelectedTextAction: String, Sendable, CaseIterable {
    case lookup
    case ai

    var title: String {
        switch self {
        case .lookup:
            return L("review_selection_menu_lookup")
        case .ai:
            return L("review_selection_menu_ai")
        }
    }
}

struct SelectedTextSnapshot: Sendable, Equatable {
    let text: String
    let sentence: String?

    init(text: String, sentence: String? = nil) {
        self.text = text
        self.sentence = sentence
    }

    var normalized: SelectedTextSnapshot? {
        guard let trimmedText = text.trimmedOrNil else {
            return nil
        }
        return SelectedTextSnapshot(text: trimmedText, sentence: sentence?.trimmedOrNil)
    }
}

class SelectedTextActionWebView: WKWebView {
    private static let selectionActionsMenuID = UIMenu.Identifier("net.ankireader.amgi.selectedTextActions")

    var currentSelectionSnapshot: SelectedTextSnapshot? {
        didSet { setNeedsMenuRebuild() }
    }

    var availableSelectionActions: [SelectedTextAction] = [] {
        didSet { setNeedsMenuRebuild() }
    }

    var onSelectionAction: ((SelectedTextAction, SelectedTextSnapshot) -> Void)?

    override var canBecomeFirstResponder: Bool {
        true
    }

    private func setNeedsMenuRebuild() {
        UIMenuSystem.main.setNeedsRebuild()
    }

    private func performSelectionAction(_ action: SelectedTextAction) {
        guard let snapshot = currentSelectionSnapshot?.normalized else { return }
        onSelectionAction?(action, snapshot)
    }

    private func selectionActionsMenu() -> UIMenu? {
        guard currentSelectionSnapshot?.normalized != nil else { return nil }

        let items = availableSelectionActions.map { action in
            UIAction(title: action.title) { [weak self] _ in
                self?.performSelectionAction(action)
            }
        }

        guard items.isEmpty == false else { return nil }
        return UIMenu(
            title: "",
            identifier: Self.selectionActionsMenuID,
            options: [.displayInline],
            children: items
        )
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard let menu = selectionActionsMenu() else { return }
        builder.insertSibling(menu, beforeMenu: .standardEdit)
    }
}
