import Foundation
import NotoCore

// 派生视图：时间线按日分组、任务看板筛选与 AI 上下文。
// 缓存存在类主体里，由 entries/tasks/dueOnly/importantOnly/editing 的 didSet 失效。

extension AppModel {
    var filtered: [Entry] { mode.isTaskView ? visibleTasks : entries }

    var aiContext: [Entry] {
        if aiUsesCurrentView { return filtered }
        return conversation.map { [$0] } ?? []
    }

    var aiContextLabel: String {
        aiUsesCurrentView ? "\(mode.isTaskView ? "筛选任务" : "已载入记录") · \(aiContext.count) 条" : "当前记录"
    }

    struct DayGroup: Identifiable {
        let id: String
        let date: Date
        var entries: [Entry]
        var label: String {
            if Calendar.current.isDateInToday(date) { return "今天" }
            if Calendar.current.isDateInYesterday(date) { return "昨天" }
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let prefix = parts.year == Calendar.current.component(.year, from: Date()) ? "" : "\(parts.year!)年"
            return "\(prefix)\(parts.month!)月\(parts.day!)日"
        }
        var shortLabel: String {
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let prefix = parts.year == Calendar.current.component(.year, from: Date()) ? "" : String(format: "%02d.", parts.year! % 100)
            return prefix + String(format: "%02d.%02d", parts.month!, parts.day!)
        }
    }

    var groups: [DayGroup] {
        if groupsTimeZone != .current { invalidateDerivedViews(); groupsTimeZone = .current }
        return memo("groups") {
            var result: [DayGroup] = []
            var visible = entries
            // Keep an active editor reachable if an external change removes its search match.
            if let editing, !visible.contains(where: { $0.id == editing.id }) {
                visible.append(editing)
                visible.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }
            }
            for entry in visible {
                let key = Self.dateKey(entry.createdAt)
                if result.last?.id == key { result[result.count - 1].entries.append(entry) }
                else { result.append(DayGroup(id: key, date: entry.createdAt, entries: [entry])) }
            }
            return result
        }
    }

    var visibleTasks: [Entry] {
        memo("visibleTasks") {
            tasks.filter {
                (!importantOnly || $0.priority == "important") &&
                (!dueOnly || (!$0.completed && ($0.due.map { $0 <= Self.dateKey(Date()) } ?? false)))
            }
        }
    }

    var taskColumns: [String: [Entry]] {
        memo("taskColumns") { Dictionary(grouping: visibleTasks, by: { $0.status ?? "pending" }) }
    }

    var calendarTasks: [Entry] {
        memo("calendarTasks") {
            visibleTasks.sorted {
                if $0.completed != $1.completed { return !$0.completed }
                if $0.priority != $1.priority { return $0.priority == "important" }
                return $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
            }
        }
    }

    var calendarGroups: [String: [Entry]] {
        memo("calendarGroups") { Dictionary(grouping: calendarTasks, by: { $0.due ?? "" }) }
    }

    var calendarDetailTasks: [Entry] { calendarGroups[calendarUnscheduled ? "" : Self.dateKey(selectedCalendarDate)] ?? [] }
}
