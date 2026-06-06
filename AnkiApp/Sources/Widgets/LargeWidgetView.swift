// AmgiApp/Sources/Widgets/LargeWidgetView.swift
import SwiftUI
import WidgetKit
import AmgiTheme

struct LargeWidgetView: View {
    @Environment(\.palette) private var palette
    let snapshot: WidgetSnapshot

    private var totalDue: Int { snapshot.totalDue }
    private var reviewedTotal: Int { snapshot.reviewedToday + totalDue }

    private var progressFraction: Double {
        guard reviewedTotal > 0 else { return 0 }
        return min(1.0, Double(snapshot.reviewedToday) / Double(reviewedTotal))
    }

    private var chartMax: Int {
        snapshot.lastSevenDays.max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header: deck name + streak pill
            HStack {
                Text(snapshot.deckName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                streakPill
            }
            .padding(.bottom, 12)

            // Hero due count
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(totalDue)")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .kerning(-2.5)
                Text(WL("widget_cards_due"))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 4)

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.textPrimary.opacity(0.07))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.accent)
                            .frame(width: geo.size.width * progressFraction, height: 4)
                    }
                }
                .frame(height: 4)

                Text(WL("widget_reviewed_today_remaining_fmt", snapshot.reviewedToday, totalDue))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 12)

            // 3-column breakdown
            HStack(spacing: 0) {
                breakdownColumn(color: .blue, label: WL("widget_count_new"), count: snapshot.newCount)
                Divider()
                breakdownColumn(color: .orange, label: WL("widget_count_learn"), count: snapshot.learnCount)
                Divider()
                breakdownColumn(color: .green, label: WL("widget_count_review"), count: snapshot.reviewCount)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 10)

            // 7-day bar chart
            VStack(alignment: .leading, spacing: 6) {
                Text(WL("widget_last_7_days"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .textCase(.uppercase)
                    .kerning(0.3)

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(snapshot.lastSevenDays.enumerated()), id: \.offset) { index, count in
                        VStack(spacing: 3) {
                            GeometryReader { geo in
                                let fraction = chartMax > 0 ? CGFloat(count) / CGFloat(chartMax) : 0
                                VStack {
                                    Spacer()
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(palette.accent.opacity(index == 6 ? 0.9 : 0.5))
                                        .frame(height: max(3, geo.size.height * fraction))
                                }
                            }
                            Text(dayLabel(index))
                                .font(.system(size: 9))
                                .foregroundStyle(index == 6 ? palette.textPrimary.opacity(0.6) : palette.textPrimary.opacity(0.25))
                        }
                    }
                }
                .frame(height: 40)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "amgi://review?deckId=\(snapshot.deckId)"))
    }

    private var streakPill: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.system(size: 13))
            Text(WL("stats_heatmap_streak", snapshot.streak))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.warning)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(palette.warning.opacity(0.12), in: Capsule())
    }

    private func breakdownColumn(color: Color, label: String, count: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .kerning(-0.8)
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var weekdayLabels: [String] {
        let formatter = DateFormatter()
        formatter.locale = WidgetLocalization.bundle.preferredLocalizations.first.map(Locale.init(identifier:)) ?? .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else {
            return ["M", "T", "W", "T", "F", "S", "S"]
        }
        return Array(symbols[1...6]) + [symbols[0]]
    }

    private func dayLabel(_ index: Int) -> String {
        let today = Calendar.current.component(.weekday, from: snapshot.snapshotDate)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat — map to 0=Mon..6=Sun
        let todayIndex = (today + 5) % 7
        let dayIndex = (todayIndex - (6 - index) + 7) % 7
        return weekdayLabels[dayIndex]
    }
}

#Preview(as: .systemLarge) {
    AmgiWidget()
} timeline: {
    WidgetEntry(date: Date(), snapshot: widgetPlaceholderSnapshot())
}
