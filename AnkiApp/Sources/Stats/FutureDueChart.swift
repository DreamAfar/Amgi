import SwiftUI
import Charts
import AnkiProto

struct FutureDueChart: View {
    let futureDue: Anki_Stats_GraphsResponse.FutureDue
    @State private var period: StatsPeriod = .month
    @State private var includeBacklog = false
    @State private var selectedDay: Int?

    private var xAxisDesiredTickCount: Int {
        switch period {
        case .day: return 3
        case .week: return 5
        case .month: return 6
        case .threeMonths: return 7
        case .year: return 8
        case .all: return 10
        }
    }

    private struct CumulativePoint: Identifiable {
        let id: Int
        let day: Int
        let cumulative: Int
    }

    private var filteredData: [(day: Int, count: Int)] {
        let maxDay = period.days
        return futureDue.futureDue
            .compactMap { (dayOffset, count) -> (day: Int, count: Int)? in
                let day = Int(dayOffset)
                if !includeBacklog && day < 0 { return nil }
                guard day < maxDay else { return nil }
                return (day: day, count: Int(count))
            }
            .sorted(by: { $0.day < $1.day })
    }

    private var totalDue: Int { filteredData.reduce(0) { $0 + $1.count } }
    private var maxDailyCount: Int { filteredData.map(\.count).max() ?? 0 }
    private var leftAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(maxDailyCount))
    }
    private var rightAxisMax: Double {
        StatsDualAxisSupport.niceUpperBound(Double(totalDue))
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
            domainMax: Double(totalDue),
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
    private var dueTomorrow: Int { filteredData.first(where: { $0.day == 1 })?.count ?? 0 }
    private var avgPerDay: Double {
        let positiveDays = filteredData.filter { $0.day >= 0 }
        guard !positiveDays.isEmpty else { return 0 }
        let maxOffset = positiveDays.map(\.day).max() ?? 1
        return Double(positiveDays.reduce(0) { $0 + $1.count }) / Double(max(maxOffset, 1))
    }

    private var barWidth: MarkDimension {
        if filteredData.count <= 30 { return .automatic }
        let w: Double = max(2.0, min(8.0, 280.0 / Double(filteredData.count)))
        return .fixed(w)
    }

    private var selectedPoint: CumulativePoint? {
        guard let selectedDay else { return nil }
        return cumulativePoints.first(where: { $0.day == selectedDay })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_future_due_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Text(L("stats_future_due_subtitle"))
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
            .onChange(of: period) { selectedDay = nil }

            if filteredData.isEmpty {
                Text(L("stats_future_due_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart {
                    ForEach(filteredData, id: \.day) { item in
                        BarMark(
                            x: .value("Day", item.day),
                            y: .value("Cards", item.count),
                            width: barWidth
                        )
                        .foregroundStyle(item.day < 0 ? Color.red.gradient : Color.blue.gradient)
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
                                    title: statsBarRangeLabel(start: selectedItem.day, bucketSize: 1),
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
                                        selectedDay = selectedDay == nearestDay ? nil : nearestDay
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: xAxisDesiredTickCount)) { value in
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

            if futureDue.haveBacklog {
                Toggle(L("stats_future_due_backlog"), isOn: $includeBacklog)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .amgiFont(.micro)
                    .controlSize(.mini)
                    .onChange(of: includeBacklog) { selectedDay = nil }
            }

            HStack(spacing: 0) {
                footerItem(L("stats_total"), value: "\(totalDue)")
                footerItem(L("stats_avg_day"), value: String(format: "%.1f", avgPerDay))
                footerItem(L("stats_future_due_tomorrow"), value: "\(dueTomorrow)")
                footerItem(L("stats_future_due_daily_load"), value: "\(futureDue.dailyLoad)")
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

