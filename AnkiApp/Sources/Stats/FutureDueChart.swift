import SwiftUI
import Charts
import AnkiProto

struct FutureDueChart: View {
    let futureDue: Anki_Stats_GraphsResponse.FutureDue
    @State private var period: StatsPeriod = .month
    @State private var includeBacklog = false
    @State private var selectedDay: Int?

    private struct DisplayPoint: Identifiable {
        let startDay: Int
        let endDay: Int
        let count: Int

        var id: Int { startDay }
        var day: Int { startDay }
    }

    private struct CumulativePoint: Identifiable {
        let id: Int
        let startDay: Int
        let cumulative: Int
    }

    private var xAxisSpan: Int {
        max(1, xAxisUpperBound - xAxisLowerBound)
    }

    private var desiredBarCount: Int {
        let target: Int
        switch period {
        case .day:
            target = 1
        case .week:
            target = 7
        case .month:
            target = 45
        case .threeMonths:
            target = 72
        case .year:
            target = 96
        case .all:
            target = 120
        }
        return max(1, min(target, xAxisSpan))
    }

    private var dayBucketSize: Int {
        return max(1, Int(ceil(Double(xAxisSpan) / Double(desiredBarCount))))
    }

    private var displayedBucketCount: Int {
        let inclusiveSpan = max(1, xAxisUpperBound - xAxisLowerBound + 1)
        return max(1, Int(ceil(Double(inclusiveSpan) / Double(dayBucketSize))))
    }

    private var sortedDueCounts: [DisplayPoint] {
        futureDue.futureDue
            .map {
                let day = Int($0.key)
                return DisplayPoint(startDay: day, endDay: day, count: Int($0.value))
            }
            .sorted(by: { $0.day < $1.day })
    }

    private var rawMinDay: Int {
        min(sortedDueCounts.map(\.startDay).min() ?? 0, 0)
    }

    private var rawMaxDay: Int {
        max(sortedDueCounts.map(\.endDay).max() ?? 0, 0)
    }

    private func roundedDown(_ value: Int, step: Int) -> Int {
        guard step > 0 else { return value }
        return Int(floor(Double(value) / Double(step))) * step
    }

    private func roundedUp(_ value: Int, step: Int) -> Int {
        guard step > 0 else { return value }
        return Int(ceil(Double(value) / Double(step))) * step
    }

    private var xAxisUpperBound: Int {
        if includeBacklog {
            switch period {
            case .month:
                return 0
            case .threeMonths, .year:
                return 400
            case .all:
                return max(roundedUp(rawMaxDay, step: 100), 0)
            case .day, .week:
                return 0
            }
        }

        switch period {
        case .month:
            return 30
        case .threeMonths:
            return 90
        case .year:
            return 400
        case .all:
            return max(roundedUp(rawMaxDay, step: 500), 500)
        case .day:
            return 1
        case .week:
            return 7
        }
    }

    private var xAxisLowerBound: Int {
        if includeBacklog {
            return roundedDown(rawMinDay, step: 200)
        }
        return 0
    }

    private var xAxisDesiredTickCount: Int {
        switch period {
        case .month:
            return includeBacklog ? 4 : 6
        case .threeMonths:
            return includeBacklog ? 5 : 7
        case .year:
            return includeBacklog ? 5 : 8
        case .all:
            return includeBacklog ? 6 : 9
        case .day:
            return 2
        case .week:
            return 4
        }
    }

    private var xAxisTickValues: [Int] {
        let lower = xAxisLowerBound
        let upper = xAxisUpperBound
        let step = niceTickStep(lowerBound: lower, upperBound: upper, targetCount: xAxisDesiredTickCount)

        guard lower <= upper else { return [] }

        let start = Int(ceil(Double(lower) / Double(step))) * step
        var values = Array(stride(from: start, through: upper, by: step))

        if values.isEmpty {
            values = [lower, upper]
        }

        if upper == 0, !values.contains(0) {
            values.append(0)
        }

        return Array(Set(values.filter { $0 >= lower && $0 <= upper })).sorted()
    }

    private var filteredData: [DisplayPoint] {
        let lowerBound = xAxisLowerBound
        let upperBound = xAxisUpperBound
        let bucketSize = dayBucketSize
        var grouped: [Int: Int] = [:]

        for point in sortedDueCounts {
            guard point.day <= upperBound else { continue }
            if point.day < lowerBound {
                continue
            }
            let bucketStart: Int
            if bucketSize == 1 {
                bucketStart = point.day
            } else {
                let offset = point.day - lowerBound
                bucketStart = lowerBound + (offset / bucketSize) * bucketSize
            }
            grouped[bucketStart, default: 0] += point.count
        }

        return grouped.keys.sorted().map { startDay in
            let endDay = min(startDay + bucketSize - 1, upperBound)
            return DisplayPoint(startDay: startDay, endDay: endDay, count: grouped[startDay] ?? 0)
        }
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
            return CumulativePoint(id: item.startDay, startDay: item.startDay, cumulative: runningTotal)
        }
    }
    private var rightAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: Double(totalDue),
            plottedMax: leftAxisMax,
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }

    private var rightAxisValues: [Double] {
        rightAxisTicks.map(\.plottedValue)
    }

    private var leftAxisTicks: [StatsAxisTick] {
        StatsDualAxisSupport.ticks(
            domainMax: leftAxisMax,
            plottedMax: leftAxisMax,
            formatter: { value in StatsDualAxisSupport.formatCount(value) }
        )
    }

    private var leftAxisValues: [Double] {
        leftAxisTicks.map(\.plottedValue)
    }

    private func axisLabel(for raw: Double, in ticks: [StatsAxisTick]) -> String {
        StatsDualAxisSupport.label(for: raw, in: ticks)
    }
    private var dueTomorrow: Int { filteredData.first(where: { $0.day == 1 })?.count ?? 0 }
    private var avgPerDay: Double {
        let positiveDays = filteredData.filter { $0.day >= 0 }
        guard !positiveDays.isEmpty else { return 0 }
        let maxOffset = positiveDays.map(\.day).max() ?? 1
        return Double(positiveDays.reduce(0) { $0 + $1.count }) / Double(max(maxOffset, 1))
    }

    private var barWidth: MarkDimension {
        if displayedBucketCount <= 24 { return .automatic }
        let w: Double = max(1.5, min(6.0, 220.0 / Double(displayedBucketCount)))
        return .fixed(w)
    }

    private func niceTickStep(lowerBound: Int, upperBound: Int, targetCount: Int) -> Int {
        let span = max(1, upperBound - lowerBound)
        let rawStep = Double(span) / Double(max(targetCount, 1))
        let magnitude = pow(10.0, floor(log10(rawStep)))
        let normalized = rawStep / magnitude

        let multiplier: Double
        if normalized <= 1 {
            multiplier = 1
        } else if normalized <= 2 {
            multiplier = 2
        } else if normalized <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }

        return max(1, Int(multiplier * magnitude))
    }

    private func xAxisLabel(for day: Int) -> String {
        day.formatted(.number.grouping(.never))
    }

    private var selectedPoint: CumulativePoint? {
        guard let selectedDay else { return nil }
        return cumulativePoints.first(where: { $0.startDay == selectedDay })
    }

    private var selectedItem: DisplayPoint? {
        guard let selectedDay else { return nil }
        return filteredData.first(where: { $0.day == selectedDay })
    }

    private func plottedCumulative(_ value: Int) -> Double {
        StatsDualAxisSupport.plottedValue(
            Double(value),
            domainMax: rightAxisMax,
            plottedMax: leftAxisMax
        )
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
                futureDueChart
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

    private var futureDueChart: some View {
        baseFutureDueChart
            .chartXScale(domain: xAxisLowerBound...xAxisUpperBound)
            .chartOverlay { proxy in
                futureDueChartOverlay(proxy: proxy)
            }
            .chartXAxis {
                futureDueChartXAxis()
            }
            .chartYScale(domain: 0...leftAxisMax)
            .chartYAxis {
                futureDueChartYAxis()
            }
            .frame(height: 200)
    }

    private var baseFutureDueChart: some View {
        Chart {
            futureDueBarMarks()
            futureDueCumulativeMarks()
            selectedFutureDueRuleMark()
        }
    }

    @ChartContentBuilder
    private func futureDueBarMarks() -> some ChartContent {
        ForEach(filteredData) { item in
            BarMark(
                x: .value("Day", item.startDay),
                y: .value("Cards", item.count),
                width: barWidth
            )
            .foregroundStyle(item.endDay < 0 ? Color.red.gradient : Color.blue.gradient)
        }
    }

    @ChartContentBuilder
    private func futureDueCumulativeMarks() -> some ChartContent {
        ForEach(cumulativePoints) { point in
            AreaMark(
                x: .value("Day", point.startDay),
                y: .value("Cumulative", plottedCumulative(point.cumulative))
            )
            .foregroundStyle(Color.amgiTextSecondary.opacity(0.08))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Day", point.startDay),
                y: .value("Cumulative", plottedCumulative(point.cumulative)),
                series: .value("Series", "cumulative")
            )
            .foregroundStyle(Color.amgiTextSecondary.opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func selectedFutureDueRuleMark() -> some ChartContent {
        if let selectedDay,
           let selectedItem,
           let selectedPoint {
            let countLabel = L("stats_card_count")
            let cumulativeLabel = L("stats_reviews_cumulative")
            RuleMark(x: .value("Selected Day", selectedDay))
                .foregroundStyle(Color.amgiAccent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                    StatsChartTooltip(
                        title: statsBarRangeLabel(
                            start: selectedItem.startDay,
                            bucketSize: selectedItem.endDay - selectedItem.startDay + 1
                        ),
                        lines: [
                            "\(countLabel): \(selectedItem.count)",
                            "\(cumulativeLabel): \(selectedPoint.cumulative)"
                        ]
                    )
                }
        }
    }

    @ViewBuilder
    private func futureDueChartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedDay(for: value, proxy: proxy, geometry: geometry)
                        }
                )
        }
    }

    private func updateSelectedDay(
        for value: SpatialTapGesture.Value,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        let plotX = value.location.x - plotFrame.origin.x
        guard plotX >= 0,
              plotX <= proxy.plotSize.width,
              let day: Int = proxy.value(atX: plotX)
        else {
            selectedDay = nil
            return
        }

        var nearestDay: Int?
        var nearestDistance = Int.max

        for item in filteredData {
            let distance = Swift.abs(item.startDay - day)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestDay = item.startDay
            }
        }

        selectedDay = selectedDay == nearestDay ? nil : nearestDay
    }

    @AxisContentBuilder
    private func futureDueChartXAxis() -> some AxisContent {
        AxisMarks(values: xAxisTickValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
            if let day = value.as(Int.self) {
                AxisValueLabel {
                    Text(xAxisLabel(for: day))
                        .amgiFont(.micro)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
    }

    @AxisContentBuilder
    private func futureDueChartYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: leftAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(axisLabel(for: raw, in: leftAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }

        AxisMarks(position: .trailing, values: rightAxisValues) { value in
            AxisTick()
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.35))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(axisLabel(for: raw, in: rightAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
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

