import SwiftUI
import Charts
import AnkiProto

struct CardCountsChart: View {
    let cardCounts: Anki_Stats_GraphsResponse.CardCounts

    private var chartData: [(name: String, count: Int, color: Color)] {
        let c = cardCounts.excludingInactive
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
                Chart(chartData, id: \.name) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 1
                    )
                    .foregroundStyle(item.color)
                }
                .frame(height: 200)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 4) {
                    ForEach(chartData, id: \.name) { item in
                        let percentage = total > 0 ? (Double(item.count) / Double(total) * 100) : 0
                        let formattedPercentage = String(format: "%.2f%%", percentage)
                        HStack(spacing: 4) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            Text(item.name)
                                .amgiFont(.caption)
                                .foregroundStyle(Color.amgiTextSecondary)
                            Spacer()
                            Text("\(item.count)  \(formattedPercentage)")
                                .amgiFont(.captionBold)
                                .monospacedDigit()
                                .foregroundStyle(Color.amgiTextPrimary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard(elevated: true)
    }
}
