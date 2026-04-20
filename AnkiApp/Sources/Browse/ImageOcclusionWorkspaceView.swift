import SwiftUI
import UIKit

private struct IOMaskSnapshot {
    var masks: [IOMask]
    var selectedMaskIndex: Int?
    var selectsAll: Bool
}

private enum IOCanvasZoomCommand {
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
                    Label(L("io_edit_action"), systemImage: "square.and.pencil")
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
    @State private var selectsAll = false
    @State private var shapeType: IOShapeType
    @State private var pendingTextPoint: CGPoint?
    @State private var pendingTextValue = ""
    @State private var showTextPrompt = false
    @State private var zoomCommand: IOCanvasZoomCommand = .fit
    @State private var zoomCommandID = 0

    init(title: String, image: UIImage, initialMasks: [IOMask], onSave: @escaping ([IOMask]) -> Void) {
        self.title = title
        self.image = image
        self.initialMasks = initialMasks
        self.onSave = onSave
        _masks = State(initialValue: initialMasks)
        _selectedMaskIndex = State(initialValue: initialMasks.isEmpty ? nil : 0)
        _shapeType = State(initialValue: initialMasks.isEmpty ? .rect : .select)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolPalette

            ZoomableOcclusionCanvasView(
                image: image,
                masks: $masks,
                selectedMaskIndex: $selectedMaskIndex,
                highlightedMaskIndices: highlightedMaskIndices,
                shapeType: shapeType,
                zoomCommand: zoomCommand,
                zoomCommandID: zoomCommandID,
                onRequestText: beginTextInsertion(at:),
                onAppend: appendMask(_:),
                onSelectionChange: handleCanvasSelectionChange(_:)
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
                Button(L("common_cancel")) { dismiss() }
                    .amgiToolbarTextButton(tone: .neutral)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("common_save")) {
                    onSave(masks)
                    dismiss()
                }
                .amgiToolbarTextButton()
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomToolbars
        }
        .alert(L("io_text_prompt_title"), isPresented: $showTextPrompt) {
            TextField(L("io_text_prompt_placeholder"), text: $pendingTextValue)
            Button(L("common_cancel"), role: .cancel) {
                pendingTextPoint = nil
                pendingTextValue = ""
            }
            Button(L("common_ok")) {
                insertTextMask()
            }
        } message: {
            Text(L("io_hint_text"))
        }
    }

    private var activeSelectionIndices: [Int] {
        if selectsAll {
            return Array(masks.indices)
        }

        guard let selectedMaskIndex, masks.indices.contains(selectedMaskIndex) else {
            return []
        }
        return [selectedMaskIndex]
    }

    private var highlightedMaskIndices: Set<Int> {
        Set(activeSelectionIndices)
    }

    private var toolPalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
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
                } label: {
                    ioPaletteChip(
                        title: L("io_tool_fill"),
                        systemImage: "paintpalette",
                        isSelected: false
                    )
                }
                .disabled(activeSelectionIndices.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.amgiSurface)
    }

    private var bottomToolbars: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
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

                toolbarIconButton(systemImage: selectsAll ? "checkmark.circle.fill" : "checkmark.circle") {
                    toggleSelectAll()
                }
                .disabled(masks.isEmpty)

                Spacer(minLength: 0)

                Menu {
                    ForEach(IOMaskAlignMode.allCases, id: \.self) { mode in
                        Button(mode.label) {
                            alignSelection(mode)
                        }
                    }
                } label: {
                    toolbarIcon(systemImage: "align.horizontal.left")
                }
                .disabled(activeSelectionIndices.count < 2)
            }

            HStack(spacing: 16) {
                toolbarIconButton(systemImage: "plus.magnifyingglass") {
                    sendZoomCommand(.zoomIn)
                }

                toolbarIconButton(systemImage: "minus.magnifyingglass") {
                    sendZoomCommand(.zoomOut)
                }

                toolbarIconButton(systemImage: "arrow.up.left.and.down.right.magnifyingglass") {
                    sendZoomCommand(.fit)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.amgiSurface)
        .overlay(alignment: .top) {
            Divider()
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
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(width: 72, height: 56)
        .background(isSelected ? Color.amgiAccent : Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func toolbarIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarIcon(systemImage: systemImage)
        }
    }

    @ViewBuilder
    private func toolbarIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .amgiToolbarIconButton()
    }

    private func handleCanvasSelectionChange(_ index: Int?) {
        selectsAll = false
        selectedMaskIndex = index
    }

    private func beginTextInsertion(at point: CGPoint) {
        pendingTextPoint = point
        pendingTextValue = ""
        showTextPrompt = true
    }

    private func insertTextMask() {
        guard let pendingTextPoint else { return }
        let text = pendingTextValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pendingTextPoint = nil
        self.pendingTextValue = ""
        guard !text.isEmpty else { return }
        appendMask(
            .text(
                left: pendingTextPoint.x,
                top: pendingTextPoint.y,
                text: text,
                scale: 1,
                fontSize: 0.055,
                extras: [:]
            )
        )
    }

    private func appendMask(_ mask: IOMask) {
        var updatedMasks = masks
        updatedMasks.append(mask)
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: updatedMasks.count - 1,
                selectsAll: false
            )
        )
    }

    private func deleteSelection() {
        let indices = activeSelectionIndices.sorted()
        guard !indices.isEmpty else { return }
        let indexSet = Set(indices)
        let updatedMasks = masks.enumerated().compactMap { index, mask in
            indexSet.contains(index) ? nil : mask
        }
        let newSelectedIndex = updatedMasks.indices.contains(0) ? min(indices.first ?? 0, updatedMasks.count - 1) : nil
        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: newSelectedIndex,
                selectsAll: false
            )
        )
    }

    private func duplicateSelection() {
        let indices = activeSelectionIndices.sorted()
        guard !indices.isEmpty else { return }

        var updatedMasks = masks
        var duplicatedIndices: [Int] = []
        for index in indices {
            let duplicate = offset(mask: masks[index], dx: 0.03, dy: 0.03)
            updatedMasks.append(duplicate)
            duplicatedIndices.append(updatedMasks.count - 1)
        }

        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: duplicatedIndices.first,
                selectsAll: duplicatedIndices.count > 1
            )
        )
    }

    private func toggleSelectAll() {
        guard !masks.isEmpty else { return }
        selectsAll.toggle()
        if selectsAll {
            selectedMaskIndex = masks.indices.first
        }
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
                selectsAll: selectsAll
            )
        )
    }

    private func alignSelection(_ mode: IOMaskAlignMode) {
        let indices = activeSelectionIndices.sorted()
        guard indices.count >= 2 else { return }

        let selectionBounds = indices
            .map { normalizedBounds(for: masks[$0]) }
            .reduce(into: CGRect.null) { partialResult, rect in
                partialResult = partialResult.union(rect)
            }

        var updatedMasks = masks
        for index in indices {
            let maskBounds = normalizedBounds(for: updatedMasks[index])
            let delta: CGPoint
            switch mode {
            case .left:
                delta = CGPoint(x: selectionBounds.minX - maskBounds.minX, y: 0)
            case .horizontalCenter:
                delta = CGPoint(x: selectionBounds.midX - maskBounds.midX, y: 0)
            case .right:
                delta = CGPoint(x: selectionBounds.maxX - maskBounds.maxX, y: 0)
            case .top:
                delta = CGPoint(x: 0, y: selectionBounds.minY - maskBounds.minY)
            case .verticalCenter:
                delta = CGPoint(x: 0, y: selectionBounds.midY - maskBounds.midY)
            case .bottom:
                delta = CGPoint(x: 0, y: selectionBounds.maxY - maskBounds.maxY)
            }
            updatedMasks[index] = offset(mask: updatedMasks[index], dx: delta.x, dy: delta.y)
        }

        commitSnapshot(
            IOMaskSnapshot(
                masks: updatedMasks,
                selectedMaskIndex: selectedMaskIndex,
                selectsAll: selectsAll
            )
        )
    }

    private func sendZoomCommand(_ command: IOCanvasZoomCommand) {
        zoomCommand = command
        zoomCommandID += 1
    }

    private func currentSnapshot() -> IOMaskSnapshot {
        IOMaskSnapshot(masks: masks, selectedMaskIndex: selectedMaskIndex, selectsAll: selectsAll)
    }

    private func commitSnapshot(_ snapshot: IOMaskSnapshot) {
        let previous = currentSnapshot()
        applySnapshot(snapshot)
        undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
            self.restoreSnapshot(previous, redo: snapshot)
        }
    }

    private func restoreSnapshot(_ snapshot: IOMaskSnapshot, redo: IOMaskSnapshot) {
        applySnapshot(snapshot)
        undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
            self.restoreSnapshot(redo, redo: snapshot)
        }
    }

    private func applySnapshot(_ snapshot: IOMaskSnapshot) {
        masks = snapshot.masks
        selectedMaskIndex = snapshot.selectedMaskIndex
        selectsAll = snapshot.selectsAll
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
    let highlightedMaskIndices: Set<Int>
    let shapeType: IOShapeType
    let zoomCommand: IOCanvasZoomCommand
    let zoomCommandID: Int
    var onRequestText: ((CGPoint) -> Void)?
    var onAppend: ((IOMask) -> Void)?
    var onSelectionChange: ((Int?) -> Void)?

    func makeCoordinator() -> OcclusionCanvasView.Coordinator {
        OcclusionCanvasView.Coordinator(
            masks: $masks,
            selectedMaskIndex: $selectedMaskIndex,
            onRequestText: onRequestText,
            onAppend: onAppend,
            onSelectionChange: onSelectionChange
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
        uiView.canvasView.highlightedMaskIndices = highlightedMaskIndices
        uiView.canvasView.shapeType = shapeType
        context.coordinator.onRequestText = onRequestText
        context.coordinator.onAppend = onAppend
        context.coordinator.onSelectionChange = onSelectionChange

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
        let availableWidth = max(boundsSize.width - 24, 1)
        let availableHeight = max(boundsSize.height - 24, 1)
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