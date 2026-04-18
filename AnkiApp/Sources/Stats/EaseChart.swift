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
        if isFSRS {
            return String(format: "%.0f%%", activeData.average / 10)
        } else {
            return String(format: "%.0f%%", activeData.average / 10)
        }
    }

    private var selectedItem: (ease: Int, count: Int)? {
        guard let selectedEase else { return nil }
        return chartData.first(where: { $0.ease == selectedEase })
    }

    private var xAxisDesiredTickCount: Int {
        min(8, max(4, chartData.count))
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
                Chart(chartData, id: \.ease) { item in
                    BarMark(
                        x: .value("Ease", item.ease),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle((isFSRS ? Color.red : Color.indigo).gradient)

                    if let selectedItem,
                       selectedItem.ease == item.ease {
                        let countLabel = L("stats_card_count")
                        RuleMark(x: .value("Selected Ease", selectedItem.ease))
                            .foregroundStyle(Color.amgiAccent.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                                StatsChartTooltip(
                                    title: "\(selectedItem.ease / 10)%",
                                    lines: ["\(countLabel): \(selectedItem.count)"]
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
                                SpatialTapGesture()
                                    .onEnded { value in
                                        let plotFrame = geometry[proxy.plotAreaFrame]
                                        let plotX = value.location.x - plotFrame.origin.x
                                        guard plotX >= 0, plotX <= proxy.plotAreaSize.width,
                                              let ease: Int = proxy.value(atX: plotX)
                                        else {
                                            selectedEase = nil
                                            return
                                        }

                                        let nearestEase = chartData.min(by: {
                                            abs($0.ease - ease) < abs($1.ease - ease)
                                        })?.ease
                                        selectedEase = selectedEase == nearestEase ? nil : nearestEase
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: xAxisDesiredTickCount)) { value in
                        AxisGridLine()
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let v = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(v / 10)%")
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
}
