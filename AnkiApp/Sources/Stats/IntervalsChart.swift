import SwiftUI
import Charts
import AnkiProto

struct IntervalsChart: View {
    let intervals: Anki_Stats_GraphsResponse.Intervals
    let isFSRS: Bool

    private struct CumulativePoint: Identifiable {
        let id: Int
        let x: Int
        let cumulative: Int
    }

    enum IntervalRange: String, CaseIterable, Identifiable {
        case month       = "1个月"
        case percentile50 = "50%"
        case percentile95 = "95%"
        case all         = "全部"
        var id: String { rawValue }
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
    private func cumulativePoints(for bins: [(label: String, x: Int, count: Int)]) -> [CumulativePoint] {
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
            formatter: { value in String(Int(value.rounded())) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(isFSRS ? L("stats_stability_title") : L("stats_intervals_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Picker("", selection: $range) {
                ForEach(IntervalRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .amgiFont(.micro)

            let (bins, _) = histogramData
            if bins.isEmpty {
                Text(L("stats_intervals_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                intervalsChart(bins: bins)
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
    private func intervalsChart(bins: [(label: String, x: Int, count: Int)]) -> some View {
        let barWVal: Double = max(2.0, min(8.0, 280.0 / Double(bins.count)))
        let barW: MarkDimension = bins.count <= 30 ? .automatic : .fixed(barWVal)
        let cumulative = cumulativePoints(for: bins)
        let total = cumulative.last?.cumulative ?? 0
        let maxCount = bins.map(\.count).max() ?? 0
        let leftAxisMax = StatsDualAxisSupport.niceUpperBound(Double(maxCount))
        let rightAxisMax = StatsDualAxisSupport.niceUpperBound(Double(total))
        let trailingTicks = rightAxisTicks(total: total, plottedMax: Int(leftAxisMax.rounded()))
        Chart {
            ForEach(bins, id: \.x) { bin in
                BarMark(
                    x: .value(L("stats_intervals_days"), bin.x),
                    y: .value(L("stats_card_count"), bin.count),
                    width: barW
                )
                .foregroundStyle(Color.teal.gradient)
            }

            ForEach(cumulative) { point in
                AreaMark(
                    x: .value(L("stats_intervals_days"), point.x),
                    y: .value(
                        "Cumulative",
                        StatsDualAxisSupport.plottedValue(
                            Double(point.cumulative),
                            domainMax: rightAxisMax,
                            plottedMax: leftAxisMax
                        )
                    )
                )
                .foregroundStyle(Color.amgiTextSecondary.opacity(0.08))
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value(L("stats_intervals_days"), point.x),
                    y: .value(
                        "Cumulative",
                        StatsDualAxisSupport.plottedValue(
                            Double(point.cumulative),
                            domainMax: rightAxisMax,
                            plottedMax: leftAxisMax
                        )
                    ),
                    series: .value("Series", "cumulative")
                )
                .foregroundStyle(Color.amgiTextSecondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
        }
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
            AxisMarks(preset: .aligned, position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                AxisValueLabel()
                    .font(AmgiFont.micro.font)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            AxisMarks(position: .trailing, values: trailingTicks.map(\.plottedValue)) { value in
                if let raw = value.as(Double.self),
                   let tick = trailingTicks.first(where: { abs($0.plottedValue - raw) < 0.0001 }) {
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
}
