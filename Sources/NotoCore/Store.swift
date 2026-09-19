import Foundation
import GRDB

// 持久化中枢：GRDB 打开与迁移。查询在 Store+Timeline，对话在 Store+Conversation，
// 增改与撤销在 Store+Mutation；同步落库在 SyncStore.swift（传输层已随 descope 移除）。
// 模型类型（Entry/ChatMessage/TodoStatus 等）在 Models.swift。

public final class Store: @unchecked Sendable {
    let db: any DatabaseWriter
    public let storageURL: URL?

    /// CLI/App 共享的账号库指针文件：同步移除前的登录遗留，Store.defaultURL 读取以兼容旧安装。
    public static var activeAccountPointer: URL {
        localURL.deletingLastPathComponent().appendingPathComponent("active-account.json")
    }

    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["NOTO_DATABASE"] { return URL(fileURLWithPath: path) }
        let pointer = activeAccountPointer
        if let data = try? Data(contentsOf: pointer), let path = try? JSONDecoder().decode(String.self, from: data) {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let root = localURL.deletingLastPathComponent().appendingPathComponent("accounts").standardizedFileURL.path + "/"
            if url.path.hasPrefix(root), FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return localURL
    }

    public init(url: URL? = Store.defaultURL, busyTimeout: TimeInterval = 1) throws {
        storageURL = url?.standardizedFileURL
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var config = Configuration()
            config.busyMode = .timeout(busyTimeout)
            db = try DatabasePool(path: url.path, configuration: config)
        } else { db = try DatabaseQueue() }
        try Self.migrator().migrate(db)
    }

    private static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "entries") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("text", .text).notNull()
                t.column("due", .text)
                t.column("completed", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "requests") { t in
                t.column("key", .text).primaryKey()
                t.column("entryID", .text).notNull()
            }
        }
        migrator.registerMigration("v2_history_index") { db in
            try db.execute(sql: "CREATE INDEX entries_history ON entries(createdAt DESC, id ASC)")
        }
        migrator.registerMigration("v3_conversations") { db in
            try db.alter(table: "entries") { $0.add(column: "hasConversation", .boolean).notNull().defaults(to: false) }
            try db.create(table: "messages") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entryID", .text).notNull().references("entries", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.execute(sql: "CREATE INDEX messages_entry ON messages(entryID, id)")
        }
        migrator.registerMigration("v4_execution") { db in
            try db.alter(table: "messages") { $0.add(column: "execution", .text) }
        }
        migrator.registerMigration("v5_task_board") { db in
            try db.alter(table: "entries") { t in
                t.add(column: "status", .text)
                t.add(column: "priority", .text)
                t.add(column: "completedAt", .datetime)
            }
            try db.execute(sql: "UPDATE entries SET status = CASE WHEN completed THEN 'completed' ELSE 'pending' END, priority = 'normal', completedAt = CASE WHEN completed THEN updatedAt ELSE NULL END WHERE kind = 'todo'")
            try db.execute(sql: "CREATE INDEX entries_tasks ON entries(kind, status, priority, due)")
        }
        registerSyncMigration(&migrator)
        migrator.registerMigration("v7_search_fts") { db in
            // trigram 分词支撑中英文子串匹配（原 instr 语义），并让搜索走索引。
            try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(text, due, content='entries', content_rowid='rowid', tokenize='trigram')")
            try db.execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(text, content='messages', content_rowid='id', tokenize='trigram')")
            try db.execute(sql: ftsTriggers(table: "entries", key: "rowid", due: true) + ftsTriggers(table: "messages", key: "id", due: false))
            try db.execute(sql: "INSERT INTO entries_fts(entries_fts) VALUES ('rebuild')")
            try db.execute(sql: "INSERT INTO messages_fts(messages_fts) VALUES ('rebuild')")
        }
        return migrator
    }

    /// FTS keeps itself in sync via the insert/delete/update trigger trio; generated
    /// once here because the shape is identical for both tables.
    private static func ftsTriggers(table: String, key: String, due: Bool) -> String {
        let columns = due ? "rowid, text, due" : "rowid, text"
        func values(_ alias: String) -> String {
            due ? "\(alias).\(key), \(alias).text, COALESCE(\(alias).due, '')" : "\(alias).\(key), \(alias).text"
        }
        return """
        CREATE TRIGGER IF NOT EXISTS \(table)_fts_ai AFTER INSERT ON \(table) BEGIN
          INSERT INTO \(table)_fts(\(columns)) VALUES (\(values("new")));
        END;
        CREATE TRIGGER IF NOT EXISTS \(table)_fts_ad AFTER DELETE ON \(table) BEGIN
          INSERT INTO \(table)_fts(\(table)_fts, \(columns)) VALUES ('delete', \(values("old")));
        END;
        CREATE TRIGGER IF NOT EXISTS \(table)_fts_au AFTER UPDATE ON \(table) BEGIN
          INSERT INTO \(table)_fts(\(table)_fts, \(columns)) VALUES ('delete', \(values("old")));
          INSERT INTO \(table)_fts(\(columns)) VALUES (\(values("new")));
        END;
        """
    }

    /// Changes made by other connections; local writes explicitly refresh the UI.
    public func dataVersion() throws -> Int {
        // data_version is connection-local: always use the writer, never a pooled reader.
        try db.writeWithoutTransaction { try Int.fetchOne($0, sql: "PRAGMA data_version") ?? 0 }
    }
}
