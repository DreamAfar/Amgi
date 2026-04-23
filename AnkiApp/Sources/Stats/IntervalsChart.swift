import SwiftUI
import Charts
import AnkiProto

struct IntervalsChart: View {
    let intervals: Anki_Stats_GraphsResponse.Intervals
    let isFSRS: Bool
    @State private var selectedBinX: Int?

    private typealias IntervalBin = (label: String, x: Int, count: Int)

    private struct CumulativePoint: Identifiable {
        let id: Int
        let x: Int
        let cumulative: Int
    }

    private struct IntervalChartState {
        let barWidth: MarkDimension
        let xAxisDesiredCount: Int
        let cumulative: [CumulativePoint]
        let total: Int
        let leftAxisMax: Double
        let rightAxisMax: Double
        let trailingTicks: [StatsAxisTick]
        let leadingTicks: [StatsAxisTick]
        let selectedBin: IntervalBin?
        let selectedPoint: CumulativePoint?

        var leadingTickValues: [Double] {
            leadingTicks.map(\.plottedValue)
        }

        var trailingTickValues: [Double] {
            trailingTicks.map(\.plottedValue)
        }
    }

    enum IntervalRange: CaseIterable, Identifiable {
        case month
        case percentile50
        case percentile95
        case all

        var id: Self { self }

        var localizedLabel: String {
            switch self {
            case .month:
                return L("stats_period_month")
            case .percentile50:
                return "50%"
            case .percentile95:
                return "95%"
            case .all:
                return L("stats_period_all")
            }
        }
    }

    @State private var range: IntervalRange = .month

    // Flat sorted array of all intervals (each card = one entry)
    private var flatIntervals: [Int] {
        var arr: [Int] = []
        for (day, cnt) in intervals.intervals {
            let n = Int(cnt)
            arr.append(contentsOf: repeatElement(Int(day), count: n))
        }
        return arr.sorted()
    }

    private func quantile(_ sorted: [Int], _ p: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }

    // Returns (bins, xMax) where bins = [(label, midpoint, count)]
    private var histogramData: (bins: [(label: String, x: Int, count: Int)], xMax: Int) {
        let sorted = flatIntervals
        guard !sorted.isEmpty else { return ([], 0) }

        let xMax: Int
        switch range {
        case .month:       xMax = 30
        case .percentile50: xMax = max(1, quantile(sorted, 0.5))
        case .percentile95: xMax = max(1, quantile(sorted, 0.95))
        case .all:          xMax = sorted.last ?? 1
        }

        let desiredBars = min(70, xMax)
        let binSize = max(1, xMax / desiredBars)

        var buckets: [Int: Int] = [:]
        for v in sorted {
            guard v <= xMax else { continue }
            let b = (v / binSize) * binSize
            buckets[b, default: 0] += 1
        }

        let bins = buckets.sorted(by: { $0.key < $1.key }).map { (k, cnt) in
            let label: String
            if binSize == 1 {
                label = "\(k)"
            } else {
                label = "\(k)-\(k + binSize - 1)"
            }
            return (label: label, x: k, count: cnt)
        }
        return (bins, xMax)
    }

    private var medianInterval: Int {
        let s = flatIntervals
        return s.isEmpty ? 0 : quantile(s, 0.5)
    }
    private func cumulativePoints(for bins: [IntervalBin]) -> [CumulativePoint] {
        var runningTotal = 0
        return bins.map { bin in
            runningTotal += bin.count
            return CumulativePoint(id: bin.x, x: bin.x, cumulative: runningTotal)
        }
    }

    private func rightAxisTicks(total: Int, plottedMax: Int) -> [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: Double(total),
            plottedMax: Double(plottedMax),
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }

    private func leftAxisTicks(plottedMax: Int) -> [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: Double(plottedMax),
            plottedMax: Double(plottedMax),
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }

    private func makeIntervalChartState(for bins: [IntervalBin]) -> IntervalChartState {
        let barWidthValue = max(2.0, min(8.0, 280.0 / Double(bins.count)))
        let barWidth: MarkDimension = bins.count <= 30 ? .automatic : .fixed(barWidthValue)
        let xAxisDesiredCount = min(10, max(4, bins.count / 8))
        let cumulative = cumulativePoints(for: bins)
        let total = cumulative.last?.cumulative ?? 0
        let maxCount = bins.map(\.count).max() ?? 0
        let leftAxisMax = StatsDualAxisSupport.niceUpperBound(Double(maxCount))
        let rightAxisMax = StatsDualAxisSupport.niceUpperBound(Double(total))
        let trailingTicks = rightAxisTicks(total: total, plottedMax: Int(leftAxisMax.rounded()))
        let leadingTicks = leftAxisTicks(plottedMax: Int(leftAxisMax.rounded()))
        let selectedBin = bins.first(where: { $0.x == selectedBinX })
        let selectedPoint = cumulative.first(where: { $0.x == selectedBinX })
        return IntervalChartState(
            barWidth: barWidth,
            xAxisDesiredCount: xAxisDesiredCount,
            cumulative: cumulative,
            total: total,
            leftAxisMax: leftAxisMax,
            rightAxisMax: rightAxisMax,
            trailingTicks: trailingTicks,
            leadingTicks: leadingTicks,
            selectedBin: selectedBin,
            selectedPoint: selectedPoint
        )
    }

    private func plottedCumulative(_ value: Int, state: IntervalChartState) -> Double {
        StatsDualAxisSupport.plottedValue(
            Double(value),
            domainMax: state.rightAxisMax,
            plottedMax: state.leftAxisMax
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(isFSRS ? L("stats_stability_title") : L("stats_intervals_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Text(isFSRS ? L("stats_stability_subtitle") : L("stats_intervals_subtitle"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)

            Picker("", selection: $range) {
                ForEach(IntervalRange.allCases) { r in
                    Text(r.localizedLabel).tag(r)
                }
            }
            .amgiSegmentedPicker()
            .amgiFont(.micro)
            .onChange(of: range) { selectedBinX = nil }

            let (bins, xMax) = histogramData
            if bins.isEmpty {
                Text(L("stats_intervals_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                intervalsChart(bins: bins, xMax: xMax)
            }

            HStack(spacing: 16) {
                footerItem(L("stats_intervals_median"), value: L("stats_intervals_days_fmt", medianInterval))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard(elevated: true)
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

    @ViewBuilder
    private func intervalsChart(bins: [IntervalBin], xMax: Int) -> some View {
        let state = makeIntervalChartState(for: bins)
        baseIntervalsChart(bins: bins, xMax: xMax, state: state)
    }

    private func baseIntervalsChart(bins: [IntervalBin], xMax: Int, state: IntervalChartState) -> some View {
        Chart {
            intervalBarMarks(bins: bins, state: state)
            intervalCumulativeMarks(state: state)
            selectedIntervalRuleMark(state: state)
        }
        .chartOverlay { proxy in
            intervalsChartOverlay(proxy: proxy, bins: bins)
        }
        .chartXScale(domain: 0...max(1, xMax))
        .chartYScale(domain: 0...state.leftAxisMax)
        .chartXAxis {
            intervalsChartXAxis(state: state)
        }
        .chartYAxis {
            intervalsChartYAxis(state: state)
        }
        .frame(height: 200)
    }

    @ChartContentBuilder
    private func intervalBarMarks(bins: [IntervalBin], state: IntervalChartState) -> some ChartContent {
        ForEach(bins, id: \.x) { bin in
            BarMark(
                x: .value(L("stats_intervals_days"), bin.x),
                y: .value(L("stats_card_count"), bin.count),
                width: state.barWidth
            )
            .foregroundStyle(Color.teal.gradient)
        }
    }

    @ChartContentBuilder
    private func intervalCumulativeMarks(state: IntervalChartState) -> some ChartContent {
        ForEach(state.cumulative) { point in
            AreaMark(
                x: .value(L("stats_intervals_days"), point.x),
                y: .value("Cumulative", plottedCumulative(point.cumulative, state: state))
            )
            .foregroundStyle(Color.amgiTextSecondary.opacity(0.08))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value(L("stats_intervals_days"), point.x),
                y: .value("Cumulative", plottedCumulative(point.cumulative, state: state)),
                series: .value("Series", "cumulative")
            )
            .foregroundStyle(Color.amgiTextSecondary.opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func selectedIntervalRuleMark(state: IntervalChartState) -> some ChartContent {
        if let selectedBin = state.selectedBin,
           let selectedPoint = state.selectedPoint,
           state.total > 0 {
            let countLabel = L("stats_card_count")
            let cumulativeLabel = L("stats_reviews_cumulative")
            let cumulativePercent = String(
                format: "%.1f%%",
                Double(selectedPoint.cumulative) / Double(state.total) * 100
            )
            RuleMark(x: .value(L("stats_intervals_days"), selectedBin.x))
                .foregroundStyle(Color.amgiAccent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                    StatsChartTooltip(
                        title: selectedBin.label,
                        lines: [
                            "\(countLabel): \(selectedBin.count)",
                            "\(cumulativeLabel): \(cumulativePercent)"
                        ]
                    )
                }
        }
    }

    @ViewBuilder
    private func intervalsChartOverlay(proxy: ChartProxy, bins: [IntervalBin]) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedBinX(for: value, proxy: proxy, geometry: geometry, bins: bins)
                        }
                )
        }
    }

    private func updateSelectedBinX(
        for value: SpatialTapGesture.Value,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        bins: [IntervalBin]
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        let plotX = value.location.x - plotFrame.origin.x
        guard plotX >= 0,
              plotX <= proxy.plotSize.width,
              let xValue: Int = proxy.value(atX: plotX)
        else {
            selectedBinX = nil
            return
        }

        let nearestX = bins.min(by: { lhs, rhs in
            abs(lhs.x - xValue) < abs(rhs.x - xValue)
        })?.x
        selectedBinX = selectedBinX == nearestX ? nil : nearestX
    }

    @AxisContentBuilder
    private func intervalsChartXAxis(state: IntervalChartState) -> some AxisContent {
        AxisMarks(values: .automatic(desiredCount: state.xAxisDesiredCount)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
            AxisValueLabel()
                .font(AmgiFont.micro.font)
                .foregroundStyle(Color.amgiTextSecondary)
        }
    }

    @AxisContentBuilder
    private func intervalsChartYAxis(state: IntervalChartState) -> some AxisContent {
        AxisMarks(position: .leading, values: state.leadingTickValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: state.leadingTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }

        AxisMarks(position: .trailing, values: state.trailingTickValues) { value in
            AxisTick()
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.35))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: state.trailingTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
    }
}
