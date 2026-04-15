import SwiftUI
import Charts
import AnkiProto

struct FutureDueChart: View {
    let futureDue: Anki_Stats_GraphsResponse.FutureDue
    @State private var period: StatsPeriod = .month
    @State private var includeBacklog = false

    private var filteredData: [(day: Int, count: Int)] {
        let maxDay = period.days
        return futureDue.futureDue
            .compactMap { (dayOffset, count) -> (day: Int, count: Int)? in
                let day = Int(dayOffset)
                if !includeBacklog && day < 0 { return nil }
                guard day < maxDay else { return nil }
                return (day: day, count: Int(count))
            }
            .sorted(by: { $0.day < $1.day })
    }

    private var totalDue: Int { filteredData.reduce(0) { $0 + $1.count } }
    private var dueTomorrow: Int { filteredData.first(where: { $0.day == 1 })?.count ?? 0 }
    private var avgPerDay: Double {
        let positiveDays = filteredData.filter { $0.day >= 0 }
        guard !positiveDays.isEmpty else { return 0 }
        let maxOffset = positiveDays.map(\.day).max() ?? 1
        return Double(positiveDays.reduce(0) { $0 + $1.count }) / Double(max(maxOffset, 1))
    }

    private var barWidth: MarkDimension {
        filteredData.count <= 30 ? .automatic : .fixed(max(2, min(8, 280.0 / Double(filteredData.count))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("stats_future_due_title")).font(.headline)

            Picker("", selection: $period) {
                Text(L("stats_period_month")).tag(StatsPeriod.month)
                Text(L("stats_period_3months")).tag(StatsPeriod.threeMonths)
                Text(L("stats_period_year")).tag(StatsPeriod.year)
                Text(L("stats_period_all")).tag(StatsPeriod.all)
            }
            .pickerStyle(.segmented)
            .font(.caption2)

            if filteredData.isEmpty {
                Text(L("stats_future_due_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(filteredData, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cards", item.count),
                        width: barWidth
                    )
                    .foregroundStyle(item.day < 0 ? Color.red.gradient : Color.blue.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned, position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
            }

            if futureDue.haveBacklog {
                Toggle(L("stats_future_due_backlog"), isOn: $includeBacklog)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .controlSize(.mini)
            }

            HStack(spacing: 0) {
                footerItem(L("stats_total"), value: "\(totalDue)")
                footerItem(L("stats_avg_day"), value: String(format: "%.1f", avgPerDay))
                footerItem(L("stats_future_due_tomorrow"), value: "\(dueTomorrow)")
                footerItem(L("stats_future_due_daily_load"), value: "\(futureDue.dailyLoad)")
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.semibold).monospacedDigit())
            Text(label).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

