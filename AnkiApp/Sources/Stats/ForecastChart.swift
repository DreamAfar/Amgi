import SwiftUI
import Charts
import AnkiKit

struct ForecastChart: View {
    let data: [DayCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("stats_forecast_title")).font(.headline)

            if data.isEmpty || data.allSatisfy({ $0.count == 0 }) {
                Text(L("stats_forecast_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(data, id: \.date) { item in
                    BarMark(
                        x: .value("Date", item.date),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle(.blue.gradient)
                }
                .frame(height: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
