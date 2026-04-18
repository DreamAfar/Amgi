import SwiftUI
import Charts
import AnkiProto

struct AddedChart: View {
    let added: Anki_Stats_GraphsResponse.Added
    @State private var period: StatsPeriod = .month
    @State private var selectedDay: Int?

    private struct CumulativePoint: Identifiable {
        let id: Int
        let day: Int
        let cumulative: Int
    }

    /// Number of days per bar bucket — capped at ~70 bars
    private var bucketSize: Int {
        switch period {
        case .day, .week, .month: return 1
        case .threeMonths: return 7
        case .year, .all: return 30
        }
    }

    private var filteredData: [(day: Int, count: Int)] {
        let maxDay = period.days
        let bkt = bucketSize
        var buckets: [Int: Int] = [:]
        for (dayOffset, count) in added.added {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) <= maxDay else { continue }
            let bucket = bkt == 1 ? day : -((-day) / bkt * bkt)
            buckets[bucket, default: 0] += Int(count)
        }
        return buckets.map { (day: $0.key, count: $0.value) }
            .sorted(by: { $0.day < $1.day })
    }

    private var totalAdded: Int { filteredData.reduce(0) { $0 + $1.count } }
    private var maxDailyCount: Int { filteredData.map(\.count).max() ?? 0 }
    private var leftAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(maxDailyCount))
    }
    private var rightAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(totalAdded))
    }
    private var cumulativePoints: [CumulativePoint] {
        var runningTotal = 0
        return filteredData.map { item in
            runningTotal += item.count
            return CumulativePoint(id: item.day, day: item.day, cumulative: runningTotal)
        }
    }
    private var rightAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: Double(totalAdded),
            plottedMax: leftAxisMax,
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }
    private var leftAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: leftAxisMax,
            plottedMax: leftAxisMax,
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }
    private var avgPerDay: Double {
        guard !filteredData.isEmpty else { return 0 }
        let span = filteredData.count * bucketSize
        return Double(totalAdded) / Double(max(span, 1))
    }
    private var selectedPoint: CumulativePoint? {
        guard let selectedDay else { return nil }
        return cumulativePoints.first(where: { $0.day == selectedDay })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_added_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Text(L("stats_added_subtitle"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)

            Picker("", selection: $period) {
                Text(L("stats_period_month")).tag(StatsPeriod.month)
                Text(L("stats_period_3months")).tag(StatsPeriod.threeMonths)
                Text(L("stats_period_year")).tag(StatsPeriod.year)
                Text(L("stats_period_all")).tag(StatsPeriod.all)
            }
            .amgiSegmentedPicker()
            .amgiFont(.micro)

            if filteredData.isEmpty {
                Text(L("stats_added_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(filteredData, id: \.day) { item in
                        let bw: Double = filteredData.count <= 30 ? 0 : max(2.0, min(8.0, 280.0 / Double(filteredData.count)))
                        let barW: MarkDimension = filteredData.count <= 30 ? .automatic : .fixed(bw)
                        BarMark(
                            x: .value("Day", item.day),
                            y: .value("Cards", item.count),
                            width: barW
                        )
                        .foregroundStyle(Color.amgiInfo.gradient)
                    }

                    ForEach(cumulativePoints) { point in
                        AreaMark(
                            x: .value("Day", point.day),
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
                            x: .value("Day", point.day),
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

                    if let selectedDay,
                       let selectedItem = filteredData.first(where: { $0.day == selectedDay }),
                       let selectedPoint {
                        let countLabel = L("stats_card_count")
                        let cumulativeLabel = L("stats_reviews_cumulative")
                        RuleMark(x: .value("Selected Day", selectedDay))
                            .foregroundStyle(Color.amgiAccent.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                                StatsChartTooltip(
                                    title: statsBarRangeLabel(start: selectedItem.day, bucketSize: bucketSize),
                                    lines: [
                                        "\(countLabel): \(selectedItem.count)",
                                        "\(cumulativeLabel): \(selectedPoint.cumulative)"
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
                                              let day: Int = proxy.value(atX: plotX)
                                        else {
                                            selectedDay = nil
                                            return
                                        }

                                        let nearestDay = filteredData.min(by: {
                                            abs($0.day - day) < abs($1.day - day)
                                        })?.day

                                        if selectedDay == nearestDay {
                                            selectedDay = nil
                                        } else {
                                            selectedDay = nearestDay
                                        }
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let day = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(day)")
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
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

            HStack(spacing: AmgiSpacing.lg) {
                footerItem(L("stats_total"), value: "\(totalAdded)")
                footerItem(L("stats_avg_day"), value: String(format: "%.1f", avgPerDay))
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
}