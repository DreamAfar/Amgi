import SwiftUI
import Charts
import AnkiProto

struct AddedChart: View {
    let added: Anki_Stats_GraphsResponse.Added
    @State private var period: StatsPeriod = .month

    /// Number of days per bar bucket — capped at ~70 bars
    private var bucketSize: Int {
        switch period {
        case .day, .week, .month: return 1
        case .threeMonths: return 7
        case .year, .all: return 30
        }
    }

    private var filteredData: [(day: Int, count: Int)] {
        let maxDay = period.days
        let bkt = bucketSize
        var buckets: [Int: Int] = [:]
        for (dayOffset, count) in added.added {
            let day = Int(dayOffset)
            guard day <= 0, abs(day) <= maxDay else { continue }
            let bucket = bkt == 1 ? day : -((-day) / bkt * bkt)
            buckets[bucket, default: 0] += Int(count)
        }
        return buckets.map { (day: $0.key, count: $0.value) }
            .sorted(by: { $0.day < $1.day })
    }

    private var totalAdded: Int { filteredData.reduce(0) { $0 + $1.count } }
    private var avgPerDay: Double {
        guard !filteredData.isEmpty else { return 0 }
        let span = filteredData.count * bucketSize
        return Double(totalAdded) / Double(max(span, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_added_title"))
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
                Text(L("stats_added_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(filteredData, id: \.day) { item in
                    let bw: Double = filteredData.count <= 30 ? 0 : max(2.0, min(8.0, 280.0 / Double(filteredData.count)))
                    let barW: MarkDimension = filteredData.count <= 30 ? .automatic : .fixed(bw)
                    BarMark(
                        x: .value("Day", item.day),
                        y: .value("Cards", item.count),
                        width: barW
                    )
                    .foregroundStyle(Color.amgiInfo.gradient)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        AxisValueLabel()
                            .amgiFont(.micro)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(
                        preset: .aligned,
                        position: .leading,
                        values: .automatic(desiredCount: 4)
                    ) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        AxisValueLabel()
                            .amgiFont(.micro)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
                .frame(height: 200)
            }

            HStack(spacing: AmgiSpacing.lg) {
                footerItem(L("stats_total"), value: "\(totalAdded)")
                footerItem(L("stats_avg_day"), value: String(format: "%.1f", avgPerDay))
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