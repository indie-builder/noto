import SwiftUI
import AppKit
import NotoCore

// 应用级状态中枢：持有数据快照、加载管线与账号切换。
// 业务动作按域拆在 AppModel+Editing / +Conversation / +Tasks，日期分组在 AppModel+Groups。

/// 新建任务的完整草稿状态；attributes/baseline 对比得出 dirty。
struct TaskDraftState {
    var started = false
    var restored = false
    var status = "pending"
    var important = false
    var hasDue = false
    var date = Date()
    var baseline = TaskDraftAttributes()
    var attributes: TaskDraftAttributes {
        TaskDraftAttributes(status: status, important: important, due: hasDue ? AppModel.dateKey(date) : nil)
    }
    func dirty(text: String) -> Bool { !text.isBlank || attributes != baseline }
    mutating func reset() {
        self = TaskDraftState()
    }
}

/// 行内/任务编辑的属状态；正文草稿在 TextDrafts.edit。
struct EditState {
    var status = "pending"
    var important = false
    var hasDue = false
    var date = Date()
    var error = ""
}

@MainActor
final class AppModel: ObservableObject {
    @Published var entries: [Entry] = [] { didSet { invalidateDerivedViews() } }
    @Published var tasks: [Entry] = [] { didSet { invalidateDerivedViews() } }
    @Published var mode: ContentMode = .notes { didSet { if persistsViewMode { UserDefaults.standard.set(mode.rawValue, forKey: "contentMode") } } }
    @Published var taskDraftState = TaskDraftState()
    @Published var dueOnly = false { didSet { invalidateDerivedViews() } }
    @Published var importantOnly = false { didSet { invalidateDerivedViews() } }
    @Published var completedLimit = 20
    @Published var taskCreating = false
    @Published var edit = EditState()
    @Published var convertedTaskID: String?
    @Published var highlightedTaskID: String?
    var taskToEditAfterReload: String?
    @Published var composerPosition: CGPoint?
    @Published var readingRequested = true
    // 输入侧去抖在 SearchInput（commitDelay）；这里收到提交后立即刷新。
    @Published var search = "" { didSet { if search != oldValue { completedLimit = 20; reload(reset: true) } } }
    @Published var hasMore = false
    @Published var loadingMore = false
    @Published var message = ""
    @Published var isError = false
    @Published var busy = false
    @Published var activeProvider: Provider?
    @Published var newConversationOpen = false
    var newConversationDraft = ""
    var conversationVisible: Bool { conversation != nil || newConversationOpen }
    @Published var conversation: Entry?
    @Published var messages: [ChatMessage] = []
    @Published var chatError = ""
    @Published var editing: Entry? { didSet { invalidateDerivedViews() } }
    @Published var settings = false
    @Published var recentlyDeleted = false
    @Published var aiUsesCurrentView = false
    @Published var undoAvailable = false
    @Published var provider: Provider { didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") } }
    private(set) var store: Store?
    @Published var lastDeletedTaskID: String?
    private let persistsViewMode: Bool
    var undoBefore: [Entry] = []
    var undoAfter: [Entry] = []
    var runner: AgentRunner?
    private var timer: Timer?
    private var dataVersion: Int?
    private(set) var reloadTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    @Published private(set) var opening = false
    private var pollTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var reloadGeneration = 0
    @Published private(set) var reloading = false
    private let pageSize = 40
    var chatDrafts: [String: String] = [:]
    /// 逐键变化的输入文本只住在这里（TextDrafts）；保存、清空、恢复都直接读写它。
    let drafts = TextDrafts()
    var taskDraftDirty: Bool { taskDraftState.dirty(text: drafts.task) }
    var editDirty: Bool {
        guard let entry = editing else { return false }
        if drafts.edit != entry.text || editDue != entry.due { return true }
        return entry.kind == "todo" && (edit.status != entry.status || edit.important != (entry.priority == "important"))
    }

    init(store injectedStore: Store? = nil) {
        persistsViewMode = injectedStore == nil && ProcessInfo.processInfo.environment["NOTO_DATABASE"] == nil
        provider = Provider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "opencode") ?? .opencode
        store = injectedStore
        if injectedStore == nil {
            try? AgentWorkspace.migrateLegacy()
            mode = ContentMode(rawValue: UserDefaults.standard.string(forKey: "contentMode") ?? "") ?? .notes
        }
        if let store {
            reload()
        }
        else if !isError {
            opening = true
            startupTask = Task { [weak self] in
                do {
                    let store = try await Task.detached(priority: .userInitiated) {
                        let url = ProcessInfo.processInfo.environment["NOTO_DATABASE"].map { URL(fileURLWithPath: $0) } ?? Store.localURL
                        return try Store(url: url, busyTimeout: 1)
                    }.value
                    guard let self else { return }
                    self.store = store
                    // 数据库打开放后台任务，慢盘不挡首屏。
                    self.opening = false; self.reload()
                } catch {
                    self?.opening = false; self?.fail(error)
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in if NSApp.isActive { self?.refreshIfChanged() } }
        }
        timer?.tolerance = 0.5
    }

    deinit {
        timer?.invalidate()
        startupTask?.cancel(); reloadTask?.cancel(); pollTask?.cancel(); loadTask?.cancel()
    }

    nonisolated static func dateKey(_ date: Date) -> String {
        let parts = TaskDates.local.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    // 派生视图的统一缓存：memo 按名字取/存，输入（entries/tasks/筛选/编辑器）一变整体失效。
    private var derivedCache: [String: Any] = [:]
    func memo<T>(_ key: String, _ make: () -> T) -> T {
        if let value = derivedCache[key] as? T { return value }
        let value = make()
        derivedCache[key] = value
        return value
    }
    func invalidateDerivedViews() { derivedCache.removeAll() }
    var groupsTimeZone = TimeZone.current

    func fail(_ error: Error) { message = error.localizedDescription; isError = true }

    /// 设置或最近删除面板打开时，全局快捷指令全部让位。
    var chromeLocked: Bool { settings || recentlyDeleted }

    // MARK: - 加载管线：版本号 + 代际计数，旧请求的结果直接丢弃。

    func reload(reset: Bool = false, debounce: Bool = false) {
        reloadTask?.cancel(); loadTask?.cancel(); loadingMore = false
        reloadGeneration += 1
        guard let store else { return }
        let generation = reloadGeneration, query = search, taskView = mode.isTaskView
        let limit = reset ? pageSize : max(pageSize, entries.count)
        reloading = true
        reloadTask = Task { [weak self] in
            do {
                if debounce && !query.isEmpty { try await Task.sleep(for: .milliseconds(200)) }
                try Task.checkCancellation()
                let result = try await Task.detached(priority: .userInitiated) {
                    // Read the version first: a concurrent commit will be caught on the next poll.
                    let version = try store.dataVersion()
                    let page = taskView ? nil : try store.page(limit: limit, search: query)
                    let tasks = taskView ? try store.todos(search: query) : nil
                    return (version, page, tasks)
                }.value
                try Task.checkCancellation()
                guard let self, generation == self.reloadGeneration else { return }
                if let page = result.1 {
                    if page.entries != self.entries { self.entries = page.entries }
                    self.hasMore = page.hasMore
                }
                if let tasks = result.2, tasks != self.tasks { self.tasks = tasks }
                self.dataVersion = result.0
                self.reloading = false
                if let id = self.taskToEditAfterReload {
                    self.taskToEditAfterReload = nil
                    if self.mode == .board, self.highlightedTaskID == id,
                       let task = self.tasks.first(where: { $0.id == id }) { self.beginEditing(task) }
                }
            } catch is CancellationError {
                // The newer request owns the loading state and results.
            } catch {
                guard let self, generation == self.reloadGeneration else { return }
                self.reloading = false; self.fail(error)
            }
        }
    }

    func refreshIfChanged() {
        guard pollTask == nil, !reloading, let store else { return }
        let generation = reloadGeneration
        pollTask = Task { [weak self] in
            defer { self?.pollTask = nil }
            do {
                let version = try await Task.detached(priority: .utility) { try store.dataVersion() }.value
                guard let self, generation == self.reloadGeneration else { return }
                if version != self.dataVersion { self.reload() }
            } catch { self?.fail(error) }
        }
    }

    // Also useful for callers that need to act on the newly loaded snapshot.
    func waitForReload() async {
        await startupTask?.value
        await pollTask?.value
        await reloadTask?.value
        await loadTask?.value
    }

    func loadMore() {
        guard hasMore, !loadingMore, !reloading, let cursor = entries.last, let store else { return }
        loadingMore = true
        let generation = reloadGeneration, query = search, limit = pageSize
        loadTask = Task { [weak self] in
            do {
                let page = try await Task.detached(priority: .userInitiated) {
                    try store.page(before: cursor, limit: limit, search: query)
                }.value
                try Task.checkCancellation()
                guard let self, generation == self.reloadGeneration else { return }
                self.entries.append(contentsOf: page.entries)
                self.hasMore = page.hasMore; self.loadingMore = false
            } catch is CancellationError {
            } catch {
                guard let self, generation == self.reloadGeneration else { return }
                self.loadingMore = false; self.fail(error)
            }
        }
    }
}
