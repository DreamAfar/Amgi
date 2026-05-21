import Foundation

enum HeatmapColorScale {
    static func opacity(
        for count: Int,
        maxCount: Int,
        minOpacity: Double = 0.2,
        maxOpacity: Double = 1.0
    ) -> Double {
        let upperBound = max(maxCount, 1)
        let normalized = Double(max(count, 0)) / Double(upperBound)
        return opacity(
            forNormalizedValue: normalized,
            minOpacity: minOpacity,
            maxOpacity: maxOpacity
        )
    }

    static func opacity(
        forNormalizedValue value: Double,
        minOpacity: Double = 0.2,
        maxOpacity: Double = 1.0
    ) -> Double {
        let clamped = min(max(value, 0), 1)
        let curved = sqrt(clamped)
        return minOpacity + (maxOpacity - minOpacity) * curved
    }
}
