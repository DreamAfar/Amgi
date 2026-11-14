//
//  ImageOcclusionEditorView.swift
//  BrowseFeature
//
//  Full-screen mask editor. The tool set mirrors Anki's mask editor —
//  select, rectangle, ellipse, polygon, text and fill, with undo/redo,
//  zoom, translucent masks, group/ungroup, duplicate, delete and the six
//  alignments — laid out as an iOS toolbar instead of a desktop sidebar.
//

#if canImport(UIKit)
import SwiftUI
import Theme
import UI

struct ImageOcclusionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    let image: UIImage
    let onSave: (_ shapes: [IOShape], _ occludeInactive: Bool) -> Void

    @State private var model: IOEditorModel
    @State private var canvas = IOCanvasController()
    @State private var showDiscardConfirmation = false

    init(
        image: UIImage,
        shapes: [IOShape],
        occludeInactive: Bool,
        onSave: @escaping (_ shapes: [IOShape], _ occludeInactive: Bool) -> Void
    ) {
        self.image = image
        self.onSave = onSave
        _model = State(initialValue: IOEditorModel(imageSize: image.size, shapes: shapes, occludeInactive: occludeInactive))
    }

    var body: some View {
        IOCanvasView(image: image, model: model, controller: canvas, accent: UIColor(palette.accent))
            .background(palette.background)
            .overlay(alignment: .top) { viewControls }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBars }
            .toolbarVisibility(.hidden, for: .tabBar)
            .navigationTitle(String(localized: "Image Occlusion", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.hasChanges)
            .toolbar { navigationToolbar }
            .sheet(item: $model.textRequest) { request in
                IOTextEntrySheet(initialText: request.initialText) { text in
                    if let text { model.submitText(text, for: request) } else { model.textRequest = nil }
                }
            }
            .confirmationDialog(
                String(localized: "Discard changes?", bundle: .module),
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Discard", bundle: .module), role: .destructive) { dismiss() }
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
            }
    }

    // MARK: - Navigation bar

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel", bundle: .module)) {
                if model.hasChanges { showDiscardConfirmation = true } else { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "Done", bundle: .module)) {
                model.cancelPolygon()
                onSave(model.shapes, model.occludeInactive)
                dismiss()
            }
            .amgiToolbarTextButton()
        }
    }

    // MARK: - Top: mode, translucency, zoom

    private var viewControls: some View {
        HStack(spacing: AmgiSpacing.sm) {
            Menu {
                Picker(String(localized: "Occlusion mode", bundle: .module), selection: $model.occludeInactive) {
                    Text("Hide all, guess one", bundle: .module).tag(true)
                    Text("Hide one, guess one", bundle: .module).tag(false)
                }
            } label: {
                Label(
                    model.occludeInactive
                        ? String(localized: "Hide all, guess one", bundle: .module)
                        : String(localized: "Hide one, guess one", bundle: .module),
                    systemImage: model.occludeInactive ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle"
                )
                .amgiFont(.caption)
                .padding(.horizontal, AmgiSpacing.md)
                .padding(.vertical, AmgiSpacing.sm)
                .amgiMaterial(.regular, in: Capsule(), interactive: true)
            }
            .accessibilityHint(Text("Hide all: the other masks stay covered on each card. Hide one: only the asked mask is covered.", bundle: .module))

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                iconButton(
                    model.translucent ? "eye.slash" : "eye",
                    label: String(localized: "Translucent masks", bundle: .module),
                    isOn: model.translucent
                ) { model.translucent.toggle() }
                iconButton("minus.magnifyingglass", label: String(localized: "Zoom out", bundle: .module)) { canvas.zoomOut() }
                iconButton("plus.magnifyingglass", label: String(localized: "Zoom in", bundle: .module)) { canvas.zoomIn() }
                iconButton("arrow.up.left.and.down.right.magnifyingglass", label: String(localized: "Fit to screen", bundle: .module)) {
                    canvas.zoomToFit()
                }
            }
            .amgiMaterial(.regular, in: Capsule())
        }
        .padding(.horizontal, AmgiSpacing.md)
        .padding(.top, AmgiSpacing.sm)
    }

    // MARK: - Bottom: context row + tools

    private var bottomBars: some View {
        VStack(spacing: AmgiSpacing.sm) {
            contextRow
            toolRow
        }
        .padding(.horizontal, AmgiSpacing.md)
        .padding(.bottom, AmgiSpacing.sm)
    }

    @ViewBuilder
    private var contextRow: some View {
        if model.currentTool == .polygon, !model.draftPolygon.isEmpty {
            HStack(spacing: AmgiSpacing.md) {
                Text("Tap the first point to close the shape.", bundle: .module)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) { model.cancelPolygon() }
                Button(String(localized: "Close shape", bundle: .module)) { model.finishPolygon() }
                    .disabled(!model.canFinishPolygon)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, AmgiSpacing.md)
            .padding(.vertical, AmgiSpacing.sm)
            .amgiMaterial(.regular, in: RoundedRectangle(cornerRadius: AmgiRadius.control, style: .continuous))
        } else if model.currentTool == .fill {
            HStack(spacing: AmgiSpacing.md) {
                ColorPicker(String(localized: "Fill color", bundle: .module), selection: fillColorBinding, supportsOpacity: false)
                    .labelsHidden()
                Text("Tap a mask or label to fill it.", bundle: .module)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(String(localized: "Default", bundle: .module)) { model.fillColor = IOStyle.maskFill }
            }
            .padding(.horizontal, AmgiSpacing.md)
            .padding(.vertical, AmgiSpacing.sm)
            .amgiMaterial(.regular, in: RoundedRectangle(cornerRadius: AmgiRadius.control, style: .continuous))
        } else if !model.selection.isEmpty {
            HStack(spacing: 0) {
                iconButton("trash", label: String(localized: "Delete", bundle: .module), role: .destructive) { model.deleteSelection() }
                iconButton("plus.square.on.square", label: String(localized: "Duplicate", bundle: .module)) { model.duplicateSelection() }
                if model.canUngroup {
                    iconButton("square.dashed", label: String(localized: "Ungroup", bundle: .module)) { model.ungroupSelection() }
                } else {
                    iconButton("square.on.square.dashed", label: String(localized: "Group", bundle: .module)) { model.groupSelection() }
                        .disabled(!model.canGroup)
                }
                alignMenu
                iconButton("checklist", label: String(localized: "Select all", bundle: .module)) { model.selectAll() }
            }
            .frame(maxWidth: .infinity)
            .amgiMaterial(.regular, in: Capsule())
        } else {
            Text(hint)
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AmgiSpacing.xs)
        }
    }

    private var hint: String {
        switch model.currentTool {
        case .select: String(localized: "Tap a mask to select it. Drag on empty space to select several.", bundle: .module)
        case .rectangle, .ellipse: String(localized: "Drag to draw a mask. Use two fingers to move and zoom.", bundle: .module)
        case .polygon: String(localized: "Tap to place points.", bundle: .module)
        case .text: String(localized: "Tap to add a label. Labels show on every card.", bundle: .module)
        case .fill: ""
        }
    }

    private var alignMenu: some View {
        Menu {
            ForEach(IOAlignment.allCases, id: \.self) { alignment in
                Button(alignment.title, systemImage: alignment.systemImage) { model.align(alignment) }
            }
        } label: {
            Image(systemName: "align.horizontal.left")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Align", bundle: .module))
    }

    private var toolRow: some View {
        HStack(spacing: 0) {
            iconButton("arrow.uturn.backward", label: String(localized: "Undo", bundle: .module)) { model.undo() }
                .disabled(!model.canUndo)
            Divider().frame(height: 24)
            ForEach(IOTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }
            Divider().frame(height: 24)
            iconButton("arrow.uturn.forward", label: String(localized: "Redo", bundle: .module)) { model.redo() }
                .disabled(!model.canRedo)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AmgiSpacing.xxs)
        .amgiMaterial(.regular, in: Capsule())
    }

    private func toolButton(_ tool: IOTool) -> some View {
        let isSelected = model.currentTool == tool
        return Button {
            model.tool = tool
        } label: {
            Image(systemName: tool.systemImage)
                .symbolVariant(isSelected ? .fill : .none)
                .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background {
                    if isSelected {
                        Capsule().fill(palette.accentSoft)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tool.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconButton(
        _ systemImage: String,
        label: String,
        isOn: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(role == .destructive ? palette.danger : (isOn ? palette.accent : palette.textPrimary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var fillColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(amgiHex: model.fillColor) ?? .yellow) },
            set: { model.fillColor = UIColor($0).amgiHexString() }
        )
    }
}

// MARK: - Labels

extension IOTool {
    var title: String {
        switch self {
        case .select: String(localized: "Select", bundle: .module)
        case .rectangle: String(localized: "Rectangle", bundle: .module)
        case .ellipse: String(localized: "Ellipse", bundle: .module)
        case .polygon: String(localized: "Polygon", bundle: .module)
        case .text: String(localized: "Text", bundle: .module)
        case .fill: String(localized: "Fill", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .rectangle: "rectangle"
        case .ellipse: "oval"
        case .polygon: "pentagon"
        case .text: "character.textbox"
        case .fill: "drop"
        }
    }
}

extension IOAlignment {
    var title: String {
        switch self {
        case .left: String(localized: "Align left", bundle: .module)
        case .horizontalCenter: String(localized: "Align centers horizontally", bundle: .module)
        case .right: String(localized: "Align right", bundle: .module)
        case .top: String(localized: "Align top", bundle: .module)
        case .verticalCenter: String(localized: "Align centers vertically", bundle: .module)
        case .bottom: String(localized: "Align bottom", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .left: "align.horizontal.left"
        case .horizontalCenter: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .verticalCenter: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }
}

// MARK: - Text entry

/// Multi-line entry for a text label; Anki labels may span several lines.
private struct IOTextEntrySheet: View {
    @Environment(\.palette) private var palette
    let initialText: String
    /// nil when the user cancels.
    let onFinish: (String?) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(initialText: String, onFinish: @escaping (String?) -> Void) {
        self.initialText = initialText
        self.onFinish = onFinish
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .padding(AmgiSpacing.md)
                .background(palette.background)
                .navigationTitle(initialText.isEmpty
                    ? String(localized: "Add label", bundle: .module)
                    : String(localized: "Edit text", bundle: .module))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", bundle: .module)) { onFinish(nil) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done", bundle: .module)) { onFinish(text) }
                            .amgiToolbarTextButton()
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}
#endif
