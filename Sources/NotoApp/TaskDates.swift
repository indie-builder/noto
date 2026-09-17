// 日期运算与领域判定：本地日历、YYYY-MM-DD 解析、月历网格、任务行共用属性。
// 只用本地时区，绝不做 UTC 解析或按 24 小时折算「天」。

import SwiftUI
import NotoCore

/// Calendar arithmetic, never UTC parsing or fixed 24-hour intervals for date-only tasks.
enum TaskDates {
    static let local: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current; calendar.firstWeekday = 2; return calendar }()
    // body 求值路径上的 formatter 必须缓存：DateFormatter 创建是毫秒级开销，且这些方法按行调用。
    private static let monthDayFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = local; formatter.dateFormat = "M月d日"; return formatter }()
    private static let fullDateFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = local; formatter.dateFormat = "yyyy年M月d日"; return formatter }()
    static func taskLabel(_ key: String, completed: Bool = false, today: Date = Date()) -> String {
        guard let value = date(key) else { return key }
        let formatter = local.isDate(value, equalTo: today, toGranularity: .year) ? monthDayFormatter : fullDateFormatter
        if completed { return formatter.string(from: value) }
        if local.isDate(value, inSameDayAs: today) { return "今天" }
        if let tomorrow = local.date(byAdding: .day, value: 1, to: today), local.isDate(value, inSameDayAs: tomorrow) { return "明天" }
        return value < local.startOfDay(for: today) ? "已逾期 · " + formatter.string(from: value) : formatter.string(from: value)
    }
    static func monthDayFormat(_ date: Date) -> String { monthDayFormatter.string(from: date) }
    static func date(_ key: String, calendar: Calendar = local) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              calendar.component(.year, from: date) == parts[0], calendar.component(.month, from: date) == parts[1], calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }
}
