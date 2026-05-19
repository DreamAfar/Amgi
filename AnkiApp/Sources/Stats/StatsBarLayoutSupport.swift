import Charts
import Foundation
import UIKit

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
        availableWidth: CGFloat = UIScreen.main.bounds.width,
        minimum: Double = 1.5,
        fillRatio: Double = 0.82
    ) -> MarkDimension {
        guard slotCount > automaticThreshold else { return .automatic }
        let plotWidth = max(Double(availableWidth) - 72, 160)
        let slotWidth = plotWidth / Double(max(slotCount, 1))
        let maximum: Double
        switch plotWidth {
        case ..<480:
            maximum = 8
        case ..<820:
            maximum = 12
        case ..<1180:
            maximum = 16
        default:
            maximum = 22
        }
        let width = max(minimum, min(maximum, slotWidth * fillRatio))
        return .fixed(width)
    }
}
