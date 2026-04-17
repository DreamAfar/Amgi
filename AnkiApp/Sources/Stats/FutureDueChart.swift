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
        if filteredData.count <= 30 { return .automatic }
        let w: Double = max(2.0, min(8.0, 280.0 / Double(filteredData.count)))
        return .fixed(w)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_future_due_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Picker("", selection: $period) {
                Text(L("stats_period_month")).tag(StatsPeriod.month)
                Text(L("stats_period_3months")).tag(StatsPeriod.threeMonths)
                Text(L("stats_period_year")).tag(StatsPeriod.year)
                Text(L("stats_period_all")).tag(StatsPeriod.all)
            }
            .pickerStyle(.segmented)
            .amgiFont(.micro)

            if filteredData.isEmpty {
                Text(L("stats_future_due_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
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
                    AxisMarks(values: .automatic(desiredCount: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let day = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(day)")
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned, position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let count = value.as(Int.self) {
                            AxisValueLabel {
                                Text("\(count)")
                                    .amgiFont(.micro)
                                    .foregroundStyle(Color.amgiTextSecondary)
                            }
                        }
                    }
                }
                .frame(height: 200)
            }

            if futureDue.haveBacklog {
                Toggle(L("stats_future_due_backlog"), isOn: $includeBacklog)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                    .amgiFont(.micro)
                    .controlSize(.mini)
            }

            HStack(spacing: 0) {
                footerItem(L("stats_total"), value: "\(totalDue)")
                footerItem(L("stats_avg_day"), value: String(format: "%.1f", avgPerDay))
                footerItem(L("stats_future_due_tomorrow"), value: "\(dueTomorrow)")
                footerItem(L("stats_future_due_daily_load"), value: "\(futureDue.dailyLoad)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard()
    }

    private func footerItem(_ label: String, value: String) -> some View {
        VStack(spacing: AmgiSpacing.xxs) {
            Text(value)
                .amgiFont(.captionBold)
                .monospacedDigit()
                .foregroundStyle(Color.amgiTextPrimary)
            Text(label)
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

