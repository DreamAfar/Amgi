import SwiftUI
import Charts
import AnkiProto

struct ButtonsChart: View {
    let buttons: Anki_Stats_GraphsResponse.Buttons
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .year

    private var buttonCounts: Anki_Stats_GraphsResponse.Buttons.ButtonCounts {
        switch period {
        case .day, .week, .month: buttons.oneMonth
        case .threeMonths: buttons.threeMonths
        case .year: buttons.oneYear
        case .all: buttons.allTime
        }
    }

    private struct ButtonEntry: Identifiable {
        let id = UUID()
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
        for (typeName, counts) in sources {
            for (index, count) in counts.prefix(4).enumerated() {
                if count > 0 {
                    result.append(ButtonEntry(
                        button: buttonLabels[index],
                        cardType: typeName,
                        count: Int(count)
                    ))
                }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_buttons_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

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
            }

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
        }
        .chartForegroundStyleScale(colorScale)
        .frame(height: 180)
    }
}
