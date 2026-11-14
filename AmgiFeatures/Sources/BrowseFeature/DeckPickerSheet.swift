//
//  DeckPickerSheet.swift
//  BrowseFeature
//

import AnkiKit
import SwiftUI
import Theme

/// Browse › Change Deck: pick the deck the selected notes' cards move to.
/// Filtered decks are left out, as in Anki — cards can't be moved into one.
struct DeckPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    let title: String
    let decks: [DeckInfo]
    let onPick: (DeckInfo) -> Void

    @State private var query = ""

    private var visibleDecks: [DeckInfo] {
        let normal = decks.filter { !$0.isFiltered }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return normal }
        return normal.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List(visibleDecks, id: \.id) { deck in
                Button {
                    onPick(deck)
                    dismiss()
                } label: {
                    row(deck)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if visibleDecks.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
            }
        }
    }

    /// Subdecks are indented under their parent and show only their own
    /// name, unless a search is running, when the full path tells them apart.
    private func row(_ deck: DeckInfo) -> some View {
        let parts = deck.name.components(separatedBy: "::")
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(spacing: AmgiSpacing.sm) {
            Image(systemName: "rectangle.stack")
                .foregroundStyle(palette.textSecondary)
            Text(searching ? deck.name : (parts.last ?? deck.name))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.leading, searching ? 0 : CGFloat(parts.count - 1) * AmgiSpacing.lg)
        .contentShape(Rectangle())
    }
}
