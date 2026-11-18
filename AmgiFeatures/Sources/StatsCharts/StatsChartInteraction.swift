//
//  StatsChartInteraction.swift
//  StatsCharts
//

import Charts
import SwiftUI
import Theme
import UI

// MARK: - Tap selection

extension View {
    /// Reports the x value under a tap on the chart's plot, or nil for a tap
    /// outside it — for showing a bar's details, as hovering does in Anki.
    ///
    /// A tap rather than `chartXSelection` or a drag: those claim the drag
    /// that scrolls the stats page, so the page stuck whenever a swipe
    /// began on a chart.
    func statsChartTap<Value: Plottable>(as type: Value.Type, _ action: @escaping (Value?) -> Void) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { tap in
                            // The plot's frame is nil until the chart has laid out.
                            guard let plotFrame = proxy.plotFrame else { return action(nil) }
                            let frame = geometry[plotFrame]
                            guard frame.contains(tap.location) else { return action(nil) }
                            action(proxy.value(atX: tap.location.x - frame.minX, as: Value.self))
                        }
                    )
            }
        }
    }
}

extension StatsBinAxis {
    /// The bar at `x`, of those given.
    func bar(at x: Double?, in bars: [StatsBar]) -> StatsBar? {
        guard let x else { return nil }
        return bars.first { Double($0.start) - 0.5 <= x && x <= Double($0.end) + 0.5 }
    }
}

/// A selected bar's details, drawn above it.
struct StatsSelectionMark: ChartContent {
    let x: Double
    let title: String
    let lines: [String]
    let color: Color

    @ChartContentBuilder
    var body: some ChartContent {
        RuleMark(x: .value(StatsMarkLabel.selection, x))
            .foregroundStyle(color.opacity(0.35))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                StatsChartTooltip(title: title, lines: lines)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Running total

/// Names for marks VoiceOver skips, kept out of the string catalog.
enum StatsMarkLabel {
    static let selection: String = "selection"
    static let position: String = "position"
    static let runningTotal: String = "running-total"
    static let series: String = "series"
}

/// The running total Anki draws over its bar charts, on its own axis on the
/// right: plotted in the left axis's units so it shares the chart.
struct StatsRunningTotal {
    struct Point: Identifiable {
        let x: Double
        let total: Double
        let plotted: Double
        var id: Double { x }
    }

    let points: [Point]
    let ticks: [StatsAxisTick]

    /// - Parameters:
    ///   - values: Each bar's position and value, in order.
    ///   - plottedMax: The top of the left axis.
    ///   - axisMax: The top of the right axis; by default a round number
    ///     above the final total.
    init(
        _ values: [(x: Double, value: Double)],
        plottedMax: Double,
        axisMax: Double? = nil,
        format: (Double) -> String
    ) {
        var running = 0.0
        var totals: [(x: Double, total: Double)] = []
        for item in values.sorted(by: { $0.x < $1.x }) {
            running += item.value
            totals.append((item.x, running))
        }
        let top = axisMax ?? StatsDualAxisSupport.niceUpperBound(running)
        // `ticks` rounds the top of the axis up again; plotting against that
        // same top keeps the line on the labels beside it.
        let scaleTop = StatsDualAxisSupport.niceUpperBound(top)
        points = totals.map {
            Point(x: $0.x, total: $0.total, plotted: StatsDualAxisSupport.plottedValue($0.total, domainMax: scaleTop, plottedMax: plottedMax))
        }
        ticks = running > 0 ? StatsDualAxisSupport.ticks(domainMax: top, plottedMax: plottedMax, formatter: format) : []
    }

    func total(at x: Double) -> Double? {
        points.last { $0.x <= x }?.total
    }
}

/// The running total as a shaded step line.
struct StatsRunningTotalMarks: ChartContent {
    let total: StatsRunningTotal
    let color: Color

    @ChartContentBuilder
    var body: some ChartContent {
        ForEach(total.points) { point in
            AreaMark(
                x: .value(StatsMarkLabel.position, point.x),
                yStart: .value(StatsMarkLabel.runningTotal, 0),
                yEnd: .value(StatsMarkLabel.runningTotal, point.plotted)
            )
            .interpolationMethod(.stepCenter)
            .foregroundStyle(color.opacity(0.12))
            .accessibilityHidden(true)

            LineMark(
                x: .value(StatsMarkLabel.position, point.x),
                y: .value(StatsMarkLabel.runningTotal, point.plotted),
                series: .value(StatsMarkLabel.series, StatsMarkLabel.runningTotal)
            )
            .interpolationMethod(.stepCenter)
            .foregroundStyle(color.opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Axes

/// Axis marks shared by the charts. Functions rather than `AxisContent`
/// types: Swift Charts doesn't let other modules conform to that protocol.
enum StatsAxes {
    /// Whole-number count labels on the left, with grid lines.
    @AxisContentBuilder
    static func count(
        _ ticks: [Double],
        format: @escaping (Double) -> String = { StatsDualAxisSupport.formatCount($0) }
    ) -> some AxisContent {
        AxisMarks(position: .leading, values: ticks) { value in
            AxisGridLine()
            if let count = value.as(Double.self) {
                AxisValueLabel(format(count))
            }
        }
    }

    /// The running total's labels on the right.
    @AxisContentBuilder
    static func runningTotal(_ ticks: [StatsAxisTick]) -> some AxisContent {
        AxisMarks(position: .trailing, values: ticks.map(\.plottedValue)) { value in
            if let plotted = value.as(Double.self) {
                AxisValueLabel(StatsDualAxisSupport.label(for: plotted, in: ticks))
            }
        }
    }

    /// Labels on the x axis at the given values.
    @AxisContentBuilder
    static func values(
        _ ticks: [Double],
        format: @escaping (Double) -> String = { "\(Int($0))" }
    ) -> some AxisContent {
        AxisMarks(values: ticks) { value in
            AxisGridLine()
            if let x = value.as(Double.self) {
                AxisValueLabel(format(x))
            }
        }
    }
}

// MARK: - Formatting

enum StatsFormat {
    /// A length of time, from seconds: "1 hr, 5 min", "45 sec".
    static func duration(seconds: Double) -> String {
        let seconds = max(0, seconds.rounded())
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 3600 ? [.hours, .minutes] : [.minutes, .seconds]
        return Duration.seconds(seconds).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: 2))
    }

    /// A span of days as Anki shows an interval: days under a month, then
    /// months, then years.
    static func days(_ days: Double) -> String {
        if days < 30 {
            return ChartSpeech.count(Int(days.rounded()), .day)
        } else if days < 365 {
            let months = (days / 30 * 10).rounded() / 10
            return String(localized: "\(months.formatted()) months", bundle: .module)
        } else {
            let years = (days / 365 * 10).rounded() / 10
            return String(localized: "\(years.formatted()) years", bundle: .module)
        }
    }

    static func percent(_ part: Double, of whole: Double) -> String {
        guard whole > 0 else { return "0%" }
        return "\(Int((part / whole * 100).rounded()))%"
    }
}

// MARK: - Table

/// Label–value rows under a chart, as Anki's tables.
struct StatsTable: View {
    let rows: [(label: String, value: String)]

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: AmgiSpacing.xxs) {
            ForEach(rows, id: \.label) { row in
                HStack(alignment: .firstTextBaseline, spacing: AmgiSpacing.sm) {
                    Text(row.label)
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: AmgiSpacing.sm)
                    Text(row.value)
                        .amgiFont(.captionBold)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}
