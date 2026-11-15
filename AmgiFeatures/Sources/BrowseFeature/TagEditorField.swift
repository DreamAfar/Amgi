//
//  TagEditorField.swift
//  BrowseFeature
//

import SwiftUI
import Theme
import UIKit

/// A note's tags as removable, editable chips followed by a text field for
/// new ones. Bound to the same space-separated string the note stores, so
/// the models and the save path stay as they were.
///
/// - Tap a chip to edit it in place; Return or tapping elsewhere commits,
///   clearing it removes the tag, and spaces split it into several.
/// - × removes a chip; a long press offers Edit, Copy and Remove.
/// - Space or Return in the field turns the text into chips (pasting
///   "a b c" gives three); matching collection tags are suggested below
///   while typing. A tag already on the note isn't added twice — its chip
///   flashes instead.
/// - Text still in the field counts as tags, so saving without pressing
///   Return doesn't lose it.
struct TagEditorField: View {
    @Binding var tags: String

    @Environment(\.palette) private var palette

    @State private var suggestionsModel = TagSuggestionsModel()
    @State private var list: [String] = []
    @State private var input = ""
    @State private var editingIndex: Int?
    @State private var editingText = ""
    @State private var highlighted: Int?
    /// The string this view last wrote, to tell its own writes from the
    /// model loading or resetting the note.
    @State private var lastWritten: String?
    @FocusState private var focus: Focus?

    private enum Focus: Hashable {
        case input
        case chip
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            TagFlowLayout(spacing: AmgiSpacing.xs) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, tag in
                    if editingIndex == index {
                        editingChip
                    } else {
                        chip(tag, at: index)
                    }
                }
                TextField(String(localized: "Add tag", bundle: .module), text: $input)
                    .amgiFont(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($focus, equals: .input)
                    .onSubmit {
                        commitInput(keepingTail: false)
                        focus = .input
                    }
                    .fillsTagRow(minWidth: 96)
            }
            suggestionRow
        }
        .padding(.vertical, AmgiSpacing.xxs)
        .onAppear { syncFromBinding(tags) }
        .onChange(of: tags) { _, newValue in
            if newValue != lastWritten { syncFromBinding(newValue) }
        }
        .onChange(of: input) { _, newValue in
            if newValue.contains(where: \.isWhitespace) {
                // A trailing space commits everything; a paste with inner
                // spaces commits all but the fragment still being typed.
                commitInput(keepingTail: !(newValue.last?.isWhitespace ?? false))
            } else {
                write()
            }
        }
        .onChange(of: focus) { old, new in
            if old == .chip, new != .chip { commitEdit() }
        }
        .task { await suggestionsModel.load() }
    }

    // MARK: - Chips

    private func chip(_ tag: String, at index: Int) -> some View {
        HStack(spacing: AmgiSpacing.xxs) {
            Text(tag)
                .amgiFont(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(palette.textSecondary)
                    .padding(AmgiSpacing.xxs)
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(palette.textPrimary)
        .padding(.leading, AmgiSpacing.sm)
        .padding(.trailing, AmgiSpacing.xs)
        .padding(.vertical, AmgiSpacing.xxs)
        .background(highlighted == index ? palette.accent.opacity(0.35) : palette.accentSoft, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { beginEditing(at: index) }
        .contextMenu {
            Button(String(localized: "Edit", bundle: .module), systemImage: "pencil") {
                beginEditing(at: index)
            }
            Button(String(localized: "Copy", bundle: .module), systemImage: "doc.on.doc") {
                UIPasteboard.general.string = tag
            }
            Button(String(localized: "Remove", bundle: .module), systemImage: "xmark", role: .destructive) {
                remove(at: index)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tag)
        .accessibilityHint(Text("Double-tap to edit", bundle: .module))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { beginEditing(at: index) }
        .accessibilityAction(named: Text("Remove", bundle: .module)) { remove(at: index) }
    }

    private var editingChip: some View {
        TextField(String(localized: "Tag", bundle: .module), text: $editingText)
            .amgiFont(.caption)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .focused($focus, equals: .chip)
            .onSubmit { focus = .input }
            .fixedSize()
            .frame(minWidth: 64, alignment: .leading)
            .padding(.horizontal, AmgiSpacing.sm)
            .padding(.vertical, AmgiSpacing.xxs)
            .overlay(Capsule().strokeBorder(palette.accent))
    }

    // MARK: - Suggestions

    @ViewBuilder
    private var suggestionRow: some View {
        let matches = NoteTagList.suggestions(
            for: input, from: suggestionsModel.allTags, excluding: list
        )
        if !matches.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AmgiSpacing.xs) {
                    ForEach(matches, id: \.self) { tag in
                        Button {
                            input = ""
                            add(tag)
                            focus = .input
                        } label: {
                            Label(tag, systemImage: "plus")
                                .amgiFont(.caption)
                                .lineLimit(1)
                                .foregroundStyle(palette.accent)
                                .padding(.horizontal, AmgiSpacing.sm)
                                .padding(.vertical, AmgiSpacing.xxs)
                                .overlay(Capsule().strokeBorder(palette.border))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .accessibilityLabel(Text("Suggested tags", bundle: .module))
        }
    }

    // MARK: - Editing

    private func syncFromBinding(_ value: String) {
        list = NoteTagList.split(value)
        input = ""
        editingIndex = nil
        lastWritten = value
    }

    /// Writes the chips plus whatever is still in the field back to the
    /// binding, so an unsubmitted tag is saved too.
    private func write() {
        let value = NoteTagList.join(list + NoteTagList.split(input))
        lastWritten = value
        if value != tags { tags = value }
    }

    private func add(_ text: String) {
        let (newList, duplicate) = NoteTagList.adding(text, to: list)
        list = newList
        if let duplicate { flash(duplicate) }
        write()
    }

    private func commitInput(keepingTail: Bool) {
        var pieces = NoteTagList.split(input)
        let tail = keepingTail ? pieces.popLast() ?? "" : ""
        input = tail
        add(NoteTagList.join(pieces))
    }

    private func remove(at index: Int) {
        if editingIndex != nil { editingIndex = nil }
        list = NoteTagList.removing(at: index, from: list)
        write()
    }

    private func beginEditing(at index: Int) {
        if let current = editingIndex {
            // Committing can remove or split the chip being edited, which
            // shifts the ones after it; only follow through when the tapped
            // chip sits before it and so kept its index.
            commitEdit()
            guard index < current else { focus = .input; return }
        }
        guard list.indices.contains(index) else { return }
        editingText = list[index]
        editingIndex = index
        focus = .chip
    }

    private func commitEdit() {
        guard let index = editingIndex else { return }
        editingIndex = nil
        list = NoteTagList.replacing(at: index, with: editingText, in: list)
        write()
    }

    private func flash(_ index: Int) {
        withAnimation(AmgiMotion.quick) { highlighted = index }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(AmgiMotion.quick) {
                if highlighted == index { highlighted = nil }
            }
        }
    }
}

#if DEBUG
#Preview {
    @Previewable @State var tags = "vocab korean 语言::日语::N5"
    Form {
        Section("Tags") {
            TagEditorField(tags: $tags)
        }
        Section {
            Text(tags)
        }
    }
}
#endif
