import SwiftUI
import Charts
import AnkiProto

struct ReviewsChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .month
    @State private var showTime = false
    @State private var selectedBucket: Int?

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
                let rawValue = Int(rev[keyPath: kp])
                let value: Int
                if showTime {
                    // Backend review time is in milliseconds; normalize to seconds for charting.
                    value = Int((Double(rawValue) / 1000.0).rounded())
                } else {
                    value = rawValue
                }
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
            formatter: { value in
                if showTime {
                    return formatTime(Int(value.rounded()))
                } else {
                    return StatsDualAxisSupport.formatCount(value)
                }
            }
        )
    }
    private var leftAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: leftAxisMax,
            plottedMax: leftAxisMax,
            formatter: { value in
                if showTime {
                    return formatTime(Int(value.rounded()))
                } else {
                    return StatsDualAxisSupport.formatCount(value)
                }
            }
        )
    }
    private var leftAxisValues: [Double] {
        leftAxisTicks.map(\.plottedValue)
    }
    private var rightAxisValues: [Double] {
        rightAxisTicks.map(\.plottedValue)
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

    private var selectedBucketEntries: [ReviewEntry] {
        guard let selectedBucket else { return [] }
        return entries
            .filter { $0.bucket == selectedBucket }
            .sorted { $0.typeIndex < $1.typeIndex }
    }

    private var selectedCumulativePoint: CumulativePoint? {
        guard let selectedBucket else { return nil }
        return cumulativePoints.first(where: { $0.bucket == selectedBucket })
    }

    private var reviewColorScale: KeyValuePairs<String, Color> {
        [
            L("stats_review_learn"): .blue,
            L("stats_review_relearn"): .orange,
            L("stats_card_young"): .green,
            L("stats_card_mature"): .purple,
            L("stats_review_filtered"): .gray,
        ]
    }

    private var xAxisMin: Int {
        let periodMin: Int
        switch period {
        case .day:
            periodMin = -1
        case .week:
            periodMin = -6
        case .month:
            periodMin = -30
        case .threeMonths:
            periodMin = -89
        case .year:
            periodMin = -364
        case .all:
            return min(entries.map(\ .bucket).min() ?? -30, -1)
        }

        let dataMin = entries.map(\.bucket).min() ?? periodMin
        return max(periodMin, dataMin)
    }

    private var xAxisDesiredTickCount: Int {
        switch period {
        case .day: return 3
        case .week: return 5
        case .month: return 6
        case .threeMonths: return 7
        case .year: return 8
        case .all: return 10
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                    Text(L("stats_reviews_title"))
                        .amgiFont(.sectionHeading)
                        .foregroundStyle(Color.amgiTextPrimary)

                    Text(showTime ? L("stats_reviews_time_subtitle") : L("stats_reviews_count_subtitle"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
                Spacer()
                Toggle(L("stats_reviews_show_time"), isOn: $showTime)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .amgiFont(.micro)
                    .controlSize(.mini)
                    .onChange(of: showTime) { selectedBucket = nil }
            }

            // Period radios — 「全时」仅在全局=全部时显示
            Picker("", selection: $period) {
                ForEach(revlogRange.allowedStatsPeriods, id: \.self) { allowedPeriod in
                    Text(allowedPeriod.localizedLabel).tag(allowedPeriod)
                }
            }
            .amgiSegmentedPicker()
            .amgiFont(.micro)
            .onChange(of: revlogRange) {
                if !revlogRange.allowedStatsPeriods.contains(period) {
                    period = revlogRange.defaultStatsPeriod
                }
                selectedBucket = nil
            }
            .onChange(of: period) { selectedBucket = nil }

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
                footerItem(L("stats_total"), value: showTime ? formatTime(totalValue) : "\(totalValue)")
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
        baseReviewChart
            .chartForegroundStyleScale(reviewColorScale)
            .chartOverlay { proxy in
                reviewChartOverlay(proxy: proxy)
            }
            .chartXScale(domain: xAxisMin...0)
            .chartYScale(domain: 0...leftAxisMax)
            .chartXAxis {
                reviewChartXAxis()
            }
            .chartYAxis {
                reviewChartYAxis()
            }
            .frame(height: 200)
    }

    private var baseReviewChart: some View {
        Chart {
            reviewBarMarks()
            reviewCumulativeMarks()
            selectedReviewRuleMark()
        }
    }

    private func plottedCumulative(_ value: Int) -> Double {
        StatsDualAxisSupport.plottedValue(
            Double(value),
            domainMax: rightAxisMax,
            plottedMax: leftAxisMax
        )
    }

    @ChartContentBuilder
    private func reviewBarMarks() -> some ChartContent {
        ForEach(entries) { entry in
            BarMark(
                x: .value("Day", entry.bucket),
                y: .value("Value", entry.value),
                width: barWidth
            )
            .foregroundStyle(by: .value("Type", entry.type))
        }
    }

    @ChartContentBuilder
    private func reviewCumulativeMarks() -> some ChartContent {
        ForEach(cumulativePoints) { point in
            AreaMark(
                x: .value("Day", point.bucket),
                y: .value(L("stats_reviews_cumulative"), plottedCumulative(point.cumulative))
            )
            .foregroundStyle(Color.amgiTextSecondary.opacity(0.08))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Day", point.bucket),
                y: .value(L("stats_reviews_cumulative"), plottedCumulative(point.cumulative)),
                series: .value("Series", "cumulative")
            )
            .foregroundStyle(.secondary.opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
            .accessibilityHidden(true)
        }
    }

    @ChartContentBuilder
    private func selectedReviewRuleMark() -> some ChartContent {
        if let selectedBucket,
           let selectedCumulativePoint,
           !selectedBucketEntries.isEmpty {
            RuleMark(x: .value("Selected Day", selectedBucket))
                .foregroundStyle(Color.amgiAccent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                    StatsChartTooltip(
                        title: statsBarRangeLabel(start: selectedBucket, bucketSize: bucketSize),
                        lines: reviewTooltipLines(selectedCumulativePoint: selectedCumulativePoint)
                    )
                }
        }
    }

    private func reviewTooltipLines(selectedCumulativePoint: CumulativePoint) -> [String] {
        let cumulativeLabel = L("stats_reviews_cumulative")
        let reviewLines = selectedBucketEntries.map { entry in
            if showTime {
                return "\(entry.type): \(formatTime(entry.value))"
            }
            return "\(entry.type): \(entry.value)"
        }
        let cumulativeLine = showTime
            ? "\(cumulativeLabel): \(formatTime(selectedCumulativePoint.cumulative))"
            : "\(cumulativeLabel): \(selectedCumulativePoint.cumulative)"
        return reviewLines + [cumulativeLine]
    }

    @ViewBuilder
    private func reviewChartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedBucket(for: value, proxy: proxy, geometry: geometry)
                        }
                )
        }
    }

    private func updateSelectedBucket(
        for value: SpatialTapGesture.Value,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        let plotX = value.location.x - plotFrame.origin.x
        guard plotX >= 0,
              plotX <= proxy.plotSize.width,
              let bucket: Int = proxy.value(atX: plotX)
        else {
            selectedBucket = nil
            return
        }

        let nearestBucket = Set(entries.map(\.bucket)).min(by: { lhs, rhs in
            abs(lhs - bucket) < abs(rhs - bucket)
        })
        selectedBucket = selectedBucket == nearestBucket ? nil : nearestBucket
    }

    @AxisContentBuilder
    private func reviewChartXAxis() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: xAxisDesiredTickCount)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
            AxisValueLabel()
                .font(AmgiFont.micro.font)
                .foregroundStyle(Color.amgiTextSecondary)
        }
    }

    @AxisContentBuilder
    private func reviewChartYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: leftAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: leftAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }

        AxisMarks(position: .trailing, values: rightAxisValues) { value in
            AxisTick()
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.35))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: rightAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
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
