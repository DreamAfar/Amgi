import SwiftUI

struct StatsChartTooltip: View {
    @Environment(\.palette) private var palette

    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
            Text(title)
                .amgiFont(.captionBold)
                .foregroundStyle(palette.textPrimary)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, AmgiSpacing.sm)
        .padding(.vertical, AmgiSpacing.xs)
        .background(palette.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.border.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

func statsBarRangeLabel(start: Int, bucketSize: Int) -> String {
    let endExclusive = start + max(bucketSize, 1)
    let larger = max(Swift.abs(start), Swift.abs(endExclusive))
    let smaller = min(Swift.abs(start), Swift.abs(endExclusive))

    if larger - smaller <= 1 {
        if start >= 0 {
            if start == 0 {
                return L("common_today")
            }
            return L("stats_in_days_single_fmt", start)
        } else {
            let days = -start
            if days == 1 {
                return L("common_yesterday")
            }
            return L("stats_days_ago_single_fmt", days)
        }
    }

    if start >= 0 {
        return L("stats_in_days_range_fmt", start, endExclusive - 1)
    } else {
        return L("stats_days_ago_range_fmt", Swift.abs(endExclusive - 1), -start)
    }
}
