//
//  IntervalsChart.swift
//  StatsCharts
//
//  Created by Vladimir Gusev on 30.03.2026.
//

public import SwiftUI
import Theme
import UI
import Charts
public import AnkiKit

/// How long until the cards are due again, by day, as Anki's histogram.
public struct IntervalsChart: View {
    let intervals: IntervalsBuckets
    let isFSRS: Bool

    public init(intervals: IntervalsBuckets, isFSRS: Bool = false) {
        self.intervals = intervals
        self.isFSRS = isFSRS
    }

    public var body: some View {
        DayHistogramChart(kind: .interval, buckets: intervals.intervals, startsAtZero: isFSRS)
    }
}

/// How long the cards should stay remembered under FSRS: the days until
/// recall falls to 90%, as Anki's stability chart.
public struct StabilityChart: View {
    let stability: IntervalsBuckets

    public init(stability: IntervalsBuckets) {
        self.stability = stability
    }

    public var body: some View {
        DayHistogramChart(kind: .stability, buckets: stability.intervals, startsAtZero: true)
    }
}

/// A histogram of days per card, with Anki's range choices: a month, half
/// the cards, 95% of them, or all.
struct DayHistogramChart: View {
    enum Kind {
        case interval, stability
    }

    enum RangeOption: Hashable, CaseIterable {
        case month, half, most, all
    }

    let kind: Kind
    let buckets: [Int: Int]
    /// SM-2 has no zero-day interval, so its axis starts at one.
    let startsAtZero: Bool

    @Environment(\.palette) private var palette
    @State private var range: RangeOption = .most
    @State private var chartWidth: CGFloat = 0
    @State private var selectedX: Double?

    private var data: [(value: Int, count: Int)] {
        buckets.filter { $0.value > 0 }
            .map { (value: $0.key, count: $0.value) }
            .sorted { $0.value < $1.value }
    }

    /// The day `fraction` of the cards are at or under.
    private func quantile(_ data: [(value: Int, count: Int)], _ fraction: Double) -> Int {
        let total = data.reduce(0) { $0 + $1.count }
        var seen = 0
        for item in data {
            seen += item.count
            if Double(seen) >= Double(total) * fraction { return item.value }
        }
        return data.last?.value ?? 0
    }

    private func makeAxis(_ data: [(value: Int, count: Int)]) -> StatsBinAxis {
        let lower = startsAtZero ? 0 : 1
        let last = data.last?.value ?? lower
        let top: Int
        switch range {
        case .month: top = min(last, 30)
        case .half: top = quantile(data, 0.5)
        case .most: top = quantile(data, 0.95)
        case .all: top = last
        }
        // A round end, as d3's `nice()` gives Anki for the open ranges.
        var upper = max(top, lower + 1)
        if range != .month {
            let increment = Int(StatsChartScale.step(span: Double(upper - lower + 1), count: 10))
            upper = Int((Double(upper + 1) / Double(increment)).rounded(.up)) * increment - 1
        }
        return StatsBinAxis(lower: lower, upper: upper, desiredBars: min(StatsChartScale.maximumBars, upper - lower + 1))
    }

    var body: some View {
        let data = self.data
        AmgiCard(
            background: .surface,
            cornerRadius: AmgiRadius.inset,
            contentInsets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                header

                if data.isEmpty {
                    Group {
                        switch kind {
                        case .interval: Text("No interval data", bundle: .module)
                        case .stability: Text("No stability data", bundle: .module)
                        }
                    }
                    .foregroundStyle(palette.textSecondary)
                    .frame(height: 180)
                } else {
                    rangePicker
                    histogram(data)
                        .frame(height: 180)
                    StatsTable(rows: [(medianLabel, StatsFormat.days(Double(quantile(data, 0.5))))])
                }
            }
        }
        .onChange(of: range) { selectedX = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
            switch kind {
            case .interval:
                Text("Review Intervals", bundle: .module).amgiFont(.bodyEmphasis)
                Text("Delays until reviews are shown again", bundle: .module)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            case .stability:
                Text("Card Stability", bundle: .module).amgiFont(.bodyEmphasis)
                Text("Delays until recall probability falls to 90%", bundle: .module)
                    .amgiFont(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var medianLabel: String {
        switch kind {
        case .interval: String(localized: "Median interval", bundle: .module)
        case .stability: String(localized: "Median stability", bundle: .module)
        }
    }

    @ViewBuilder
    private var rangePicker: some View {
        #if !os(watchOS)
        Picker(selection: $range) {
            Text("1 Month", bundle: .module).tag(RangeOption.month)
            Text(verbatim: "50%").tag(RangeOption.half)
            Text(verbatim: "95%").tag(RangeOption.most)
            Text("All Time", bundle: .module).tag(RangeOption.all)
        } label: {
            Text("Range", bundle: .module)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #endif
    }

    private func histogram(_ data: [(value: Int, count: Int)]) -> some View {
        let axis = makeAxis(data)
        let bars = axis.bars(data)
        let total = Double(bars.reduce(0) { $0 + $1.count })
        let counts = StatsChartScale.countAxis(maximum: bars.map(\.count).max() ?? 0)
        let running = StatsRunningTotal(
            bars.map { ($0.center, total > 0 ? Double($0.count) / total * 100 : 0) },
            plottedMax: counts.top,
            axisMax: 100,
            format: { "\(Int($0.rounded()))%" }
        )
        let width = StatsChartScale.barWidth(
            plotWidth: StatsChartScale.plotWidth(chartWidth: chartWidth, trailingAxis: true),
            slots: axis.slots
        )
        let selected = axis.bar(at: selectedX, in: bars)
        let selectedTotal = selected.map { "\(Int((running.total(at: $0.center) ?? 0).rounded()))%" } ?? ""
        return Chart {
            ForEach(bars) { bar in
                histogramBar(bar, width: width)
            }
            StatsRunningTotalMarks(total: running, color: palette.textSecondary)
            if let selected {
                StatsSelectionMark(
                    x: selected.center,
                    title: rangeLabel(selected),
                    lines: [
                        ChartSpeech.count(selected.count, .card),
                        String(localized: "Running total: \(selectedTotal)", bundle: .module),
                    ],
                    color: palette.accent
                )
            }
        }
        .chartXScale(domain: axis.domain)
        .chartYScale(domain: 0...counts.top)
        .chartXAxis { StatsAxes.values(axis.ticks) }
        .chartYAxis {
            StatsAxes.count(counts.ticks)
            StatsAxes.runningTotal(running.ticks)
        }
        .statsChartTap(as: Double.self) { x in
            let bar = axis.bar(at: x, in: bars)
            selectedX = bar == nil || bar == selected ? nil : bar?.center
        }
        .measuringWidth($chartWidth)
    }

    private func rangeLabel(_ bar: StatsBar) -> String {
        bar.size > 1
            ? "\(StatsFormat.days(Double(bar.start))) – \(StatsFormat.days(Double(bar.end)))"
            : StatsFormat.days(Double(bar.start))
    }

    @ChartContentBuilder
    private func histogramBar(_ bar: StatsBar, width: MarkDimension) -> some ChartContent {
        BarMark(
            x: .value(String(localized: "Days", bundle: .module), bar.center),
            y: .value(String(localized: "Cards", bundle: .module), bar.count),
            width: width
        )
        .foregroundStyle(palette.accent.gradient)
        .accessibilityLabel(rangeLabel(bar))
        .accessibilityValue(ChartSpeech.count(bar.count, .card))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    IntervalsChart(intervals: .sample)
        .padding()
}
#endif
