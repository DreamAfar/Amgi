import SwiftUI
import Charts
import AnkiProto

struct HourlyChart: View {
    let hours: Anki_Stats_GraphsResponse.Hours
    let revlogRange: RevlogRange
    @State private var period: StatsPeriod = .year

    private var hourData: [Anki_Stats_GraphsResponse.Hours.Hour] {
        switch period {
        case .day, .week, .month: return hours.oneMonth
        case .threeMonths:        return hours.threeMonths
        case .year:               return hours.oneYear
        case .all:                return hours.allTime
        }
    }

    private struct HourEntry: Identifiable {
        let id: Int
        let hour: Int
        let total: Int
        let correctPct: Double
    }

    private var entries: [HourEntry] {
        let data = hourData
        guard data.count == 24 else {
            return (0..<24).map { HourEntry(id: $0, hour: $0, total: 0, correctPct: 0) }
        }
        return data.enumerated().map { index, hour in
            let pct = hour.total > 0 ? Double(hour.correct) / Double(hour.total) * 100 : 0
            return HourEntry(id: index, hour: index, total: Int(hour.total), correctPct: pct)
        }
    }

    private var isEmpty: Bool { entries.allSatisfy { $0.total == 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: AmgiSpacing.sm) {
            Text(L("stats_hourly_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Picker("", selection: $period) {
                Text(L("stats_period_month")).tag(StatsPeriod.month)
                Text(L("stats_period_3months")).tag(StatsPeriod.threeMonths)
                Text(L("stats_period_year")).tag(StatsPeriod.year)
                if revlogRange == .all {
                    Text(L("stats_period_all")).tag(StatsPeriod.all)
                }
            }
            .pickerStyle(.segmented)
            .amgiFont(.micro)
            .onChange(of: revlogRange) {
                if revlogRange == .year && period == .all { period = .year }
            }

            if isEmpty {
                Text(L("stats_hourly_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                let maxTotal = entries.map(\.total).max() ?? 1
                Chart(entries) { entry in
                    BarMark(
                        x: .value("Hour", entry.hour),
                        y: .value(L("stats_hourly_reviews"), entry.total),
                        width: .fixed(9)
                    )
                    .foregroundStyle(
                        Color(hue: 0.58, saturation: 0.5 + 0.5 * Double(entry.total) / Double(max(maxTotal, 1)), brightness: 0.7).gradient
                    )
                    LineMark(
                        x: .value("Hour", entry.hour),
                        y: .value(L("stats_hourly_correct_pct"), entry.correctPct),
                        series: .value("Series", "pct")
                    )
                    .foregroundStyle(.green.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        if let h = value.as(Int.self) {
                            AxisValueLabel(formatHour(h))
                                .font(AmgiFont.micro.font)
                                .foregroundStyle(Color.amgiTextSecondary)
                        }
                    }
                }
                .chartXScale(domain: 0...23)
                .chartYAxis {
                    AxisMarks(preset: .aligned, position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.amgiTextTertiary.opacity(0.25))
                        AxisValueLabel()
                            .font(AmgiFont.micro.font)
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
                .frame(height: 200)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .amgiCard()
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0  { return "0" }
        if hour == 12 { return "12" }
        return "\(hour)"
    }
}
