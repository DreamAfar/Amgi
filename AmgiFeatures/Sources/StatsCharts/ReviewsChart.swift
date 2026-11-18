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

    fileprivate struct ReviewEntry: Identifiable {
        static let typeCount = 5

        var id: Int { day * Self.typeCount + typeIndex }
        /// The day, or for a bar of several days its first one.
        let day: Int
        var size = 1
        let typeIndex: Int
        let type: String
        let count: Int
        let color: Color
    }

    private var entries: [ReviewEntry] {
        let maxDay = period.days
        let types: [(String, KeyPath<ReviewCountsAndTimes.Reviews, Int>, Color)] = [
            (String(localized: "Learn", bundle: .module), \.learn, palette.cardStateNew),
            (String(localized: "Relearn", bundle: .module), \.relearn, palette.cardStateRelearn),
            (String(localized: "Young", bundle: .module), \.young, palette.cardStateLearning),
            (String(localized: "Mature", bundle: .module), \.mature, palette.cardStateMature),
            (String(localized: "Filtered", bundle: .module), \.filtered, palette.textTertiary),
        ]
        var result: [ReviewEntry] = []
        for (day, rev) in reviews.count {
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

    private func totalReviews(_ entries: [ReviewEntry]) -> Int {
        entries.reduce(0) { $0 + $1.count }
    }

    private func avgPerDay(_ entries: [ReviewEntry]) -> Double {
        guard !entries.isEmpty else { return 0 }
        let uniqueDays = Set(entries.map(\.day)).count
        return Double(totalReviews(entries)) / Double(max(uniqueDays, 1))
    }

    public var body: some View {
        let entries = self.entries
        AmgiCard(
            background: .surface,
            cornerRadius: AmgiRadius.inset,
            contentInsets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reviews", bundle: .module).amgiFont(.bodyEmphasis)

                if entries.isEmpty {
                    Text("No review data", bundle: .module).foregroundStyle(palette.textSecondary).frame(height: 180)
                } else {
                    reviewsChart(entries)
                        .frame(height: 180)
                }

                HStack(spacing: 16) {
                    footerItem(String(localized: "Total", bundle: .module), value: "\(totalReviews(entries))")
                    footerItem(String(localized: "Avg/day", bundle: .module), value: String(format: "%.1f", avgPerDay(entries)))
                }
            }
        }
    }
}

private extension ReviewsChart {
    func reviewsChart(_ entries: [ReviewEntry]) -> some View {
        // The period up to today, as in Anki, or back to the first review.
        let lower = period == .all ? min(entries.first?.day ?? 0, -1) : -(period.days - 1)
        let axis = StatsBinAxis(lower: lower, upper: 0)
        let bars = binned(entries, axis: axis)
        var totals: [Int: Int] = [:]
        for bar in bars { totals[bar.day, default: 0] += bar.count }
        let counts = StatsChartScale.countAxis(maximum: totals.values.max() ?? 0)
        let width = StatsChartScale.barWidth(plotWidth: StatsChartScale.plotWidth(chartWidth: chartWidth), slots: axis.slots)
        return Chart(bars) { entry in
            reviewBar(entry, width: width)
        }
        .chartForegroundStyleScale([
            String(localized: "Learn", bundle: .module): palette.cardStateNew,
            String(localized: "Relearn", bundle: .module): palette.cardStateRelearn,
            String(localized: "Young", bundle: .module): palette.cardStateLearning,
            String(localized: "Mature", bundle: .module): palette.cardStateMature,
            String(localized: "Filtered", bundle: .module): palette.textTertiary,
        ])
        .chartXScale(domain: axis.domain)
        .chartYScale(domain: 0...counts.top)
        .chartXAxis {
            AxisMarks(values: axis.ticks) { value in
                AxisGridLine()
                if let day = value.as(Double.self) {
                    AxisValueLabel("\(Int(day))")
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: counts.ticks) { value in
                AxisGridLine()
                if let count = value.as(Double.self) {
                    AxisValueLabel("\(Int(count))")
                }
            }
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
    func reviewBar(_ entry: ReviewEntry, width: MarkDimension) -> some ChartContent {
        BarMark(
            x: .value(String(localized: "Day", bundle: .module), Double(entry.day) + Double(entry.size - 1) / 2),
            y: .value(String(localized: "Count", bundle: .module), entry.count),
            width: width
        )
        .foregroundStyle(by: .value(String(localized: "Type", bundle: .module), entry.type))
        .accessibilityLabel("\(entry.type), \(ChartSpeech.days(entry.day, entry.day + entry.size - 1))")
        .accessibilityValue(ChartSpeech.count(entry.count, .review))
    }

    func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).amgiFont(.captionBold).monospacedDigit()
            Text(label).amgiFont(.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ReviewsChart(reviews: .sampleYear, period: .month)
        .padding()
}
#endif
