import SwiftUI
import AnkiClients
import Dependencies

// MARK: - EditImageOcclusionNoteView

struct EditImageOcclusionNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Dependency(\.imageOcclusionClient) private var client

    let noteId: Int64
    let onSave: () -> Void

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var uiImage: UIImage?
    @State private var masks: [IOMask] = []
    @State private var shapeType: IOShapeType = .rect
    @State private var header: String = ""
    @State private var backExtra: String = ""
    @State private var tagsText: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
                } else {
                    Form {
                        // MARK: Image (read-only in edit mode)
                        if let img = uiImage {
                            Section(L("io_section_image")) {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .frame(maxHeight: 200)
                                    .frame(maxWidth: .infinity)
                            }

                            // MARK: Shape picker + canvas
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
                                OcclusionCanvasView(
                                    image: img,
                                    masks: $masks,
                                    shapeType: shapeType,
                                    onAppend: appendMask(_:)
                                )
                                    .frame(height: canvasHeight(for: img))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))

                                if !masks.isEmpty {
                                    HStack {
                                        Text(L("io_mask_count", masks.count))
                                            .amgiFont(.caption)
                                            .foregroundStyle(Color.amgiTextSecondary)
                                        Spacer()
                                        Button(role: .destructive) {
                                            removeLast()
                                        } label: {
                                            Label(L("io_remove_last"), systemImage: "arrow.uturn.backward")
                                                .font(AmgiFont.caption.font)
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
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }

                        if let err = saveError {
                            Section {
                                Text(err)
                                    .amgiStatusBadge(.danger)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.amgiBackground)
                }
            }
            .navigationTitle(L("io_edit_nav_title"))
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
                    .disabled(isLoading || masks.isEmpty || isSaving)
                    .overlay { if isSaving { ProgressView().scaleEffect(0.7) } }
                }
            }
            .task { await loadNote() }
        }
    }

    private var shapeHint: String {
        switch shapeType {
        case .rect:    return L("io_hint_rect")
        case .ellipse: return L("io_hint_ellipse")
        case .polygon: return L("io_hint_polygon")
        }
    }

    private func removeLast() {
        guard !masks.isEmpty else { return }
        let removed = masks.removeLast()
        undoManager?.registerUndo(withTarget: UIApplication.shared) { _ in
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

    private func canvasHeight(for image: UIImage) -> CGFloat {
        let screenWidth = UIScreen.main.bounds.width - 64
        let ratio = image.size.height / image.size.width
        return min(screenWidth * ratio, 280)
    }

    @MainActor
    private func loadNote() async {
        isLoading = true
        loadError = nil
        do {
            let data = try client.getNote(noteId)

            // Decode image
            if let img = UIImage(data: data.imageData) {
                uiImage = img
            }

            // Parse header/backExtra/tags
            header = data.header
            backExtra = data.backExtra
            tagsText = data.tags.joined(separator: " ")

            // Parse occlusion string back to IOMask array
            masks = parseMasks(from: data.occlusions)
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func save() async {
        guard !masks.isEmpty else { return }
        isSaving = true
        saveError = nil
        let occlusions = masks.enumerated().map { idx, mask in
            mask.occlusionText(index: idx)
        }.joined(separator: "\n")
        let tags = tagsText.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        do {
            try client.updateNote(noteId, occlusions, header, backExtra, tags)
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Occlusion string parser

/// Parses "{{c1::image-occlusion:rect:left=X:top=Y:width=W:height=H}}" etc. → [IOMask]
private func parseMasks(from occlusions: String) -> [IOMask] {
    let lines = occlusions.components(separatedBy: "\n")
    var result: [IOMask] = []
    for line in lines {
        guard let inner = extractClozeBody(line) else { continue }
        // inner = "image-occlusion:rect:left=X:top=Y:..."
        let parts = inner.components(separatedBy: ":")
        guard parts.count >= 2, parts[0] == "image-occlusion" else { continue }
        let shapeName = parts[1]
        var props: [String: CGFloat] = [:]
        for part in parts.dropFirst(2) {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2, let v = Double(kv[1]) {
                props[kv[0]] = CGFloat(v)
            }
        }
        switch shapeName {
        case "rect":
            if let l = props["left"], let t = props["top"],
               let w = props["width"], let h = props["height"] {
                result.append(.rect(left: l, top: t, width: w, height: h))
            }
        case "ellipse":
            if let l = props["left"], let t = props["top"],
               let rx = props["rx"], let ry = props["ry"] {
                result.append(.ellipse(left: l, top: t, rx: rx, ry: ry))
            }
        case "polygon":
            // polygon points are in the last colon-segment as "x1,y1 x2,y2 ..."
            // Find the "points=..." token (may contain commas and spaces)
            if let pointsPart = parts.first(where: { $0.hasPrefix("points=") }) {
                let raw = String(pointsPart.dropFirst("points=".count))
                let coords = raw.components(separatedBy: CharacterSet(charactersIn: ", "))
                    .compactMap { Double($0) }
                var pts: [CGPoint] = []
                var i = 0
                while i + 1 < coords.count {
                    pts.append(CGPoint(x: coords[i], y: coords[i + 1]))
                    i += 2
                }
                if pts.count >= 3 {
                    result.append(.polygon(points: pts))
                }
            }
        default:
            break
        }
    }
    return result
}

private func extractClozeBody(_ cloze: String) -> String? {
    // "{{c1::image-occlusion:...}}" → "image-occlusion:..."
    guard cloze.hasPrefix("{{"), cloze.hasSuffix("}}") else { return nil }
    let inner = String(cloze.dropFirst(2).dropLast(2))
    guard let colonIdx = inner.range(of: "::") else { return nil }
    return String(inner[colonIdx.upperBound...])
}
