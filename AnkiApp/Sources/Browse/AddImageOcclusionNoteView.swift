import SwiftUI
import PhotosUI
import AnkiClients
import Dependencies

// MARK: - Shape type

enum IOShapeType: String, CaseIterable {
    case rect, ellipse, polygon

    var label: String {
        switch self {
        case .rect:    return L("io_shape_rect")
        case .ellipse: return L("io_shape_ellipse")
        case .polygon: return L("io_shape_polygon")
        }
    }

    var systemImage: String {
        switch self {
        case .rect:    return "rectangle"
        case .ellipse: return "oval"
        case .polygon: return "pentagon"
        }
    }
}

// MARK: - Mask model

enum IOMask {
    /// left/top/width/height in 0-1 fractions
    case rect(left: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat)
    /// left/top = top-left corner of bounding box; rx/ry = radii, all 0-1 fractions
    case ellipse(left: CGFloat, top: CGFloat, rx: CGFloat, ry: CGFloat)
    /// points: normalized (x, y) pairs
    case polygon(points: [CGPoint])

    func occlusionText(index: Int) -> String {
        let n = index + 1
        switch self {
        case .rect(let l, let t, let w, let h):
            return "{{c\(n)::image-occlusion:rect:left=\(f(l)):top=\(f(t)):width=\(f(w)):height=\(f(h))}}"
        case .ellipse(let l, let t, let rx, let ry):
            return "{{c\(n)::image-occlusion:ellipse:left=\(f(l)):top=\(f(t)):rx=\(f(rx)):ry=\(f(ry))}}"
        case .polygon(let pts):
            let ptsStr = pts.map { "\(f($0.x)),\(f($0.y))" }.joined(separator: " ")
            return "{{c\(n)::image-occlusion:polygon:points=\(ptsStr)}}"
        }
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
    @State private var shapeType: IOShapeType = .rect
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
                        if let img = selectedImage {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .frame(maxHeight: 200)
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(L("io_pick_image"), systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
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
                            .font(.caption2)
                    }

                    Section {
                        OcclusionCanvasView(
                            image: uiImage,
                            masks: $masks,
                            shapeType: shapeType,
                            onAppend: appendMask(_:)
                        )
                            .frame(height: canvasHeight(for: uiImage))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        if !masks.isEmpty {
                            HStack {
                                Text(L("io_mask_count", masks.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) {
                                    removeLast()
                                } label: {
                                    Label(L("io_remove_last"), systemImage: "arrow.uturn.backward")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
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
                        .font(.caption2)
                }

                // MARK: Error
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(L("io_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        undoManager?.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!(undoManager?.canUndo ?? false))
                    Spacer()
                    Button {
                        undoManager?.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!(undoManager?.canRedo ?? false))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("common_save")) {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .overlay {
                        if isSaving { ProgressView().scaleEffect(0.7) }
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        selectedImage != nil && !masks.isEmpty
    }

    private func removeLast() {
        guard !masks.isEmpty else { return }
        let removed = masks.removeLast()
        undoManager?.registerUndo(withTarget: UIApplication.shared) { [masks] _ in
            self.masks.append(removed)
            self.undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
                _ = self.masks.popLast()
            }
        }
    }

    private func appendMask(_ mask: IOMask) {
        masks.append(mask)
        undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
            _ = self.masks.popLast()
            self.undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
                self.masks.append(mask)
            }
        }
    }

    private var shapeHint: String {
        switch shapeType {
        case .rect:    return L("io_hint_rect")
        case .ellipse: return L("io_hint_ellipse")
        case .polygon: return L("io_hint_polygon")
        }
    }

    private func canvasHeight(for image: UIImage) -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width - 64  // approx form width
        let ratio = image.size.height / image.size.width
        return min(screenWidth * ratio, 280)
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }
        self.masks = []

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
    let shapeType: IOShapeType
    var onAppend: ((IOMask) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(masks: $masks, onAppend: onAppend)
    }

    func makeUIView(context: Context) -> OcclusionCanvasUIView {
        let view = OcclusionCanvasUIView(image: image)
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: OcclusionCanvasUIView, context: Context) {
        uiView.image = image
        uiView.masks = masks
        uiView.shapeType = shapeType
        context.coordinator.onAppend = onAppend
        uiView.setNeedsDisplay()
    }

    final class Coordinator {
        @Binding var masks: [IOMask]
        var onAppend: ((IOMask) -> Void)?
        init(masks: Binding<[IOMask]>, onAppend: ((IOMask) -> Void)?) {
            _masks = masks
            self.onAppend = onAppend
        }

        func appendMask(_ mask: IOMask) {
            if let onAppend {
                // validate before delegating to undo-aware handler
                switch mask {
                case .rect(_, _, let w, let h) where w > 0.02 && h > 0.02: onAppend(mask)
                case .ellipse(_, _, let rx, let ry) where rx > 0.01 && ry > 0.01: onAppend(mask)
                case .polygon(let pts) where pts.count >= 3: onAppend(mask)
                default: break
                }
            } else {
                switch mask {
                case .rect(_, _, let w, let h) where w > 0.02 && h > 0.02: masks.append(mask)
                case .ellipse(_, _, let rx, let ry) where rx > 0.01 && ry > 0.01: masks.append(mask)
                case .polygon(let pts) where pts.count >= 3: masks.append(mask)
                default: break
                }
            }
        }
    }
}

// MARK: - OcclusionCanvasUIView

final class OcclusionCanvasUIView: UIView {
    var image: UIImage
    var masks: [IOMask] = []
    var shapeType: IOShapeType = .rect
    weak var coordinator: OcclusionCanvasView.Coordinator?

    private var dragStart: CGPoint?
    private var currentDragRect: CGRect?
    private var polygonPoints: [CGPoint] = []

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
            ctx.setFillColor(inactiveFill)
            ctx.setStrokeColor(inactiveStroke)
            ctx.setLineWidth(1.5)
            drawMask(ctx: ctx, mask: mask, imgRect: imgRect)
            drawOrdinal(ctx: ctx, index: i, mask: mask, imgRect: imgRect)
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
        case .rect(let l, let t, let w, let h):
            ctx.addRect(CGRect(
                x: imgRect.minX + l * imgRect.width,
                y: imgRect.minY + t * imgRect.height,
                width: w * imgRect.width,
                height: h * imgRect.height
            ))
            ctx.drawPath(using: .fillStroke)
        case .ellipse(let l, let t, let rx, let ry):
            let absRx = rx * imgRect.width
            let absRy = ry * imgRect.height
            let cx = imgRect.minX + l * imgRect.width + absRx
            let cy = imgRect.minY + t * imgRect.height + absRy
            ctx.addEllipse(in: CGRect(x: cx - absRx, y: cy - absRy, width: absRx * 2, height: absRy * 2))
            ctx.drawPath(using: .fillStroke)
        case .polygon(let pts):
            guard let first = pts.first else { return }
            let abs = { (p: CGPoint) -> CGPoint in
                CGPoint(x: imgRect.minX + p.x * imgRect.width,
                        y: imgRect.minY + p.y * imgRect.height)
            }
            ctx.move(to: abs(first))
            for pt in pts.dropFirst() { ctx.addLine(to: abs(pt)) }
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }
    }

    private func drawOrdinal(ctx: CGContext, index: Int, mask: IOMask, imgRect: CGRect) {
        let center: CGPoint
        switch mask {
        case .rect(let l, let t, let w, let h):
            center = CGPoint(x: imgRect.minX + (l + w / 2) * imgRect.width,
                             y: imgRect.minY + (t + h / 2) * imgRect.height)
        case .ellipse(let l, let t, let rx, let ry):
            center = CGPoint(x: imgRect.minX + (l + rx) * imgRect.width,
                             y: imgRect.minY + (t + ry) * imgRect.height)
        case .polygon(let pts):
            let cx = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
            let cy = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
            center = CGPoint(x: imgRect.minX + cx * imgRect.width,
                             y: imgRect.minY + cy * imgRect.height)
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
        guard shapeType == .rect || shapeType == .ellipse else { return }
        let loc = g.location(in: self)
        switch g.state {
        case .began:
            dragStart = loc
            currentDragRect = nil
        case .changed:
            guard let start = dragStart else { return }
            currentDragRect = makeRect(from: start, to: loc)
            setNeedsDisplay()
        case .ended:
            guard let start = dragStart else { return }
            let r = makeRect(from: start, to: loc)
            let imgRect = imageRect(in: bounds)
            let mask = normalizedMask(from: r, in: imgRect)
            coordinator?.appendMask(mask)
            dragStart = nil
            currentDragRect = nil
            setNeedsDisplay()
        default:
            dragStart = nil
            currentDragRect = nil
            setNeedsDisplay()
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard shapeType == .polygon else { return }
        polygonPoints.append(g.location(in: self))
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
            coordinator?.appendMask(.polygon(points: pts))
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
            return .ellipse(left: l, top: t, rx: w / 2, ry: h / 2)
        } else {
            return .rect(left: l, top: t, width: w, height: h)
        }
    }
}
