import SwiftUI
import Charts
import AnkiProto
struct RetrievabilityChart: View {
    @Environment(\.palette) private var palette

    let retrievability: Anki_Stats_GraphsResponse.Retrievability

    @State private var selectedBucketStart: Int?
    @State private var containerWidth: CGFloat = 390

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
        return StatsFormatSupport.percentValue(Double(retrievability.average))
    }

    private var estimatedKnowledgeLabel: String {
        L(
            "stats_retrievability_knowledge_fmt",
            StatsFormatSupport.count(Int(retrievability.sumByCard.rounded())),
            StatsFormatSupport.count(Int(retrievability.sumByNote.rounded()))
        )
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
    private var yAxisValues: [Double] {
        yAxisTicks.map(\.plottedValue)
    }

    private var barWidth: MarkDimension {
        StatsBarLayoutSupport.barWidth(
            slotCount: chartData.count,
            automaticThreshold: 12,
            availableWidth: containerWidth,
            minimum: 6,
            fillRatio: 0.84,
            maximumOverride: 16
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                    Text(L("stats_retrievability_title"))
                        .amgiFont(.sectionHeading)
                        .foregroundStyle(palette.textPrimary)

                    Text(L("stats_retrievability_subtitle"))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            if chartData.allSatisfy({ $0.count == 0 }) {
                Text(L("stats_retrievability_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                retrievabilityChart

                VStack(alignment: .leading, spacing: AmgiSpacing.xs) {
                    footerLine(L("stats_retrievability_average"), value: averageLabel)
                    footerLine(L("stats_retrievability_knowledge"), value: estimatedKnowledgeLabel)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .statsTrackWidth($containerWidth)
        .statsCard(elevated: true)
    }

    private var retrievabilityChart: some View {
        baseRetrievabilityChart
            .chartXScale(domain: 0...100)
            .chartOverlay { proxy in
                retrievabilityChartOverlay(proxy: proxy)
            }
            .chartXAxis {
                retrievabilityChartXAxis()
            }
            .chartYScale(domain: 0...yAxisMax)
            .chartYAxis {
                retrievabilityChartYAxis()
            }
            .frame(height: 180)
            .zIndex(selectedBucketStart == nil ? 0 : 1)
    }

    private var baseRetrievabilityChart: some View {
        Chart(chartData) { item in
            retrievabilityBarMark(for: item)
            selectedRetrievabilityRuleMark(for: item)
        }
    }

    @ChartContentBuilder
    private func retrievabilityBarMark(for item: Bucket) -> some ChartContent {
        BarMark(
            x: .value("Retrievability", item.center),
            y: .value("Cards", item.count),
            width: barWidth
        )
        .foregroundStyle(bucketColor(for: item.center).gradient)
    }

    @ChartContentBuilder
    private func selectedRetrievabilityRuleMark(for item: Bucket) -> some ChartContent {
        if let selectedBucket,
           selectedBucket.start == item.start {
            let countLabel = L("stats_card_count")
            RuleMark(x: .value("Selected Retrievability", selectedBucket.center))
                .foregroundStyle(palette.accent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                    StatsChartTooltip(
                        title: selectedBucket.label,
                        lines: ["\(countLabel): \(StatsFormatSupport.cards(selectedBucket.count))"]
                    )
                }
        }
    }

    @ViewBuilder
    private func retrievabilityChartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            let overlay = Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedBucketStart(
                                at: value.location,
                                proxy: proxy,
                                geometry: geometry,
                                togglesSelection: true
                            )
                        }
                )
            if selectedBucketStart != nil {
                overlay.simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.2)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value,
                                  StatsSelectionSupport.isHorizontalDrag(drag.translation)
                            else { return }

                            updateSelectedBucketStart(
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

    private func updateSelectedBucketStart(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        togglesSelection: Bool,
        emitFeedback: Bool = false
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            if togglesSelection {
                selectedBucketStart = nil
            }
            return
        }

        let plotFrame = geometry[plotFrameAnchor]
        let plotX = location.x - plotFrame.origin.x
        guard plotX >= 0,
              plotX <= proxy.plotSize.width,
              let retrievabilityValue: Double = proxy.value(atX: plotX)
        else {
            if togglesSelection {
                selectedBucketStart = nil
            }
            return
        }

        var nearestBucketStart: Int?
        var nearestDistance = Double.greatestFiniteMagnitude

        for item in chartData {
            let distance = Swift.abs(item.center - retrievabilityValue)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestBucketStart = item.start
            }
        }

        let nextSelection = togglesSelection && selectedBucketStart == nearestBucketStart ? nil : nearestBucketStart
        guard selectedBucketStart != nextSelection else { return }
        selectedBucketStart = nextSelection
        if emitFeedback, nextSelection != nil {
            StatsSelectionSupport.selectionChanged()
        }
    }

    @AxisContentBuilder
    private func retrievabilityChartXAxis() -> some AxisContent {
        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
            AxisGridLine()
                .foregroundStyle(palette.textTertiary.opacity(0.25))
            if let v = value.as(Int.self) {
                AxisValueLabel {
                    Text("\(v)%")
                        .amgiFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    @AxisContentBuilder
    private func retrievabilityChartYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: yAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(palette.textTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(StatsDualAxisSupport.label(for: raw, in: yAxisTicks))
                        .amgiFont(.micro)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private func bucketColor(for center: Double) -> Color {
        let progress = min(max(center / 100.0, 0), 1)
        return Color(hue: 0.02 + (0.30 * progress), saturation: 0.72, brightness: 0.9)
    }

    private func footerLine(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AmgiSpacing.xs) {
            Text("\(label)：")
                .amgiFont(.caption)
                .foregroundStyle(palette.textSecondary)
            Text(value)
                .amgiFont(.captionBold)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }
}
