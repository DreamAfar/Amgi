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
    let embedInNavigationStack: Bool

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var uiImage: UIImage?
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
    @State private var saveError: String?

    init(noteId: Int64, onSave: @escaping () -> Void, embedInNavigationStack: Bool = true) {
        self.noteId = noteId
        self.onSave = onSave
        self.embedInNavigationStack = embedInNavigationStack
    }

    var body: some View {
        Group {
            if embedInNavigationStack {
                NavigationStack {
                    editorBody
                }
            } else {
                editorBody
            }
        }
    }

    private var editorBody: some View {
        Group {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = loadError {
                    AmgiStatusMessageView(
                        title: L("common_error"),
                        message: err,
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                } else {
                    Form {
                        if let img = uiImage {
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
                                        image: img,
                                        masks: $masks,
                                        selectedMaskIndex: $selectedMaskIndex,
                                        shapeType: shapeType,
                                        onRequestText: beginTextInsertion(at:),
                                        onAppend: appendMask(_:)
                                    )
                                    .frame(height: canvasHeight(for: img))
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

                        if let err = saveError {
                            Section {
                                Text(err)
                                    .amgiStatusText(.danger, font: .caption)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.amgiBackground)
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
        .navigationTitle(L("io_edit_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedInNavigationStack {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("common_cancel")) { dismiss() }
                        .amgiToolbarTextButton(tone: .neutral)
                }
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

    private var shapeHint: String {
        switch shapeType {
        case .rect:    return L("io_hint_rect")
        case .ellipse: return L("io_hint_ellipse")
        case .polygon: return L("io_hint_polygon")
        case .text:    return L("io_hint_text")
        }
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
            selectedMaskIndex = nil
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
        let parts = inner.components(separatedBy: ":")
        guard parts.count >= 2, parts[0] == "image-occlusion" else { continue }
        let shapeName = parts[1]
        let stringProps = parseIOProperties(from: parts.dropFirst(2).joined(separator: ":"))
        switch shapeName {
        case "rect":
            if let l = ioCGFloat(stringProps["left"]), let t = ioCGFloat(stringProps["top"]),
               let w = ioCGFloat(stringProps["width"]), let h = ioCGFloat(stringProps["height"]) {
                result.append(.rect(left: l, top: t, width: w, height: h, extras: ioExtras(from: stringProps, excluding: ["left", "top", "width", "height"])))
            }
        case "ellipse":
            if let l = ioCGFloat(stringProps["left"]), let t = ioCGFloat(stringProps["top"]),
               let rx = ioCGFloat(stringProps["rx"]), let ry = ioCGFloat(stringProps["ry"]) {
                result.append(.ellipse(left: l, top: t, rx: rx, ry: ry, extras: ioExtras(from: stringProps, excluding: ["left", "top", "rx", "ry"])))
            }
        case "polygon":
            if let raw = stringProps["points"] {
                let coords = raw.components(separatedBy: CharacterSet(charactersIn: ", "))
                    .compactMap { Double($0) }
                var pts: [CGPoint] = []
                var i = 0
                while i + 1 < coords.count {
                    pts.append(CGPoint(x: coords[i], y: coords[i + 1]))
                    i += 2
                }
                if pts.count >= 3 {
                    result.append(.polygon(points: pts, extras: ioExtras(from: stringProps, excluding: ["points"])))
                }
            }
        case "text":
            if let l = ioCGFloat(stringProps["left"]),
               let t = ioCGFloat(stringProps["top"]),
               let text = stringProps["text"],
               !text.isEmpty {
                let scale = ioCGFloat(stringProps["scale"]) ?? 1
                let fontSize = ioCGFloat(stringProps["fs"]) ?? 0.055
                result.append(
                    .text(
                        left: l,
                        top: t,
                        text: text,
                        scale: scale,
                        fontSize: fontSize,
                        extras: ioExtras(from: stringProps, excluding: ["left", "top", "text", "scale", "fs"])
                    )
                )
            }
        default:
            break
        }
    }
    return result
}

private func parseIOProperties(from source: String) -> [String: String] {
    guard !source.isEmpty,
          let regex = try? NSRegularExpression(pattern: "([A-Za-z]+)=") else {
        return [:]
    }

    let nsSource = source as NSString
    let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
    guard !matches.isEmpty else { return [:] }

    var properties: [String: String] = [:]
    for (index, match) in matches.enumerated() {
        let key = nsSource.substring(with: match.range(at: 1))
        let valueStart = match.range.location + match.range.length
        let valueEnd = index + 1 < matches.count ? matches[index + 1].range.location - 1 : nsSource.length
        guard valueEnd >= valueStart else { continue }
        let value = nsSource.substring(with: NSRange(location: valueStart, length: valueEnd - valueStart))
        properties[key] = value
    }
    return properties
}

private func ioCGFloat(_ value: String?) -> CGFloat? {
    guard let value, let numeric = Double(value) else { return nil }
    return CGFloat(numeric)
}

private func ioExtras(from properties: [String: String], excluding keys: Set<String>) -> [String: String] {
    properties.filter { !keys.contains($0.key) }
}

private func extractClozeBody(_ cloze: String) -> String? {
    // "{{c1::image-occlusion:...}}" → "image-occlusion:..."
    guard cloze.hasPrefix("{{"), cloze.hasSuffix("}}") else { return nil }
    let inner = String(cloze.dropFirst(2).dropLast(2))
    guard let colonIdx = inner.range(of: "::") else { return nil }
    return String(inner[colonIdx.upperBound...])
}
