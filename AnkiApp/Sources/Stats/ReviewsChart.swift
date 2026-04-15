import SwiftUI
import Charts
import AnkiProto

struct ReviewsChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let period: StatsPeriod

    private struct ReviewEntry: Identifiable {
        let id = UUID()
        let day: Int
        let type: String
        let count: Int
        let color: Color
    }

    private var entries: [ReviewEntry] {
        let maxDay = period.days
        let types: [(String, KeyPath<Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews, UInt32>, Color)] = [
            (L("stats_review_learn"), \.learn, .blue),
            (L("stats_review_relearn"), \.relearn, .orange),
            (L("stats_card_young"), \.young, .green),
            (L("stats_card_mature"), \.mature, .purple),
            (L("stats_review_filtered"), \.filtered, .gray),
        ]
        var result: [ReviewEntry] = []
        for (dayOffset, rev) in reviews.count {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) <= maxDay else { continue }
            for (name, kp, color) in types {
                let value = Int(rev[keyPath: kp])
                if value > 0 {
                    result.append(ReviewEntry(day: day, type: name, count: value, color: color))
                }
            }
        }
        return result.sorted(by: { $0.day < $1.day })
    }

    private var totalReviews: Int {
        entries.reduce(0) { $0 + $1.count }
    }

    private var avgPerDay: Double {
        guard !entries.isEmpty else { return 0 }
        let uniqueDays = Set(entries.map(\.day)).count
        return Double(totalReviews) / Double(max(uniqueDays, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("stats_reviews_title")).font(.headline)

            if entries.isEmpty {
                Text(L("stats_reviews_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Day", entry.day),
                        y: .value("Count", entry.count)
                    )
                    .foregroundStyle(by: .value("Type", entry.type))
                    .position(by: .value("Type", entry.type))
                }
                .chartForegroundStyleScale([
                    L("stats_review_learn"): Color.blue,
                    L("stats_review_relearn"): Color.orange,
                    L("stats_card_young"): Color.green,
                    L("stats_card_mature"): Color.purple,
                    L("stats_review_filtered"): Color.gray,
                ])
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 10)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        if let day = value.as(Int.self), day % 3 == 0 {
                            AxisValueLabel(anchor: .top) {
                                Text("\(day)")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(
                        preset: .aligned,
                        position: .leading,
                        values: .automatic(desiredCount: 4)
                    ) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
                .chartPlotStyle { plotArea in
                    plotArea
                        .padding(.top, 40)
                        .padding(.leading, 60)
                }
            }

            HStack(spacing: 16) {
                footerItem(L("stats_total"), value: "\(totalReviews)")
                footerItem(L("stats_avg_day"), value: String(format: "%.1f", avgPerDay))
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
