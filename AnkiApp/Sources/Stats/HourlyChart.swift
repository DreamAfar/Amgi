import SwiftUI
import Charts
import AnkiProto

struct HourlyChart: View {
    let hours: Anki_Stats_GraphsResponse.Hours
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .year
    @State private var selectedHour: Int?

    private var hourData: [Anki_Stats_GraphsResponse.Hours.Hour] {
        switch period {
        case .day, .week, .month: return hours.oneMonth
        case .threeMonths:        return hours.threeMonths
        case .year:               return hours.oneYear
        case .all:                return hours.allTime
        }
    }

    private struct HourEntry: Identifiable {
        let id: Int
        let hour: Int
        let total: Int
        let correct: Int
        let correctPct: Double
    }

    private var entries: [HourEntry] {
        let data = hourData
        guard data.count == 24 else {
            return (0..<24).map { HourEntry(id: $0, hour: $0, total: 0, correct: 0, correctPct: 0) }
        }
        return data.enumerated().map { index, hour in
            let pct = hour.total > 0 ? Double(hour.correct) / Double(hour.total) * 100 : 0
            return HourEntry(id: index, hour: index, total: Int(hour.total), correct: Int(hour.correct), correctPct: pct)
        }
    }

    private var selectedEntry: HourEntry? {
        guard let selectedHour else { return nil }
        return entries.first(where: { $0.hour == selectedHour })
    }

    private var isEmpty: Bool { entries.allSatisfy { $0.total == 0 } }
    private var maxReviewCount: Int { entries.map(\.total).max() ?? 0 }
    private var leftAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(maxReviewCount))
    }
    private var rightAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(100)
    }
    private var rightAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: 100,
            plottedMax: leftAxisMax,
            formatter: { value in "\(Int(value.rounded()))%" }
        )
    }
    private var leftAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: leftAxisMax,
            plottedMax: leftAxisMax,
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_hourly_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Text(L("stats_hourly_subtitle"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)

            Picker("", selection: $period) {
                ForEach(revlogRange.allowedStatsPeriods, id: \.self) { allowedPeriod in
                    Text(allowedPeriod.localizedLabel).tag(allowedPeriod)
                }
            }
            .amgiSegmentedPicker()
            .amgiFont(.micro)
            .onChange(of: revlogRange) {
                if !revlogRange.allowedStatsPeriods.contains(period) {
                    period = revlogRange.defaultStatsPeriod
                }
                selectedHour = nil
            }
            .onChange(of: period) { selectedHour = nil }

            if isEmpty {
                Text(L("stats_hourly_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(entries) { entry in
                        BarMark(
                            x: .value("Hour", entry.hour),
                            y: .value(L("stats_hourly_reviews"), entry.total),
                            width: .fixed(9)
                        )
                        .foregroundStyle(
                            Color(hue: 0.58, saturation: 0.5 + 0.5 * Double(entry.total) / Double(max(maxReviewCount, 1)), brightness: 0.7).gradient
                        )
                    }

                    ForEach(entries) { entry in
                        AreaMark(
                            x: .value("Hour", entry.hour),
                            y: .value(
                                L("stats_hourly_correct_pct"),
                                StatsDualAxisSupport.plottedValue(
                                    entry.correctPct,
                                    domainMax: rightAxisMax,
                                    plottedMax: leftAxisMax
                                )
                            )
                        )
                        .foregroundStyle(Color.amgiTextSecondary.opacity(0.08))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Hour", entry.hour),
                            y: .value(
                                L("stats_hourly_correct_pct"),
                                StatsDualAxisSupport.plottedValue(
                                    entry.correctPct,
                                    domainMax: rightAxisMax,
                                    plottedMax: leftAxisMax
                                )
                            ),
                            series: .value("Series", "pct")
                        )
                        .foregroundStyle(.green.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.catmullRom)
                    }

                    if let selectedEntry {
                        let reviewsLabel = L("stats_hourly_reviews")
                        let correctLabel = L("stats_hourly_correct_pct")
                        let correctText = String(format: "%.1f%%", selectedEntry.correctPct)
                        RuleMark(x: .value("Selected Hour", selectedEntry.hour))
                            .foregroundStyle(Color.amgiAccent.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                                StatsChartTooltip(
                                    title: "\(selectedEntry.hour)-\(selectedEntry.hour + 1)",
                                    lines: [
                                        "\(reviewsLabel): \(selectedEntry.total)",
                                        "\(correctLabel): \(correctText) (\(selectedEntry.correct)/\(selectedEntry.total))"
                                    ]
                                )
                            }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        let plotFrame = geometry[proxy.plotAreaFrame]
                                        let plotX = value.location.x - plotFrame.origin.x
                                        guard plotX >= 0, plotX <= proxy.plotAreaSize.width,
                                              let hour: Int = proxy.value(atX: plotX)
                                        else {
                                            selectedHour = nil
                                            return
                                        }

                                        let nearestHour = entries.min(by: {
                                            abs($0.hour - hour) < abs($1.hour - hour)
                                        })?.hour
                                        selectedHour = selectedHour == nearestHour ? nil : nearestHour
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: Array(0...23)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.2))
                        if let h = value.as(Int.self) {
                            AxisValueLabel(formatHour(h))
                                .font(AmgiFont.micro.font)
                                .foregroundStyle(Color.amgiTextSecondary.opacity(h % 2 == 0 ? 1 : 0.55))
                        }
                    }
                }
                .chartXScale(domain: 0...23)
                .chartYScale(domain: 0...leftAxisMax)
                .chartYAxis {
                    AxisMarks(position: .leading, values: leftAxisTicks.map(\.plottedValue)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let raw = value.as(Double.self),
                           let tick = leftAxisTicks.first(where: { abs($0.plottedValue - raw) < 0.0001 }) {
                            AxisValueLabel {
                                Text(tick.label)
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }

                    AxisMarks(position: .trailing, values: rightAxisTicks.map(\.plottedValue)) { value in
                        if let raw = value.as(Double.self),
                           let tick = rightAxisTicks.first(where: { abs($0.plottedValue - raw) < 0.0001 }) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard(elevated: true)
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0  { return "0" }
        if hour == 12 { return "12" }
        return "\(hour)"
    }
}
