import SwiftUI
import AnkiProto

struct TodayStatsCard: View {
    let today: Anki_Stats_GraphsResponse.Today
    var embedded: Bool = false
    var compactText: Bool = false

    private var primaryValueFont: Font {
        compactText
            ? .system(size: 17, weight: .semibold, design: .default)
            : .title3.weight(.semibold)
    }

    private var badgeValueFont: Font {
        compactText
            ? .system(size: 13, weight: .medium, design: .default)
            : .subheadline.weight(.medium)
    }

    private var accuracy: String {
        guard today.answerCount > 0 else { return "---" }
        let pct = Int(Double(today.correctCount) / Double(today.answerCount) * 100)
        return "\(pct)%"
    }

    private var matureAccuracy: String {
        guard today.matureCount > 0 else { return "---" }
        let pct = Int(Double(today.matureCorrect) / Double(today.matureCount) * 100)
        return "\(pct)%"
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: compactText ? 10 : 12) {
            if !embedded {
                Text(L("stats_today_title"))
                    .amgiFont(.sectionHeading)
                    .foregroundStyle(Color.amgiTextPrimary)
            }

            VStack(spacing: compactText ? 10 : 12) {
                HStack {
                    statItem(title: L("stats_today_reviewed"), value: "\(today.answerCount)", color: Color.amgiTextPrimary)
                    Spacer()
                    statItem(title: L("stats_today_time"), value: formatTime(today.answerMillis), color: Color.amgiTextPrimary)
                    Spacer()
                    statItem(title: L("stats_today_correct"), value: accuracy, color: .green)
                    Spacer()
                    statItem(title: L("stats_today_mature"), value: matureAccuracy, color: .purple)
                }
                Divider()
                HStack {
                    statBadge(L("stats_card_new"), count: today.learnCount, color: .cyan)
                    Spacer()
                    statBadge(L("stats_card_learn"), count: today.relearnCount, color: .orange)
                    Spacer()
                    statBadge(L("stats_card_review"), count: today.reviewCount, color: .green)
                    Spacer()
                    statBadge(L("stats_card_again"), count: today.answerCount - today.correctCount, color: .red)
                }
            }
        }

        Group {
            if embedded {
                content
            } else {
                content
                    .amgiCard(elevated: true)
            }
        }
    }

    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(primaryValueFont)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .amgiFont(compactText ? .micro : .caption)
                .foregroundStyle(Color.amgiTextSecondary)
                .lineLimit(1)
        }
    }

    private func statBadge(_ title: String, count: UInt32, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(badgeValueFont)
                .foregroundStyle(color)
                .lineLimit(1)
            Text(title)
                .amgiFont(.micro)
                .foregroundStyle(Color.amgiTextSecondary)
                .lineLimit(1)
        }
    }

    private func formatTime(_ ms: UInt32) -> String {
        let seconds = ms / 1000
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
