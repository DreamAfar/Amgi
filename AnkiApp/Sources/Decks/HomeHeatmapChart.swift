import SwiftUI
import AnkiProto

struct HomeHeatmapChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    let preferredHeight: CGFloat

    private let calendar = Calendar.current
    private let cellSpacing: CGFloat = 4

    private struct Layout {
        let weeks: [[Date]]
        let monthLabels: [(title: String, weekIndex: Int)]
        let cellSize: CGFloat
    }

    private var dayCountMap: [Int: Int] {
        var map: [Int: Int] = [:]
        for (dayOffset, rev) in reviews.count {
            let total = Int(rev.learn + rev.relearn + rev.young + rev.mature + rev.filtered)
            if total > 0 {
                map[Int(dayOffset)] = total
            }
        }
        return map
    }

    private var maxCount: Int {
        max(dayCountMap.values.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("deck_list_heatmap_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            if dayCountMap.isEmpty {
                Text(L("stats_heatmap_empty"))
                    .amgiFont(.body)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: max(84, preferredHeight - 52))
            } else {
                GeometryReader { proxy in
                    let layout = layout(for: proxy.size)

                    VStack(alignment: .leading, spacing: 10) {
                        monthHeader(layout: layout)
                        grid(layout: layout)
                        legend(layout: layout)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(height: max(92, preferredHeight - 52))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.amgiSurfaceElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.amgiBorder.opacity(0.22), lineWidth: 1)
        )
    }

    private func monthHeader(layout: Layout) -> some View {
        let labelLookup = Dictionary(uniqueKeysWithValues: layout.monthLabels.map { ($0.weekIndex, $0.title) })

        return HStack(spacing: cellSpacing) {
            ForEach(Array(layout.weeks.indices), id: \.self) { weekIndex in
                Text(labelLookup[weekIndex] ?? "")
                    .amgiFont(.caption)
                    .foregroundStyle(Color.amgiTextSecondary)
                    .lineLimit(1)
                    .frame(width: layout.cellSize, alignment: .leading)
            }
        }
    }

    private func grid(layout: Layout) -> some View {
        HStack(alignment: .top, spacing: cellSpacing) {
            ForEach(Array(layout.weeks.indices), id: \.self) { weekIndex in
                VStack(spacing: cellSpacing) {
                    ForEach(Array(layout.weeks[weekIndex].indices), id: \.self) { dayIndex in
                        let date = layout.weeks[weekIndex][dayIndex]
                        let offset = dayOffset(for: date)
                        let count = dayCountMap[offset] ?? 0
                        let isFuture = date > Date()

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isFuture ? Color.clear : heatColor(count: count))
                            .overlay {
                                if isFuture {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(Color.amgiBorder, lineWidth: 0.5)
                                        .opacity(0.25)
                                }
                            }
                            .frame(width: layout.cellSize, height: layout.cellSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(layout: Layout) -> some View {
        HStack(spacing: 4) {
            Spacer()
            Text(L("stats_heatmap_less"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.amgiPositive.opacity(max(0.12, intensity)))
                    .frame(width: layout.cellSize, height: layout.cellSize)
            }
            Text(L("stats_heatmap_more"))
                .amgiFont(.caption)
                .foregroundStyle(Color.amgiTextSecondary)
        }
    }

    private func layout(for size: CGSize) -> Layout {
        let width = max(220, size.width)
        let gridHeight = max(72, size.height - 30)
        let heightLimitedCell = floor((gridHeight - (cellSpacing * 6)) / 7)
        let estimatedColumns = Int((width + cellSpacing) / max(8, heightLimitedCell + cellSpacing))
        let weekCount = min(36, max(24, estimatedColumns))
        let cellSize = max(
            8,
            floor((width - (cellSpacing * CGFloat(weekCount - 1))) / CGFloat(weekCount))
        )

        let today = calendar.startOfDay(for: Date())
        let endWeekStart = startOfWeek(containing: today)
        let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: endWeekStart) ?? endWeekStart

        let weeks: [[Date]] = (0..<weekCount).map { weekOffset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: firstWeekStart) ?? firstWeekStart
            return (0..<7).map { dayOffset in
                calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
            }
        }

        let monthLabels = monthLabels(for: weeks)
        return Layout(weeks: weeks, monthLabels: monthLabels, cellSize: cellSize)
    }

    private func monthLabels(for weeks: [[Date]]) -> [(title: String, weekIndex: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月"

        var labels: [(title: String, weekIndex: Int)] = []
        var lastMonth = -1

        for (index, week) in weeks.enumerated() {
            guard let firstDate = week.first else { continue }
            let month = calendar.component(.month, from: firstDate)
            if month != lastMonth {
                labels.append((formatter.string(from: firstDate), index))
                lastMonth = month
            }
        }

        return labels
    }

    private func startOfWeek(containing date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))
            ?? calendar.startOfDay(for: date)
    }

    private func dayOffset(for date: Date) -> Int {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    private func heatColor(count: Int) -> Color {
        if count == 0 {
            return Color.amgiSurface
        }

        let intensity = min(1.0, Double(count) / Double(maxCount))
        return Color.amgiPositive.opacity(max(0.2, intensity))
    }
}