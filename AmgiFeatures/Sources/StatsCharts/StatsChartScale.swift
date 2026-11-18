//
//  StatsChartScale.swift
//  StatsCharts
//

import Charts
import SwiftUI

/// Grouping, bar widths and axis ticks shared by the bar charts, following
/// what Anki's own graphs do (`ts/routes/graphs`).
///
/// Without it, a day-by-day chart drew one bar per day: a year was 365 bars
/// about a point wide each, run together into a solid block.
enum StatsChartScale {
    /// The most bars a day chart draws, as in Anki (`desiredBars = min(70, …)`).
    static let maximumBars = 70

    // MARK: Ticks

    /// d3's `tickIncrement`: the step of about `count` round ticks across
    /// `span` — 1, 2 or 5 times a power of ten, never below `minimum`.
    static func step(span: Double, count: Int, minimum: Double = 1) -> Double {
        guard span > 0, count > 0 else { return minimum }
        let raw = span / Double(count)
        let power = pow(10, floor(log10(raw)))
        let error = raw / power
        let factor: Double
        if error >= Double(50).squareRoot() {
            factor = 10
        } else if error >= Double(10).squareRoot() {
            factor = 5
        } else if error >= Double(2).squareRoot() {
            factor = 2
        } else {
            factor = 1
        }
        return max(minimum, factor * power)
    }

    /// Multiples of a round step from `lower` to `upper`, for an axis that
    /// shouldn't land on arbitrary numbers.
    static func ticks(from lower: Double, to upper: Double, count: Int, minimumStep: Double = 1) -> [Double] {
        guard upper > lower else { return [lower] }
        let increment = step(span: upper - lower, count: count, minimum: minimumStep)
        let first = (lower / increment).rounded(.up) * increment
        return Array(stride(from: first, through: upper + increment * 0.001, by: increment))
    }

    /// A count axis: whole numbers from 0, about four of them, and the top of
    /// the axis rounded up to the next one. The automatic axis showed
    /// fractions such as 0.5 cards when the counts were small.
    static func countAxis(maximum: Int) -> (top: Double, ticks: [Double]) {
        let maximum = Double(max(maximum, 1))
        let increment = step(span: maximum, count: 4)
        let top = (maximum / increment).rounded(.up) * increment
        return (top, Array(stride(from: 0, through: top + increment * 0.001, by: increment)))
    }

    // MARK: Bins

    /// Values per bar for an axis covering `span` values, so it draws at most
    /// about `desiredBars` bars — Anki bins with `scale.ticks(desiredBars)`.
    static func binSize(span: Int, desiredBars: Int = maximumBars) -> Int {
        guard span > desiredBars else { return 1 }
        return Int(step(span: Double(span), count: desiredBars))
    }

    /// The first value of the bar `value` falls in: bars are aligned to
    /// multiples of their size, as Anki's thresholds are.
    static func barStart(of value: Int, size: Int) -> Int {
        guard size > 1 else { return value }
        return Int((Double(value) / Double(size)).rounded(.down)) * size
    }

    // MARK: Bar width

    /// A bar width leaving a visible gap between bars however many there are.
    /// Swift Charts' automatic width shrinks to nothing on a dense numeric
    /// axis; this keeps each bar to about 70% of its slot.
    static func barWidth(plotWidth: CGFloat, slots: Int) -> MarkDimension {
        guard plotWidth > 0, slots > 0 else { return .automatic }
        let slot = Double(plotWidth) / Double(slots)
        let ratio = slots > 40 ? 0.7 : 0.75
        return .fixed(min(28, max(1.5, slot * ratio)))
    }

    /// The chart's width less room for the count labels, near enough
    /// to the plot's width to size the bars.
    static func plotWidth(chartWidth: CGFloat) -> CGFloat {
        max(0, chartWidth - 36)
    }
}

/// The x axis of a binned bar chart: the values `lower ... upper`, grouped
/// into bars of `size`, with a fixed domain so a period shows its full range
/// rather than only the days that happen to have data.
struct StatsBinAxis: Equatable {
    let lower: Int
    let upper: Int
    let size: Int

    init(lower: Int, upper: Int, desiredBars: Int = StatsChartScale.maximumBars) {
        self.lower = min(lower, upper)
        self.upper = max(lower, upper)
        size = StatsChartScale.binSize(span: self.upper - self.lower + 1, desiredBars: desiredBars)
    }

    private var firstStart: Int { StatsChartScale.barStart(of: lower, size: size) }
    private var lastStart: Int { StatsChartScale.barStart(of: upper, size: size) }

    /// How many bars fit across the axis.
    var slots: Int { (lastStart - firstStart) / size + 1 }

    var domain: ClosedRange<Double> {
        (Double(firstStart) - 0.5)...(Double(lastStart + size) - 0.5)
    }

    /// About five round values to label.
    var ticks: [Double] {
        StatsChartScale.ticks(from: Double(lower), to: Double(upper), count: 5)
    }

    func contains(_ value: Int) -> Bool { (lower...upper).contains(value) }

    /// `values` within the axis, summed into its bars.
    func bars(_ values: [(value: Int, count: Int)]) -> [StatsBar] {
        var totals: [Int: Int] = [:]
        for item in values where contains(item.value) {
            totals[StatsChartScale.barStart(of: item.value, size: size), default: 0] += item.count
        }
        return totals.keys.sorted().map { StatsBar(start: $0, size: size, count: totals[$0] ?? 0) }
    }
}

/// One bar: the values `start ... start + size - 1`.
struct StatsBar: Identifiable, Hashable {
    let start: Int
    let size: Int
    let count: Int

    var id: Int { start }
    var end: Int { start + size - 1 }
    /// Where the bar is drawn: the middle of its values.
    var center: Double { Double(start) + Double(size - 1) / 2 }
}

extension ChartSpeech {
    /// The day or run of days a bar covers.
    static func days(_ start: Int, _ end: Int) -> String {
        start == end ? day(start) : "\(day(start)) – \(day(end))"
    }
}

extension View {
    /// Keeps `width` up to date with the view's width, for sizing bars.
    func measuringWidth(_ width: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.wrappedValue = $0 }
    }
}
