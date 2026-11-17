//
//  DeckListRowView.swift
//  UI
//
//  Created by Vladimir Gusev on 14.05.2026.
//

public import SwiftUI
import Theme

public struct DeckListRowView: View {
    let data: DeckRowViewData
    let isSelected: Bool
    /// One line, without the deck tile or the due line.
    let isCompact: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onRename: () -> Void

    @State private var showDeleteAlert = false
    @Environment(\.palette) private var palette

    public init(
        data: DeckRowViewData,
        isSelected: Bool = false,
        isCompact: Bool = false,
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRename: @escaping () -> Void
    ) {
        self.data = data
        self.isSelected = isSelected
        self.isCompact = isCompact
        self.onTap = onTap
        self.onDelete = onDelete
        self.onRename = onRename
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if !isCompact {
                    DeckTile(name: data.name, isFiltered: data.isFiltered)
                }
                if isCompact {
                    // One line: the name, with the filtered-deck mark the
                    // tile carries in the full list. The counts on the right
                    // say what the due line would.
                    HStack(spacing: 6) {
                        if data.isFiltered {
                            Image(systemName: "bolt.fill")
                                .amgiFont(.micro)
                                .foregroundStyle(palette.customStudyBadge)
                                .accessibilityLabel(Text("Filtered deck", bundle: .module))
                        }
                        Text(data.name)
                            .amgiFont(.body)
                            .bold()
                            .foregroundStyle(palette.textPrimary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.name)
                            .amgiFont(.body)
                            .bold()
                            .foregroundStyle(palette.textPrimary)
                        Text(metaLine)
                            .amgiFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailingContent
                Image(systemName: "chevron.forward")
                    .amgiFont(.micro)
                    .foregroundStyle(palette.textTertiary)
                    .accessibilityHidden(true)
            }
            // 11 keeps a one-line row at the 44pt touch height.
            .padding(.vertical, isCompact ? 11 : 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The due line isn't drawn in the compact list; VoiceOver still reads it.
        .accessibilityValue(isCompact ? Text(metaLine) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // A destructive swipe removes the row before the user can confirm.
            Button { showDeleteAlert = true } label: {
                Label(String(localized: "Delete", bundle: .module), systemImage: "trash")
            }
            .tint(palette.danger)
            Button { onRename() } label: {
                Label(String(localized: "Rename", bundle: .module), systemImage: "pencil")
            }
            .tint(.orange)
        }
        .alert(String(localized: "Delete \"\(data.name)\"?", bundle: .module), isPresented: $showDeleteAlert) {
            Button(String(localized: "Delete", bundle: .module), role: .destructive, action: onDelete)
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: {
            Text("This will permanently delete the deck and all its cards.", bundle: .module)
        }
    }

    private var metaLine: String {
        switch (data.totalCount, data.subdeckCount) {
        case (0, _):           return String(localized: "Up to date", bundle: .module)
        case (let n, 0):       return String(localized: "\(n) due", bundle: .module)
        case (let n, let s):   return String(localized: "\(n) due · \(s) subdecks", bundle: .module)
        }
    }

    @ViewBuilder
    private var trailingContent: some View {
        if data.totalCount == 0 {
            Image(systemName: "checkmark")
                .foregroundStyle(palette.textTertiary)
        } else {
            DeckCountBadges(
                newCount: data.newCount,
                learnCount: data.learnCount,
                reviewCount: data.reviewCount
            )
        }
    }
}

// MARK: - DeckTile

struct DeckTile: View {
    let name: String
    let isFiltered: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let resolved = DeckTileGlyph.resolve(deckName: name, palette: palette)
        let fill: Color
        let glyphColor: Color
        switch resolved.mode {
        case .emoji:
            fill = palette.surfaceElevated
            glyphColor = palette.textPrimary
        case .letter(let tint):
            fill = tint
            glyphColor = .white
        case .monogram(let tint):
            fill = tint.opacity(0.11)
            glyphColor = tint
        }

        return ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: AmgiRadius.control, style: .continuous)
                .fill(fill)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(resolved.display)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(glyphColor)
                )
            if isFiltered {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.background)
                    .frame(width: 14, height: 14)
                    .background(palette.customStudyBadge, in: Circle())
                    .offset(x: 4, y: 4)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Due cards row") {
    DeckListRowView(
        data: DeckRowViewData(
            id: 1,
            name: "한국어",
            fullName: "한국어",
            newCount: 20,
            learnCount: 93,
            reviewCount: 74,
            isFiltered: false,
            subdeckCount: 4
        ),
        onTap: {}, onDelete: {}, onRename: {}
    )
    .padding()
    .environment(\.palette, .vividLight)
}

#Preview("Up to date row") {
    DeckListRowView(
        data: DeckRowViewData(
            id: 2,
            name: "Español",
            fullName: "Español",
            newCount: 0,
            learnCount: 0,
            reviewCount: 0,
            isFiltered: false,
            subdeckCount: 0
        ),
        onTap: {}, onDelete: {}, onRename: {}
    )
    .padding()
    .environment(\.palette, .vividLight)
}

#Preview("Compact rows") {
    VStack(spacing: 0) {
        DeckListRowView(
            data: DeckRowViewData(
                id: 1, name: "eggrolls-JLPT10k-v3.5", fullName: "eggrolls-JLPT10k-v3.5",
                newCount: 20, learnCount: 4, reviewCount: 710, isFiltered: false, subdeckCount: 5
            ),
            isCompact: true,
            onTap: {}, onDelete: {}, onRename: {}
        )
        Divider()
        DeckListRowView(
            data: DeckRowViewData(
                id: 2, name: "Hardest cards", fullName: "Hardest cards",
                newCount: 0, learnCount: 0, reviewCount: 24, isFiltered: true, subdeckCount: 0
            ),
            isCompact: true,
            onTap: {}, onDelete: {}, onRename: {}
        )
    }
    .padding()
    .environment(\.palette, .vividLight)
}

#Preview("Filtered deck row") {
    DeckListRowView(
        data: DeckRowViewData(
            id: 3,
            name: "Hardest cards",
            fullName: "Hardest cards",
            newCount: 0,
            learnCount: 0,
            reviewCount: 24,
            isFiltered: true,
            subdeckCount: 0
        ),
        onTap: {}, onDelete: {}, onRename: {}
    )
    .padding()
    .environment(\.palette, .vividLight)
}
#endif
