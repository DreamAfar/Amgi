//
//  NoteImageMenu.swift
//  BrowseFeature
//

import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// An image tapped in a note field, as the page reported it.
struct TappedImage: Equatable, Sendable {
    /// Position among the field's images.
    let index: Int
    /// The `src` attribute as written in the field: usually a media filename.
    let src: String
    /// The `width` attribute, or empty.
    let width: String
    /// Where the menu points: the top centre of the image, in the web
    /// view's coordinates.
    let anchor: CGPoint

    init?(message: [String: Any]) {
        guard let index = (message["index"] as? NSNumber)?.intValue, index >= 0 else { return nil }
        func number(_ key: String) -> CGFloat {
            (message[key] as? NSNumber).map { CGFloat(truncating: $0) } ?? 0
        }
        self.index = index
        src = message["src"] as? String ?? ""
        width = message["width"] as? String ?? ""
        anchor = CGPoint(x: number("x") + number("w") / 2, y: number("y"))
    }
}

/// What the image menu offers, and the page script for each edit.
enum NoteImageMenu {
    /// Display widths, as a share of the field's width so they hold on any
    /// screen. Only the `width` attribute changes; the file stays as it is.
    static let widths = ["25%", "50%", "75%"]

    static func script(index: Int, action: String, value: String) -> String {
        "amgi.imageAction(\(index), \(RichTextCommand.literal(action)), \(RichTextCommand.literal(value)))"
    }
}

#if canImport(UIKit)
extension NoteImageMenu {
    enum Action: Equatable {
        case copyFilename
        /// A `width` attribute value, or nil for the original size.
        case resize(String?)
        case replace(RichTextToolbar.ImageSource)
        case remove
    }

    @MainActor
    static func menu(for image: TappedImage, canReplace: Bool, onAction: @escaping (Action) -> Void) -> UIMenu {
        func item(_ title: String, _ symbol: String?, isOn: Bool = false, attributes: UIMenuElement.Attributes = [], _ action: Action) -> UIAction {
            UIAction(
                title: title,
                image: symbol.flatMap(UIImage.init(systemName:)),
                attributes: attributes,
                state: isOn ? .on : .off
            ) { _ in onAction(action) }
        }

        let sizes = UIMenu(
            title: String(localized: "Display Size", bundle: .module),
            image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"),
            children: widths.map { width in
                item(width, nil, isOn: image.width == width, .resize(width))
            } + [
                item(String(localized: "Original Size", bundle: .module), nil, isOn: image.width.isEmpty, .resize(nil)),
            ]
        )

        var children: [UIMenuElement] = [
            item(String(localized: "Copy Filename", bundle: .module), "doc.on.doc", .copyFilename),
            sizes,
        ]
        if canReplace {
            var sources = [item(String(localized: "Photo Library", bundle: .module), "photo.on.rectangle", .replace(.photoLibrary))]
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                sources.append(item(String(localized: "Take Photo", bundle: .module), "camera", .replace(.camera)))
            }
            sources.append(item(String(localized: "Choose File", bundle: .module), "folder", .replace(.files)))
            children.append(UIMenu(
                title: String(localized: "Replace Image", bundle: .module),
                image: UIImage(systemName: "arrow.triangle.2.circlepath"),
                children: sources
            ))
        }
        children.append(item(String(localized: "Remove", bundle: .module), "trash", attributes: .destructive, .remove))
        return UIMenu(title: image.src, children: children)
    }
}
#endif
