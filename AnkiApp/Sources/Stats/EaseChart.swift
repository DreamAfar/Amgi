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
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                Text(isFSRS ? L("stats_difficulty_title") : L("stats_ease_title"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(Color.amgiTextPrimary)
                Spacer()
                Text(L("stats_ease_avg_fmt", averageEase))
                    .amgiFont(.captionBold)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if chartData.isEmpty {
                Text(L("stats_ease_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
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
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let v = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(v / 10)%")
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard(elevated: true)
    }
}
