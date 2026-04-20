import SwiftUI
import PhotosUI
import AnkiClients
import Dependencies

// MARK: - Shape type

enum IOShapeType: String, CaseIterable {
    case rect, ellipse, polygon, text

    var label: String {
        switch self {
        case .rect:    return L("io_shape_rect")
        case .ellipse: return L("io_shape_ellipse")
        case .polygon: return L("io_shape_polygon")
        case .text:    return L("io_shape_text")
        }
    }

    var systemImage: String {
        switch self {
        case .rect:    return "rectangle"
        case .ellipse: return "oval"
        case .polygon: return "pentagon"
        case .text:    return "textformat"
        }
    }
}

// MARK: - Mask model

enum IOMask {
    /// left/top/width/height in 0-1 fractions
    case rect(left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, extras: [String: String])
    /// left/top = top-left corner of bounding box; rx/ry = radii, all 0-1 fractions
    case ellipse(left: CGFloat, top: CGFloat, rx: CGFloat, ry: CGFloat, extras: [String: String])
    /// points: normalized (x, y) pairs
    case polygon(points: [CGPoint], extras: [String: String])
    /// left/top = top-left anchor; scale/fs match upstream image-occlusion text props.
    case text(left: CGFloat, top: CGFloat, text: String, scale: CGFloat, fontSize: CGFloat, extras: [String: String])

    func occlusionText(index: Int) -> String {
        let n = index + 1
        switch self {
        case .rect(let l, let t, let w, let h, let extras):
            return clozeText(
                index: n,
                shape: "rect",
                properties: [("left", f(l)), ("top", f(t)), ("width", f(w)), ("height", f(h))],
                extras: extras,
                reservedKeys: ["left", "top", "width", "height"]
            )
        case .ellipse(let l, let t, let rx, let ry, let extras):
            return clozeText(
                index: n,
                shape: "ellipse",
                properties: [("left", f(l)), ("top", f(t)), ("rx", f(rx)), ("ry", f(ry))],
                extras: extras,
                reservedKeys: ["left", "top", "rx", "ry"]
            )
        case .polygon(let pts, let extras):
            let ptsStr = pts.map { "\(f($0.x)),\(f($0.y))" }.joined(separator: " ")
            return clozeText(
                index: n,
                shape: "polygon",
                properties: [("points", ptsStr)],
                extras: extras,
                reservedKeys: ["points"]
            )
        case .text(let l, let t, let text, let scale, let fontSize, let extras):
            return clozeText(
                index: n,
                shape: "text",
                properties: [("left", f(l)), ("top", f(t)), ("text", text), ("scale", f(scale)), ("fs", f(fontSize))],
                extras: extras,
                reservedKeys: ["left", "top", "text", "scale", "fs"]
            )
        }
    }

    var extras: [String: String] {
        switch self {
        case .rect(_, _, _, _, let extras),
             .ellipse(_, _, _, _, let extras),
             .polygon(_, let extras),
             .text(_, _, _, _, _, let extras):
            return extras
        }
    }

    private func clozeText(
        index: Int,
        shape: String,
        properties: [(String, String)],
        extras: [String: String],
        reservedKeys: Set<String>
    ) -> String {
        let extraTokens = extras.keys.sorted().compactMap { key -> String? in
            guard !reservedKeys.contains(key), let value = extras[key], !value.isEmpty else {
                return nil
            }
            return "\(key)=\(value)"
        }
        let allTokens = properties.map { "\($0)=\($1)" } + extraTokens
        return "{{c\(index)::image-occlusion:\(shape):\(allTokens.joined(separator: ":"))}}"
    }

    private func f(_ v: CGFloat) -> String { String(format: "%.3g", v) }
}

// MARK: - AddImageOcclusionNoteView

struct AddImageOcclusionNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Dependency(\.imageOcclusionClient) private var client

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var masks: [IOMask] = []
    @State private var selectedMaskIndex: Int?
    @State private var shapeType: IOShapeType = .rect
    @State private var pendingTextPoint: CGPoint?
    @State private var pendingTextValue = ""
    @State private var showTextPrompt = false
    @State private var header: String = ""
    @State private var backExtra: String = ""
    @State private var tagsText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var imageURL: URL?

    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Image picker
                Section {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(
                            L("io_pick_image"),
                            systemImage: selectedImage == nil ? "photo.on.rectangle.angled" : "photo.badge.plus"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: selectedItem) {
                        Task { await loadImage(from: selectedItem) }
                    }
                } header: {
                    Text(L("io_section_image"))
                }

                // MARK: Shape picker + canvas
                if let uiImage = selectedImage {
                    Section {
                        Picker(L("io_shape_picker_label"), selection: $shapeType) {
                            ForEach(IOShapeType.allCases, id: \.self) { s in
                                Label(s.label, systemImage: s.systemImage).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(shapeHint)
                            .amgiFont(.caption)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            OcclusionCanvasView(
                                image: uiImage,
                                masks: $masks,
                                selectedMaskIndex: $selectedMaskIndex,
                                shapeType: shapeType,
                                onRequestText: beginTextInsertion(at:),
                                onAppend: appendMask(_:)
                            )
                            .frame(height: canvasHeight(for: uiImage))
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            if !masks.isEmpty {
                                HStack {
                                    Text(L("io_mask_count", masks.count))
                                        .amgiFont(.caption)
                                        .foregroundStyle(Color.amgiTextSecondary)
                                    if let selectedMaskIndex,
                                       masks.indices.contains(selectedMaskIndex) {
                                        Text("#\(selectedMaskIndex + 1)")
                                            .amgiFont(.caption)
                                            .foregroundStyle(Color.amgiAccent)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        removeSelectedMask()
                                    } label: {
                                        Label(L("common_delete"), systemImage: "trash")
                                            .font(AmgiFont.caption.font)
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(selectedMaskIndex == nil)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.amgiSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text(L("io_section_masks"))
                    }
                }

                // MARK: Text fields
                Section(L("io_section_content")) {
                    TextField(L("io_header_placeholder"), text: $header)
                    TextField(L("io_back_extra_placeholder"), text: $backExtra)
                }

                Section {
                    TextField(L("io_tags_placeholder"), text: $tagsText)
                } header: {
                    Text(L("io_section_tags"))
                } footer: {
                    Text(L("io_tags_hint"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }

                // MARK: Error
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .amgiStatusText(.danger, font: .caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.amgiBackground)
            .toolbar(.hidden, for: .tabBar)
            .navigationTitle(L("io_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                        .amgiToolbarTextButton(tone: .neutral)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        undoManager?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .amgiToolbarIconButton()
                    }
                    .disabled(!(undoManager?.canUndo ?? false))
                    Spacer()
                    Button {
                        undoManager?.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .amgiToolbarIconButton()
                    }
                    .disabled(!(undoManager?.canRedo ?? false))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_save")) {
                        Task { await save() }
                    }
                    .amgiToolbarTextButton()
                    .disabled(!canSave || isSaving)
                    .overlay {
                        if isSaving { ProgressView().scaleEffect(0.7) }
                    }
                }
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
    }

    private var canSave: Bool {
        selectedImage != nil && !masks.isEmpty
    }

    private func removeSelectedMask() {
        guard let selectedMaskIndex, masks.indices.contains(selectedMaskIndex) else { return }
        let removed = masks.remove(at: selectedMaskIndex)
        self.selectedMaskIndex = nil
        undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
            let restoredIndex = min(selectedMaskIndex, self.masks.count)
            self.masks.insert(removed, at: restoredIndex)
            self.selectedMaskIndex = restoredIndex
            self.undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
                guard self.masks.indices.contains(restoredIndex) else { return }
                _ = self.masks.remove(at: restoredIndex)
                self.selectedMaskIndex = nil
            }
        }
    }

    private func appendMask(_ mask: IOMask) {
        masks.append(mask)
        selectedMaskIndex = masks.count - 1
        undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
            _ = self.masks.popLast()
            self.selectedMaskIndex = nil
            self.undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
                self.masks.append(mask)
                self.selectedMaskIndex = self.masks.count - 1
            }
        }
    }

    private var shapeHint: String {
        switch shapeType {
        case .rect:    return L("io_hint_rect")
        case .ellipse: return L("io_hint_ellipse")
        case .polygon: return L("io_hint_polygon")
        case .text:    return L("io_hint_text")
        }
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

    private func canvasHeight(for image: UIImage) -> CGFloat {
        let screenBounds = UIScreen.main.bounds
        let screenWidth = screenBounds.width - 32
        let ratio = image.size.height / image.size.width
        let idealHeight = screenWidth * ratio
        let maxHeight = min(screenBounds.height * 0.62, 620)
        let minHeight = min(max(screenBounds.height * 0.32, 300), maxHeight)
        return min(max(idealHeight, minHeight), maxHeight)
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        self.masks = []
        self.selectedMaskIndex = nil

        // Load as UIImage
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            selectedImage = img

            // Write a temporary file for the upload path
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "io_pick_\(Int(Date().timeIntervalSince1970)).jpg"
            let url = tempDir.appendingPathComponent(filename)
            if let jpegData = img.jpegData(compressionQuality: 0.92) {
                try? jpegData.write(to: url)
                imageURL = url
            }
        }
    }

    @MainActor
    private func save() async {
        guard let url = imageURL, !masks.isEmpty else { return }
        isSaving = true
        errorMessage = nil

        let occlusions = masks.enumerated().map { idx, mask in
            mask.occlusionText(index: idx)
        }.joined(separator: "\n")
        let tags = tagsText.split(separator: " ").map(String.init).filter { !$0.isEmpty }

        do {
            try client.addNote(url, occlusions, header, backExtra, tags)
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Mask model (defined above as IOMask enum)

// MARK: - OcclusionCanvasView

struct OcclusionCanvasView: UIViewRepresentable {
    let image: UIImage
    @Binding var masks: [IOMask]
    @Binding var selectedMaskIndex: Int?
    let shapeType: IOShapeType
    var onRequestText: ((CGPoint) -> Void)?
    var onAppend: ((IOMask) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(masks: $masks, selectedMaskIndex: $selectedMaskIndex, onRequestText: onRequestText, onAppend: onAppend)
    }

    func makeUIView(context: Context) -> OcclusionCanvasUIView {
        let view = OcclusionCanvasUIView(image: image)
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: OcclusionCanvasUIView, context: Context) {
        uiView.image = image
        uiView.masks = masks
        uiView.selectedMaskIndex = selectedMaskIndex
        uiView.shapeType = shapeType
        context.coordinator.onRequestText = onRequestText
        context.coordinator.onAppend = onAppend
        uiView.setNeedsDisplay()
    }

    final class Coordinator {
        @Binding var masks: [IOMask]
        @Binding var selectedMaskIndex: Int?
        var onRequestText: ((CGPoint) -> Void)?
        var onAppend: ((IOMask) -> Void)?
        init(masks: Binding<[IOMask]>, selectedMaskIndex: Binding<Int?>, onRequestText: ((CGPoint) -> Void)?, onAppend: ((IOMask) -> Void)?) {
            _masks = masks
            _selectedMaskIndex = selectedMaskIndex
            self.onRequestText = onRequestText
            self.onAppend = onAppend
        }

        func appendMask(_ mask: IOMask) {
            if let onAppend {
                // validate before delegating to undo-aware handler
                switch mask {
                case .rect(_, _, let w, let h, _) where w > 0.02 && h > 0.02: onAppend(mask)
                case .ellipse(_, _, let rx, let ry, _) where rx > 0.01 && ry > 0.01: onAppend(mask)
                case .polygon(let pts, _) where pts.count >= 3: onAppend(mask)
                case .text(_, _, let text, _, _, _) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty: onAppend(mask)
                default: break
                }
            } else {
                switch mask {
                case .rect(_, _, let w, let h, _) where w > 0.02 && h > 0.02: masks.append(mask)
                case .ellipse(_, _, let rx, let ry, _) where rx > 0.01 && ry > 0.01: masks.append(mask)
                case .polygon(let pts, _) where pts.count >= 3: masks.append(mask)
                case .text(_, _, let text, _, _, _) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty: masks.append(mask)
                default: break
                }
            }
        }

        func selectMask(_ index: Int?) {
            selectedMaskIndex = index
        }

        func requestText(at point: CGPoint) {
            onRequestText?(point)
        }

        func updateMask(at index: Int, to mask: IOMask) {
            guard masks.indices.contains(index) else { return }
            masks[index] = mask
        }
    }
}

// MARK: - OcclusionCanvasUIView

final class OcclusionCanvasUIView: UIView {
    private enum ActiveDrag {
        case move(maskIndex: Int, start: CGPoint, original: IOMask)
        case resize(maskIndex: Int, start: CGPoint, original: IOMask)
        case polygonVertex(maskIndex: Int, vertexIndex: Int)
    }

    var image: UIImage
    var masks: [IOMask] = []
    var selectedMaskIndex: Int?
    var shapeType: IOShapeType = .rect
    weak var coordinator: OcclusionCanvasView.Coordinator?

    private var dragStart: CGPoint?
    private var currentDragRect: CGRect?
    private var polygonPoints: [CGPoint] = []
    private var activeDrag: ActiveDrag?

    init(image: UIImage) {
        self.image = image
        super.init(frame: .zero)
        backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let imgRect = imageRect(in: bounds)
        image.draw(in: imgRect)

        let inactiveFill = UIColor(red: 1, green: 0.92, blue: 0.64, alpha: 0.75).cgColor
        let inactiveStroke = UIColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1).cgColor

        for (i, mask) in masks.enumerated() {
            ctx.setFillColor((maskFillColor(for: mask) ?? UIColor(cgColor: inactiveFill)).cgColor)
            let isSelected = i == selectedMaskIndex
            ctx.setStrokeColor((isSelected ? UIColor.systemBlue : UIColor(cgColor: inactiveStroke)).cgColor)
            ctx.setLineWidth(isSelected ? 2.5 : 1.5)
            drawMask(ctx: ctx, mask: mask, imgRect: imgRect)
            drawOrdinal(ctx: ctx, index: i, mask: mask, imgRect: imgRect)
            if isSelected {
                drawSelectionOutline(ctx: ctx, mask: mask, imgRect: imgRect)
            }
        }

        // In-progress drag (rect or ellipse)
        if let dr = currentDragRect {
            ctx.setFillColor(UIColor(red: 1, green: 0.55, blue: 0.55, alpha: 0.5).cgColor)
            ctx.setStrokeColor(UIColor(red: 0.8, green: 0, blue: 0, alpha: 0.8).cgColor)
            ctx.setLineWidth(1.5)
            if shapeType == .ellipse {
                ctx.addEllipse(in: dr)
            } else {
                ctx.addRect(dr)
            }
            ctx.drawPath(using: .fillStroke)
        }

        // In-progress polygon
        if !polygonPoints.isEmpty {
            ctx.setFillColor(UIColor(red: 1, green: 0.55, blue: 0.55, alpha: 0.3).cgColor)
            ctx.setStrokeColor(UIColor(red: 0.8, green: 0, blue: 0, alpha: 0.9).cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: polygonPoints[0])
            for pt in polygonPoints.dropFirst() { ctx.addLine(to: pt) }
            ctx.drawPath(using: .fillStroke)
            for pt in polygonPoints {
                ctx.setFillColor(UIColor.systemRed.cgColor)
                ctx.fillEllipse(in: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8))
            }
        }
    }

    // MARK: - Draw helpers

    private func drawMask(ctx: CGContext, mask: IOMask, imgRect: CGRect) {
        switch mask {
        case .rect(let l, let t, let w, let h, _):
            ctx.addRect(CGRect(
                x: imgRect.minX + l * imgRect.width,
                y: imgRect.minY + t * imgRect.height,
                width: w * imgRect.width,
                height: h * imgRect.height
            ))
            ctx.drawPath(using: .fillStroke)
        case .ellipse(let l, let t, let rx, let ry, _):
            let absRx = rx * imgRect.width
            let absRy = ry * imgRect.height
            let cx = imgRect.minX + l * imgRect.width + absRx
            let cy = imgRect.minY + t * imgRect.height + absRy
            ctx.addEllipse(in: CGRect(x: cx - absRx, y: cy - absRy, width: absRx * 2, height: absRy * 2))
            ctx.drawPath(using: .fillStroke)
        case .polygon(let pts, _):
            guard let first = pts.first else { return }
            let abs = { (p: CGPoint) -> CGPoint in
                CGPoint(x: imgRect.minX + p.x * imgRect.width,
                        y: imgRect.minY + p.y * imgRect.height)
            }
            ctx.move(to: abs(first))
            for pt in pts.dropFirst() { ctx.addLine(to: abs(pt)) }
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        case .text(let l, let t, let text, let scale, let fontSize, _):
            let frame = textFrame(
                for: text,
                left: l,
                top: t,
                scale: scale,
                fontSize: fontSize,
                imgRect: imgRect
            )
            let backgroundPath = UIBezierPath(roundedRect: frame, cornerRadius: 8)
            ctx.saveGState()
            ctx.addPath(backgroundPath.cgPath)
            ctx.setFillColor(UIColor(white: 1, alpha: 0.88).cgColor)
            ctx.fillPath()
            ctx.restoreGState()

            let attrs: [NSAttributedString.Key: Any] = [
                .font: textFont(scale: scale, fontSize: fontSize, imgRect: imgRect),
                .foregroundColor: UIColor.label
            ]
            (text as NSString).draw(
                at: CGPoint(x: frame.minX + 10, y: frame.minY + 6),
                withAttributes: attrs
            )
        }
    }

    private func drawOrdinal(ctx: CGContext, index: Int, mask: IOMask, imgRect: CGRect) {
        let center: CGPoint
        switch mask {
        case .rect(let l, let t, let w, let h, _):
            center = CGPoint(x: imgRect.minX + (l + w / 2) * imgRect.width,
                             y: imgRect.minY + (t + h / 2) * imgRect.height)
        case .ellipse(let l, let t, let rx, let ry, _):
            center = CGPoint(x: imgRect.minX + (l + rx) * imgRect.width,
                             y: imgRect.minY + (t + ry) * imgRect.height)
        case .polygon(let pts, _):
            let cx = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
            let cy = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
            center = CGPoint(x: imgRect.minX + cx * imgRect.width,
                             y: imgRect.minY + cy * imgRect.height)
        case .text(let l, let t, let text, let scale, let fontSize, _):
            center = CGPoint(
                x: textFrame(for: text, left: l, top: t, scale: scale, fontSize: fontSize, imgRect: imgRect).midX,
                y: textFrame(for: text, left: l, top: t, scale: scale, fontSize: fontSize, imgRect: imgRect).midY
            )
        }
        let label = "\(index + 1)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.darkText
        ]
        let sz = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs)
    }

    // MARK: - Gestures

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        let loc = g.location(in: self)
        let imgRect = imageRect(in: bounds)
        switch g.state {
        case .began:
            if let drag = beginMaskDrag(at: loc, imgRect: imgRect) {
                activeDrag = drag
                return
            }
            guard shapeType == .rect || shapeType == .ellipse else { return }
            dragStart = loc
            currentDragRect = nil
        case .changed:
            if let activeDrag {
                updateMaskDrag(activeDrag, location: loc, imgRect: imgRect)
                return
            }
            guard shapeType == .rect || shapeType == .ellipse else { return }
            guard let start = dragStart else { return }
            currentDragRect = makeRect(from: start, to: loc)
            setNeedsDisplay()
        case .ended:
            if activeDrag != nil {
                activeDrag = nil
                setNeedsDisplay()
                return
            }
            guard shapeType == .rect || shapeType == .ellipse else { return }
            guard let start = dragStart else { return }
            let r = makeRect(from: start, to: loc)
            let mask = normalizedMask(from: r, in: imgRect)
            coordinator?.appendMask(mask)
            dragStart = nil
            currentDragRect = nil
            setNeedsDisplay()
        default:
            activeDrag = nil
            dragStart = nil
            currentDragRect = nil
            setNeedsDisplay()
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let location = g.location(in: self)
        let imgRect = imageRect(in: bounds)
        if shapeType == .polygon {
            polygonPoints.append(location)
            setNeedsDisplay()
            return
        }
        if shapeType == .text {
            guard imgRect.contains(location) else { return }
            let normalizedPoint = CGPoint(
                x: max(0, min(1, (location.x - imgRect.minX) / imgRect.width)),
                y: max(0, min(1, (location.y - imgRect.minY) / imgRect.height))
            )
            coordinator?.requestText(at: normalizedPoint)
            return
        }

        let selected = hitTestMaskIndex(at: location, imgRect: imgRect)
        selectedMaskIndex = selected
        coordinator?.selectMask(selected)
        setNeedsDisplay()
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        guard shapeType == .polygon else { return }
        if polygonPoints.count >= 3 {
            let imgRect = imageRect(in: bounds)
            let pts = polygonPoints.map { pt -> CGPoint in
                CGPoint(
                    x: max(0, min(1, (pt.x - imgRect.minX) / imgRect.width)),
                    y: max(0, min(1, (pt.y - imgRect.minY) / imgRect.height))
                )
            }
            coordinator?.appendMask(.polygon(points: pts, extras: [:]))
        }
        polygonPoints.removeAll()
        setNeedsDisplay()
    }

    // MARK: - Helpers

    private func makeRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func imageRect(in bounds: CGRect) -> CGRect {
        let s = image.size
        let scale = min(bounds.width / s.width, bounds.height / s.height)
        let w = s.width * scale, h = s.height * scale
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    private func normalizedMask(from r: CGRect, in imgRect: CGRect) -> IOMask {
        let l = max(0, min(1, (r.minX - imgRect.minX) / imgRect.width))
        let t = max(0, min(1, (r.minY - imgRect.minY) / imgRect.height))
        let w = max(0, min(1 - l, r.width / imgRect.width))
        let h = max(0, min(1 - t, r.height / imgRect.height))
        if shapeType == .ellipse {
            return .ellipse(left: l, top: t, rx: w / 2, ry: h / 2, extras: [:])
        } else {
            return .rect(left: l, top: t, width: w, height: h, extras: [:])
        }
    }

    private func maskFillColor(for mask: IOMask) -> UIColor? {
        guard let fill = mask.extras["fill"] else { return nil }
        return UIColor(ioHex: fill)
    }

    private func textFrame(
        for text: String,
        left: CGFloat,
        top: CGFloat,
        scale: CGFloat,
        fontSize: CGFloat,
        imgRect: CGRect
    ) -> CGRect {
        let font = textFont(scale: scale, fontSize: fontSize, imgRect: imgRect)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding = CGSize(width: 20, height: 12)
        let origin = CGPoint(
            x: imgRect.minX + left * imgRect.width,
            y: imgRect.minY + top * imgRect.height
        )
        return CGRect(origin: origin, size: CGSize(width: textSize.width + padding.width, height: textSize.height + padding.height))
    }

    private func textFont(scale: CGFloat, fontSize: CGFloat, imgRect: CGRect) -> UIFont {
        let resolvedSize = max(14, imgRect.height * max(fontSize, 0.02) * max(scale, 1))
        return UIFont.systemFont(ofSize: resolvedSize, weight: .semibold)
    }

    private func drawSelectionOutline(ctx: CGContext, mask: IOMask, imgRect: CGRect) {
        let bounds = maskBounds(for: mask, imgRect: imgRect).insetBy(dx: -6, dy: -6)
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(bounds)
        if case .polygon(let points, _) = mask {
            for point in points {
                let handleCenter = CGPoint(x: imgRect.minX + point.x * imgRect.width, y: imgRect.minY + point.y * imgRect.height)
                ctx.fill(handleRect(center: handleCenter).insetBy(dx: 1, dy: 1))
            }
        } else {
            ctx.fill(handleRect(center: CGPoint(x: bounds.maxX, y: bounds.maxY)).insetBy(dx: 1, dy: 1))
        }
        ctx.restoreGState()
    }

    private func maskBounds(for mask: IOMask, imgRect: CGRect) -> CGRect {
        switch mask {
        case .rect(let l, let t, let w, let h, _):
            return CGRect(
                x: imgRect.minX + l * imgRect.width,
                y: imgRect.minY + t * imgRect.height,
                width: w * imgRect.width,
                height: h * imgRect.height
            )
        case .ellipse(let l, let t, let rx, let ry, _):
            return CGRect(
                x: imgRect.minX + l * imgRect.width,
                y: imgRect.minY + t * imgRect.height,
                width: rx * imgRect.width * 2,
                height: ry * imgRect.height * 2
            )
        case .polygon(let pts, _):
            let absolutePoints = pts.map {
                CGPoint(x: imgRect.minX + $0.x * imgRect.width, y: imgRect.minY + $0.y * imgRect.height)
            }
            let xs = absolutePoints.map(\.x)
            let ys = absolutePoints.map(\.y)
            return CGRect(
                x: xs.min() ?? imgRect.minX,
                y: ys.min() ?? imgRect.minY,
                width: (xs.max() ?? imgRect.minX) - (xs.min() ?? imgRect.minX),
                height: (ys.max() ?? imgRect.minY) - (ys.min() ?? imgRect.minY)
            )
        case .text(let l, let t, let text, let scale, let fontSize, _):
            return textFrame(for: text, left: l, top: t, scale: scale, fontSize: fontSize, imgRect: imgRect)
        }
    }

    private func hitTestMaskIndex(at point: CGPoint, imgRect: CGRect) -> Int? {
        for index in masks.indices.reversed() {
            if maskContainsPoint(masks[index], point: point, imgRect: imgRect) {
                return index
            }
        }
        return nil
    }

    private func maskContainsPoint(_ mask: IOMask, point: CGPoint, imgRect: CGRect) -> Bool {
        switch mask {
        case .rect:
            return maskBounds(for: mask, imgRect: imgRect).contains(point)
        case .ellipse(let l, let t, let rx, let ry, _):
            let rect = CGRect(
                x: imgRect.minX + l * imgRect.width,
                y: imgRect.minY + t * imgRect.height,
                width: rx * imgRect.width * 2,
                height: ry * imgRect.height * 2
            )
            guard rect.width > 0, rect.height > 0 else { return false }
            let normalizedX = (point.x - rect.midX) / (rect.width / 2)
            let normalizedY = (point.y - rect.midY) / (rect.height / 2)
            return normalizedX * normalizedX + normalizedY * normalizedY <= 1
        case .polygon(let pts, _):
            let path = UIBezierPath()
            guard let first = pts.first else { return false }
            path.move(to: CGPoint(x: imgRect.minX + first.x * imgRect.width, y: imgRect.minY + first.y * imgRect.height))
            for pt in pts.dropFirst() {
                path.addLine(to: CGPoint(x: imgRect.minX + pt.x * imgRect.width, y: imgRect.minY + pt.y * imgRect.height))
            }
            path.close()
            return path.contains(point)
        case .text:
            return maskBounds(for: mask, imgRect: imgRect).contains(point)
        }
    }

    private func beginMaskDrag(at location: CGPoint, imgRect: CGRect) -> ActiveDrag? {
        if let selectedMaskIndex,
           masks.indices.contains(selectedMaskIndex) {
            let selectedMask = masks[selectedMaskIndex]
            if case .polygon(let points, _) = selectedMask,
               let vertexIndex = polygonVertexIndex(near: location, points: points, imgRect: imgRect) {
                return .polygonVertex(maskIndex: selectedMaskIndex, vertexIndex: vertexIndex)
            }
            if handleRect(center: resizeHandleCenter(for: selectedMask, imgRect: imgRect)).contains(location),
               !isPolygonMask(selectedMask) {
                return .resize(maskIndex: selectedMaskIndex, start: location, original: selectedMask)
            }
            if maskContainsPoint(selectedMask, point: location, imgRect: imgRect) {
                return .move(maskIndex: selectedMaskIndex, start: location, original: selectedMask)
            }
        }

        guard let hitIndex = hitTestMaskIndex(at: location, imgRect: imgRect),
              masks.indices.contains(hitIndex) else {
            return nil
        }
        let hitMask = masks[hitIndex]
        selectedMaskIndex = hitIndex
        coordinator?.selectMask(hitIndex)
        if case .polygon(let points, _) = hitMask,
           let vertexIndex = polygonVertexIndex(near: location, points: points, imgRect: imgRect) {
            return .polygonVertex(maskIndex: hitIndex, vertexIndex: vertexIndex)
        }
        return .move(maskIndex: hitIndex, start: location, original: hitMask)
    }

    private func updateMaskDrag(_ drag: ActiveDrag, location: CGPoint, imgRect: CGRect) {
        switch drag {
        case .move(let maskIndex, let start, let original):
            let delta = CGPoint(x: location.x - start.x, y: location.y - start.y)
            guard let updated = movedMask(original, delta: delta, imgRect: imgRect) else { return }
            coordinator?.updateMask(at: maskIndex, to: updated)
        case .resize(let maskIndex, let start, let original):
            let delta = CGPoint(x: location.x - start.x, y: location.y - start.y)
            guard let updated = resizedMask(original, delta: delta, imgRect: imgRect) else { return }
            coordinator?.updateMask(at: maskIndex, to: updated)
        case .polygonVertex(let maskIndex, let vertexIndex):
            guard case .polygon(let points, let extras) = masks[maskIndex] else { return }
            var updatedPoints = points
            updatedPoints[vertexIndex] = CGPoint(
                x: max(0, min(1, (location.x - imgRect.minX) / imgRect.width)),
                y: max(0, min(1, (location.y - imgRect.minY) / imgRect.height))
            )
            coordinator?.updateMask(at: maskIndex, to: .polygon(points: updatedPoints, extras: extras))
        }
        setNeedsDisplay()
    }

    private func movedMask(_ mask: IOMask, delta: CGPoint, imgRect: CGRect) -> IOMask? {
        let dx = delta.x / imgRect.width
        let dy = delta.y / imgRect.height
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
            let frame = textFrame(for: text, left: left, top: top, scale: scale, fontSize: fontSize, imgRect: imgRect)
            let normalizedWidth = frame.width / imgRect.width
            let normalizedHeight = frame.height / imgRect.height
            return .text(
                left: max(0, min(1 - normalizedWidth, left + dx)),
                top: max(0, min(1 - normalizedHeight, top + dy)),
                text: text,
                scale: scale,
                fontSize: fontSize,
                extras: extras
            )
        }
    }

    private func resizedMask(_ mask: IOMask, delta: CGPoint, imgRect: CGRect) -> IOMask? {
        switch mask {
        case .rect(let left, let top, let width, let height, let extras):
            let newWidth = max(0.02, min(1 - left, width + delta.x / imgRect.width))
            let newHeight = max(0.02, min(1 - top, height + delta.y / imgRect.height))
            return .rect(left: left, top: top, width: newWidth, height: newHeight, extras: extras)
        case .ellipse(let left, let top, let rx, let ry, let extras):
            let newWidth = max(0.02, min(1 - left, rx * 2 + delta.x / imgRect.width))
            let newHeight = max(0.02, min(1 - top, ry * 2 + delta.y / imgRect.height))
            return .ellipse(left: left, top: top, rx: newWidth / 2, ry: newHeight / 2, extras: extras)
        default:
            return movedMask(mask, delta: delta, imgRect: imgRect)
        }
    }

    private func resizeHandleCenter(for mask: IOMask, imgRect: CGRect) -> CGPoint {
        let bounds = maskBounds(for: mask, imgRect: imgRect).insetBy(dx: -6, dy: -6)
        return CGPoint(x: bounds.maxX, y: bounds.maxY)
    }

    private func handleRect(center: CGPoint) -> CGRect {
        CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)
    }

    private func polygonVertexIndex(near point: CGPoint, points: [CGPoint], imgRect: CGRect) -> Int? {
        for (index, polygonPoint) in points.enumerated() {
            let absolute = CGPoint(x: imgRect.minX + polygonPoint.x * imgRect.width, y: imgRect.minY + polygonPoint.y * imgRect.height)
            if handleRect(center: absolute).contains(point) {
                return index
            }
        }
        return nil
    }

    private func isPolygonMask(_ mask: IOMask) -> Bool {
        if case .polygon = mask {
            return true
        }
        return false
    }
}

private extension UIColor {
    convenience init?(ioHex: String) {
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

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
