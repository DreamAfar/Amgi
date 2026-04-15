import SwiftUI
import Charts
import AnkiProto

struct AddedChart: View {
    let added: Anki_Stats_GraphsResponse.Added
    let period: StatsPeriod

    private var filteredData: [(day: Int, count: Int)] {
        let maxDay = period.days
        return added.added
            .compactMap { (dayOffset, count) -> (day: Int, count: Int)? in
                let day = Int(dayOffset)
                guard day <= 0, abs(day) <= maxDay else { return nil }
                return (day: day, count: Int(count))
            }
            .sorted(by: { $0.day < $1.day })
    }

    private var totalAdded: Int { filteredData.reduce(0) { $0 + $1.count } }
    private var avgPerDay: Double {
        guard !filteredData.isEmpty else { return 0 }
        let days = Set(filteredData.map(\.day)).count
        return Double(totalAdded) / Double(max(days, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("stats_added_title")).font(.headline)

            if filteredData.isEmpty {
                Text(L("stats_added_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(filteredData, id: \.day) { item in
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cards", item.count)
                    )
                    .foregroundStyle(.cyan.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 10)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        if let day = value.as(Int.self), day % 3 == 0 {
                            AxisValueLabel(anchor: .top) {
                                Text("\(day)")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(
                        preset: .aligned,
                        position: .leading,
                        values: .automatic(desiredCount: 4)
                    ) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.2))
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 200)
            }

            HStack(spacing: 16) {
                footerItem(L("stats_total"), value: "\(totalAdded)")
                footerItem(L("stats_avg_day"), value: String(format: "%.1f", avgPerDay))
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
