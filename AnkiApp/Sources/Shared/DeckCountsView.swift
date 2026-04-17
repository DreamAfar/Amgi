import SwiftUI
import AnkiKit

struct DeckCountsView: View {
    let counts: DeckCounts

    var body: some View {
        HStack(spacing: 8) {
            if counts.newCount > 0 {
                countBadge(counts.newCount, color: .amgiAccent)
            }
            if counts.learnCount > 0 {
                countBadge(counts.learnCount, color: .amgiWarning)
            }
            if counts.reviewCount > 0 {
                countBadge(counts.reviewCount, color: .amgiPositive)
            }
            if counts.total == 0 {
                Text("\u{2713}")
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
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
