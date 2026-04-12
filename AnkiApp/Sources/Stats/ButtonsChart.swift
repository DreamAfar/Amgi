import SwiftUI
import Charts
import AnkiProto

struct ButtonsChart: View {
    let buttons: Anki_Stats_GraphsResponse.Buttons
    let period: StatsPeriod

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
        VStack(alignment: .leading, spacing: 8) {
            Text(L("stats_buttons_title")).font(.headline)

            if entries.isEmpty {
                Text(L("stats_buttons_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Button", entry.button),
                        y: .value("Count", entry.count)
                    )
                    .foregroundStyle(by: .value("Type", entry.cardType))
                }
                .chartForegroundStyleScale([
                    L("stats_card_learn"): Color.blue,
                    L("stats_card_young"): Color.green,
                    L("stats_card_mature"): Color.purple,
                ])
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
