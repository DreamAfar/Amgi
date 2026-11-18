//
//  ReviewsChart.swift
//  StatsCharts
//
//  Created by Vladimir Gusev on 30.03.2026.
//

public import SwiftUI
import Theme
import UI
import Charts
public import AnkiKit

public struct ReviewsChart: View {
    let reviews: ReviewCountsAndTimes
    let period: StatsPeriod

    public init(reviews: ReviewCountsAndTimes, period: StatsPeriod) {
        self.reviews = reviews
        self.period = period
    }

    @Environment(\.palette) private var palette
    @State private var chartWidth: CGFloat = 0
    @State private var selectedX: Double?
    @State private var mode: Mode = .count

    /// What the bars measure, as Anki's Count/Time switch.
    fileprivate enum Mode: Hashable {
        case count, time
    }

    fileprivate struct ReviewEntry: Identifiable {
        static let typeCount = 5

        var id: Int { day * Self.typeCount + typeIndex }
        /// The day, or for a bar of several days its first one.
        let day: Int
        var size = 1
        let typeIndex: Int
        let type: String
        /// Reviews, or milliseconds spent on them.
        let count: Int
        let color: Color

        var center: Double { Double(day) + Double(size - 1) / 2 }
    }

    private var types: [(String, KeyPath<ReviewCountsAndTimes.Reviews, Int>, Color)] {
        [
            (String(localized: "Learn", bundle: .module), \.learn, palette.cardStateNew),
            (String(localized: "Relearn", bundle: .module), \.relearn, palette.cardStateRelearn),
            (String(localized: "Young", bundle: .module), \.young, palette.cardStateLearning),
            (String(localized: "Mature", bundle: .module), \.mature, palette.cardStateMature),
            (String(localized: "Filtered", bundle: .module), \.filtered, palette.textTertiary),
        ]
    }

    private func entries(_ source: [Int: ReviewCountsAndTimes.Reviews]) -> [ReviewEntry] {
        let maxDay = period.days
        let types = self.types
        var result: [ReviewEntry] = []
        for (day, rev) in source {
            guard day <= 0, -day < maxDay else { continue }
            for (typeIndex, (name, kp, color)) in types.enumerated() {
                let value = rev[keyPath: kp]
                if value > 0 {
                    result.append(ReviewEntry(
                        day: day, typeIndex: typeIndex,
                        type: name, count: value, color: color
                    ))
                }
            }
        }
        return result.sorted(by: { $0.day < $1.day })
    }

    /// The period up to today, as in Anki, or back to the first review.
    private func makeAxis(_ countEntries: [ReviewEntry]) -> StatsBinAxis {
        let lower = period == .all ? min(countEntries.first?.day ?? 0, -1) : -(period.days - 1)
        return StatsBinAxis(lower: lower, upper: 0)
    }

    public var body: some View {
        let countEntries = entries(reviews.count)
        let axis = makeAxis(countEntries)
        let shown = mode == .count ? countEntries : entries(reviews.time)
        AmgiCard(
            background: .surface,
            cornerRadius: AmgiRadius.inset,
            contentInsets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Reviews", bundle: .module).amgiFont(.bodyEmphasis)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    modePicker
                }

                if shown.isEmpty {
                    Text("No review data", bundle: .module).foregroundStyle(palette.textSecondary).frame(height: 180)
                } else {
                    reviewsChart(shown, axis: axis)
                        .frame(height: 180)
                }

                StatsTable(rows: tableRows(countEntries: countEntries, timeEntries: entries(reviews.time), axis: axis))
            }
        }
        .onChange(of: mode) { selectedX = nil }
    }

    @ViewBuilder
    private var modePicker: some View {
        #if os(watchOS)
        EmptyView()
        #else
        Picker(selection: $mode) {
            Text("Count", bundle: .module).tag(Mode.count)
            Text("Time", bundle: .module).tag(Mode.time)
        } label: {
            Text("Reviews", bundle: .module)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        #endif
    }
}

private extension ReviewsChart {
    func reviewsChart(_ entries: [ReviewEntry], axis: StatsBinAxis) -> some View {
        let bars = binned(entries, axis: axis)
        // One slot per bar position, holding every type's total.
        let slots = Dictionary(grouping: bars, by: \.day)
            .map { StatsBar(start: $0.key, size: axis.size, count: $0.value.reduce(0) { $0 + $1.count }) }
            .sorted { $0.start < $1.start }
        let scale = ValueScale(mode: mode, maximum: slots.map(\.count).max() ?? 0)
        let running = StatsRunningTotal(
            slots.map { ($0.center, scale.plotted($0.count)) },
            plottedMax: scale.top,
            format: { scale.label($0) }
        )
        let width = StatsChartScale.barWidth(
            plotWidth: StatsChartScale.plotWidth(chartWidth: chartWidth, trailingAxis: true),
            slots: axis.slots
        )
        let selected = axis.bar(at: selectedX, in: slots)
        return Chart {
            ForEach(bars) { entry in
                reviewBar(entry, width: width, scale: scale)
            }
            StatsRunningTotalMarks(total: running, color: palette.textSecondary)
            if let selected {
                StatsSelectionMark(
                    x: selected.center,
                    title: ChartSpeech.days(selected.start, selected.end),
                    lines: tooltipLines(bars.filter { $0.day == selected.start }, running: running.total(at: selected.center) ?? 0, scale: scale),
                    color: palette.accent
                )
            }
        }
        .chartForegroundStyleScale([
            String(localized: "Learn", bundle: .module): palette.cardStateNew,
            String(localized: "Relearn", bundle: .module): palette.cardStateRelearn,
            String(localized: "Young", bundle: .module): palette.cardStateLearning,
            String(localized: "Mature", bundle: .module): palette.cardStateMature,
            String(localized: "Filtered", bundle: .module): palette.textTertiary,
        ])
        .chartXScale(domain: axis.domain)
        .chartYScale(domain: 0...scale.top)
        .chartXAxis { StatsAxes.values(axis.ticks) }
        .chartYAxis {
            StatsAxes.count(scale.ticks) { scale.label($0) }
            StatsAxes.runningTotal(running.ticks)
        }
        .statsChartTap(as: Double.self) { x in
            let bar = axis.bar(at: x, in: slots)
            selectedX = bar == nil || bar == selected ? nil : bar?.center
        }
        .measuringWidth($chartWidth)
    }

    /// Each type's reviews summed into the axis's bars.
    func binned(_ entries: [ReviewEntry], axis: StatsBinAxis) -> [ReviewEntry] {
        guard axis.size > 1 else { return entries.filter { axis.contains($0.day) } }
        var result: [ReviewEntry] = []
        let byType = Dictionary(grouping: entries, by: \.typeIndex)
        for typeIndex in byType.keys.sorted() {
            guard let group = byType[typeIndex], let first = group.first else { continue }
            for bar in axis.bars(group.map { ($0.day, $0.count) }) {
                result.append(ReviewEntry(
                    day: bar.start, size: bar.size, typeIndex: typeIndex,
                    type: first.type, count: bar.count, color: first.color
                ))
            }
        }
        return result.sorted { ($0.day, $0.typeIndex) < ($1.day, $1.typeIndex) }
    }

    @ChartContentBuilder
    func reviewBar(_ entry: ReviewEntry, width: MarkDimension, scale: ValueScale) -> some ChartContent {
        BarMark(
            x: .value(String(localized: "Day", bundle: .module), entry.center),
            y: .value(String(localized: "Count", bundle: .module), scale.plotted(entry.count)),
            width: width
        )
        .foregroundStyle(by: .value(String(localized: "Type", bundle: .module), entry.type))
        .accessibilityLabel("\(entry.type), \(ChartSpeech.days(entry.day, entry.day + entry.size - 1))")
        .accessibilityValue(scale.spoken(entry.count))
    }

    func tooltipLines(_ entries: [ReviewEntry], running: Double, scale: ValueScale) -> [String] {
        let total = entries.reduce(0) { $0 + $1.count }
        return entries.map { "\($0.type): \(scale.text($0.count))" } + [
            String(localized: "Total: \(scale.text(total))", bundle: .module),
            String(localized: "Running total: \(scale.label(running))", bundle: .module),
        ]
    }

    /// Anki's table: days studied, total, and the averages, with the answer
    /// time when showing time.
    func tableRows(countEntries: [ReviewEntry], timeEntries: [ReviewEntry], axis: StatsBinAxis) -> [(label: String, value: String)] {
        let periodDays = axis.upper - axis.lower + 1
        let studiedDays = Set(countEntries.filter { axis.contains($0.day) }.map(\.day)).count
        let reviewCount = countEntries.filter { axis.contains($0.day) }.reduce(0) { $0 + $1.count }
        let studied = String(
            localized: "\(studiedDays) of \(periodDays) (\(Int((Double(studiedDays) / Double(max(periodDays, 1)) * 100).rounded()))%)",
            bundle: .module
        )
        guard mode == .time else {
            return [
                (String(localized: "Days studied", bundle: .module), studied),
                (String(localized: "Total", bundle: .module), ChartSpeech.count(reviewCount, .review)),
                (String(localized: "Average for days studied", bundle: .module),
                 String(localized: "\(Int((Double(reviewCount) / Double(max(studiedDays, 1))).rounded())) reviews/day", bundle: .module)),
                (String(localized: "Average over period", bundle: .module),
                 String(localized: "\(Int((Double(reviewCount) / Double(max(periodDays, 1))).rounded())) reviews/day", bundle: .module)),
            ]
        }
        let seconds = Double(timeEntries.filter { axis.contains($0.day) }.reduce(0) { $0 + $1.count }) / 1000
        let perAnswer = reviewCount > 0 ? seconds / Double(reviewCount) : 0
        let perMinute = seconds > 0 ? Double(reviewCount) * 60 / seconds : 0
        return [
            (String(localized: "Days studied", bundle: .module), studied),
            (String(localized: "Total", bundle: .module), StatsFormat.duration(seconds: seconds)),
            (String(localized: "Average for days studied", bundle: .module),
             String(localized: "\(Int((seconds / 60 / Double(max(studiedDays, 1))).rounded())) minutes/day", bundle: .module)),
            (String(localized: "Average over period", bundle: .module),
             String(localized: "\(Int((seconds / 60 / Double(max(periodDays, 1))).rounded())) minutes/day", bundle: .module)),
            (String(localized: "Average answer time", bundle: .module),
             String(localized: "\(perAnswer.formatted(.number.precision(.fractionLength(1))))s (\(perMinute.formatted(.number.precision(.fractionLength(1)))) cards/minute)", bundle: .module)),
        ]
    }
}

/// The y axis of the reviews chart: plain counts, or time in minutes —
/// labelled in hours once a bar reaches two.
private struct ValueScale {
    let mode: ReviewsChart.Mode
    let top: Double
    let ticks: [Double]
    private let inHours: Bool

    init(mode: ReviewsChart.Mode, maximum: Int) {
        self.mode = mode
        let minutes = Double(maximum) / 60_000
        let axis: (top: Double, ticks: [Double])
        if mode == .count {
            axis = StatsChartScale.countAxis(maximum: maximum)
        } else if minutes >= 120 {
            let hours = StatsChartScale.countAxis(maximum: Int((minutes / 60).rounded(.up)))
            axis = (hours.top * 60, hours.ticks.map { $0 * 60 })
        } else {
            axis = StatsChartScale.valueAxis(maximum: minutes)
        }
        top = axis.top
        ticks = axis.ticks
        inHours = mode == .time && minutes >= 120
    }

    /// A raw value — reviews, or milliseconds — in the axis's units.
    func plotted(_ value: Int) -> Double {
        mode == .count ? Double(value) : Double(value) / 60_000
    }

    /// An axis value: a count, or minutes.
    func label(_ value: Double) -> String {
        guard mode == .time else { return StatsDualAxisSupport.formatCount(value) }
        return inHours
            ? String(localized: "\(StatsDualAxisSupport.formatCount(value / 60))h", bundle: .module)
            : String(localized: "\(StatsDualAxisSupport.formatCount(value))m", bundle: .module)
    }

    /// A raw value for the tooltip.
    func text(_ value: Int) -> String {
        mode == .count ? StatsDualAxisSupport.formatCount(Double(value)) : StatsFormat.duration(seconds: Double(value) / 1000)
    }

    func spoken(_ value: Int) -> String {
        mode == .count ? ChartSpeech.count(value, .review) : StatsFormat.duration(seconds: Double(value) / 1000)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ReviewsChart(reviews: .sampleYear, period: .month)
        .padding()
}
#endif
