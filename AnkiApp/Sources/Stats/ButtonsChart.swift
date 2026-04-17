import SwiftUI
import Charts
import AnkiProto

struct ButtonsChart: View {
    let buttons: Anki_Stats_GraphsResponse.Buttons
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .year
    @State private var selectedBarKey: String?

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

    private func totalForType(_ typeIndex: Int) -> Int {
        entries
            .filter { $0.typeIndex == typeIndex }
            .reduce(0) { $0 + $1.count }
    }

    private func correctPercentForType(_ typeIndex: Int) -> Double {
        let typeEntries = entries.filter { $0.typeIndex == typeIndex }
        let total = typeEntries.reduce(0) { $0 + $1.count }
        guard total > 0 else { return 0 }
        let correct = typeEntries.filter { $0.buttonIndex > 0 }.reduce(0) { $0 + $1.count }
        return Double(correct) / Double(total) * 100
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
            .pickerStyle(.segmented)
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
        .amgiCard(elevated: true)
    }

    @ViewBuilder
    private var buttonsChart: some View {
        let colorScale: KeyValuePairs<String, Color> = [
            L("stats_card_learn"):  .blue,
            L("stats_card_young"):  .green,
            L("stats_card_mature"): .purple,
        ]
        Chart(entries) { entry in
            BarMark(
                x: .value("Button", entry.button),
                y: .value("Count", entry.count)
            )
            .foregroundStyle(by: .value("Type", entry.cardType))

            if let selectedEntry,
               selectedEntry.id == entry.id {
                let countLabel = L("stats_card_count")
                let correctLabel = L("stats_today_correct")
                let shareText = String(format: "%.1f%%", share)
                let correctText = String(format: "%.1f%%", correctPercentForType(selectedEntry.typeIndex))
                RuleMark(x: .value("Selected Button", entry.button))
                    .foregroundStyle(Color.amgiAccent.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit, y: .fit)) {
                        let total = totalForType(selectedEntry.typeIndex)
                        let share = total > 0 ? Double(selectedEntry.count) / Double(total) * 100 : 0
                        StatsChartTooltip(
                            title: "\(selectedEntry.button) • \(selectedEntry.cardType)",
                            lines: [
                                "\(countLabel): \(selectedEntry.count) (\(shareText))",
                                "\(correctLabel): \(correctText)"
                            ]
                        )
                    }
            }
        }
        .chartForegroundStyleScale(colorScale)
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
                                guard plotX >= 0, plotX <= proxy.plotAreaSize.width else {
                                    selectedBarKey = nil
                                    return
                                }

                                let buttonSlotWidth = proxy.plotAreaSize.width / CGFloat(max(buttonLabels.count, 1))
                                let rawButtonIndex = Int(plotX / buttonSlotWidth)
                                let buttonIndex = min(max(rawButtonIndex, 0), buttonLabels.count - 1)
                                let localX = plotX - CGFloat(buttonIndex) * buttonSlotWidth
                                let typeSlotWidth = buttonSlotWidth / CGFloat(max(cardTypes.count, 1))
                                let rawTypeIndex = Int(localX / typeSlotWidth)
                                let typeIndex = min(max(rawTypeIndex, 0), cardTypes.count - 1)
                                let key = "\(buttonIndex)-\(typeIndex)"

                                selectedBarKey = selectedBarKey == key ? nil : key
                            }
                    )
            }
        }
        .frame(height: 180)
    }
}
