//
//  ButtonsChart.swift
//  StatsCharts
//
//  Created by Vladimir Gusev on 30.03.2026.
//

public import SwiftUI
import Theme
import UI
import Charts
public import AnkiKit

public struct ButtonsChart: View {
    let buttons: ButtonsBuckets
    let period: StatsPeriod

    public init(buttons: ButtonsBuckets, period: StatsPeriod) {
        self.buttons = buttons
        self.period = period
    }

    @Environment(\.palette) private var palette
    @State private var selectedGroup: String?

    private var buttonCounts: ButtonsBuckets.ButtonCounts {
        switch period {
        case .day, .week, .month: buttons.oneMonth
        case .threeMonths: buttons.threeMonths
        case .year: buttons.oneYear
        case .all: buttons.allTime
        }
    }

    fileprivate struct ButtonEntry: Identifiable {
        /// Stable across rebuilds — Charts diffs marks by `id`, and a fresh
        /// `UUID` would re-identify every bar on every `body` pass.
        var id: String { "\(cardType)-\(button)" }
        let button: String
        let cardType: String
        let count: Int
    }

    /// A card type's presses of each button, Again to Easy.
    fileprivate struct ButtonGroup {
        let name: String
        let counts: [Int]

        var total: Int { counts.reduce(0, +) }
        /// Everything but Again, as Anki counts correct answers.
        var correct: Int { counts.dropFirst().reduce(0, +) }
    }

    private var buttonLabels: [String] {
        [
            String(localized: "Again", bundle: .module), String(localized: "Hard", bundle: .module),
            String(localized: "Good", bundle: .module), String(localized: "Easy", bundle: .module),
        ]
    }

    private var groups: [ButtonGroup] {
        let bc = buttonCounts
        return [
            ButtonGroup(name: String(localized: "Learning", bundle: .module), counts: Array(bc.learning.prefix(4))),
            ButtonGroup(name: String(localized: "Young", bundle: .module), counts: Array(bc.young.prefix(4))),
            ButtonGroup(name: String(localized: "Mature", bundle: .module), counts: Array(bc.mature.prefix(4))),
        ]
    }

    private func entries(_ groups: [ButtonGroup]) -> [ButtonEntry] {
        let labels = buttonLabels
        var result: [ButtonEntry] = []
        for group in groups {
            for (index, count) in group.counts.enumerated() where count > 0 && index < labels.count {
                result.append(ButtonEntry(button: labels[index], cardType: group.name, count: count))
            }
        }
        return result
    }

    public var body: some View {
        let groups = self.groups
        let entries = entries(groups)
        AmgiCard(
            background: .surface,
            cornerRadius: AmgiRadius.inset,
            contentInsets: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Answer Buttons", bundle: .module).amgiFont(.bodyEmphasis)

                if entries.isEmpty {
                    Text("No button data", bundle: .module).foregroundStyle(palette.textSecondary).frame(height: 180)
                } else {
                    buttonsChart(entries, groups: groups)
                        .frame(height: 180)
                    StatsTable(rows: groups.filter { $0.total > 0 }.map { group in
                        (label: group.name, value: String(localized: "\(StatsFormat.percent(Double(group.correct), of: Double(group.total))) correct", bundle: .module))
                    })
                }
            }
        }
    }
}

private extension ButtonsChart {
    func buttonsChart(_ entries: [ButtonEntry], groups: [ButtonGroup]) -> some View {
        let counts = StatsChartScale.countAxis(maximum: entries.map(\.count).max() ?? 0)
        let selected = groups.first { $0.name == selectedGroup }
        let labels = buttonLabels
        return Chart {
            ForEach(entries) { entry in
                buttonBar(entry)
            }
            if let selected {
                RuleMark(x: .value(StatsMarkLabel.selection, selected.name))
                    .foregroundStyle(palette.accent.opacity(0.12))
                    .lineStyle(StrokeStyle(lineWidth: 0))
                    .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        StatsChartTooltip(title: selected.name, lines: tooltipLines(selected, labels: labels))
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartForegroundStyleScale([
            labels[0]: palette.danger,
            labels[1]: palette.warning,
            labels[2]: palette.positive,
            labels[3]: palette.info,
        ])
        .chartXScale(domain: groups.map(\.name))
        .chartYScale(domain: 0...counts.top)
        .chartYAxis { StatsAxes.count(counts.ticks) }
        .statsChartTap(as: String.self) { name in
            selectedGroup = name == nil || name == selectedGroup ? nil : name
        }
    }

    @ChartContentBuilder
    func buttonBar(_ entry: ButtonEntry) -> some ChartContent {
        BarMark(
            x: .value(String(localized: "Type", bundle: .module), entry.cardType),
            y: .value(String(localized: "Count", bundle: .module), entry.count)
        )
        .position(by: .value(String(localized: "Button", bundle: .module), entry.button))
        .foregroundStyle(by: .value(String(localized: "Button", bundle: .module), entry.button))
        .accessibilityLabel("\(entry.cardType), \(entry.button)")
        .accessibilityValue(ChartSpeech.count(entry.count, .press))
    }

    /// Anki's details: each button's presses and share, and how many were
    /// correct.
    func tooltipLines(_ group: ButtonGroup, labels: [String]) -> [String] {
        let total = Double(group.total)
        let presses = group.counts.enumerated().map { index, count in
            "\(labels[index]): \(StatsDualAxisSupport.formatCount(Double(count))) (\(StatsFormat.percent(Double(count), of: total)))"
        }
        let correct = String(
            localized: "Correct: \(StatsDualAxisSupport.formatCount(Double(group.correct))) of \(StatsDualAxisSupport.formatCount(total)) (\(StatsFormat.percent(Double(group.correct), of: total)))",
            bundle: .module
        )
        return presses + [correct]
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ButtonsChart(buttons: .sample, period: .month)
        .padding()
}
#endif
