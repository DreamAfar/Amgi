import SwiftUI
import Charts
import AnkiProto

struct ReviewsChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let period: StatsPeriod

    private struct ReviewEntry: Identifiable {
        let id = UUID()
        let bucket: Int   // representative day offset (negative)
        let type: String
        let count: Int
        let color: Color
    }

    /// Number of days per bar bucket based on period
    private var bucketSize: Int {
        switch period {
        case .day, .week, .month: return 1
        case .threeMonths: return 7
        case .year, .all: return 30
        }
    }

    private var entries: [ReviewEntry] {
        let maxDay = period.days
        let bkt = bucketSize
        let types: [(String, KeyPath<Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews, UInt32>, Color)] = [
            (L("stats_review_learn"), \.learn, .blue),
            (L("stats_review_relearn"), \.relearn, .orange),
            (L("stats_card_young"), \.young, .green),
            (L("stats_card_mature"), \.mature, .purple),
            (L("stats_review_filtered"), \.filtered, .gray),
        ]
        // Accumulate by bucket
        var bucketTotals: [Int: [Int: Int]] = [:] // bucket -> typeIndex -> count
        for (dayOffset, rev) in reviews.count {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) <= maxDay else { continue }
            let bucket = bkt == 1 ? day : -((-day) / bkt * bkt)
            for (idx, (_, kp, _)) in types.enumerated() {
                let value = Int(rev[keyPath: kp])
                if value > 0 {
                    bucketTotals[bucket, default: [:]][idx, default: 0] += value
                }
            }
        }
        var result: [ReviewEntry] = []
        for (bucket, typeCounts) in bucketTotals {
            for (idx, count) in typeCounts {
                let (name, _, color) = types[idx]
                result.append(ReviewEntry(bucket: bucket, type: name, count: count, color: color))
            }
        }
        return result.sorted { $0.bucket < $1.bucket }
    }

    private var totalReviews: Int {
        entries.reduce(0) { $0 + $1.count }
    }

    private var avgPerDay: Double {
        guard !entries.isEmpty else { return 0 }
        let uniqueDays = Set(entries.map(\.bucket)).count
        let span = uniqueDays * bucketSize
        return Double(totalReviews) / Double(max(span, 1))
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
                        x: .value("Day", entry.bucket),
                        y: .value("Count", entry.count),
                        width: bucketSize == 1 ? .automatic : .fixed(max(4, 200.0 / Double(period.days / bucketSize)))
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
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
