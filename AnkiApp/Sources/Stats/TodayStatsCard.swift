import SwiftUI
import AnkiProto

struct TodayStatsCard: View {
    let today: Anki_Stats_GraphsResponse.Today

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
        VStack(spacing: 12) {
            HStack {
                statItem(title: L("stats_today_reviewed"), value: "\(today.answerCount)", color: .primary)
                Spacer()
                statItem(title: L("stats_today_time"), value: formatTime(today.answerMillis), color: .primary)
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
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func statBadge(_ title: String, count: UInt32, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.subheadline.weight(.medium)).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
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
