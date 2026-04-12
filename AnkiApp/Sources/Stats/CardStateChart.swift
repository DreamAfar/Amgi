import SwiftUI
import Charts
import AnkiKit

struct CardStateChart: View {
    let breakdown: CardStateBreakdown

    private var chartData: [(String, Int, Color)] {
        [
            (L("stats_card_new"), breakdown.newCount, Color.blue),
            (L("stats_card_learn"), breakdown.learningCount, Color.orange),
            (L("stats_card_review"), breakdown.reviewCount, Color.green),
            (L("stats_card_suspended"), breakdown.suspendedCount, Color.gray),
        ].filter { $0.1 > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("stats_card_states_title")).font(.headline)

            if chartData.isEmpty {
                Text(L("stats_card_states_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(chartData, id: \.0) { item in
                    SectorMark(angle: .value("Count", item.1), innerRadius: .ratio(0.5))
                        .foregroundStyle(item.2)
                }
                .frame(height: 180)

                HStack(spacing: 16) {
                    ForEach(chartData, id: \.0) { item in
                        HStack(spacing: 4) {
                            Circle().fill(item.2).frame(width: 8, height: 8)
                            Text("\(item.0): \(item.1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
