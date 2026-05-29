import SwiftUI
import Charts
import AnkiProto
private enum CardCountsPreferences {
    static let separateInactiveKey = "stats_card_counts_separate_inactive"
}

struct CardCountsChart: View {
    let cardCounts: Anki_Stats_GraphsResponse.CardCounts
    let prefersWideSingleColumnLayout: Bool
    @Environment(\.palette) private var palette
    @AppStorage(CardCountsPreferences.separateInactiveKey) private var separateInactive = true
    @State private var containerWidth: CGFloat = 390
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(
        cardCounts: Anki_Stats_GraphsResponse.CardCounts,
        prefersWideSingleColumnLayout: Bool = false
    ) {
        self.cardCounts = cardCounts
        self.prefersWideSingleColumnLayout = prefersWideSingleColumnLayout
    }

    private var chartData: [(name: String, count: Int, color: Color)] {
        let c = separateInactive ? cardCounts.excludingInactive : cardCounts.includingInactive
        return [
            (L("stats_card_new"), Int(c.newCards), .cyan),
            (L("stats_card_learn"), Int(c.learn), .blue),
            (L("stats_card_relearning"), Int(c.relearn), .orange),
            (L("stats_card_young"), Int(c.young), .green),
            (L("stats_card_mature"), Int(c.mature), .purple),
            (L("stats_card_suspended"), Int(c.suspended), .gray),
            (L("stats_card_buried"), Int(c.buried), .brown),
        ].filter { $0.count > 0 }
    }

    private var total: Int { chartData.reduce(0) { $0 + $1.count } }

    private var prefersCompactLegendLayout: Bool {
        horizontalSizeClass == .compact || containerWidth < 300
    }

    private var legendColumns: [GridItem] {
        if prefersCompactLegendLayout {
            return [GridItem(.flexible(minimum: 0), spacing: 12)]
        }

        return [
            GridItem(.flexible(minimum: 0), spacing: 12),
            GridItem(.flexible(minimum: 0), spacing: 12),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                Text(L("stats_card_counts_title"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(L("stats_total_count", total))
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if chartData.isEmpty {
                Text(L("stats_card_counts_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                if prefersWideSingleColumnLayout {
                    wideSingleColumnLayout
                } else {
                    defaultLayout
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsTrackWidth($containerWidth)
        .statsCard(elevated: true)
    }

    private var donutChart: some View {
        Chart(chartData, id: \.name) { item in
            SectorMark(
                angle: .value("Count", item.count),
                innerRadius: .ratio(0.5),
                angularInset: 1
            )
            .foregroundStyle(item.color)
        }
    }

    private var legendItems: some View {
        ForEach(chartData, id: \.name) { item in
            let percentage = total > 0 ? (Double(item.count) / Double(total) * 100) : 0
            let formattedPercentage = String(format: "%.2f%%", percentage)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text(item.name)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(item.count)")
                        .amgiFont(.captionBold)
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(formattedPercentage)
                        .amgiFont(.captionBold)
                        .monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var separateInactiveToggle: some View {
        Toggle(L("stats_card_counts_separate_inactive"), isOn: $separateInactive)
            .amgiFont(.caption)
            .foregroundStyle(palette.textSecondary)
            .tint(palette.accent) // Apply accent color to toggle
    }

    private var defaultLayout: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            donutChart
                .frame(height: 180)

            LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 8) {
                legendItems
            }

            separateInactiveToggle
        }
    }

    private var wideSingleColumnLayout: some View {
        let chartWidth = min(max(containerWidth * 0.30, 220), 320)

        return HStack(alignment: .top, spacing: 28) {
            donutChart
                .aspectRatio(1, contentMode: .fit)
                .frame(width: chartWidth, height: chartWidth)
                .layoutPriority(1)

            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible(minimum: 220), spacing: 16)], spacing: 10) {
                    legendItems
                }

                Spacer(minLength: 0)

                separateInactiveToggle
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: max(chartWidth, 240), alignment: .top)
    }
}
