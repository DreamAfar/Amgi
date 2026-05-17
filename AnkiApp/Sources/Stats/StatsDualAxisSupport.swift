import Foundation

struct StatsAxisTick {
    let plottedValue: Double
    let label: String
}

enum StatsDualAxisSupport {
    private static let groupedIntFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func plottedValue(_ value: Double, domainMax: Double, plottedMax: Double) -> Double {
        guard domainMax > 0, plottedMax > 0 else { return 0 }
        return (value / domainMax) * plottedMax
    }

    static func formatCount(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return groupedIntFormatter.string(from: NSNumber(value: rounded)) ?? String(rounded)
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

    static func label(for targetValue: Double, in ticks: [StatsAxisTick], tolerance: Double = 0.0001) -> String {
        for tick in ticks {
            let distance: Double = Swift.abs(tick.plottedValue - targetValue)
            if distance < tolerance {
                return tick.label
            }
        }

        return ""
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

enum StatsFormatSupport {
    static func count(_ value: Int) -> String {
        StatsDualAxisSupport.formatCount(Double(value))
    }

    static func count(_ value: Double) -> String {
        StatsDualAxisSupport.formatCount(value)
    }

    static func cards(_ value: Int) -> String {
        L("stats_cards_with_unit_fmt", count(value))
    }

    static func cardsPerDay(_ value: Double) -> String {
        L("stats_cards_per_day_fmt", count(value))
    }

    static func reviews(_ value: Int) -> String {
        L("stats_reviews_with_unit_fmt", count(value))
    }

    static func reviewsPerDay(_ value: Double) -> String {
        L("stats_reviews_per_day_fmt", count(value))
    }

    static func minutesPerDay(_ value: Double) -> String {
        L("stats_minutes_per_day_fmt", count(value))
    }

    static func percentText(_ value: Double, digits: Int = 0) -> String {
        if digits == 0 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.\(digits)f", value)
    }

    static func amountOfTotal(_ amount: Int, total: Int, digits: Int = 2) -> String {
        let percent = total > 0 ? Double(amount) / Double(total) * 100 : 0
        return L(
            "stats_amount_of_total_with_percentage_fmt",
            count(amount),
            count(total),
            percentText(percent, digits: digits)
        )
    }

    static func timeShort(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds.rounded()))s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return trimmedDecimal(minutes, digits: 1) + "m"
        }

        let hours = seconds / 3600
        return trimmedDecimal(hours, digits: 1) + "h"
    }

    static func hourRange(startHour: Int, endHour: Int) -> String {
        L("stats_hour_range_fmt", startHour, endHour)
    }

    private static func trimmedDecimal(_ value: Double, digits: Int) -> String {
        let multiplier = pow(10.0, Double(digits))
        let roundedValue = (value * multiplier).rounded() / multiplier
        if roundedValue == roundedValue.rounded(.towardZero) {
            return String(Int(roundedValue))
        }
        return String(format: "%.\(digits)f", roundedValue)
    }
}
