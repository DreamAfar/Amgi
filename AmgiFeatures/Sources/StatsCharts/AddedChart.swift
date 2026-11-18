//
//  AddedChart.swift
//  StatsCharts
//
//  Created by Vladimir Gusev on 30.03.2026.
//

public import SwiftUI
import Theme
import UI
import Charts
public import AnkiKit

public struct AddedChart: View {
    let added: AddedSeries
    let period: StatsPeriod

    public init(added: AddedSeries, period: StatsPeriod) {
        self.added = added
        self.period = period
    }

    @Environment(\.palette) private var palette
    @State private var chartWidth: CGFloat = 0

    private var filteredData: [(day: Int, count: Int)] {
        let maxDay = period.days
        return added.added
            .compactMap { (dayOffset, count) -> (day: Int, count: Int)? in
                let day = Int(dayOffset)
                guard day <= 0, -day < maxDay else { return nil }
                return (day: day, count: Int(count))
            }
            .sorted(by: { $0.day < $1.day })
    }

    private var totalAdded: Int { filteredData.reduce(0) { $0 + $1.count } }
    private var avgPerDay: Double {
        guard !filteredData.isEmpty else { return 0 }
        let days = Set(filteredData.map(\.day)).count
        return Double(totalAdded) / Double(max(days, 1))
    }

    public var body: some View {
        AmgiCard(
            background: .surface,
            cornerRadius: AmgiRadius.inset,
            contentInsets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cards Added", bundle: .module).amgiFont(.bodyEmphasis)

                if filteredData.isEmpty {
                    Text("No cards added", bundle: .module).foregroundStyle(palette.textSecondary).frame(height: 180)
                } else {
                    addedChart(filteredData)
                        .frame(height: 180)
                }

                HStack(spacing: 16) {
                    footerItem(String(localized: "Total", bundle: .module), value: "\(totalAdded)")
                    footerItem(String(localized: "Avg/day", bundle: .module), value: String(format: "%.1f", avgPerDay))
                }
            }
        }
    }
}

private extension AddedChart {
    func addedChart(_ data: [(day: Int, count: Int)]) -> some View {
        // The period up to today, as in Anki, or back to the first card added.
        let lower = period == .all ? min(data.first?.day ?? 0, -1) : -(period.days - 1)
        let axis = StatsBinAxis(lower: lower, upper: 0)
        let bars = axis.bars(data.map { ($0.day, $0.count) })
        let counts = StatsChartScale.countAxis(maximum: bars.map(\.count).max() ?? 0)
        let width = StatsChartScale.barWidth(plotWidth: StatsChartScale.plotWidth(chartWidth: chartWidth), slots: axis.slots)
        return Chart(bars, id: \.start) { bar in
            addedBar(bar, width: width)
        }
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

    @ChartContentBuilder
    func addedBar(_ bar: StatsBar, width: MarkDimension) -> some ChartContent {
        BarMark(
            x: .value(String(localized: "Day", bundle: .module), bar.center),
            y: .value(String(localized: "Cards", bundle: .module), bar.count),
            width: width
        )
        .foregroundStyle(palette.accent.gradient)
        .accessibilityLabel(ChartSpeech.days(bar.start, bar.end))
        .accessibilityValue(ChartSpeech.count(bar.count, .card))
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
    AddedChart(added: .sample, period: .month)
        .padding()
}
#endif
