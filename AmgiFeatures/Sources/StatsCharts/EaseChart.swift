//
//  EaseChart.swift
//  StatsCharts
//
//  Created by Vladimir Gusev on 30.03.2026.
//

public import SwiftUI
import Theme
import UI
import Charts
public import AnkiKit

/// How the cards' ease is spread — or under FSRS, which has no ease, their
/// difficulty, as Anki shows in its place.
///
/// Both arrive in percent: ease buckets are the ease factor over 10 (250 is
/// 250%), difficulty buckets 0–100.
public struct EaseChart: View {
    let eases: EaseBuckets
    let difficulty: EaseBuckets
    let isFSRS: Bool

    public init(eases: EaseBuckets, difficulty: EaseBuckets = EaseBuckets(), isFSRS: Bool = false) {
        self.eases = eases
        self.difficulty = difficulty
        self.isFSRS = isFSRS
    }

    @Environment(\.palette) private var palette
    @State private var chartWidth: CGFloat = 0
    @State private var selectedX: Double?

    private var buckets: EaseBuckets { isFSRS ? difficulty : eases }

    private var chartData: [(value: Int, count: Int)] {
        buckets.eases
            .map { (value: $0.key, count: $0.value) }
            .sorted(by: { $0.value < $1.value })
    }

    private var averageLabel: String {
        guard buckets.average > 0 else { return "---" }
        return String(format: "%.0f%%", buckets.average)
    }

    /// Anki's ranges: ease from its 130% floor in about 20 bars, difficulty
    /// across 0–100% in 20.
    private func makeAxis(_ data: [(value: Int, count: Int)]) -> StatsBinAxis {
        if isFSRS {
            return StatsBinAxis(lower: 0, upper: 100, desiredBars: 20)
        }
        let lower = min(data.first?.value ?? 130, 130)
        let upper = max(data.last?.value ?? 250, lower + 20)
        return StatsBinAxis(lower: lower, upper: upper, desiredBars: 20)
    }

    public var body: some View {
        let chartData = self.chartData
        AmgiCard(
            background: .surface,
            cornerRadius: AmgiRadius.inset,
            contentInsets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Group {
                        if isFSRS {
                            Text("Card Difficulty", bundle: .module)
                        } else {
                            Text("Card Ease", bundle: .module)
                        }
                    }
                    .amgiFont(.bodyEmphasis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Avg: \(averageLabel)", bundle: .module)
                        .amgiFont(.captionBold)
                        .foregroundStyle(palette.textSecondary)
                }

                if chartData.isEmpty {
                    Group {
                        if isFSRS {
                            Text("No difficulty data", bundle: .module)
                        } else {
                            Text("No ease data", bundle: .module)
                        }
                    }
                    .foregroundStyle(palette.textSecondary)
                    .frame(height: 180)
                } else {
                    easeChart(chartData)
                        .frame(height: 180)
                }
            }
        }
    }
}

private extension EaseChart {
    func easeChart(_ data: [(value: Int, count: Int)]) -> some View {
        let axis = makeAxis(data)
        let bars = axis.bars(data)
        let counts = StatsChartScale.countAxis(maximum: bars.map(\.count).max() ?? 0)
        let total = bars.reduce(0) { $0 + $1.count }
        let width = StatsChartScale.barWidth(plotWidth: StatsChartScale.plotWidth(chartWidth: chartWidth), slots: axis.slots)
        let selected = axis.bar(at: selectedX, in: bars)
        return Chart {
            ForEach(bars) { bar in
                easeBar(bar, width: width)
            }
            if let selected {
                StatsSelectionMark(
                    x: selected.center,
                    title: selected.size > 1 ? "\(selected.start)%–\(selected.end + 1)%" : "\(selected.start)%",
                    lines: [
                        ChartSpeech.count(selected.count, .card),
                        StatsFormat.percent(Double(selected.count), of: Double(total)),
                    ],
                    color: palette.accent
                )
            }
        }
        .chartXScale(domain: axis.domain)
        .chartYScale(domain: 0...counts.top)
        .chartXAxis { StatsAxes.values(axis.ticks) { "\(Int($0))%" } }
        .chartYAxis { StatsAxes.count(counts.ticks) }
        .statsChartTap(as: Double.self) { x in
            let bar = axis.bar(at: x, in: bars)
            selectedX = bar == nil || bar == selected ? nil : bar?.center
        }
        .measuringWidth($chartWidth)
    }

    @ChartContentBuilder
    func easeBar(_ bar: StatsBar, width: MarkDimension) -> some ChartContent {
        BarMark(
            x: .value(
                isFSRS ? String(localized: "Difficulty", bundle: .module) : String(localized: "Ease", bundle: .module),
                bar.center
            ),
            y: .value(String(localized: "Cards", bundle: .module), bar.count),
            width: width
        )
        .foregroundStyle(palette.accent.gradient)
        .accessibilityLabel(
            isFSRS
                ? String(localized: "\(bar.start)% difficulty", bundle: .module)
                : String(localized: "\(bar.start)% ease", bundle: .module)
        )
        .accessibilityValue(ChartSpeech.count(bar.count, .card))
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    EaseChart(eases: .sample)
        .padding()
}
#endif
