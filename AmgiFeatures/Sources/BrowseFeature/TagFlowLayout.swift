//
//  TagFlowLayout.swift
//  BrowseFeature
//

import SwiftUI

/// Lays subviews out left to right and wraps to a new row when the next
/// one doesn't fit, centring each row's items vertically. A subview marked
/// with `fillsTagRow(minWidth:)` (the tag editor's text field) takes the
/// rest of its row, or starts a new row when less than `minWidth` is left.
/// Items wider than the row are proposed the row width so they truncate.
struct TagFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
            }
            y += row.height + spacing
        }
    }

    private struct Item {
        var index: Int
        var x: CGFloat
        var size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width proposed: CGFloat?, subviews: Subviews) -> [Row] {
        let maxWidth = proposed ?? .infinity
        var rows: [Row] = [Row()]
        var x: CGFloat = 0

        func newRow() {
            rows.append(Row())
            x = 0
        }

        for index in subviews.indices {
            let subview = subviews[index]
            let size: CGSize
            if let minWidth = subview[FillsTagRowKey.self] {
                if x > 0, maxWidth - x < minWidth { newRow() }
                let available = maxWidth.isFinite ? maxWidth - x : minWidth
                size = subview.sizeThatFits(ProposedViewSize(width: available, height: nil))
            } else {
                let ideal = subview.sizeThatFits(ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil))
                if x > 0, x + ideal.width > maxWidth { newRow() }
                size = ideal
            }
            rows[rows.count - 1].items.append(Item(index: index, x: x, size: size))
            rows[rows.count - 1].width = x + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            x += size.width + spacing
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

private struct FillsTagRowKey: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

extension View {
    /// In a `TagFlowLayout`, take the rest of the row, wrapping first when
    /// less than `minWidth` is left.
    func fillsTagRow(minWidth: CGFloat) -> some View {
        layoutValue(key: FillsTagRowKey.self, value: minWidth)
    }
}
