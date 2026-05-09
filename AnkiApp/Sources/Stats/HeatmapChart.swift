import SwiftUI
import AnkiProto

struct HeatmapChart: View {
    let reviews: Anki_Stats_GraphsResponse.ReviewCountsAndTimes
    var compactHeight: CGFloat? = nil
    var embedded: Bool = false
    var canLoadMoreHistory: Bool = false
    var isLoadingMoreHistory: Bool = false
    var onLoadMoreHistory: (() -> Void)? = nil
    var onTapHeatmap: (() -> Void)? = nil

    @State private var isNearLoadMoreThreshold = false
    @State private var isLoadMoreArmed = false
    @State private var hasTriggeredLoadMore = false

    private var isCompact: Bool {
        compactHeight != nil
    }

    private let leadingEdgeThreshold: CGFloat = 6
    private let loadResetThreshold: CGFloat = 24
    private let loadTriggerOverscrollThreshold: CGFloat = 40

    private var cellSpacing: CGFloat {
        isCompact ? 1.25 : 2
    }

    private var weekdayLabelWidth: CGFloat {
        isCompact ? 16 : 22
    }

    private var cellSize: CGFloat {
        guard let compactHeight else { return 12 }

        let reservedHeight: CGFloat = 92
        let availableGridHeight = max(56, compactHeight - reservedHeight)
        let computed = (availableGridHeight - (cellSpacing * 6)) / 7
        return min(12, max(7, computed))
    }

    // MARK: - Day Count Map (dayOffset -> total reviews)

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

    private var maxCount: Int { dayCountMap.values.max() ?? 1 }

    // MARK: - Date Mapping

    private let calendar = Calendar.current

    private func dayOffset(for date: Date) -> Int {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: today, to: target).day ?? 0
    }

    // MARK: - Computed Stats

    private var totalReviews: Int {
        dayCountMap.values.reduce(0, +)
    }

    private var currentStreak: Int {
        var streak = 0
        var offset = 0
        // If no reviews today, start from yesterday
        if dayCountMap[0] == nil || dayCountMap[0] == 0 {
            offset = -1
        }
        while let count = dayCountMap[offset], count > 0 {
            streak += 1
            offset -= 1
        }
        return streak
    }

    private var reviewsThisWeek: Int {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        return (0...daysFromMonday).reduce(0) { $0 + (dayCountMap[-$1] ?? 0) }
    }

    private var reviewsThisMonth: Int {
        let day = calendar.component(.day, from: Date())
        return (0..<day).reduce(0) { $0 + (dayCountMap[-$1] ?? 0) }
    }

    // MARK: - Grid Data

    /// Number of weeks to show based on data range
    private var weeksToShow: Int {
        guard let minOffset = dayCountMap.keys.min() else { return 52 }
        let totalDays = Swift.abs(minOffset) + 7 // add a week buffer
        let weeksNeeded = totalDays / 7 + 1
        return max(weeksNeeded, 52) // at least 1 year
    }

    private var weeks: [[Date]] {
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .weekOfYear, value: -(weeksToShow - 1), to: today)!
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startDate)
        )!

        var result: [[Date]] = []
        var current = startOfWeek
        while current <= today {
            var week: [Date] = []
            for dayOff in 0..<7 {
                week.append(calendar.date(byAdding: .day, value: dayOff, to: current)!)
            }
            result.append(week)
            current = calendar.date(byAdding: .weekOfYear, value: 1, to: current)!
        }
        return result
    }

    private var monthLabels: [(String, Int)] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        var labels: [(String, Int)] = []
        var lastMonth = -1
        for (weekIdx, week) in weeks.enumerated() {
            let month = calendar.component(.month, from: week[0])
            if month != lastMonth {
                labels.append((fmt.string(from: week[0]), weekIdx))
                lastMonth = month
            }
        }
        return labels
    }

    // MARK: - Body

    var body: some View {
        let chartContent = VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("stats_heatmap_title"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(Color.amgiTextPrimary)
                headerLegend
                Spacer()
                if currentStreak > 0 {
                    Label(L("stats_heatmap_streak", currentStreak), systemImage: "flame.fill")
                        .amgiFont(.captionBold)
                        .foregroundStyle(.orange)
                }
            }

            if dayCountMap.isEmpty {
                Text(L("stats_heatmap_empty"))
                    .foregroundStyle(Color.amgiTextSecondary)
                    .frame(maxWidth: .infinity, minHeight: isCompact ? 72 : 100)
            } else {
                if !isCompact {
                    HStack(spacing: 16) {
                        summaryItem(value: "\(totalReviews)", label: L("stats_total"))
                        summaryItem(value: "\(reviewsThisMonth)", label: L("stats_this_month"))
                        summaryItem(value: "\(reviewsThisWeek)", label: L("stats_this_week"))
                        summaryItem(value: "\(dayCountMap[0] ?? 0)", label: L("common_today"))
                    }
                }

                heatmapScrollView
            }
        }

        Group {
            if embedded {
                chartContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                chartContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(isCompact ? 10 : 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.amgiSurfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.amgiBorder.opacity(0.32), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
            }
        }
        .onChange(of: canLoadMoreHistory) { _, canLoad in
            if !canLoad {
                isNearLoadMoreThreshold = false
                isLoadMoreArmed = false
                hasTriggeredLoadMore = false
            }
        }
    }

    // MARK: - Helpers

    private var headerLegend: some View {
        HStack(spacing: isCompact ? 3 : 4) {
            Text(L("stats_heatmap_less"))
                .amgiFont(.micro)
                .foregroundStyle(Color.amgiTextSecondary)
            ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { intensity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green.opacity(max(0.1, intensity)))
                    .frame(width: cellSize, height: cellSize)
            }
            Text(L("stats_heatmap_more"))
                .amgiFont(.micro)
                .foregroundStyle(Color.amgiTextSecondary)
        }
    }

    private var heatmapScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Spacer().frame(width: weekdayLabelWidth)
                    ForEach(0..<weeks.count, id: \.self) { weekIdx in
                        if let label = monthLabels.first(where: { $0.1 == weekIdx }) {
                            Text(label.0)
                                .font(.system(size: 9, weight: .medium, design: .default))
                                .foregroundStyle(Color.amgiTextSecondary)
                                .fixedSize()
                                .frame(width: cellSize + cellSpacing, alignment: .leading)
                        } else {
                            Spacer().frame(width: cellSize + cellSpacing)
                        }
                    }
                }
                .frame(height: 14)

                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { day in
                            Text(weekdayLabel(day))
                                .font(.system(size: 8))
                                .foregroundStyle(Color.amgiTextSecondary)
                                .frame(width: weekdayLabelWidth, height: cellSize)
                        }
                    }

                    HStack(spacing: cellSpacing) {
                        ForEach(0..<weeks.count, id: \.self) { weekIdx in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { dayIdx in
                                    let date = weeks[weekIdx][dayIdx]
                                    let offset = dayOffset(for: date)
                                    let count = dayCountMap[offset] ?? 0
                                    let isFuture = date > Date()

                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isFuture ? Color.clear : heatColor(count: count))
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapHeatmap?()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded { _ in
                    guard canLoadMoreHistory, !isLoadingMoreHistory, !hasTriggeredLoadMore else { return }
                    if isNearLoadMoreThreshold {
                        isLoadMoreArmed = true
                    }
                }
        )
        .onScrollGeometryChange(
            for: CGFloat.self,
            of: { geometry in geometry.contentOffset.x }
        ) { _, newValue in
            handleHorizontalScroll(offset: newValue)
        }
        .overlay(alignment: .leading) {
            if canLoadMoreHistory && (isLoadingMoreHistory || isNearLoadMoreThreshold || isLoadMoreArmed) {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(.leading, 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func summaryItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .amgiFont(.micro)
                .foregroundStyle(Color.amgiTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func weekdayLabel(_ index: Int) -> String {
        switch index {
        case 1: "M"
        case 3: "W"
        case 5: "F"
        default: ""
        }
    }

    private func heatColor(count: Int) -> Color {
        if count == 0 { return Color(.systemGray6) }
        let intensity = min(1.0, Double(count) / Double(max(maxCount, 1)))
        return .green.opacity(max(0.2, intensity))
    }

    private func handleHorizontalScroll(offset: CGFloat) {
        guard canLoadMoreHistory else { return }

        let isNearLeadingEdge = offset <= leadingEdgeThreshold
        isNearLoadMoreThreshold = isNearLeadingEdge

        if offset > loadResetThreshold {
            isLoadMoreArmed = false
            hasTriggeredLoadMore = false
            return
        }

        guard isLoadMoreArmed else { return }

        if offset <= -loadTriggerOverscrollThreshold {
            guard !hasTriggeredLoadMore else { return }
            hasTriggeredLoadMore = true
            isLoadMoreArmed = false
            onLoadMoreHistory?()
        }
    }
}
