import Foundation
import GRDB

// 对话：问答消息的原子落库与 AI actions 的事务化应用。

extension Store {
    public func startConversation(_ question: String) throws -> Entry {
        var entry = Entry(kind: "note", text: question.trimmingCharacters(in: .whitespacesAndNewlines))
        entry.hasConversation = true
        try Self.validate(entry)
        return try db.write { db in
            try entry.insert(db)
            try ChatMessage(entryID: entry.id, role: "user", text: entry.text).insert(db)
            return try Entry.fetchOne(db, key: entry.id)!
        }
    }

    public func messages(for entryID: String) throws -> [ChatMessage] {
        try db.read { try ChatMessage.filter(Column("entryID") == entryID).order(Column("id")).fetchAll($0) }
    }

    public func setExecution(_ text: String, for question: ChatMessage) throws {
        guard let id = question.id else { throw NotoError("消息不存在。") }
        try db.write { db in
            try db.execute(sql: "UPDATE messages SET execution = ? WHERE id = ? AND entryID = ? AND role = 'user'", arguments: [text, id, question.entryID])
        }
    }

    public func appendQuestion(_ text: String, to entryID: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 50_000 else { throw NotoError("问题不能为空，且不能超过 50,000 字。") }
        try db.write { db in
            guard var entry = try Entry.fetchOne(db, key: entryID) else { throw NotoError("记录不存在。") }
            if !entry.hasConversation {
                entry.hasConversation = true
                try entry.update(db)
            }
            try ChatMessage(entryID: entryID, role: "user", text: text).insert(db)
        }
    }

    /// apply 前的一致性校验：回复目标未变、expected 快照未变，任一失配整体回滚。
    private func guardUnchanged(_ db: Database, actions: [AIAction], expected: [Entry]?, replyingTo: ChatMessage?) throws {
        if let question = replyingTo {
            let last = try ChatMessage.filter(Column("entryID") == question.entryID).order(Column("id").desc).fetchOne(db)
            guard last?.id == question.id, last?.text == question.text, question.role == "user" else {
                throw NotoError("对话已发生变化，或回复为空，请重新打开后重试。")
            }
        }
        if let expected {
            let originals = Dictionary(expected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for id in actions.compactMap(\.id) {
                guard originals[id] == (try Entry.fetchOne(db, key: id)) else {
                    throw NotoError("相关记录刚刚被修改，请重新提交这次操作。")
                }
            }
        }
    }

    /// One transaction per AI reply: every action lands or none does.
    public func apply(_ actions: [AIAction], expected: [Entry]? = nil, replyingTo: ChatMessage? = nil, reply: String? = nil) throws -> [Entry] {
        guard actions.count <= 30 else { throw NotoError("一次最多修改 30 条记录。") }
        guard replyingTo == nil || (reply != nil && !reply!.isEmpty && reply!.count <= 50_000) else {
            throw NotoError("对话已发生变化，或回复为空，请重新打开后重试。")
        }
        return try db.write { db in
            try guardUnchanged(db, actions: actions, expected: expected, replyingTo: replyingTo)
            var result: [Entry] = []
            for action in actions {
                switch action.operation {
                case "add_note", "add_todo":
                    let entry = Entry(kind: action.operation == "add_note" ? "note" : "todo", text: (action.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), due: action.due, status: action.status, priority: action.priority)
                    try Self.validate(entry); try entry.insert(db); result.append(entry)
                case "complete", "reopen":
                    guard let id = action.id, var entry = try Entry.fetchOne(db, key: id) else { throw NotoError("AI 引用的记录不存在，未做任何修改。") }
                    guard entry.kind == "todo" else { throw NotoError("只能完成或重新打开待办。") }
                    try Self.modify(&entry, status: action.operation == "complete" ? "completed" : "pending")
                    try entry.update(db); result.append(entry)
                case "update", "convert_to_todo":
                    guard let id = action.id, var entry = try Entry.fetchOne(db, key: id) else { throw NotoError("AI 引用的记录不存在，未做任何修改。") }
                    try Self.modify(&entry, text: action.text, due: action.due, clearDue: action.clearDue ?? false,
                                    status: action.status, priority: action.priority, convert: action.operation == "convert_to_todo")
                    try entry.update(db); result.append(entry)
                default: throw NotoError("AI 返回了不支持的操作，未做任何修改。")
                }
            }
            if let question = replyingTo, let reply {
                try ChatMessage(entryID: question.entryID, role: "assistant", text: reply).insert(db)
            }
            return try result.map { try Entry.fetchOne(db, key: $0.id)! }
        }
    }
}
