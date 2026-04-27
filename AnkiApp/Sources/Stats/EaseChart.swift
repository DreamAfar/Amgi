import SwiftUI
import Charts
import AnkiProto

struct EaseChart: View {
    let eases: Anki_Stats_GraphsResponse.Eases
    let difficulty: Anki_Stats_GraphsResponse.Eases
    let isFSRS: Bool
    @State private var selectedEase: Int?

    /// Active dataset: difficulty for FSRS decks, eases for SM-2
    private var activeData: Anki_Stats_GraphsResponse.Eases {
        isFSRS ? difficulty : eases
    }

    private var chartData: [(ease: Int, count: Int)] {
        activeData.eases
            .map { (ease: Int($0.key), count: Int($0.value)) }
            .sorted(by: { $0.ease < $1.ease })
    }

    private var averageEase: String {
        guard activeData.average > 0 else { return "---" }
        return String(format: "%.0f%%", activeData.average)
    }

    private var selectedItem: (ease: Int, count: Int)? {
        guard let selectedEase else { return nil }
        return chartData.first(where: { $0.ease == selectedEase })
    }

    private var xAxisDesiredTickCount: Int {
        min(8, max(4, chartData.count))
    }

    private var xAxisLowerBound: Int {
        isFSRS ? 0 : 130
    }

    private var xAxisUpperBound: Int {
        if isFSRS {
            return 100
        }
        return max(300, (chartData.last?.ease ?? 300) + 10)
    }

    private var xAxisValues: [Int] {
        if isFSRS {
            return Array(stride(from: 0, through: 100, by: 20))
        }
        let step = max(20, ((xAxisUpperBound - xAxisLowerBound) / xAxisDesiredTickCount / 10) * 10)
        let values = Array(stride(from: xAxisLowerBound, through: xAxisUpperBound, by: step))
        return values.isEmpty ? [xAxisLowerBound, xAxisUpperBound] : values
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

    private func yAxisLabel(for raw: Double) -> String {
        StatsDualAxisSupport.label(for: raw, in: yAxisTicks)
    }

    private func difficultyColor(for value: Int) -> Color {
        let clamped = max(0, min(100, value))
        let normalized = Double(clamped) / 100
        let start: UIColor
        let end: UIColor
        let progress: Double

        if normalized <= 0.5 {
            start = UIColor(red: 0.20, green: 0.68, blue: 0.34, alpha: 1)
            end = UIColor(red: 0.96, green: 0.78, blue: 0.24, alpha: 1)
            progress = normalized / 0.5
        } else {
            start = UIColor(red: 0.96, green: 0.78, blue: 0.24, alpha: 1)
            end = UIColor(red: 0.84, green: 0.25, blue: 0.21, alpha: 1)
            progress = (normalized - 0.5) / 0.5
        }

        var startRed: CGFloat = 0
        var startGreen: CGFloat = 0
        var startBlue: CGFloat = 0
        var startAlpha: CGFloat = 0
        var endRed: CGFloat = 0
        var endGreen: CGFloat = 0
        var endBlue: CGFloat = 0
        var endAlpha: CGFloat = 0
        start.getRed(&startRed, green: &startGreen, blue: &startBlue, alpha: &startAlpha)
        end.getRed(&endRed, green: &endGreen, blue: &endBlue, alpha: &endAlpha)

        let mix = CGFloat(progress)
        return Color(
            red: Double(startRed + (endRed - startRed) * mix),
            green: Double(startGreen + (endGreen - startGreen) * mix),
            blue: Double(startBlue + (endBlue - startBlue) * mix),
            opacity: Double(startAlpha + (endAlpha - startAlpha) * mix)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: AmgiSpacing.xxs) {
                    Text(isFSRS ? L("stats_difficulty_title") : L("stats_ease_title"))
                        .amgiFont(.sectionHeading)
                        .foregroundStyle(Color.amgiTextPrimary)

                    Text(isFSRS ? L("stats_difficulty_subtitle") : L("stats_ease_subtitle"))
                        .amgiFont(.caption)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
                Spacer()
                Text(L("stats_ease_avg_fmt", averageEase))
                    .amgiFont(.captionBold)
                    .foregroundStyle(Color.amgiTextSecondary)
            }

            if chartData.isEmpty {
                Text(L("stats_ease_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                easeChart()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard(elevated: true)
    }

    @ViewBuilder
    private func easeChart() -> some View {
        baseEaseChart
            .chartXScale(domain: xAxisLowerBound...xAxisUpperBound)
            .chartOverlay { proxy in
                easeChartOverlay(proxy: proxy)
            }
            .chartXAxis {
                easeChartXAxis()
            }
            .chartYScale(domain: 0...yAxisMax)
            .chartYAxis {
                easeChartYAxis()
            }
            .frame(height: 180)
    }

    private var baseEaseChart: some View {
        Chart {
            easeBarMarks()
            selectedEaseRuleMark()
        }
    }

    @ViewBuilder
    private func easeChartOverlay(proxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            updateSelectedEase(for: value, proxy: proxy, geometry: geometry)
                        }
                )
        }
    }

    private func updateSelectedEase(
        for value: SpatialTapGesture.Value,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        let plotX = value.location.x - plotFrame.origin.x
        guard plotX >= 0,
              plotX <= proxy.plotSize.width,
              let ease: Int = proxy.value(atX: plotX)
        else {
            selectedEase = nil
            return
        }

        var nearestEase: Int?
        var nearestDistance = Int.max

        for item in chartData {
            let distance = Swift.abs(item.ease - ease)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestEase = item.ease
            }
        }

        selectedEase = selectedEase == nearestEase ? nil : nearestEase
    }

    @AxisContentBuilder
    private func easeChartXAxis() -> some AxisContent {
        AxisMarks(values: xAxisValues) { value in
            AxisGridLine()
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
            if let axisValue = value.as(Int.self) {
                AxisValueLabel {
                    Text("\(axisValue)%")
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
    }

    @AxisContentBuilder
    private func easeChartYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: yAxisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))

            AxisValueLabel {
                if let raw = value.as(Double.self) {
                    Text(yAxisLabel(for: raw))
                        .amgiFont(.micro)
                        .foregroundStyle(Color.amgiTextSecondary)
                }
            }
        }
    }

    @ChartContentBuilder
    private func easeBarMarks() -> some ChartContent {
        ForEach(chartData, id: \.ease) { item in
            BarMark(
                x: .value("Ease", item.ease),
                y: .value("Cards", item.count)
            )
            .foregroundStyle((isFSRS ? difficultyColor(for: item.ease) : Color.indigo).gradient)
        }
    }

    @ChartContentBuilder
    private func selectedEaseRuleMark() -> some ChartContent {
        if let selectedItem {
            let countLabel = L("stats_card_count")
            RuleMark(x: .value("Selected Ease", selectedItem.ease))
                .foregroundStyle(Color.amgiAccent.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                    StatsChartTooltip(
                        title: "\(selectedItem.ease)%",
                        lines: ["\(countLabel): \(selectedItem.count)"]
                    )
                }
        }
    }
}
