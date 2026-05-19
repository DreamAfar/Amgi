import SwiftUI
import Charts
import AnkiProto
private enum CardCountsPreferences {
    static let separateInactiveKey = "stats_card_counts_separate_inactive"
}

struct CardCountsChart: View {
    let cardCounts: Anki_Stats_GraphsResponse.CardCounts
    let prefersWideSingleColumnLayout: Bool
    @AppStorage(CardCountsPreferences.separateInactiveKey) private var separateInactive = true
    @State private var containerWidth: CGFloat = 390

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

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                Text(L("stats_card_counts_title"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(Color.amgiTextPrimary)
                Spacer()
                Text(L("stats_total_count", total))
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if chartData.isEmpty {
                Text(L("stats_card_counts_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
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
        .amgiCard(elevated: true)
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
            HStack(spacing: 8) {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text(item.name)
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(item.count)")
                    .amgiFont(.captionBold)
                    .monospacedDigit()
                    .foregroundStyle(Color.amgiTextPrimary)
                Text(formattedPercentage)
                    .amgiFont(.captionBold)
                    .monospacedDigit()
                    .foregroundStyle(Color.amgiTextSecondary)
            }
        }
    }

    private var separateInactiveToggle: some View {
        Toggle(L("stats_card_counts_separate_inactive"), isOn: $separateInactive)
            .amgiFont(.caption)
            .foregroundStyle(Color.amgiTextSecondary)
    }

    private var defaultLayout: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            donutChart
                .frame(height: 200)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 4) {
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
