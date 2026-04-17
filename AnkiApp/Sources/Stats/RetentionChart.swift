import SwiftUI
import AnkiProto

struct RetentionChart: View {
    let trueRetention: Anki_Stats_GraphsResponse.TrueRetentionStats
    let revlogRange: RevlogRange

    enum DisplayMode: String, CaseIterable, Identifiable {
        case young   = "欠熟练"
        case mature  = "已熟练"
        case summary = "汇总"
        var id: String { rawValue }
    }

    @State private var mode: DisplayMode = .summary

    private typealias TR = Anki_Stats_GraphsResponse.TrueRetentionStats.TrueRetention

    private struct RetentionRow: Identifiable {
        let id: String
        let label: String
        let passed: UInt32
        let failed: UInt32
        var total: UInt32 { passed + failed }
        var rate: Double { total > 0 ? Double(passed) / Double(total) : -1 }
    }

    private func makeRows(for tr: Anki_Stats_GraphsResponse.TrueRetentionStats) -> [RetentionRow] {
        func row(_ label: String, _ r: TR) -> RetentionRow {
            switch mode {
            case .young:
                return RetentionRow(id: label, label: label, passed: r.youngPassed, failed: r.youngFailed)
            case .mature:
                return RetentionRow(id: label, label: label, passed: r.maturePassed, failed: r.matureFailed)
            case .summary:
                return RetentionRow(id: label, label: label,
                    passed: r.youngPassed + r.maturePassed,
                    failed: r.youngFailed + r.matureFailed)
            }
        }
        var rows: [RetentionRow] = [
            row(L("common_today"),             tr.today),
            row(L("stats_retention_yesterday"), tr.yesterday),
            row(L("stats_period_week"),         tr.week),
            row(L("stats_period_month"),        tr.month),
            row(L("stats_period_year"),         tr.year),
        ]
        // 仅全局=全部时才显示「全部时间」行，与上游 TrueRetention 逻辑一致
        if revlogRange == .all {
            rows.append(row(L("stats_period_all"), tr.allTime))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("stats_retention_title"))
                .amgiFont(.sectionHeading)
                .foregroundStyle(Color.amgiTextPrimary)

            Picker("", selection: $mode) {
                ForEach(DisplayMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .font(AmgiFont.micro.font)

            let rows = makeRows(for: trueRetention)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text(L("stats_retention_period"))
                        .amgiFont(.micro).foregroundStyle(Color.amgiTextSecondary)
                    Text(L("stats_retention_passed"))
                        .amgiFont(.micro).foregroundStyle(Color.amgiTextSecondary)
                    Text(L("stats_retention_failed"))
                        .amgiFont(.micro).foregroundStyle(Color.amgiTextSecondary)
                    Text(L("stats_retention_rate"))
                        .amgiFont(.micro).foregroundStyle(Color.amgiTextSecondary)
                    Text(L("stats_total"))
                        .amgiFont(.micro).foregroundStyle(Color.amgiTextSecondary)
                }
                Divider()
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label).amgiFont(.caption)
                        Text("\(row.passed)").font(AmgiFont.caption.font.monospacedDigit())
                        Text("\(row.failed)").font(AmgiFont.caption.font.monospacedDigit())
                        retentionBadge(row.rate)
                        Text("\(row.total)")
                            .font(AmgiFont.caption.font.monospacedDigit())
                            .foregroundStyle(Color.amgiTextSecondary)
                    }
                }
            }
        }
        .amgiCard(elevated: true)
    }

    private func retentionBadge(_ rate: Double) -> some View {
        Text(rate >= 0 ? "\(Int((rate * 100).rounded()))%" : "---")
            .font(AmgiFont.captionBold.font.monospacedDigit())
            .foregroundStyle(retentionColor(rate))
    }

    private func retentionColor(_ rate: Double) -> Color {
        if rate < 0    { return .secondary }
        if rate >= 0.9 { return .green }
        if rate >= 0.8 { return .orange }
        return .red
    }
}

