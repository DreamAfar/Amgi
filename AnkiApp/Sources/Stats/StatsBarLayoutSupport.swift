import Charts
import Foundation

enum StatsBarLayoutSupport {
    static func displayedSlotCount(
        lowerBound: Int,
        upperBound: Int,
        bucketSize: Int
    ) -> Int {
        guard bucketSize > 0, upperBound >= lowerBound else { return 1 }
        let inclusiveSpan = upperBound - lowerBound + 1
        return max(1, Int(ceil(Double(inclusiveSpan) / Double(bucketSize))))
    }

    static func barWidth(
        slotCount: Int,
        automaticThreshold: Int = 24,
        denominator: Double = 220,
        minimum: Double = 1.5,
        maximum: Double = 6
    ) -> MarkDimension {
        guard slotCount > automaticThreshold else { return .automatic }
        let width = max(minimum, min(maximum, denominator / Double(slotCount)))
        return .fixed(width)
    }
}
