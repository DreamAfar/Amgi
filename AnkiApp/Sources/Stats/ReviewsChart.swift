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
    private var maxBucketValue: Int {
        var bucketSum: [Int: Int] = [:]
        for entry in entries {
            bucketSum[entry.bucket, default: 0] += entry.value
        }
        return bucketSum.values.max() ?? 0
    }
    private var leftAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(maxBucketValue))
    }
    private var rightAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(totalValue))
    }
    private var rightAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: Double(totalValue),
            plottedMax: leftAxisMax,
            formatter: { value in String(Int(value.rounded())) }
        )
    }
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
        let width: Double = max(2.0, min(8.0, 300.0 / Double(numBars)))
        return .fixed(width)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                Text(L("stats_reviews_title"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(Color.amgiTextPrimary)
                Spacer()
                Toggle(L("stats_reviews_show_time"), isOn: $showTime)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .amgiFont(.micro)
                    .controlSize(.mini)
            }

            // Period radios — 「全时」仅在全局=全部时显示
            Picker("", selection: $period) {
                ForEach(revlogRange.allowedStatsPeriods, id: \.self) { allowedPeriod in
                    Text(allowedPeriod.localizedLabel).tag(allowedPeriod)
                }
            }
            .pickerStyle(.segmented)
            .amgiFont(.micro)
            .onChange(of: revlogRange) {
                if !revlogRange.allowedStatsPeriods.contains(period) {
                    period = revlogRange.defaultStatsPeriod
                }
            }

            if entries.isEmpty {
                Text(L("stats_reviews_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                reviewChart
            }

            // Footer stats
            HStack(spacing: 0) {
                footerItem(L("stats_study_days"), value: "\(uniqueStudyDays)")
                footerItem(L("stats_total"), value: totalValue > 3600 ? formatTime(totalValue) : "\(totalValue)")
                let avgAllStr = showTime ? formatTime(Int(avgAllDays)) : String(format: "%.1f", avgAllDays)
                let avgStudyStr = showTime ? formatTime(Int(avgStudyDays)) : String(format: "%.1f", avgStudyDays)
                footerItem(L("stats_avg_day_all"), value: avgAllStr)
                footerItem(L("stats_avg_day_studied"), value: avgStudyStr)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard(elevated: true)
    }

    @ViewBuilder
    private var reviewChart: some View {
        let colorScale: KeyValuePairs<String, Color> = [
            L("stats_review_learn"):    .blue,
            L("stats_review_relearn"):  .orange,
            L("stats_card_young"):      .green,
            L("stats_card_mature"):     .purple,
            L("stats_review_filtered"): .gray,
        ]
        Chart {
            ForEach(entries) { entry in
                BarMark(
                    x: .value("Day", entry.bucket),
                    y: .value("Value", entry.value),
                    width: barWidth
                )
                .foregroundStyle(by: .value("Type", entry.type))
            }
            ForEach(cumulativePoints) { pt in
                AreaMark(
                    x: .value("Day", pt.bucket),
                    y: .value(
                        L("stats_reviews_cumulative"),
                        StatsDualAxisSupport.plottedValue(
                            Double(pt.cumulative),
                            domainMax: rightAxisMax,
                            plottedMax: leftAxisMax
                        )
                    )
                )
                .foregroundStyle(Color.amgiTextSecondary.opacity(0.08))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Day", pt.bucket),
                    y: .value(
                        L("stats_reviews_cumulative"),
                        StatsDualAxisSupport.plottedValue(
                            Double(pt.cumulative),
                            domainMax: rightAxisMax,
                            plottedMax: leftAxisMax
                        )
                    ),
                    series: .value("Series", "cumulative")
                )
                .foregroundStyle(.secondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
                .accessibilityHidden(true)
            }
        }
        .chartForegroundStyleScale(colorScale)
        .chartYScale(domain: 0...leftAxisMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                AxisValueLabel()
                    .font(AmgiFont.micro.font)
                    .foregroundStyle(Color.amgiTextSecondary)
            }
        }
        .chartYAxis {
            AxisMarks(
                preset: .aligned,
                position: .leading,
                values: .automatic(desiredCount: 4)
            ) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                AxisValueLabel()
                    .font(AmgiFont.micro.font)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            AxisMarks(position: .trailing, values: rightAxisTicks.map(\.plottedValue)) { value in
                if let raw = value.as(Double.self),
                   let tick = rightAxisTicks.first(where: { abs($0.plottedValue - raw) < 0.0001 }) {
                    AxisTick()
                        .foregroundStyle(Color.amgiTextTertiary.opacity(0.35))
                    AxisValueLabel {
                        Text(tick.label)
                            .amgiFont(.micro)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
            }
        }
        .frame(height: 200)
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: AmgiSpacing.xxs) {
            Text(value)
                .amgiFont(.captionBold)
                .monospacedDigit()
                .foregroundStyle(Color.amgiTextPrimary)
            Text(label)
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return String(format: "%.1fh", Double(seconds) / 3600)
    }
}
