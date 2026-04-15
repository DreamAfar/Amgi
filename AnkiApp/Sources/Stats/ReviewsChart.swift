import SwiftUI
import Charts
import AnkiProto

struct ReviewsChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .month
    @State private var showTime = false

    private struct ReviewEntry: Identifiable {
        let id = UUID()
        let bucket: Int   // representative day offset (negative)
        let typeIndex: Int
        let type: String
        let value: Int    // count or time (seconds)
        let color: Color
    }

    private struct CumulativePoint: Identifiable {
        let id: Int
        let bucket: Int
        let cumulative: Int
    }

    private static let typeInfo: [(String, Color)] = [
        (L("stats_review_learn"),    .blue),
        (L("stats_review_relearn"),  .orange),
        (L("stats_card_young"),      .green),
        (L("stats_card_mature"),     .purple),
        (L("stats_review_filtered"), .gray),
    ]

    private static let valueKeys: [KeyPath<Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews, UInt32>] = [
        \.learn, \.relearn, \.young, \.mature, \.filtered,
    ]

    /// Number of days per bar bucket — capped at ~70 bars (mirrors desiredBars = min(70, abs(xMin)))
    private var bucketSize: Int {
        let days = period.days
        return max(1, days / 70)
    }

    private var entries: [ReviewEntry] {
        let maxDay = period.days
        let bkt = bucketSize
        let sourceMap = showTime ? reviews.time : reviews.count
        var bucketTotals: [Int: [Int: Int]] = [:]
        for (dayOffset, rev) in sourceMap {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) <= maxDay else { continue }
            let bucket = bkt == 1 ? day : -((-day) / bkt * bkt)
            for (idx, kp) in Self.valueKeys.enumerated() {
                let value = Int(rev[keyPath: kp])
                if value > 0 {
                    bucketTotals[bucket, default: [:]][idx, default: 0] += value
                }
            }
        }
        var result: [ReviewEntry] = []
        for (bucket, typeCounts) in bucketTotals {
            for (idx, value) in typeCounts {
                let (name, color) = Self.typeInfo[idx]
                result.append(ReviewEntry(bucket: bucket, typeIndex: idx, type: name, value: value, color: color))
            }
        }
        return result.sorted { ($0.bucket, $0.typeIndex) < ($1.bucket, $1.typeIndex) }
    }

    private var cumulativePoints: [CumulativePoint] {
        // Sum all types per bucket, then accumulate
        var bucketSum: [Int: Int] = [:]
        for e in entries { bucketSum[e.bucket, default: 0] += e.value }
        let sorted = bucketSum.sorted { $0.key < $1.key }
        var cum = 0
        return sorted.enumerated().map { _, kv in
            cum += kv.value
            return CumulativePoint(id: kv.key, bucket: kv.key, cumulative: cum)
        }
    }

    private var totalValue: Int { entries.reduce(0) { $0 + $1.value } }
    private var uniqueStudyDays: Int { Set(entries.map(\.bucket)).count }

    private var avgAllDays: Double {
        let span = max(period.days, 1)
        return Double(totalValue) / Double(span)
    }

    private var avgStudyDays: Double {
        guard uniqueStudyDays > 0 else { return 0 }
        return Double(totalValue) / Double(uniqueStudyDays)
    }

    private var barWidth: MarkDimension {
        let numBars = period.days / max(bucketSize, 1)
        if numBars <= 30 { return .automatic }
        return .fixed(max(2, min(8, 300.0 / Double(numBars))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("stats_reviews_title")).font(.headline)
                Spacer()
                Toggle(L("stats_reviews_show_time"), isOn: $showTime)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .controlSize(.mini)
            }

            // Period radios — 「全时」仅在全局=全部时显示
            Picker("", selection: $period) {
                Text(L("stats_period_month")).tag(StatsPeriod.month)
                Text(L("stats_period_3months")).tag(StatsPeriod.threeMonths)
                Text(L("stats_period_year")).tag(StatsPeriod.year)
                if revlogRange == .all {
                    Text(L("stats_period_all")).tag(StatsPeriod.all)
                }
            }
            .pickerStyle(.segmented)
            .font(.caption2)
            .onChange(of: revlogRange) {
                if revlogRange == .year && period == .all { period = .year }
            }

            if entries.isEmpty {
                Text(L("stats_reviews_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(entries) { entry in
                        BarMark(
                            x: .value("Day", entry.bucket),
                            y: .value("Value", entry.value),
                            width: barWidth
                        )
                        .foregroundStyle(by: .value("Type", entry.type))
                        .stacked(using: .standard)
                    }
                    ForEach(cumulativePoints) { pt in
                        LineMark(
                            x: .value("Day", pt.bucket),
                            y: .value(L("stats_reviews_cumulative"), pt.cumulative),
                            series: .value("Series", "cumulative")
                        )
                        .foregroundStyle(.secondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                        .accessibilityHidden(true)
                    }
                }
                .chartForegroundStyleScale([
                    L("stats_review_learn"):    Color.blue,
                    L("stats_review_relearn"):  Color.orange,
                    L("stats_card_young"):      Color.green,
                    L("stats_card_mature"):     Color.purple,
                    L("stats_review_filtered"): Color.gray,
                ])
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
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

            // Footer stats
            HStack(spacing: 0) {
                footerItem(L("stats_study_days"), value: "\(uniqueStudyDays)")
                footerItem(L("stats_total"), value: totalValue > 3600 ? formatTime(totalValue) : "\(totalValue)")
                footerItem(L("stats_avg_day_all"), value: showTime ? formatTime(Int(avgAllDays)) : String(format: "%.1f", avgAllDays))
                footerItem(L("stats_avg_day_studied"), value: showTime ? formatTime(Int(avgStudyDays)) : String(format: "%.1f", avgStudyDays))
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

    private func formatTime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return String(format: "%.1fh", Double(seconds) / 3600)
    }
}
