import SwiftUI

struct StatsChartTooltip: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
            Text(title)
                .amgiFont(.captionBold)
                .foregroundStyle(Color.amgiTextPrimary)

            ForEach(lines, id: \.self) { line in
                Text(line)
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }
        }
        .padding(.horizontal, AmgiSpacing.sm)
        .padding(.vertical, AmgiSpacing.xs)
        .background(Color.amgiSurfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.amgiBorder.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}

func statsBarRangeLabel(start: Int, bucketSize: Int) -> String {
    if bucketSize <= 1 {
        return "\(start)"
    }

    let end = start + bucketSize - 1
    return "\(start) to \(end)"
}