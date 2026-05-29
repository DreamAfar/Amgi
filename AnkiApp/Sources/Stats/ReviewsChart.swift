import SwiftUI
import Charts
import AnkiProto
struct ReviewsChart: View {
    @Environment(\.palette) private var palette

    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .month
    @State private var showTime = false
    @State private var selectedBucket: Int?
    @State private var containerWidth: CGFloat = 390

    private typealias ReviewValue = Anki_Stats_GraphsResponse.ReviewCountsAndTimes.Reviews

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

    private struct FooterMetric: Identifiable {
        let id = UUID()
        let label: String
        let value: String
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

    private var filteredCountRows: [(Int, ReviewValue)] {
        filteredRows(from: reviews.count)
    }

    private var filteredTimeRows: [(Int, ReviewValue)] {
        filteredRows(from: reviews.time)
    }

    private var entries: [ReviewEntry] {
        let bkt = bucketSize
        let sourceRows = showTime ? filteredTimeRows : filteredCountRows
        var bucketTotals: [Int: [Int: Int]] = [:]
        for (day, rev) in sourceRows {
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
                    return formatTime(value)
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
                    return formatTime(value)
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
    private var uniqueStudyDays: Int { filteredCountRows.count }
    private var periodDayCount: Int { max(-xAxisMin + 1, 1) }
    private var studiedPercent: Double {
        guard periodDayCount > 0 else { return 0 }
        return Double(uniqueStudyDays) / Double(periodDayCount) * 100
    }
    private var totalReviewCount: Int {
        filteredCountRows.reduce(0) { partialResult, item in
            partialResult + reviewCountTotal(item.1)
        }
    }
    private var totalSeconds: Double {
        filteredTimeRows.reduce(0) { partialResult, item in
            partialResult + reviewTimeSeconds(item.1)
        }
    }
    private var averageAnswerSeconds: Double {
        guard totalReviewCount > 0 else { return 0 }
        return totalSeconds / Double(totalReviewCount)
    }

    private var barWidth: MarkDimension {
        StatsBarLayoutSupport.barWidth(
            slotCount: StatsBarLayoutSupport.displayedSlotCount(
                lowerBound: xAxisMin,
                upperBound: 0,
                bucketSize: bucketSize
            ),
            availableWidth: containerWidth
        )
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
            return min(entries.map(\.bucket).min() ?? -30, -1)
        }

        return periodMin
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
                        .foregroundStyle(palette.textPrimary)

                    Text(showTime ? L("stats_reviews_time_subtitle") : L("stats_reviews_count_subtitle"))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
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
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                reviewChart
            }

            HStack(spacing: 0) {
                ForEach(footerMetrics) { metric in
                    footerItem(metric.label, value: metric.value)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsTrackWidth($containerWidth)
        .statsCard(elevated: true)
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
            .zIndex(selectedBucket == nil ? 0 : 1)
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
            .foregroundStyle(palette.textSecondary.opacity(0.08))
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
                .foregroundStyle(palette.accent.opacity(0.35))
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
        var valuesByType: [Int: Int] = [:]
        for entry in selectedBucketEntries {
            valuesByType[entry.typeIndex] = entry.value
        }
        let tooltipOrder = [4, 0, 1, 2, 3]
        let dayTotal = selectedBucketEntries.reduce(0) { $0 + $1.value }
        let totalLine = showTime
            ? formatTime(Double(dayTotal))
            : formatReviewCount(dayTotal)
        let reviewLines = tooltipOrder.map { typeIndex in
            let typeName = Self.typeInfo[typeIndex].0
            let value = valuesByType[typeIndex] ?? 0
            if showTime {
                return "\(typeName): \(formatTime(Double(value)))"
            }
            return "\(typeName): \(formatReviewCount(value))"
        }
        let cumulativeLine = showTime
            ? "\(cumulativeLabel): \(formatTime(Double(selectedCumulativePoint.cumulative)))"
            : "\(cumulativeLabel): \(formatReviewCount(selectedCumulativePoint.cumulative))"
        return [totalLine] + reviewLines + [cumulativeLine]
    }

    @ViewBuilder
    private func reviewChartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let overlay = Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedBucket(
                                at: value.location,
                                proxy: proxy,
                                geometry: geometry,
                                togglesSelection: true
                            )
                        }
                )
            if selectedBucket != nil {
                overlay.simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.2)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value,
                                  StatsSelectionSupport.isHorizontalDrag(drag.translation)
                            else { return }

                            updateSelectedBucket(
                                at: drag.location,
                                proxy: proxy,
                                geometry: geometry,
                                togglesSelection: false,
                                emitFeedback: true
                            )
                        }
                )
            } else {
                overlay
            }
        }
    }

    private func updateSelectedBucket(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        togglesSelection: Bool,
        emitFeedback: Bool = false
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            if togglesSelection {
                selectedBucket = nil
            }
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        let plotX = location.x - plotFrame.origin.x
        guard plotX >= 0,
              plotX <= proxy.plotSize.width,
              let bucket: Int = proxy.value(atX: plotX)
        else {
            if togglesSelection {
                selectedBucket = nil
            }
            return
        }

        var seenBuckets: Set<Int> = []
        var nearestBucket: Int?
        var nearestDistance = Int.max

        for entry in entries {
            let candidate = entry.bucket
            guard seenBuckets.insert(candidate).inserted else { continue }

            let distance = Swift.abs(candidate - bucket)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestBucket = candidate
            }
        }

        let nextSelection = togglesSelection && selectedBucket == nearestBucket ? nil : nearestBucket
        guard selectedBucket != nextSelection else { return }
        selectedBucket = nextSelection
        if emitFeedback, nextSelection != nil {
            StatsSelectionSupport.selectionChanged()
        }
    }

    @AxisContentBuilder
    private func reviewChartXAxis() -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: xAxisDesiredTickCount)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(palette.textTertiary.opacity(0.25))
            AxisValueLabel()
                .font(AmgiFont.micro.font)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @AxisContentBuilder
    private func reviewChartYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: leftAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(palette.textTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: leftAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }

        AxisMarks(position: .trailing, values: rightAxisValues) { value in
            AxisTick()
                .foregroundStyle(palette.textTertiary.opacity(0.35))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: rightAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: AmgiSpacing.xxs) {
            Text(value)
                .amgiFont(.captionBold)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var footerMetrics: [FooterMetric] {
        var metrics: [FooterMetric] = [
            FooterMetric(
                label: L("stats_study_days"),
                value: L("stats_study_days_ratio_fmt", uniqueStudyDays, periodDayCount, studiedPercent)
            ),
            FooterMetric(
                label: L("stats_total"),
                value: showTime ? formatTime(totalSeconds) : formatReviewFooterCount(totalReviewCount)
            ),
            FooterMetric(
                label: L("stats_avg_day_all"),
                value: showTime
                    ? formatTime(totalSeconds / Double(periodDayCount))
                    : formatReviewFooterCount(Int((Double(totalReviewCount) / Double(periodDayCount)).rounded()))
            )
        ]

        if studiedPercent < 100, uniqueStudyDays > 0 {
            metrics.append(
                FooterMetric(
                    label: L("stats_avg_day_studied"),
                    value: showTime
                        ? formatTime(totalSeconds / Double(uniqueStudyDays))
                        : formatReviewFooterCount(Int((Double(totalReviewCount) / Double(uniqueStudyDays)).rounded()))
                )
            )
        }

        if showTime, averageAnswerSeconds > 0 {
            metrics.append(
                FooterMetric(
                    label: L("stats_average_answer_time_short"),
                    value: formatTime(averageAnswerSeconds)
                )
            )
        }

        return metrics
    }

    private func filteredRows(from sourceMap: [Int32: ReviewValue]) -> [(Int, ReviewValue)] {
        sourceMap.compactMap { dayOffset, reviewValue in
            let day = Int(dayOffset)
            guard isDayInSelectedPeriod(day) else { return nil }
            return (day, reviewValue)
        }
    }

    private func isDayInSelectedPeriod(_ day: Int) -> Bool {
        guard day <= 0 else { return false }
        switch period {
        case .day:
            return day >= -1
        case .week:
            return day >= -6
        case .month:
            return day >= -30
        case .threeMonths:
            return day >= -89
        case .year:
            return day >= -364
        case .all:
            return true
        }
    }

    private func reviewCountTotal(_ reviewValue: ReviewValue) -> Int {
        Self.valueKeys.reduce(0) { partialResult, keyPath in
            partialResult + Int(reviewValue[keyPath: keyPath])
        }
    }

    private func reviewTimeSeconds(_ reviewValue: ReviewValue) -> Double {
        Self.valueKeys.reduce(0.0) { partialResult, keyPath in
            partialResult + (Double(reviewValue[keyPath: keyPath]) / 1000)
        }
    }

    private func formatReviewCount(_ count: Int) -> String {
        StatsFormatSupport.reviews(count)
    }

    private func formatReviewFooterCount(_ count: Int) -> String {
        L("stats_reviews_short_unit_fmt", StatsFormatSupport.count(count))
    }

    private func formatReviewsPerDay(_ count: Double) -> String {
        StatsFormatSupport.reviewsPerDay(count)
    }

    private func formatTime(_ seconds: Double) -> String {
        StatsFormatSupport.timeShort(seconds)
    }
}
