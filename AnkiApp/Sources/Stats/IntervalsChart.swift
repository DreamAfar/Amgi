import SwiftUI
import Charts
import AnkiProto

struct IntervalsChart: View {
    let intervals: Anki_Stats_GraphsResponse.Intervals
    let isFSRS: Bool

    enum IntervalRange: String, CaseIterable, Identifiable {
        case month       = "1个月"
        case percentile50 = "50%"
        case percentile95 = "95%"
        case all         = "全部"
        var id: String { rawValue }
    }

    @State private var range: IntervalRange = .month

    // Flat sorted array of all intervals (each card = one entry)
    private var flatIntervals: [Int] {
        var arr: [Int] = []
        for (day, cnt) in intervals.intervals {
            let n = Int(cnt)
            arr.append(contentsOf: repeatElement(Int(day), count: n))
        }
        return arr.sorted()
    }

    private func quantile(_ sorted: [Int], _ p: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let idx = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
        return sorted[idx]
    }

    // Returns (bins, xMax) where bins = [(label, midpoint, count)]
    private var histogramData: (bins: [(label: String, x: Int, count: Int)], xMax: Int) {
        let sorted = flatIntervals
        guard !sorted.isEmpty else { return ([], 0) }

        let xMax: Int
        switch range {
        case .month:       xMax = 30
        case .percentile50: xMax = max(1, quantile(sorted, 0.5))
        case .percentile95: xMax = max(1, quantile(sorted, 0.95))
        case .all:          xMax = sorted.last ?? 1
        }

        let desiredBars = min(70, xMax)
        let binSize = max(1, xMax / desiredBars)

        var buckets: [Int: Int] = [:]
        for v in sorted {
            guard v <= xMax else { continue }
            let b = (v / binSize) * binSize
            buckets[b, default: 0] += 1
        }

        let bins = buckets.sorted(by: { $0.key < $1.key }).map { (k, cnt) in
            let label: String
            if binSize == 1 {
                label = "\(k)"
            } else {
                label = "\(k)-\(k + binSize - 1)"
            }
            return (label: label, x: k, count: cnt)
        }
        return (bins, xMax)
    }

    private var medianInterval: Int {
        let s = flatIntervals
        return s.isEmpty ? 0 : quantile(s, 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isFSRS ? L("stats_stability_title") : L("stats_intervals_title")).font(.headline)

            Picker("", selection: $range) {
                ForEach(IntervalRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)
            .font(.caption2)

            let (bins, _) = histogramData
            if bins.isEmpty {
                Text(L("stats_intervals_empty"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                intervalsChart(bins: bins)
            }

            HStack(spacing: 16) {
                footerItem(L("stats_intervals_median"), value: L("stats_intervals_days_fmt", medianInterval))
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

    @ViewBuilder
    private func intervalsChart(bins: [(label: String, x: Int, count: Int)]) -> some View {
        let barWVal: Double = max(2.0, min(8.0, 280.0 / Double(bins.count)))
        let barW: MarkDimension = bins.count <= 30 ? .automatic : .fixed(barWVal)
        Chart(bins, id: \.x) { bin in
            BarMark(
                x: .value(L("stats_intervals_days"), bin.x),
                y: .value(L("stats_card_count"), bin.count),
                width: barW
            )
            .foregroundStyle(Color.teal.gradient)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.gray.opacity(0.2))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.gray.opacity(0.2))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 200)
    }
}
