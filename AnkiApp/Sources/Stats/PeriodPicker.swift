import SwiftUI

enum StatsPeriod: String, CaseIterable, Sendable {
    case day = "Today"
    case week = "7 Days"
    case month = "1 Month"
    case threeMonths = "3 Months"
    case year = "1 Year"
    case all = "All Time"

    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 31
        case .threeMonths: 92
        case .year: 365
        case .all: 36500
        }
    }

    var requestDays: UInt32 {
        switch self {
        case .all:
            return 0
        default:
            return UInt32(days)
        }
    }

    var localizedLabel: String {
        switch self {
        case .day: L("stats_period_day")
        case .week: L("stats_period_week")
        case .month: L("stats_period_month")
        case .threeMonths: L("stats_period_3months")
        case .year: L("stats_period_year")
        case .all: L("stats_period_all")
        }
    }

    var shortLabel: String {
        switch self {
        case .day: L("stats_period_day_short")
        case .week: L("stats_period_week_short")
        case .month: L("stats_period_month_short")
        case .threeMonths: L("stats_period_3months_short")
        case .year: L("stats_period_year_short")
        case .all: L("stats_period_all_short")
        }
    }
}
