import SwiftUI
import AnkiKit
import AmgiTheme

struct DeckCountsView: View {
    let counts: DeckCounts
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            if counts.newCount > 0 {
                countBadge(counts.newCount, color: palette.accent)
            }
            if counts.learnCount > 0 {
                countBadge(counts.learnCount, color: palette.warning)
            }
            if counts.reviewCount > 0 {
                countBadge(counts.reviewCount, color: palette.positive)
            }
            if counts.total == 0 {
                Text("\u{2713}")
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func countBadge(_ count: Int, color: Color) -> some View {
        Text("\(count)")
            .amgiFont(.captionBold)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}
