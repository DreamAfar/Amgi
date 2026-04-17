import Foundation

struct StatsAxisTick {
    let plottedValue: Double
    let label: String
}

enum StatsDualAxisSupport {
    static func plottedValue(_ value: Double, domainMax: Double, plottedMax: Double) -> Double {
        guard domainMax > 0, plottedMax > 0 else { return 0 }
        return (value / domainMax) * plottedMax
    }

    static func niceUpperBound(_ domainMax: Double, desiredTickCount: Int = 4) -> Double {
        guard domainMax > 0 else { return 1 }
        let step = niceStep(domainMax / Double(max(desiredTickCount, 1)))
        return ceil(domainMax / step) * step
    }

    static func ticks(
        domainMax: Double,
        plottedMax: Double,
        desiredTickCount: Int = 4,
        formatter: (Double) -> String
    ) -> [StatsAxisTick] {
        guard domainMax > 0, plottedMax > 0 else { return [] }

        let step = niceStep(domainMax / Double(max(desiredTickCount, 1)))
        let tickMax = niceUpperBound(domainMax, desiredTickCount: desiredTickCount)
        var result: [StatsAxisTick] = []
        var value = 0.0

        while value <= tickMax + (step * 0.5) {
            result.append(
                StatsAxisTick(
                    plottedValue: plottedValue(value, domainMax: tickMax, plottedMax: plottedMax),
                    label: formatter(value)
                )
            )
            value += step
        }

        return result
    }

    private static func niceStep(_ rawStep: Double) -> Double {
        guard rawStep > 0 else { return 1 }

        let exponent = floor(log10(rawStep))
        let fraction = rawStep / pow(10, exponent)
        let niceFraction: Double

        switch fraction {
        case ..<1.5:
            niceFraction = 1
        case ..<3:
            niceFraction = 2
        case ..<7:
            niceFraction = 5
        default:
            niceFraction = 10
        }

        return niceFraction * pow(10, exponent)
    }
}