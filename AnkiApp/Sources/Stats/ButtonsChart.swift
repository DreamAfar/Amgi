import SwiftUI
import Charts
import AnkiProto
struct ButtonsChart: View {
    let buttons: Anki_Stats_GraphsResponse.Buttons
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .year
    @State private var selectedBarKey: String?
    @State private var containerWidth: CGFloat = 390

    private var buttonCounts: Anki_Stats_GraphsResponse.Buttons.ButtonCounts {
        switch period {
        case .day, .week, .month: buttons.oneMonth
        case .threeMonths: buttons.threeMonths
        case .year: buttons.oneYear
        case .all: buttons.allTime
        }
    }

    private struct ButtonEntry: Identifiable {
        let id: String
        let buttonIndex: Int
        let typeIndex: Int
        let button: String
        let cardType: String
        let count: Int
    }

    private var buttonLabels: [String] {
        [L("review_rating_again"), L("review_rating_hard"), L("review_rating_good"), L("review_rating_easy")]
    }
    private var cardTypes: [String] {
        [L("stats_card_learn"), L("stats_card_young"), L("stats_card_mature")]
    }

    private var entries: [ButtonEntry] {
        let bc = buttonCounts
        let sources: [(String, [UInt32])] = [
            (L("stats_card_learn"), bc.learning),
            (L("stats_card_young"), bc.young),
            (L("stats_card_mature"), bc.mature),
        ]
        var result: [ButtonEntry] = []
        for (typeIndex, source) in sources.enumerated() {
            let (typeName, counts) = source
            for (index, count) in counts.prefix(4).enumerated() {
                if count > 0 {
                    result.append(ButtonEntry(
                        id: "\(index)-\(typeIndex)",
                        buttonIndex: index,
                        typeIndex: typeIndex,
                        button: buttonLabels[index],
                        cardType: typeName,
                        count: Int(count)
                    ))
                }
            }
        }
        return result
    }

    private var selectedEntry: ButtonEntry? {
        guard let selectedBarKey else { return nil }
        return entries.first(where: { $0.id == selectedBarKey })
    }

    private var maxCount: Int { entries.map(\.count).max() ?? 0 }
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
    private var yAxisValues: [Double] {
        yAxisTicks.map(\.plottedValue)
    }

    private var barWidth: MarkDimension {
        StatsBarLayoutSupport.barWidth(
            slotCount: max(entries.count, 4),
            automaticThreshold: 0,
            availableWidth: containerWidth,
            minimum: 8,
            fillRatio: 0.48
        )
    }

    private func totalForType(_ typeIndex: Int) -> Int {
        entries
            .filter { $0.typeIndex == typeIndex }
            .reduce(0) { $0 + $1.count }
    }

    private func correctCountsForType(_ typeIndex: Int) -> (correct: Int, total: Int) {
        let typeEntries = entries.filter { $0.typeIndex == typeIndex }
        let total = typeEntries.reduce(0) { $0 + $1.count }
        let correct = typeEntries.filter { $0.buttonIndex > 0 }.reduce(0) { $0 + $1.count }
        return (correct, total)
    }

    private func correctPercentForType(_ typeIndex: Int) -> Double {
        let counts = correctCountsForType(typeIndex)
        let total = counts.total
        guard total > 0 else { return 0 }
        return Double(counts.correct) / Double(total) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_buttons_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Text(L("stats_buttons_subtitle"))
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
                selectedBarKey = nil
            }
            .onChange(of: period) { selectedBarKey = nil }

            if entries.isEmpty {
                Text(L("stats_buttons_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                buttonsChart
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsTrackWidth($containerWidth)
        .statsCard(elevated: true)
    }

    private var buttonsColorScale: KeyValuePairs<String, Color> {
        [
            L("review_rating_again"): .red,
            L("review_rating_hard"): .orange,
            L("review_rating_good"): .green,
            L("review_rating_easy"): .blue,
        ]
    }

    @ViewBuilder
    private var buttonsChart: some View {
        baseButtonsChart
            .chartForegroundStyleScale(buttonsColorScale)
            .chartLegend(position: .bottom, alignment: .center, spacing: 8)
            .chartYScale(domain: 0...yAxisMax)
            .chartYAxis {
                buttonsChartYAxis()
            }
            .chartOverlay { proxy in
                buttonsChartOverlay(proxy: proxy)
            }
            .frame(height: 180)
            .zIndex(selectedBarKey == nil ? 0 : 1)
    }

    private var baseButtonsChart: some View {
        Chart(entries) { entry in
            buttonBarMark(for: entry)
            selectedButtonRuleMark(for: entry)
        }
    }

    @ChartContentBuilder
    private func buttonBarMark(for entry: ButtonEntry) -> some ChartContent {
        BarMark(
            x: .value("Type", entry.cardType),
            y: .value("Count", entry.count),
            width: barWidth
        )
        .position(by: .value("Button", entry.button))
        .foregroundStyle(by: .value("Button", entry.button))
    }

    @ChartContentBuilder
    private func selectedButtonRuleMark(for entry: ButtonEntry) -> some ChartContent {
        if let selectedEntry,
           selectedEntry.id == entry.id {
            PointMark(
                x: .value("Type", entry.cardType),
                y: .value("Count", entry.count)
            )
                .position(by: .value("Button", entry.button))
                .symbolSize(0)
                .foregroundStyle(.clear)
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                    StatsChartTooltip(
                        title: tooltipTitle(for: selectedEntry),
                        lines: tooltipLines(for: selectedEntry)
                    )
                }
        }
    }

    private func tooltipTitle(for entry: ButtonEntry) -> String {
        entry.cardType
    }

    private func tooltipLines(for entry: ButtonEntry) -> [String] {
        let total = totalForType(entry.typeIndex)
        let share = total > 0 ? Double(entry.count) / Double(total) * 100 : 0
        let shareText = StatsFormatSupport.percentText(share)
        let correctCounts = correctCountsForType(entry.typeIndex)
        let correctText = StatsFormatSupport.percentText(correctPercentForType(entry.typeIndex))

        return [
            L("stats_button_number_fmt", entry.buttonIndex + 1, entry.button),
            L("stats_button_times_pressed_fmt", StatsFormatSupport.count(entry.count), shareText),
            L(
                "stats_button_correct_fmt",
                StatsFormatSupport.count(correctCounts.correct),
                StatsFormatSupport.count(correctCounts.total),
                correctText
            )
        ]
    }

    @AxisContentBuilder
    private func buttonsChartYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: yAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: yAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func buttonsChartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let overlay = Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedBarKey(
                                at: value.location,
                                proxy: proxy,
                                geometry: geometry,
                                togglesSelection: true
                            )
                        }
                )
            if selectedBarKey != nil {
                overlay.simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.2)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value,
                                  StatsSelectionSupport.isHorizontalDrag(drag.translation)
                            else { return }

                            updateSelectedBarKey(
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

    private func updateSelectedBarKey(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        togglesSelection: Bool,
        emitFeedback: Bool = false
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        let plotX = location.x - plotFrame.origin.x
        guard plotX >= 0, plotX <= proxy.plotSize.width else {
            if togglesSelection {
                selectedBarKey = nil
            }
            return
        }

        let typeSlotWidth = proxy.plotSize.width / CGFloat(max(cardTypes.count, 1))
        let rawTypeIndex = Int(plotX / typeSlotWidth)
        let typeIndex = min(max(rawTypeIndex, 0), cardTypes.count - 1)
        let localX = plotX - CGFloat(typeIndex) * typeSlotWidth
        let buttonSlotWidth = typeSlotWidth / CGFloat(max(buttonLabels.count, 1))
        let rawButtonIndex = Int(localX / buttonSlotWidth)
        let buttonIndex = min(max(rawButtonIndex, 0), buttonLabels.count - 1)
        let key = "\(buttonIndex)-\(typeIndex)"

        let nextSelection = togglesSelection && selectedBarKey == key ? nil : key
        guard selectedBarKey != nextSelection else { return }
        selectedBarKey = nextSelection
        if emitFeedback, nextSelection != nil {
            StatsSelectionSupport.selectionChanged()
        }
    }
}
