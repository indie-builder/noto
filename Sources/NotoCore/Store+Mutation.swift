import Foundation
import GRDB

// 增改与撤销：所有写入路径汇聚到 change/modify，保证校验与 updatedAt 只写一处。

extension Store {
    public func add(kind: String, text: String, due: String? = nil, requestID: String? = nil, status: String? = nil, priority: String? = nil) throws -> Entry {
        let entry = Entry(kind: kind, text: text.trimmingCharacters(in: .whitespacesAndNewlines), due: due, status: status, priority: priority)
        try Self.validate(entry)
        return try db.write { db in
            if let requestID,
               let id = try String.fetchOne(db, sql: "SELECT entryID FROM requests WHERE key = ?", arguments: [requestID]),
               let existing = try Entry.fetchOne(db, key: id) {
                guard existing.kind == entry.kind, existing.text == entry.text, existing.due == entry.due, existing.status == entry.status, existing.priority == entry.priority else {
                    throw NotoError("相同 request-id 已用于不同内容。")
                }
                return existing
            }
            try entry.insert(db)
            if let requestID { try db.execute(sql: "INSERT INTO requests (key, entryID) VALUES (?, ?)", arguments: [requestID, entry.id]) }
            return try Entry.fetchOne(db, key: entry.id)!
        }
    }

    public func updateNote(id: String, text: String) throws -> Entry {
        try change(id: id, text: text, noteOnly: true)
    }

    public func setCompleted(id: String, completed: Bool, expected: Entry? = nil) throws -> Entry {
        try updateTodo(id: id, status: completed ? "completed" : "pending", expected: expected)
    }

    public func update(id: String, text: String, due: String?, expected: Entry? = nil) throws -> Entry {
        try change(id: id, text: text, due: due, clearDue: due == nil, expected: expected)
    }

    public func updateTodo(id: String, text: String? = nil, due: String? = nil, clearDue: Bool = false,
                           status: String? = nil, priority: String? = nil, expected: Entry? = nil) throws -> Entry {
        try change(id: id, text: text, due: due, clearDue: clearDue, status: status, priority: priority, todoOnly: true, expected: expected)
    }

    public func convertToTodo(id: String, expected: Entry? = nil) throws -> Entry {
        try change(id: id, convert: true, expected: expected)
    }

    private func change(id: String, text: String? = nil, due: String? = nil, clearDue: Bool = false,
                        status: String? = nil, priority: String? = nil, todoOnly: Bool = false,
                        convert: Bool = false, noteOnly: Bool = false, expected: Entry? = nil) throws -> Entry {
        try db.write { db in
            guard var entry = try Entry.fetchOne(db, key: id), !todoOnly || entry.kind == "todo" else { throw NotoError("记录不存在或不是任务。") }
            if noteOnly && entry.kind != "note" { throw NotoError("笔记不存在。") }
            if let expected, expected != entry { throw NotoError("这条记录已在其他地方修改。草稿已保留，请取消后重新打开记录。") }
            try Self.modify(&entry, text: text, due: due, clearDue: clearDue, status: status, priority: priority, convert: convert)
            try entry.update(db)
            return try Entry.fetchOne(db, key: entry.id)!
        }
    }

    /// 撤销只回滚这次操作的记录；其他进程的并发修改用乐观校验拦下。
    public func undo(before: [Entry], after: [Entry]) throws {
        try db.write { db in
            for changed in after {
                guard try Entry.fetchOne(db, key: changed.id) == changed else { throw NotoError("记录已被其他操作修改，无法直接撤销。") }
            }
            let originals = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for changed in after {
                if let original = originals[changed.id] { try original.update(db) }
                else { _ = try Entry.deleteOne(db, key: changed.id) }
            }
        }
    }

    static func validate(_ entry: Entry) throws {
        let length = entry.kind == "todo" ? entry.text.unicodeScalars.count : entry.text.count
        guard ["note", "todo"].contains(entry.kind), !entry.text.isEmpty, length <= 50_000 else {
            throw NotoError("内容不能为空，且不能超过 50,000 字。")
        }
        if entry.kind == "todo" {
            guard let status = entry.status, TodoStatus(rawValue: status) != nil,
                  let priority = entry.priority, TodoPriority(rawValue: priority) != nil,
                  entry.completed == (status == "completed"), (entry.completedAt != nil) == entry.completed else {
                throw NotoError("任务状态或优先级无效。")
            }
        } else if entry.status != nil || entry.priority != nil || entry.completedAt != nil || entry.completed {
            throw NotoError("只有任务可以设置状态和优先级。")
        }
        if let due = entry.due {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard due.count == 10, let date = formatter.date(from: due), formatter.string(from: date) == due else {
                throw NotoError("日期请使用有效的 YYYY-MM-DD 格式。")
            }
            guard entry.kind == "todo" else { throw NotoError("只有待办可以设置日期。") }
        }
    }

    /// Apply field changes to an entry in place; bumps updatedAt only when something changed.
    static func modify(_ entry: inout Entry, text: String? = nil, due: String? = nil, clearDue: Bool = false,
                       status: String? = nil, priority: String? = nil, convert: Bool = false) throws {
        let before = entry
        if convert && entry.kind == "note" { entry.kind = "todo"; entry.status = "pending"; entry.priority = "normal" }
        if let text { entry.text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if clearDue && due != nil { throw NotoError("不能同时设置和清除截止日期。") }
        if clearDue { entry.due = nil } else if let due { entry.due = due }
        if let status {
            if status != entry.status { entry.completedAt = status == "completed" ? Date() : nil }
            entry.status = status
        }
        if let priority { entry.priority = priority }
        entry.completed = entry.status == "completed"
        try validate(entry)
        if entry != before { entry.updatedAt = Date() }
    }
}
