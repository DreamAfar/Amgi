import SwiftUI
import Charts
import AnkiProto

struct RetrievabilityChart: View {
    let retrievability: Anki_Stats_GraphsResponse.Retrievability

    @State private var selectedBucketStart: Int?

    private struct Bucket: Identifiable {
        let start: Int
        let end: Int
        let count: Int

        var id: Int { start }
        var center: Double { Double(start + end) / 2.0 }
        var label: String { "\(start)-\(end)%" }
    }

    private var chartData: [Bucket] {
        guard !retrievability.retrievability.isEmpty else { return [] }

        return stride(from: 0, through: 95, by: 5).map { start in
            let end = start == 95 ? 100 : start + 4
            let count = retrievability.retrievability.reduce(into: 0) { partial, entry in
                let value = min(Int(entry.key), 100)
                if value >= start && value <= end {
                    partial += Int(entry.value)
                }
            }
            return Bucket(start: start, end: end, count: count)
        }
    }

    private var averageLabel: String {
        guard retrievability.average > 0 else { return "---" }
        return String(format: "%.0f%%", retrievability.average)
    }

    private var selectedBucket: Bucket? {
        guard let selectedBucketStart else { return nil }
        return chartData.first(where: { $0.start == selectedBucketStart })
    }

    private var maxCount: Int { chartData.map(\.count).max() ?? 0 }
    private var yAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(maxCount))
    }
    private var yAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: yAxisMax,
            plottedMax: yAxisMax,
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                    Text(L("stats_retrievability_title"))
                        .amgiFont(.sectionHeading)
                        .foregroundStyle(Color.amgiTextPrimary)

                    Text(L("stats_retrievability_subtitle"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
                Spacer()
                Text(L("stats_ease_avg_fmt", averageLabel))
                    .amgiFont(.captionBold)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if chartData.allSatisfy({ $0.count == 0 }) {
                Text(L("stats_retrievability_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(chartData) { item in
                    BarMark(
                        x: .value("Retrievability", item.center),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle(bucketColor(for: item.center).gradient)

                    if let selectedBucket,
                       selectedBucket.start == item.start {
                        let countLabel = L("stats_card_count")
                        RuleMark(x: .value("Selected Retrievability", selectedBucket.center))
                            .foregroundStyle(Color.amgiAccent.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                                StatsChartTooltip(
                                    title: selectedBucket.label,
                                    lines: ["\(countLabel): \(selectedBucket.count)"]
                                )
                            }
                    }
                }
                .chartXScale(domain: 0...100)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        let plotFrame = geometry[proxy.plotAreaFrame]
                                        let plotX = value.location.x - plotFrame.origin.x
                                        guard plotX >= 0,
                                              plotX <= proxy.plotAreaSize.width,
                                              let retrievabilityValue: Double = proxy.value(atX: plotX)
                                        else {
                                            selectedBucketStart = nil
                                            return
                                        }

                                        let nearestBucket = chartData.min(by: {
                                            abs($0.center - retrievabilityValue) < abs($1.center - retrievabilityValue)
                                        })?.start
                                        selectedBucketStart = selectedBucketStart == nearestBucket ? nil : nearestBucket
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let v = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(v)%")
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...yAxisMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisTicks.map(\.plottedValue)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let raw = value.as(Double.self),
                           let tick = yAxisTicks.first(where: { abs($0.plottedValue - raw) < 0.0001 }) {
                            AxisValueLabel {
                                Text(tick.label)
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard(elevated: true)
    }

    private func bucketColor(for center: Double) -> Color {
        let progress = min(max(center / 100.0, 0), 1)
        return Color(hue: 0.02 + (0.30 * progress), saturation: 0.72, brightness: 0.9)
    }
}