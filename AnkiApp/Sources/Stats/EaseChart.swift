import SwiftUI
import Charts
import AnkiProto

struct EaseChart: View {
    let eases: Anki_Stats_GraphsResponse.Eases
    let difficulty: Anki_Stats_GraphsResponse.Eases
    let isFSRS: Bool

    /// Active dataset: difficulty for FSRS decks, eases for SM-2
    private var activeData: Anki_Stats_GraphsResponse.Eases {
        isFSRS ? difficulty : eases
    }

    private var chartData: [(ease: Int, count: Int)] {
        activeData.eases
            .map { (ease: Int($0.key), count: Int($0.value)) }
            .sorted(by: { $0.ease < $1.ease })
    }

    private var averageEase: String {
        guard activeData.average > 0 else { return "---" }
        if isFSRS {
            return String(format: "%.0f%%", activeData.average / 10)
        } else {
            return String(format: "%.0f%%", activeData.average / 10)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(isFSRS ? L("stats_difficulty_title") : L("stats_ease_title")).font(.headline)
                Spacer()
                Text(L("stats_ease_avg_fmt", averageEase))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if chartData.isEmpty {
                Text(L("stats_ease_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(chartData, id: \.ease) { item in
                    BarMark(
                        x: .value("Ease", item.ease),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle((isFSRS ? Color.red : Color.indigo).gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine()
                        if let v = value.as(Int.self) {
                            AxisValueLabel("\(v / 10)%")
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
