//
//  SelectionMenuWebView.swift
//  AppShared
//

#if canImport(UIKit)
public import UIKit
public import WebKit

/// Text the user selected in a web view, with the sentence around it.
public struct WebSelection: Sendable, Equatable {
    public let text: String
    /// The sentence containing the selection, when it could be found.
    public let sentence: String?

    public init(text: String, sentence: String?) {
        self.text = text
        self.sentence = sentence
    }

    /// From `SelectionMenuWebView.selectionScript`'s result.
    public init?(scriptResult: Any?) {
        guard let result = scriptResult as? [String: Any],
              let text = (result["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let sentence = (result["sentence"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(text: text, sentence: sentence?.isEmpty == false ? sentence : nil)
    }

    /// The sentence with the selection wrapped in `<b>`, for a note field.
    public var sentenceHTML: String? {
        guard let sentence else { return nil }
        guard let range = sentence.range(of: text) else { return sentence }
        return sentence.replacingCharacters(in: range, with: "<b>\(text)</b>")
    }
}

/// An item this app adds to the system's text-selection menu.
public struct WebSelectionAction {
    public let title: String
    public let systemImage: String
    public let handler: @MainActor (WebSelection) -> Void

    public init(title: String, systemImage: String, handler: @escaping @MainActor (WebSelection) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.handler = handler
    }
}

/// A web view whose text-selection menu — the system's own, with Copy,
/// Look Up and the rest — also offers this app's actions, placed ahead
/// of them. The menu keeps the system's look in every iOS version;
/// only the items are ours.
open class SelectionMenuWebView: WKWebView {
    /// Read each time the menu opens, so it can change with the content.
    public var selectionActions: [WebSelectionAction] = []

    override open func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context, !selectionActions.isEmpty else { return }
        let items = selectionActions.map { action in
            UIAction(title: action.title, image: UIImage(systemName: action.systemImage)) { [weak self] _ in
                self?.currentSelection { selection in
                    if let selection { action.handler(selection) }
                }
            }
        }
        let menu = UIMenu(options: .displayInline, children: items)
        // Ahead of Copy / Look Up, so the app's actions show without
        // paging the menu.
        if builder.menu(for: .standardEdit) != nil {
            builder.insertSibling(menu, beforeMenu: .standardEdit)
        } else {
            builder.insertChild(menu, atStartOfMenu: .root)
        }
    }

    /// The current selection, or nil when nothing is selected.
    public func currentSelection(_ completion: @escaping @MainActor (WebSelection?) -> Void) {
        evaluateJavaScript(Self.selectionScript) { result, _ in
            completion(WebSelection(scriptResult: result))
        }
    }

    /// Returns `{text, sentence}` for the selection: the sentence is cut
    /// from the selection's block at the nearest sentence ends (Chinese,
    /// Japanese and Latin punctuation, or a line break).
    public static let selectionScript = #"""
(function () {
  var selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) { return null; }
  var text = selection.toString().replace(/\s+/g, ' ').trim();
  if (!text) { return null; }
  var node = selection.getRangeAt(0).startContainer;
  var element = node.nodeType === 3 ? node.parentElement : node;
  var block = (element && element.closest('p, li, td, th, blockquote, dd, dt, h1, h2, h3, h4, h5, h6, div')) || document.body;
  var full = (block.innerText || '').replace(/\s+/g, ' ');
  var at = full.indexOf(text);
  var sentence = null;
  if (at >= 0) {
    var terminators = '。！？!?.\n';
    var start = at;
    while (start > 0 && at - start < 200 && terminators.indexOf(full[start - 1]) < 0) { start--; }
    var end = at + text.length;
    if (terminators.indexOf(full[end - 1]) < 0) {
      while (end < full.length && end - at < 300) {
        var ch = full[end];
        end++;
        if (terminators.indexOf(ch) >= 0) { break; }
      }
    }
    sentence = full.slice(start, end).trim();
  }
  return { text: text, sentence: sentence };
})()
"""#
}
#endif
