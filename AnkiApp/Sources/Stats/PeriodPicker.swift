import SwiftUI

/// 全局两档选择器，对应上游 RevlogRange（近一年 / 全部）。
/// 控制从后端获取多少历史数据，并决定各图表是否显示「全时」选项。
enum RevlogRange: String, CaseIterable {
    case year = "year"
    case all  = "all"

    /// 传给 statsClient.fetchGraphs 的天数（0 = 全部）
    var requestDays: UInt32 {
        switch self {
        case .year: return 365
        case .all:  return 0
        }
    }

    var localizedLabel: String {
        switch self {
        case .year: return L("stats_range_year")
        case .all:  return L("stats_range_all")
        }
    }
}

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
