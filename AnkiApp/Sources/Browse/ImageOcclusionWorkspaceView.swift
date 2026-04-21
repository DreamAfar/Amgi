import SwiftUI
import UIKit

private struct IOMaskSnapshot: Equatable {
    var masks: [IOMask]
    var selectedMaskIndex: Int?
    var selectedMaskIndices: Set<Int>
}

enum IOCanvasZoomCommand {
    case zoomIn
    case zoomOut
    case fit
}

private enum IOMaskFillOption: CaseIterable {
    case `default`
    case yellow
    case red
    case blue
    case green

    var label: String {
        switch self {
        case .default: return L("rich_text_color_default")
        case .yellow: return L("io_fill_yellow")
        case .red: return L("rich_text_color_red")
        case .blue: return L("rich_text_color_blue")
        case .green: return L("rich_text_color_green")
        }
    }

    var hex: String? {
        switch self {
        case .default: return nil
        case .yellow: return "FFEBA2CC"
        case .red: return "FF8E8ECC"
        case .blue: return "8FB8FFCC"
        case .green: return "A7E3AECC"
        }
    }
}

private enum IOMaskAlignMode: CaseIterable {
    case left
    case horizontalCenter
    case right
    case top
    case verticalCenter
    case bottom

    var label: String {
        switch self {
        case .left: return L("io_align_left")
        case .horizontalCenter: return L("io_align_center_h")
        case .right: return L("io_align_right")
        case .top: return L("io_align_top")
        case .verticalCenter: return L("io_align_center_v")
        case .bottom: return L("io_align_bottom")
        }
    }
}

private enum IOOcclusionMode: CaseIterable {
    case hideAllGuessOne
    case hideOneGuessOne

    var label: String {
        switch self {
        case .hideAllGuessOne: return L("io_mode_hide_all_guess_one")
        case .hideOneGuessOne: return L("io_mode_hide_one_guess_one")
        }
    }

    var occludesInactive: Bool {
        switch self {
        case .hideAllGuessOne: return true
        case .hideOneGuessOne: return false
        }
    }
}

func imageOcclusionPreviewHeight(for image: UIImage) -> CGFloat {
    let screenBounds = UIScreen.main.bounds
    let screenWidth = screenBounds.width - 32
    let ratio = image.size.height / max(image.size.width, 1)
    let idealHeight = screenWidth * ratio
    return min(max(idealHeight, 180), 260)
}

struct ImageOcclusionMaskSummaryCard: View {
    let image: UIImage
    let masks: [IOMask]
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OcclusionCanvasView(
                image: image,
                masks: .constant(masks),
                selectedMaskIndex: .constant(nil),
                shapeType: .select
            )
            .frame(height: imageOcclusionPreviewHeight(for: image))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)

            HStack(spacing: 12) {
                Text(masks.isEmpty ? L("io_no_masks") : L("io_mask_count", masks.count))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                Spacer()
                Button(action: action) {
                    Text(L("io_edit_action"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color.amgiSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct ImageOcclusionWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    let title: String
    let image: UIImage
    let initialMasks: [IOMask]
    let onSave: ([IOMask]) -> Void

    @State private var masks: [IOMask]
    @State private var selectedMaskIndex: Int?
    @State private var selectedMaskIndices: Set<Int>
    @State private var shapeType: IOShapeType
    @State private var pendingTextPoint: CGPoint?
    @State private var pendingTextValue = ""
    @State private var pendingTextMaskIndex: Int?
    @State private var pendingTextColor = Color.black
    @State private var showTextEditor = false
    @State private var showFillEditor = false
    @State private var fillEditorColor = Color.yellow
    @State private var showDiscardConfirmation = false
    @State private var showsTranslucentMasks = true
    @State private var occlusionMode: IOOcclusionMode
    @State private var transformStartSnapshot: IOMaskSnapshot?
    @State private var zoomCommand: IOCanvasZoomCommand = .fit
    @State private var zoomCommandID = 0

    init(title: String, image: UIImage, initialMasks: [IOMask], onSave: @escaping ([IOMask]) -> Void) {
        self.title = title
        self.image = image
        self.initialMasks = initialMasks
        self.onSave = onSave
        _masks = State(initialValue: initialMasks)
        let initialSelection = initialMasks.indices.first
        _selectedMaskIndex = State(initialValue: initialSelection)
        _selectedMaskIndices = State(initialValue: initialSelection.map { Set([$0]) } ?? [])
        _shapeType = State(initialValue: initialMasks.isEmpty ? .rect : .select)
        _occlusionMode = State(initialValue: initialMasks.contains(where: \.occludesInactive) ? .hideAllGuessOne : .hideOneGuessOne)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolPalette

            ZoomableOcclusionCanvasView(
                image: image,
                masks: $masks,
                selectedMaskIndex: $selectedMaskIndex,
                selectedMaskIndices: highlightedMaskIndices,
                highlightedMaskIndices: highlightedMaskIndices,
                shapeType: shapeType,
                maskOpacity: showsTranslucentMasks ? 0.72 : 0.94,
                zoomCommand: zoomCommand,
                zoomCommandID: zoomCommandID,
                onRequestText: beginTextInsertion(at:),
                onRequestTextEdit: beginTextEditing(maskIndex:),
                onAppend: appendMask(_:),
                onSelectionChange: handleCanvasSelectionChange(_:),
                onTransformDidBegin: handleTransformDidBegin,
                onTransformDidEnd: handleTransformDidEnd
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.amgiBackground)
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(L("common_cancel")) { requestDismiss() }
                    .amgiToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_save")) { saveWorkspace() }
                .amgiToolbarTextButton()
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomToolbars
        }
        .confirmationDialog(L("io_discard_changes_title"), isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button(L("io_discard_changes_action"), role: .destructive) {
                dismiss()
            }
            Button(L("common_cancel"), role: .cancel) {}
        } message: {
            Text(L("io_discard_changes_message"))
        }
        .sheet(isPresented: $showTextEditor) {
            textEditorSheet
        }
        .sheet(isPresented: $showFillEditor) {
            fillEditorSheet
        }
    }

    private var activeSelectionIndices: [Int] {
        let filtered = selectedMaskIndices.filter { masks.indices.contains($0) }
        if !filtered.isEmpty {
            return filtered.sorted()
        }

        guard let selectedMaskIndex, masks.indices.contains(selectedMaskIndex) else {
            return []
        }
        return [selectedMaskIndex]
    }

    private var highlightedMaskIndices: Set<Int> {
        Set(activeSelectionIndices)
    }

    private var allMasksSelected: Bool {
        !masks.isEmpty && highlightedMaskIndices.count == masks.count
    }

    private var hasUnsavedChanges: Bool {
        masks != initialMasks
    }

    private var textEditorTitle: String {
        pendingTextMaskIndex == nil ? L("io_text_prompt_title") : L("io_text_edit_title")
    }

    private var toolPalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IOShapeType.allCases, id: \.self) { tool in
                    ioPaletteButton(
                        title: tool.label,
                        systemImage: tool.systemImage,
                        isSelected: shapeType == tool
                    ) {
                        shapeType = tool
                    }
                }

                Menu {
                    ForEach(IOMaskFillOption.allCases, id: \.self) { option in
                        Button(option.label) {
                            applyFill(option.hex)
                        }
                    }
                    Divider()
                    Button(L("io_fill_custom")) {
                        openFillEditor()
                    }
                    Button(L("rich_text_color_default")) {
                        applyFill(nil)
                    }
                } label: {
                    ioPaletteChip(
                        title: L("io_tool_fill"),
                        systemImage: "paintpalette",
                        isSelected: false
                    )
                }
                .disabled(activeSelectionIndices.isEmpty)

                Menu {
                    ForEach(IOOcclusionMode.allCases, id: \.self) { mode in
                        Button(mode.label) {
                            applyOcclusionMode(mode)
                        }
                    }
                } label: {
                    ioPaletteChip(
                        title: L("io_tool_mode"),
                        systemImage: "square.stack.3d.up",
                        isSelected: false
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.amgiSurface)
    }

    private var bottomToolbars: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolbarIconButton(systemImage: "arrow.uturn.backward") {
                        undoManager?.undo()
                    }
                    .disabled(!(undoManager?.canUndo ?? false))

                    toolbarIconButton(systemImage: "arrow.uturn.forward") {
                        undoManager?.redo()
                    }
                    .disabled(!(undoManager?.canRedo ?? false))

                    toolbarIconButton(systemImage: "trash") {
                        deleteSelection()
                    }
                    .disabled(activeSelectionIndices.isEmpty)

                    toolbarIconButton(systemImage: "plus.square.on.square") {
                        duplicateSelection()
                    }
                    .disabled(activeSelectionIndices.isEmpty)

                    toolbarIconButton(systemImage: allMasksSelected ? "checkmark.circle.fill" : "checkmark.circle") {
                        toggleSelectAll()
                    }
                    .disabled(masks.isEmpty)

                    toolbarIconButton(systemImage: "arrow.left.arrow.right") {
                        invertSelection()
                    }
                    .disabled(masks.isEmpty)

                    toolbarIconButton(systemImage: showsTranslucentMasks ? "circle.lefthalf.filled" : "circle") {
                        showsTranslucentMasks.toggle()
                    }
                    .disabled(masks.isEmpty)
                }
                .padding(.horizontal, 16)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    toolbarIconButton(systemImage: "link") {
                        groupSelection()
                    }
                    .disabled(activeSelectionIndices.count < 2)

                    toolbarIconButton(systemImage: "link.slash", fallbackSystemImage: "scissors") {
                        ungroupSelection()
                    }
                    .disabled(activeSelectionIndices.isEmpty || !activeSelectionIndices.contains(where: { masks[$0].serializationOrdinal != nil }))

                    Menu {
                        ForEach(IOMaskAlignMode.allCases, id: \.self) { mode in
                            Button(mode.label) {
                                alignSelection(mode)
                            }
                        }
                    } label: {
                        toolbarIcon(systemImage: "align.horizontal.left")
                    }
                    .disabled(activeSelectionIndices.isEmpty)

                    toolbarIconButton(systemImage: "plus.magnifyingglass") {
                        sendZoomCommand(.zoomIn)
                    }

                    toolbarIconButton(systemImage: "minus.magnifyingglass") {
                        sendZoomCommand(.zoomOut)
                    }

                    toolbarIconButton(systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
                        sendZoomCommand(.fit)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.amgiSurface)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var textEditorSheet: some View {
        NavigationStack {
            Form {
                Section(L("io_text_prompt_title")) {
                    TextField(L("io_text_prompt_placeholder"), text: $pendingTextValue, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section(L("io_text_color")) {
                    ColorPicker(L("io_fill_custom"), selection: $pendingTextColor, supportsOpacity: true)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(textEditorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) {
                        closeTextEditor()
                    }
                    .amgiToolbarTextButton(tone: .neutral)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_save")) {
                        insertOrUpdateTextMask()
                    }
                    .amgiToolbarTextButton()
                    .disabled(pendingTextValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var fillEditorSheet: some View {
        NavigationStack {
            Form {
                Section(L("io_fill_custom")) {
                    ColorPicker(L("io_fill_custom"), selection: $fillEditorColor, supportsOpacity: true)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .navigationTitle(L("io_fill_custom"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) {
                        showFillEditor = false
                    }
                    .amgiToolbarTextButton(tone: .neutral)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(L("rich_text_color_default")) {
                        showFillEditor = false
                        applyFill(nil)
                    }
                    .amgiToolbarTextButton(tone: .neutral)

                    Button(L("common_save")) {
                        showFillEditor = false
                        applyFill(hexString(for: fillEditorColor))
                    }
                    .amgiToolbarTextButton()
                }
            }
        }
    }

    @ViewBuilder
    private func ioPaletteButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ioPaletteChip(title: title, systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func ioPaletteChip(
        title: String,
        systemImage: String,
        isSelected: Bool
    ) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(width: 60, height: 46)
        .background(isSelected ? Color.amgiAccent : Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func toolbarIconButton(systemImage: String, fallbackSystemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarIcon(systemImage: systemImage, fallbackSystemImage: fallbackSystemImage)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toolbarIcon(systemImage: String, fallbackSystemImage: String? = nil) -> some View {
        let resolvedSymbol = if UIImage(systemName: systemImage) != nil {
            systemImage
        } else {
            fallbackSystemImage ?? "questionmark"
        }

        Image(systemName: resolvedSymbol)
            .font(.system(size: 13, weight: .semibold))
            .amgiToolbarIconButton(size: 30)
    }

    private func handleCanvasSelectionChange(_ selection: OcclusionCanvasView.IOCanvasSelectionChange) {
        switch selection {
        case .replace(let index):
            guard let index, masks.indices.contains(index) else {
                selectedMaskIndex = nil
                selectedMaskIndices = []
                return
            }
            let group = groupedSelectionIndices(for: index)
            selectedMaskIndex = index
            selectedMaskIndices = group
        case .toggle(let index):
            guard masks.indices.contains(index) else { return }
            let group = groupedSelectionIndices(for: index)
            if group.isSubset(of: selectedMaskIndices) {
                selectedMaskIndices.subtract(group)
                if selectedMaskIndices.isEmpty {
                    selectedMaskIndex = nil
                } else if let selectedMaskIndex, !selectedMaskIndices.contains(selectedMaskIndex) {
                    self.selectedMaskIndex = selectedMaskIndices.sorted().first
                }
            } else {
                selectedMaskIndices.formUnion(group)
                selectedMaskIndex = index
            }
        }
    }

    private func beginTextInsertion(at point: CGPoint) {
        pendingTextPoint = point
        pendingTextMaskIndex = nil
        pendingTextValue = ""
        pendingTextColor = .black
        showTextEditor = true
    }

    private func beginTextEditing(maskIndex: Int) {
        guard masks.indices.contains(maskIndex),
              case .text(_, _, let text, _, _, let extras) = masks[maskIndex] else {
            return
        }
        pendingTextPoint = nil
        pendingTextMaskIndex = maskIndex
        pendingTextValue = text
        pendingTextColor = color(from: extras["fill"], fallback: .black)
        showTextEditor = true
    }

    private func closeTextEditor() {
        pendingTextPoint = nil
        pendingTextMaskIndex = nil
        pendingTextValue = ""
        showTextEditor = false
    }

    private func insertOrUpdateTextMask() {
        let text = pendingTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let fillHex = hexString(for: pendingTextColor)

        if let pendingTextMaskIndex, masks.indices.contains(pendingTextMaskIndex) {
            var updatedMasks = masks
            updatedMasks[pendingTextMaskIndex] = updatedMasks[pendingTextMaskIndex].updatingText(text, fillHex: fillHex)
            commitSnapshot(
                IOMaskSnapshot(
                    masks: updatedMasks,
                    selectedMaskIndex: pendingTextMaskIndex,
                    selectedMaskIndices: groupedSelectionIndices(for: pendingTextMaskIndex, in: updatedMasks)
                )
            )
        } else if let pendingTextPoint {
            appendMask(
                .text(
                    left: pendingTextPoint.x,
                    top: pendingTextPoint.y,
                    text: text,
                    scale: 1,
                    fontSize: 0.055,
                    extras: ["fill": fillHex]
                )
            )
        }

        closeTextEditor()
    }

    private func appendMask(_ mask: IOMask) {
        var updatedMasks = masks
        updatedMasks.append(mask.applyingOccludeInactive(occlusionMode.occludesInactive))
        let newIndex = updatedMasks.count - 1
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: newIndex,
                selectedMaskIndices: [newIndex]
            )
        )
    }

    private func deleteSelection() {
        let indices = activeSelectionIndices
        guard !indices.isEmpty else { return }
        let indexSet = Set(indices)
        let updatedMasks = masks.enumerated().compactMap { index, mask in
            indexSet.contains(index) ? nil : mask
        }
        let newSelection = updatedMasks.indices.first.map { Set([$0]) } ?? []
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: newSelection.sorted().first,
                selectedMaskIndices: newSelection
            )
        )
    }

    private func duplicateSelection() {
        let indices = activeSelectionIndices
        guard !indices.isEmpty else { return }

        var updatedMasks = masks
        var duplicatedIndices: Set<Int> = []
        var ordinalMapping: [Int: Int] = [:]

        for index in indices {
            var duplicate = offset(mask: masks[index], dx: 0.03, dy: 0.03).applyingSerializationOrdinal(nil)
            if let ordinal = masks[index].serializationOrdinal {
                let mappedOrdinal = ordinalMapping[ordinal] ?? nextAvailableOrdinal(in: updatedMasks, reserved: Set(ordinalMapping.values))
                ordinalMapping[ordinal] = mappedOrdinal
                duplicate = duplicate.applyingSerializationOrdinal(mappedOrdinal)
            }
            updatedMasks.append(duplicate)
            duplicatedIndices.insert(updatedMasks.count - 1)
        }

        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: duplicatedIndices.sorted().first,
                selectedMaskIndices: duplicatedIndices
            )
        )
    }

    private func toggleSelectAll() {
        guard !masks.isEmpty else { return }
        if allMasksSelected {
            selectedMaskIndices = []
            selectedMaskIndex = nil
        } else {
            selectedMaskIndices = Set(masks.indices)
            selectedMaskIndex = masks.indices.first
        }
    }

    private func invertSelection() {
        guard !masks.isEmpty else { return }
        let inverted = Set(masks.indices).subtracting(selectedMaskIndices)
        selectedMaskIndices = inverted
        if let selectedMaskIndex, inverted.contains(selectedMaskIndex) {
            return
        }
        self.selectedMaskIndex = inverted.sorted().first
    }

    private func openFillEditor() {
        fillEditorColor = color(from: activeSelectionIndices.first.flatMap { masks[$0].extras["fill"] }, fallback: .yellow)
        showFillEditor = true
    }

    private func applyFill(_ hex: String?) {
        let indices = activeSelectionIndices
        guard !indices.isEmpty else { return }

        var updatedMasks = masks
        for index in indices {
            updatedMasks[index] = updatedMasks[index].applyingFill(hex)
        }
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: selectedMaskIndex,
                selectedMaskIndices: Set(indices)
            )
        )
    }

    private func applyOcclusionMode(_ mode: IOOcclusionMode) {
        occlusionMode = mode
        guard !masks.isEmpty else { return }

        let updatedMasks = masks.map { $0.applyingOccludeInactive(mode.occludesInactive) }
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: selectedMaskIndex,
                selectedMaskIndices: Set(activeSelectionIndices)
            )
        )
    }

    private func groupSelection() {
        let indices = activeSelectionIndices
        guard indices.count >= 2 else { return }
        let targetOrdinal = indices.compactMap { masks[$0].serializationOrdinal }.min()
            ?? nextAvailableOrdinal(in: masks)
        var updatedMasks = masks
        for index in indices {
            updatedMasks[index] = updatedMasks[index].applyingSerializationOrdinal(targetOrdinal)
        }
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: selectedMaskIndex,
                selectedMaskIndices: Set(indices)
            )
        )
    }

    private func ungroupSelection() {
        let indices = activeSelectionIndices
        guard !indices.isEmpty else { return }
        var updatedMasks = masks
        for index in indices {
            updatedMasks[index] = updatedMasks[index].applyingSerializationOrdinal(nil)
        }
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: selectedMaskIndex,
                selectedMaskIndices: Set(indices)
            )
        )
    }

    private func alignSelection(_ mode: IOMaskAlignMode) {
        let indices = activeSelectionIndices
        guard !indices.isEmpty else { return }

        let canvasBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        var updatedMasks = masks
        for index in indices {
            let maskBounds = normalizedBounds(for: updatedMasks[index])
            let delta: CGPoint
            switch mode {
            case .left:
                delta = CGPoint(x: canvasBounds.minX - maskBounds.minX, y: 0)
            case .horizontalCenter:
                delta = CGPoint(x: canvasBounds.midX - maskBounds.midX, y: 0)
            case .right:
                delta = CGPoint(x: canvasBounds.maxX - maskBounds.maxX, y: 0)
            case .top:
                delta = CGPoint(x: 0, y: canvasBounds.minY - maskBounds.minY)
            case .verticalCenter:
                delta = CGPoint(x: 0, y: canvasBounds.midY - maskBounds.midY)
            case .bottom:
                delta = CGPoint(x: 0, y: canvasBounds.maxY - maskBounds.maxY)
            }
            updatedMasks[index] = offset(mask: updatedMasks[index], dx: delta.x, dy: delta.y)
        }

        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: selectedMaskIndex,
                selectedMaskIndices: Set(indices)
            )
        )
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func saveWorkspace() {
        onSave(masks)
        dismiss()
    }

    private func handleTransformDidBegin() {
        if transformStartSnapshot == nil {
            transformStartSnapshot = currentSnapshot()
        }
    }

    private func handleTransformDidEnd() {
        guard let previousSnapshot = transformStartSnapshot else { return }
        transformStartSnapshot = nil
        let current = currentSnapshot()
        guard current != previousSnapshot else { return }
        registerUndo(previous: previousSnapshot, current: current)
    }

    private func sendZoomCommand(_ command: IOCanvasZoomCommand) {
        zoomCommand = command
        zoomCommandID += 1
    }

    private func groupedSelectionIndices(for index: Int, in masks: [IOMask]? = nil) -> Set<Int> {
        let resolvedMasks = masks ?? self.masks
        guard resolvedMasks.indices.contains(index) else { return [] }
        guard let ordinal = resolvedMasks[index].serializationOrdinal else {
            return [index]
        }
        return Set(resolvedMasks.indices.filter { resolvedMasks[$0].serializationOrdinal == ordinal })
    }

    private func nextAvailableOrdinal(in masks: [IOMask], reserved: Set<Int> = []) -> Int {
        let currentMax = masks.compactMap(\.serializationOrdinal).max() ?? 0
        var candidate = currentMax + 1
        while reserved.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    private func color(from hex: String?, fallback: Color) -> Color {
        guard let hex, let color = workspaceUIColor(ioHex: hex) else {
            return fallback
        }
        return Color(uiColor: color)
    }

    private func hexString(for color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "%02X%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255)),
            Int(round(alpha * 255))
        )
    }

    private func workspaceUIColor(ioHex: String) -> UIColor? {
        let sanitized = ioHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard sanitized.count == 6 || sanitized.count == 8,
              let value = UInt64(sanitized, radix: 16) else {
            return nil
        }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat

        if sanitized.count == 8 {
            red = CGFloat((value & 0xFF000000) >> 24) / 255
            green = CGFloat((value & 0x00FF0000) >> 16) / 255
            blue = CGFloat((value & 0x0000FF00) >> 8) / 255
            alpha = CGFloat(value & 0x000000FF) / 255
        } else {
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        }

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func currentSnapshot() -> IOMaskSnapshot {
        IOMaskSnapshot(
            masks: masks,
            selectedMaskIndex: selectedMaskIndex,
            selectedMaskIndices: Set(activeSelectionIndices)
        )
    }

    private func commitSnapshot(_ snapshot: IOMaskSnapshot) {
        let previous = currentSnapshot()
        applySnapshot(snapshot)
        registerUndo(previous: previous, current: snapshot)
    }

    private func registerUndo(previous: IOMaskSnapshot, current: IOMaskSnapshot) {
        undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
            self.restoreSnapshot(previous, redo: current)
        }
    }

    private func restoreSnapshot(_ snapshot: IOMaskSnapshot, redo: IOMaskSnapshot) {
        applySnapshot(snapshot)
        registerUndo(previous: redo, current: snapshot)
    }

    private func applySnapshot(_ snapshot: IOMaskSnapshot) {
        masks = snapshot.masks
        selectedMaskIndices = snapshot.selectedMaskIndices.filter { snapshot.masks.indices.contains($0) }
        if let selectedMaskIndex = snapshot.selectedMaskIndex, snapshot.masks.indices.contains(selectedMaskIndex) {
            self.selectedMaskIndex = selectedMaskIndex
        } else {
            self.selectedMaskIndex = selectedMaskIndices.sorted().first
        }
        occlusionMode = snapshot.masks.contains(where: \.occludesInactive) ? .hideAllGuessOne : .hideOneGuessOne
    }

    private func normalizedBounds(for mask: IOMask) -> CGRect {
        switch mask {
        case .rect(let left, let top, let width, let height, _):
            return CGRect(x: left, y: top, width: width, height: height)
        case .ellipse(let left, let top, let rx, let ry, _):
            return CGRect(x: left, y: top, width: rx * 2, height: ry * 2)
        case .polygon(let points, _):
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            return CGRect(
                x: xs.min() ?? 0,
                y: ys.min() ?? 0,
                width: (xs.max() ?? 0) - (xs.min() ?? 0),
                height: (ys.max() ?? 0) - (ys.min() ?? 0)
            )
        case .text(let left, let top, let text, let scale, let fontSize, _):
            return CGRect(origin: CGPoint(x: left, y: top), size: normalizedTextSize(text: text, scale: scale, fontSize: fontSize))
        }
    }

    private func normalizedTextSize(text: String, scale: CGFloat, fontSize: CGFloat) -> CGSize {
        let resolvedSize = max(14, image.size.height * max(fontSize, 0.02) * max(scale, 1))
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: resolvedSize, weight: .semibold)]
        let textSize = (text as NSString).size(withAttributes: attrs)
        return CGSize(
            width: min(1, (textSize.width + 20) / max(image.size.width, 1)),
            height: min(1, (textSize.height + 12) / max(image.size.height, 1))
        )
    }

    private func offset(mask: IOMask, dx: CGFloat, dy: CGFloat) -> IOMask {
        switch mask {
        case .rect(let left, let top, let width, let height, let extras):
            return .rect(
                left: max(0, min(1 - width, left + dx)),
                top: max(0, min(1 - height, top + dy)),
                width: width,
                height: height,
                extras: extras
            )
        case .ellipse(let left, let top, let rx, let ry, let extras):
            return .ellipse(
                left: max(0, min(1 - rx * 2, left + dx)),
                top: max(0, min(1 - ry * 2, top + dy)),
                rx: rx,
                ry: ry,
                extras: extras
            )
        case .polygon(let points, let extras):
            let minX = points.map(\.x).min() ?? 0
            let maxX = points.map(\.x).max() ?? 1
            let minY = points.map(\.y).min() ?? 0
            let maxY = points.map(\.y).max() ?? 1
            let clampedDX = max(-minX, min(1 - maxX, dx))
            let clampedDY = max(-minY, min(1 - maxY, dy))
            let shifted = points.map {
                CGPoint(x: $0.x + clampedDX, y: $0.y + clampedDY)
            }
            return .polygon(points: shifted, extras: extras)
        case .text(let left, let top, let text, let scale, let fontSize, let extras):
            let size = normalizedTextSize(text: text, scale: scale, fontSize: fontSize)
            return .text(
                left: max(0, min(1 - size.width, left + dx)),
                top: max(0, min(1 - size.height, top + dy)),
                text: text,
                scale: scale,
                fontSize: fontSize,
                extras: extras
            )
        }
    }
}

struct ZoomableOcclusionCanvasView: UIViewRepresentable {
    let image: UIImage
    @Binding var masks: [IOMask]
    @Binding var selectedMaskIndex: Int?
    let selectedMaskIndices: Set<Int>
    let highlightedMaskIndices: Set<Int>
    let shapeType: IOShapeType
    let maskOpacity: CGFloat
    let zoomCommand: IOCanvasZoomCommand
    let zoomCommandID: Int
    var onRequestText: ((CGPoint) -> Void)?
    var onRequestTextEdit: ((Int) -> Void)?
    var onAppend: ((IOMask) -> Void)?
    var onSelectionChange: ((OcclusionCanvasView.IOCanvasSelectionChange) -> Void)?
    var onTransformDidBegin: (() -> Void)?
    var onTransformDidEnd: (() -> Void)?

    func makeCoordinator() -> OcclusionCanvasView.Coordinator {
        OcclusionCanvasView.Coordinator(
            masks: $masks,
            selectedMaskIndex: $selectedMaskIndex,
            onRequestText: onRequestText,
            onRequestTextEdit: onRequestTextEdit,
            onAppend: onAppend,
            onSelectionChange: onSelectionChange,
            onTransformDidBegin: onTransformDidBegin,
            onTransformDidEnd: onTransformDidEnd
        )
    }

    func makeUIView(context: Context) -> ZoomableOcclusionCanvasContainer {
        let view = ZoomableOcclusionCanvasContainer(image: image)
        view.canvasView.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ZoomableOcclusionCanvasContainer, context: Context) {
        uiView.updateImage(image)
        uiView.canvasView.image = image
        uiView.canvasView.masks = masks
        uiView.canvasView.selectedMaskIndex = selectedMaskIndex
        uiView.canvasView.activeSelectionIndices = selectedMaskIndices
        uiView.canvasView.highlightedMaskIndices = highlightedMaskIndices
        uiView.canvasView.shapeType = shapeType
        uiView.canvasView.maskOpacity = maskOpacity
        context.coordinator.onRequestText = onRequestText
        context.coordinator.onRequestTextEdit = onRequestTextEdit
        context.coordinator.onAppend = onAppend
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onTransformDidBegin = onTransformDidBegin
        context.coordinator.onTransformDidEnd = onTransformDidEnd

        if context.coordinator.lastZoomCommandID != zoomCommandID {
            context.coordinator.lastZoomCommandID = zoomCommandID
            uiView.apply(zoomCommand)
        }

        uiView.canvasView.setNeedsDisplay()
    }
}

final class ZoomableOcclusionCanvasContainer: UIScrollView, UIScrollViewDelegate {
    let canvasView: OcclusionCanvasUIView
    private var lastBoundsSize: CGSize = .zero
    private var imageSize: CGSize

    init(image: UIImage) {
        self.canvasView = OcclusionCanvasUIView(image: image)
        self.imageSize = image.size
        super.init(frame: .zero)

        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        minimumZoomScale = 1
        maximumZoomScale = 5
        backgroundColor = UIColor(Color.amgiSurfaceElevated)
        layer.cornerRadius = 24
        addSubview(canvasView)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            relayoutCanvas(resetZoom: false)
        }
        centerCanvas()
    }

    func updateImage(_ image: UIImage) {
        canvasView.image = image
        if image.size != imageSize {
            imageSize = image.size
            relayoutCanvas(resetZoom: true)
        }
    }

    func apply(_ command: IOCanvasZoomCommand) {
        switch command {
        case .zoomIn:
            setZoomScale(min(maximumZoomScale, zoomScale * 1.2), animated: true)
        case .zoomOut:
            setZoomScale(max(minimumZoomScale, zoomScale / 1.2), animated: true)
        case .fit:
            layoutIfNeeded()
            relayoutCanvas(resetZoom: true)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        canvasView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerCanvas()
    }

    private func relayoutCanvas(resetZoom: Bool) {
        let fittedSize = fittedCanvasSize(for: bounds.size)
        canvasView.frame = CGRect(origin: .zero, size: fittedSize)
        contentSize = fittedSize
        minimumZoomScale = 1
        maximumZoomScale = 5
        if resetZoom || zoomScale < minimumZoomScale {
            zoomScale = minimumZoomScale
        }
        centerCanvas()
    }

    private func fittedCanvasSize(for boundsSize: CGSize) -> CGSize {
        let availableWidth = max(boundsSize.width - 8, 1)
        let availableHeight = max(boundsSize.height - 8, 1)
        let scale = min(availableWidth / max(imageSize.width, 1), availableHeight / max(imageSize.height, 1))
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private func centerCanvas() {
        var frame = canvasView.frame
        frame.origin.x = frame.width < bounds.width ? (bounds.width - frame.width) / 2 : 0
        frame.origin.y = frame.height < bounds.height ? (bounds.height - frame.height) / 2 : 0
        canvasView.frame = frame
    }
}

private extension IOMask {
    func applyingFill(_ hex: String?) -> IOMask {
        var updatedExtras = extras
        if let hex {
            updatedExtras["fill"] = hex
        } else {
            updatedExtras.removeValue(forKey: "fill")
        }

        switch self {
        case .rect(let left, let top, let width, let height, _):
            return .rect(left: left, top: top, width: width, height: height, extras: updatedExtras)
        case .ellipse(let left, let top, let rx, let ry, _):
            return .ellipse(left: left, top: top, rx: rx, ry: ry, extras: updatedExtras)
        case .polygon(let points, _):
            return .polygon(points: points, extras: updatedExtras)
        case .text(let left, let top, let text, let scale, let fontSize, _):
            return .text(left: left, top: top, text: text, scale: scale, fontSize: fontSize, extras: updatedExtras)
        }
    }
}