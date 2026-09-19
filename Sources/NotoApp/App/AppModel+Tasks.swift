import Foundation
import NotoCore

struct TaskDraftAttributes: Equatable {
    var status = "pending"
    var important = false
    var due: String?
}

// 任务域：删除恢复、看板筛选与草稿。
extension AppModel {
    func deleteTask(_ entry: Entry) {
        guard !busy, leaveUnchangedEditor(), let store else { return }
        let unsentQuestion = conversation?.id == entry.id ? drafts.chat : chatDrafts[entry.id] ?? ""
        if !unsentQuestion.isEmpty {
            fail(NotoError("请先发送或清空这条任务的对话草稿。")); return
        }
        do {
            try store.deleteTodo(id: entry.id, expected: entry)
            lastDeletedTaskID = entry.id
            if conversation?.id == entry.id { conversation = nil; messages = []; drafts.chat = ""; readingRequested = true }
            chatDrafts.removeValue(forKey: entry.id)
            message = "已删除任务，可恢复上次删除。"; isError = false; reload()
        } catch { fail(error) }
    }

    func restoreLastDeletedTask() {
        guard let id = lastDeletedTaskID else { return }
        do { try restoreTask(id) } catch { fail(error) }
    }
    func restoreTask(_ id: String) throws {
        guard let store else { throw NotoError("无法打开本地数据。") }
        try store.restoreTodo(id: id)
        if lastDeletedTaskID == id { lastDeletedTaskID = nil }
        message = "已恢复任务。"; isError = false; reload()
    }

    /// 最近删除列表：读取走 AppModel，按当前 store 身份丢弃过期结果。
    func deletedTasks() async -> [Entry] {
        guard let store else { return [] }
        let result = (try? await Task.detached(priority: .utility) { try store.deletedTodos() }.value) ?? []
        guard store === self.store else { return [] }
        return result
    }

    func showDueTasks() {
        guard leaveUnchangedEditor() else { return }
        switchMode(.board)
        importantOnly = false; search = ""; dueOnly = true
    }

    func switchMode(_ value: ContentMode) {
        guard value != mode, leaveUnchangedEditor() else { return }
        composerPosition = nil; readingRequested = true
        mode = value; dueOnly = false; completedLimit = 20
        if search.isEmpty { reload(reset: true) } else { search = "" }
    }

    func setImportantOnly(_ value: Bool) {
        guard leaveUnchangedEditor() else { return }
        importantOnly = value; completedLimit = 20
    }

    /// 看板与日历筛选行的统一清除动作。
    func clearFilters() {
        setSearch(""); setImportantOnly(false); dueOnly = false
    }

    func showNewTask(status: String = "pending") {
        if taskCreating { return }
        guard leaveUnchangedEditor() else { return }
        composerPosition = nil; readingRequested = true
        taskDraftState.restored = taskDraftState.started && taskDraftDirty
        if !taskDraftState.restored {
            taskDraftState.status = status
            taskDraftState.hasDue = false
            taskDraftState.date = Date()
            taskDraftState.important = false
            taskDraftState.baseline = taskDraftState.attributes
        }
        taskDraftState.started = true; edit.error = ""; taskCreating = true
    }

    /// A fresh quick-entry adopts the clicked context; reopening a draft preserves its choices.
    func quickCreateTask(status: String = "pending", date: Date? = nil) {
        guard !taskCreating, !settings, !recentlyDeleted else { return }
        let resuming = taskDraftState.started && taskDraftDirty
        showNewTask(status: status)
        guard taskCreating, !resuming else { return }
        taskDraftState.hasDue = date != nil
        if let date { taskDraftState.date = date }
        taskDraftState.important = importantOnly
        taskDraftState.baseline = taskDraftState.attributes
    }

    func saveNewTask() {
        guard !drafts.task.isBlank else { return }
        do {
            guard let store else { throw NotoError("无法打开本地数据，草稿已保留。") }
            let entry = try store.add(kind: "todo", text: drafts.task,
                                      due: taskDraftState.hasDue ? Self.dateKey(taskDraftState.date) : nil,
                                      status: taskDraftState.status, priority: taskDraftState.important ? "important" : "normal")
            taskCreating = false; taskDraftState.reset(); drafts.task = ""
            dueOnly = false
            if !search.isEmpty { search = "" }
            if importantOnly && entry.priority != "important" { importantOnly = false }
            remember(before: [], after: [entry], message: "已添加任务。")
            highlightedTaskID = entry.id
        } catch { edit.error = error.localizedDescription }
    }

    @discardableResult
    func changeTask(_ entry: Entry, status: String? = nil, priority: String? = nil, due: String? = nil, clearDue: Bool = false) -> Bool {
        guard leaveUnchangedEditor() else { return false }
        do {
            guard let store else { throw NotoError("无法打开本地数据。") }
            let changed = try store.updateTodo(id: entry.id, due: due, clearDue: clearDue, status: status, priority: priority, expected: entry)
            if changed != entry {
                remember(before: [entry], after: [changed], message: "已更新任务。")
                if conversation?.id == entry.id { conversation = changed }
            }
            return true
        } catch { fail(error); reload(); return false }
    }

    func convertToTask(_ entry: Entry) {
        guard leaveUnchangedEditor() else { return }
        do {
            guard let store else { throw NotoError("无法打开本地数据。") }
            let changed = try store.convertToTodo(id: entry.id, expected: entry)
            remember(before: [entry], after: [changed], message: "已转为任务。")
            convertedTaskID = changed.id
            if conversation?.id == changed.id { conversation = changed }
        } catch { fail(error) }
    }

    func showConvertedTask() {
        guard let id = convertedTaskID, leaveUnchangedEditor() else { return }
        importantOnly = false; highlightedTaskID = id; taskToEditAfterReload = id
        if mode == .board { reload(reset: true) } else { switchMode(.board) }
    }

}
