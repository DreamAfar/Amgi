import SwiftUI
import Charts
import AnkiProto
struct AddedChart: View {
    let added: Anki_Stats_GraphsResponse.Added
    @State private var period: StatsPeriod = .month
    @State private var selectedDay: Int?
    @State private var containerWidth: CGFloat = 390

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

    private var xAxisMin: Int {
        let periodMin: Int
        switch period {
        case .day:
            periodMin = -1
        case .week:
            periodMin = -6
        case .month:
            periodMin = -30
        case .threeMonths:
            periodMin = -89
        case .year:
            periodMin = -364
        case .all:
            return min(filteredData.map(\.day).min() ?? -30, -1)
        }
        return periodMin
    }

    private var filteredData: [(day: Int, count: Int)] {
        let maxDay = period.days
        let bkt = bucketSize
        var buckets: [Int: Int] = [:]
        for (dayOffset, count) in added.added {
            let day = Int(dayOffset)
            guard day <= 0, Swift.abs(day) <= maxDay else { continue }
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
    private var barWidth: MarkDimension {
        StatsBarLayoutSupport.barWidth(
            slotCount: StatsBarLayoutSupport.displayedSlotCount(
                lowerBound: xAxisMin,
                upperBound: 0,
                bucketSize: bucketSize
            ),
            availableWidth: containerWidth
        )
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
    private var leftAxisValues: [Double] {
        leftAxisTicks.map(\.plottedValue)
    }
    private var rightAxisValues: [Double] {
        rightAxisTicks.map(\.plottedValue)
    }
    private var avgPerDay: Double {
        Double(totalAdded) / Double(periodDayCount)
    }
    private var periodDayCount: Int { max(Swift.abs(xAxisMin) + 1, 1) }
    private var selectedPoint: CumulativePoint? {
        guard let selectedDay else { return nil }
        return cumulativePoints.first(where: { $0.day == selectedDay })
    }
    private var selectedBar: (day: Int, count: Int)? {
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
                addedChart()
            }

            HStack(spacing: AmgiSpacing.lg) {
                footerItem(L("stats_total"), value: StatsFormatSupport.cards(totalAdded))
                footerItem(L("stats_avg_day"), value: StatsFormatSupport.cardsPerDay(avgPerDay))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsTrackWidth($containerWidth)
        .statsCard(elevated: true)
    }

    @ViewBuilder
    private func addedChart() -> some View {
        baseAddedChart
            .chartOverlay { proxy in
                addedChartOverlay(proxy: proxy)
            }
            .chartXScale(domain: xAxisMin...0)
            .chartXAxis {
                addedChartXAxis()
            }
            .chartYScale(domain: 0...leftAxisMax)
            .chartYAxis {
                addedChartYAxis()
            }
            .frame(height: 200)
            .zIndex(selectedDay == nil ? 0 : 1)
    }

    private var baseAddedChart: some View {
        Chart {
            addedBarMarks()
            addedCumulativeMarks()
            selectedDayRuleMark()
        }
    }

    @ChartContentBuilder
    private func addedBarMarks() -> some ChartContent {
        ForEach(filteredData, id: \.day) { item in
            BarMark(
                x: .value("Day", item.day),
                y: .value("Cards", item.count),
                width: barWidth
            )
            .foregroundStyle(Color.amgiInfo.gradient)
        }
    }

    @ChartContentBuilder
    private func addedCumulativeMarks() -> some ChartContent {
        ForEach(cumulativePoints) { point in
            let plottedValue = plottedCumulative(point.cumulative)

            AreaMark(
                x: .value("Day", point.day),
                y: .value("Cumulative", plottedValue)
            )
            .foregroundStyle(Color.amgiTextSecondary.opacity(0.08))
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Day", point.day),
                y: .value("Cumulative", plottedValue),
                series: .value("Series", "cumulative")
            )
            .foregroundStyle(Color.amgiTextSecondary.opacity(0.45))
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func selectedDayRuleMark() -> some ChartContent {
        if let selectedDay,
           let selectedBar,
           let selectedPoint {
            let countLabel = L("stats_card_count")
            let cumulativeLabel = L("stats_reviews_cumulative")
            RuleMark(x: .value("Selected Day", selectedDay))
                .foregroundStyle(Color.amgiAccent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                    StatsChartTooltip(
                        title: statsBarRangeLabel(start: selectedBar.day, bucketSize: bucketSize),
                        lines: [
                            "\(countLabel): \(StatsFormatSupport.cards(selectedBar.count))",
                            "\(cumulativeLabel): \(StatsFormatSupport.cards(selectedPoint.cumulative))"
                        ]
                    )
                }
        }
    }

    @ViewBuilder
    private func addedChartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let overlay = Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedDay(
                                at: value.location,
                                proxy: proxy,
                                geometry: geometry,
                                togglesSelection: true
                            )
                        }
                )
            if selectedDay != nil {
                overlay.simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.2)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value,
                                  StatsSelectionSupport.isHorizontalDrag(drag.translation)
                            else { return }

                            updateSelectedDay(
                                at: drag.location,
                                proxy: proxy,
                                geometry: geometry,
                                togglesSelection: false,
                                emitFeedback: true
                            )
                        }
                )
            } else {
                overlay
            }
        }
    }

    private func updateSelectedDay(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        togglesSelection: Bool,
        emitFeedback: Bool = false
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            if togglesSelection {
                selectedDay = nil
            }
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        let plotX = location.x - plotFrame.origin.x

        guard plotX >= 0,
              plotX <= proxy.plotSize.width,
              let day: Int = proxy.value(atX: plotX)
        else {
            if togglesSelection {
                selectedDay = nil
            }
            return
        }

        var nearestDay: Int?
        var nearestDistance = Int.max

        for item in filteredData {
            let distance = Swift.abs(item.day - day)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestDay = item.day
            }
        }

        let nextSelection = togglesSelection && selectedDay == nearestDay ? nil : nearestDay
        guard selectedDay != nextSelection else { return }
        selectedDay = nextSelection
        if emitFeedback, nextSelection != nil {
            StatsSelectionSupport.selectionChanged()
        }
    }

    @AxisContentBuilder
    private func addedChartXAxis() -> some AxisContent {
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

    @AxisContentBuilder
    private func addedChartYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: leftAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: leftAxisTicks))
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
                    Text(StatsDualAxisSupport.label(for: raw, in: rightAxisTicks))
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
