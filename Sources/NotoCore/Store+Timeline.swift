import Foundation
import GRDB

// 只读查询：时间线分页、任务看板、搜索与备份。

extension Store {
    public func list(kind: String? = nil) throws -> [Entry] {
        try db.read { db in
            var query = Entry.all()
            if let kind { query = query.filter(Column("kind") == kind) }
            return try query.order(Column("createdAt").desc, Column("id")).fetchAll(db)
        }
    }

    public func entry(id: String) throws -> Entry? {
        try db.read { try Entry.fetchOne($0, key: id) }
    }

    public struct Backup: Encodable {
        public let entries: [Entry]
        public let conversations: [String: [ChatMessage]]
    }

    /// Both tables come from one snapshot, with two queries regardless of conversation count.
    public func backup() throws -> Backup {
        try db.read { db in
            let entries = try Entry.order(Column("createdAt").desc, Column("id")).fetchAll(db)
            let messages = try ChatMessage.order(Column("id")).fetchAll(db)
            var conversations = Dictionary(grouping: messages, by: \.entryID)
            for entry in entries where entry.hasConversation && conversations[entry.id] == nil {
                conversations[entry.id] = []
            }
            return Backup(entries: entries, conversations: conversations)
        }
    }

    /// 子串搜索：≥3 个字符走 trigram FTS 索引（中英文子串均可），更短的查询回退 instr 全表扫描。
    private static func searchFilter(_ search: String) -> (sql: String, arguments: [String]) {
        if search.count >= 3 {
            let phrase = "\"" + search.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            return (sql: """
                (entries.rowid IN (SELECT rowid FROM entries_fts WHERE entries_fts MATCH ?)
                 OR EXISTS (SELECT 1 FROM messages WHERE messages.entryID = entries.id
                            AND messages.id IN (SELECT rowid FROM messages_fts WHERE messages_fts MATCH ?)))
                """, arguments: [phrase, phrase])
        }
        return (sql: "(instr(lower(entries.text), lower(?)) > 0 OR instr(COALESCE(due, ''), ?) > 0 OR EXISTS (SELECT 1 FROM messages WHERE messages.entryID = entries.id AND instr(lower(messages.text), lower(?)) > 0))", arguments: [search, search, search])
    }

    /// 任务排序：进行中的在前，完成的按结束时间倒序；未完成先重要后截止日期。
    private static let taskOrder = """
        CASE status WHEN 'pending' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END,
        CASE WHEN status = 'completed' THEN completedAt END DESC,
        CASE WHEN status != 'completed' THEN priority = 'important' END DESC,
        CASE WHEN status != 'completed' THEN due IS NULL END ASC,
        CASE WHEN status != 'completed' THEN due END ASC,
        createdAt DESC, id ASC
        """

    /// Independent of the timeline's 40-row window; searches full task conversations.
    // ponytail: fetch matching tasks for column counts; move completed paging into SQL if large archives slow refresh.
    public func todos(search: String = "", status: String = "all", priority: String? = nil) throws -> [Entry] {
        guard ["all", "open"].contains(status) || TodoStatus(rawValue: status) != nil else { throw NotoError("任务状态无效。") }
        if let priority, TodoPriority(rawValue: priority) == nil { throw NotoError("任务优先级无效。") }
        return try db.read { db in
            var query = Entry.filter(Column("kind") == "todo")
            if status == "open" { query = query.filter(Column("status") != "completed") }
            else if status != "all" { query = query.filter(Column("status") == status) }
            if let priority { query = query.filter(Column("priority") == priority) }
            if !search.isEmpty {
                let filter = Self.searchFilter(search)
                query = query.filter(sql: filter.sql, arguments: StatementArguments(filter.arguments))
            }
            return try query.order(sql: Self.taskOrder).fetchAll(db)
        }
    }

    public struct Page: Sendable {
        public let entries: [Entry]
        public let hasMore: Bool
    }

    /// Keyset pagination: tied timestamps are ordered by ID; new inserts do not shift older pages.
    public func page(before: Entry? = nil, limit: Int = 40, search: String = "") throws -> Page {
        guard limit > 0 else { throw NotoError("分页数量必须大于零。") }
        return try db.read { db in
            var query = Entry.all()
            if let before {
                query = query.filter(Column("createdAt") < before.createdAt || (Column("createdAt") == before.createdAt && Column("id") > before.id))
            }
            if !search.isEmpty {
                let filter = Self.searchFilter(search)
                query = query.filter(sql: filter.sql, arguments: StatementArguments(filter.arguments))
            }
            let rows = try query.order(Column("createdAt").desc, Column("id")).limit(limit + 1).fetchAll(db)
            return Page(entries: Array(rows.prefix(limit)), hasMore: rows.count > limit)
        }
    }
}
