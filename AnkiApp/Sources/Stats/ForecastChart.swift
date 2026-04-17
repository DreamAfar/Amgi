import SwiftUI
import Charts
import AnkiKit

struct ForecastChart: View {
    let data: [DayCount]

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_forecast_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            if data.isEmpty || data.allSatisfy({ $0.count == 0 }) {
                Text(L("stats_forecast_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(data, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle(Color.amgiAccent.gradient)
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard()
    }
}
