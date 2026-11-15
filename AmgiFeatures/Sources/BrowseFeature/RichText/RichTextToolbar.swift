//
//  RichTextToolbar.swift
//  BrowseFeature
//

#if canImport(UIKit)
import Foundation
import UIKit

/// The formatting bar above the keyboard while a note field is being
/// edited. One scrolling row: the toggles people reach for most first,
/// menus for the choices that need a second step (colors, lists,
/// alignment, MathJax, images), and a fixed button at the trailing edge to
/// put the keyboard away. Toggles light up to match the caret.
///
/// Built on `UIInputView` so it takes the keyboard's own backdrop and
/// reads as part of it in both appearances.
@MainActor
final class RichTextToolbar: UIInputView {
    enum ImageSource: CaseIterable {
        case photoLibrary, camera, files
    }

    var onCommand: ((RichTextCommand) -> Void)?
    var onImage: ((ImageSource) -> Void)?
    var onDismiss: (() -> Void)?

    private let accent: UIColor
    private var toggles: [Toggle: UIButton] = [:]
    private var listButton: UIButton?
    private var alignButton: UIButton?
    private var formatting = RichTextFormatting()

    private enum Toggle: CaseIterable {
        case bold, italic, underline, strikethrough, subscriptText, superscriptText
    }

    private static let barHeight: CGFloat = 46
    private static let buttonSize: CGFloat = 36

    init(accent: UIColor, showsImages: Bool) {
        self.accent = accent
        super.init(
            frame: CGRect(x: 0, y: 0, width: 320, height: Self.barHeight),
            inputViewStyle: .keyboard
        )
        allowsSelfSizing = true
        build(showsImages: showsImages)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.barHeight)
    }

    /// Lights the toggles that apply at the caret.
    func apply(_ formatting: RichTextFormatting) {
        guard formatting != self.formatting else { return }
        self.formatting = formatting
        toggles[.bold]?.isSelected = formatting.bold
        toggles[.italic]?.isSelected = formatting.italic
        toggles[.underline]?.isSelected = formatting.underline
        toggles[.strikethrough]?.isSelected = formatting.strikethrough
        toggles[.subscriptText]?.isSelected = formatting.subscriptText
        toggles[.superscriptText]?.isSelected = formatting.superscriptText
        listButton?.isSelected = formatting.bulletList || formatting.numberedList
        alignButton?.isSelected = formatting.alignment != .left
        alignButton?.configuration?.image = UIImage(systemName: formatting.alignment.symbol)
        listButton?.menu = listMenu()
        alignButton?.menu = alignMenu()
    }

    // MARK: - Layout

    private func build(showsImages: Bool) {
        let dismiss = makeButton(
            symbol: "keyboard.chevron.compact.down",
            title: String(localized: "Hide Keyboard", bundle: .module)
        ) { [weak self] in self?.onDismiss?() }
        dismiss.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismiss)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        var groups: [[UIView]] = [
            [
                toggle(.bold, symbol: "bold", title: String(localized: "Bold", bundle: .module), command: .bold),
                toggle(.italic, symbol: "italic", title: String(localized: "Italic", bundle: .module), command: .italic),
                toggle(.underline, symbol: "underline", title: String(localized: "Underline", bundle: .module), command: .underline),
                toggle(.strikethrough, symbol: "strikethrough", title: String(localized: "Strikethrough", bundle: .module), command: .strikethrough),
            ],
            [
                menuButton(
                    symbol: "paintpalette",
                    title: String(localized: "Text Color", bundle: .module),
                    menu: colorMenu(RichTextSwatch.textColors, removeTitle: nil) { color in .textColor(color ?? "inherit") }
                ),
                menuButton(
                    symbol: "highlighter",
                    title: String(localized: "Highlight", bundle: .module),
                    menu: colorMenu(
                        RichTextSwatch.highlights,
                        removeTitle: String(localized: "No Highlight", bundle: .module)
                    ) { color in .highlight(color) }
                ),
            ],
            [
                toggle(.subscriptText, symbol: "textformat.subscript", title: String(localized: "Subscript", bundle: .module), command: .subscriptText),
                toggle(.superscriptText, symbol: "textformat.superscript", title: String(localized: "Superscript", bundle: .module), command: .superscriptText),
            ],
        ]

        let list = menuButton(symbol: "list.bullet", title: String(localized: "List", bundle: .module), menu: listMenu())
        let align = menuButton(symbol: RichTextAlignment.left.symbol, title: String(localized: "Alignment", bundle: .module), menu: alignMenu())
        listButton = list
        alignButton = align
        groups.append([list, align])

        var insert: [UIView] = [
            menuButton(symbol: "function", title: String(localized: "MathJax", bundle: .module), menu: mathMenu()),
        ]
        if showsImages {
            insert.append(menuButton(symbol: "photo", title: String(localized: "Insert Image", bundle: .module), menu: imageMenu()))
        }
        groups.append(insert)

        groups.append([
            makeButton(symbol: "eraser", title: String(localized: "Clear formatting", bundle: .module)) { [weak self] in
                self?.onCommand?(.clearFormatting)
            },
            makeButton(symbol: "arrow.uturn.backward", title: String(localized: "Undo", bundle: .module)) { [weak self] in
                self?.onCommand?(.undo)
            },
            makeButton(symbol: "arrow.uturn.forward", title: String(localized: "Redo", bundle: .module)) { [weak self] in
                self?.onCommand?(.redo)
            },
        ])

        for (index, group) in groups.enumerated() {
            if index > 0 { stack.addArrangedSubview(separator()) }
            group.forEach(stack.addArrangedSubview)
        }

        NSLayoutConstraint.activate([
            dismiss.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            dismiss.centerYAnchor.constraint(equalTo: centerYAnchor),

            divider.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor, constant: -4),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
            divider.heightAnchor.constraint(equalToConstant: 24),

            scroll.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    private func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(line)
        NSLayoutConstraint.activate([
            holder.widthAnchor.constraint(equalToConstant: 13),
            holder.heightAnchor.constraint(equalToConstant: 20),
            line.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            line.topAnchor.constraint(equalTo: holder.topAnchor),
            line.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            line.widthAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),
        ])
        return holder
    }

    // MARK: - Buttons

    private func makeButton(symbol: String, title: String, action: (() -> Void)?) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: symbol)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        configuration.contentInsets = .zero
        configuration.background.cornerRadius = 8

        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        button.showsLargeContentViewer = true
        button.largeContentTitle = title
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize),
        ])
        let tint = self.accent
        button.configurationUpdateHandler = { updated in
            var configuration = updated.configuration
            configuration?.baseForegroundColor = updated.isSelected ? tint : UIColor.label
            if updated.isSelected {
                configuration?.background.backgroundColor = tint.withAlphaComponent(0.16)
            } else if updated.isHighlighted {
                configuration?.background.backgroundColor = UIColor.label.withAlphaComponent(0.08)
            } else {
                configuration?.background.backgroundColor = UIColor.clear
            }
            updated.configuration = configuration
        }
        if let action {
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        return button
    }

    private func toggle(_ toggle: Toggle, symbol: String, title: String, command: RichTextCommand) -> UIButton {
        let button = makeButton(symbol: symbol, title: title) { [weak self] in self?.onCommand?(command) }
        toggles[toggle] = button
        return button
    }

    private func menuButton(symbol: String, title: String, menu: UIMenu) -> UIButton {
        let button = makeButton(symbol: symbol, title: title, action: nil)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        return button
    }

    // MARK: - Menus

    private func action(_ title: String, symbol: String? = nil, image: UIImage? = nil, isOn: Bool = false, _ command: RichTextCommand) -> UIAction {
        UIAction(
            title: title,
            image: image ?? symbol.flatMap(UIImage.init(systemName:)),
            state: isOn ? .on : .off
        ) { [weak self] _ in self?.onCommand?(command) }
    }

    private func colorMenu(
        _ swatches: [RichTextSwatch],
        removeTitle: String?,
        command: @escaping (String?) -> RichTextCommand
    ) -> UIMenu {
        var children: [UIMenuElement] = swatches.map { swatch in
            action(swatch.title, image: swatch.image, command(swatch.css))
        }
        if let removeTitle {
            children.append(UIMenu(options: .displayInline, children: [
                action(removeTitle, symbol: "circle.slash", command(nil)),
            ]))
        }
        return UIMenu(children: children)
    }

    private func listMenu() -> UIMenu {
        UIMenu(children: [
            action(String(localized: "Bulleted List", bundle: .module), symbol: "list.bullet", isOn: formatting.bulletList, .bulletList),
            action(String(localized: "Numbered List", bundle: .module), symbol: "list.number", isOn: formatting.numberedList, .numberedList),
        ])
    }

    private func alignMenu() -> UIMenu {
        UIMenu(children: RichTextAlignment.allCases.map { alignment in
            let title = switch alignment {
            case .left: String(localized: "Align Left", bundle: .module)
            case .center: String(localized: "Center", bundle: .module)
            case .right: String(localized: "Align Right", bundle: .module)
            }
            return action(title, symbol: alignment.symbol, isOn: formatting.alignment == alignment, .align(alignment))
        })
    }

    private func mathMenu() -> UIMenu {
        UIMenu(children: [
            action(String(localized: "Inline Equation", bundle: .module), symbol: "x.squareroot", .math(.inline)),
            action(String(localized: "Block Equation", bundle: .module), symbol: "sum", .math(.block)),
            action(String(localized: "Chemical Equation", bundle: .module), symbol: "flask", .math(.chemistry)),
        ])
    }

    private func imageMenu() -> UIMenu {
        func item(_ title: String, _ symbol: String, _ source: ImageSource) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in self?.onImage?(source) }
        }
        var children = [item(String(localized: "Photo Library", bundle: .module), "photo.on.rectangle", .photoLibrary)]
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            children.append(item(String(localized: "Take Photo", bundle: .module), "camera", .camera))
        }
        children.append(item(String(localized: "Choose File", bundle: .module), "folder", .files))
        return UIMenu(children: children)
    }
}

/// A preset color of the text-color and highlight menus.
struct RichTextSwatch {
    let title: String
    /// `#rrggbb`, as written into the field.
    let css: String

    @MainActor var image: UIImage? {
        guard let value = UInt32(css.dropFirst(), radix: 16) else { return nil }
        let color = UIColor(cgColor: CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        ))
        return UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    /// Mid-tone hues that stay readable on both a light and a dark card.
    static var textColors: [RichTextSwatch] {
        [
            RichTextSwatch(title: String(localized: "Red", bundle: .module), css: "#e53935"),
            RichTextSwatch(title: String(localized: "Orange", bundle: .module), css: "#f57c00"),
            RichTextSwatch(title: String(localized: "Green", bundle: .module), css: "#43a047"),
            RichTextSwatch(title: String(localized: "Teal", bundle: .module), css: "#00897b"),
            RichTextSwatch(title: String(localized: "Blue", bundle: .module), css: "#1e88e5"),
            RichTextSwatch(title: String(localized: "Purple", bundle: .module), css: "#8e24aa"),
            RichTextSwatch(title: String(localized: "Pink", bundle: .module), css: "#d81b60"),
            RichTextSwatch(title: String(localized: "Gray", bundle: .module), css: "#757575"),
        ]
    }

    static var highlights: [RichTextSwatch] {
        [
            RichTextSwatch(title: String(localized: "Yellow", bundle: .module), css: "#ffeb3b"),
            RichTextSwatch(title: String(localized: "Green", bundle: .module), css: "#a5d6a7"),
            RichTextSwatch(title: String(localized: "Blue", bundle: .module), css: "#90caf9"),
            RichTextSwatch(title: String(localized: "Pink", bundle: .module), css: "#f48fb1"),
            RichTextSwatch(title: String(localized: "Orange", bundle: .module), css: "#ffcc80"),
            RichTextSwatch(title: String(localized: "Purple", bundle: .module), css: "#ce93d8"),
        ]
    }
}
#endif
