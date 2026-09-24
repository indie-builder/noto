import SwiftUI
import AppKit
import NotoCore

// Keep the existing persisted "tasks" value for the board.
enum ContentMode: String, CaseIterable, Identifiable {
    case notes, board = "tasks"
    var id: String { rawValue }
    var isTaskView: Bool { self != .notes }
    var label: String { switch self { case .notes: "记录"; case .board: "看板" } }
    var icon: String { switch self { case .notes: "text.alignleft"; case .board: "rectangle.split.3x1" } }
    var shortcut: KeyEquivalent { switch self { case .notes: "1"; case .board: "2" } }
}

// 任务行的共用判定与文案：看板卡与时间线行保持一致。
extension Entry {
    var isImportant: Bool { priority == "important" }
    var isOverdue: Bool { !completed && (due.map { $0 < AppModel.dateKey(Date()) } ?? false) }
    var dueLabel: String { due.map { TaskDates.taskLabel($0, completed: completed) } ?? "" }
}

struct ImportantTaskFilter: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Button { model.setImportantOnly(!model.importantOnly) } label: {
                ActionIcon(model.importantOnly ? "star.fill" : "star")
                    .foregroundStyle(model.importantOnly ? Color.accentColor : Color.secondary)
                    .background(model.importantOnly ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
            }.buttonStyle(QuietButtonStyle(icon: true)).help(model.importantOnly ? "显示全部任务" : "只看重要任务")
                .accessibilityLabel("只看重要任务").accessibilityValue(model.importantOnly ? "已开启" : "已关闭")
        }
    }
}

struct TaskCompletionButton: View {
    let entry: Entry
    @ObservedObject var model: AppModel
    var body: some View {
        Button { model.changeTask(entry, status: entry.completed ? "pending" : "completed") } label: {
            ActionIcon(entry.completed ? "checkmark.circle.fill" : entry.status == "in_progress" ? "circle.lefthalf.filled" : "circle")
                .contentTransition(.symbolEffect(.replace))
                .animation(NotoMotion.animation(.feedback), value: entry.status)
                .foregroundStyle(entry.completed ? Color.accentColor : Color.secondary)
        }.buttonStyle(QuietButtonStyle(icon: true)).help(entry.completed ? "重新打开" : "完成任务")
            .accessibilityLabel(entry.completed ? "重新打开：\(entry.text)" : "完成：\(entry.text)")
    }
}

struct TaskBoard: View {
    @ObservedObject var model: AppModel
    @State private var column: TodoStatus = .pending
    @State private var revealedTaskID: String?
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 720
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 4) {
                    if compact && !model.dueOnly {
                        ForEach(TodoStatus.allCases, id: \.self) { status in
                            TaskDropArea(onDrop: { entry in
                                guard model.changeTask(entry, status: status.rawValue) else { return false }
                                column = status; return true
                            }) {
                                Button { column = status } label: {
                                    HStack(spacing: 6) {
                                        Text(status.label)
                                        Text("\(model.taskColumns[status.rawValue]?.count ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                                    }.font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                        .background {
                                            if column == status {
                                                RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07))
                                            }
                                        }
                                        .animation(NotoMotion.animation(.navigation), value: column == status)
                                }.buttonStyle(NavigationButtonStyle(minHeight: 32)).accessibilityLabel("显示\(status.label)")
                                    .accessibilityAddTraits(column == status ? .isSelected : [])
                                    .help("显示\(status.label)；拖入任务可更改状态")
                            }.frame(maxWidth: .infinity).frame(height: 32)
                        }
                    } else { Spacer() }
                    ImportantTaskFilter(model: model)
                }
                if model.dueOnly || model.importantOnly || !model.search.isEmpty {
                    FilterStatusRow(model: model, dueOnlyTitle: "到期待办 · \(model.visibleTasks.count) 项")
                }
                if model.dueOnly {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if model.visibleTasks.isEmpty { Text("暂无到期待办").font(NotoDesign.caption).foregroundStyle(.secondary).padding(24) }
                            ForEach(model.visibleTasks) { entry in TaskCard(entry: entry, model: model) }
                        }.frame(maxWidth: 620).frame(maxWidth: .infinity)
                    }
                } else if compact {
                    ZStack { TaskColumn(model: model, status: column, showsHeading: false).id(column).transition(.opacity) }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(TodoStatus.allCases, id: \.self) { status in TaskColumn(model: model, status: status) }
                    }
                }
            }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
                .animation(NotoMotion.animation(.navigation), value: column)
        }
        .onChange(of: model.tasks) { _, tasks in revealNewTask(in: tasks) }
        .onChange(of: model.highlightedTaskID) { _, _ in revealNewTask(in: model.tasks) }
    }
    private func revealNewTask(in tasks: [Entry]) {
        guard let id = model.highlightedTaskID, id != revealedTaskID,
              let task = tasks.first(where: { $0.id == id }), let status = TodoStatus(rawValue: task.status ?? "pending") else { return }
        column = status; revealedTaskID = id
    }
}


private struct TaskColumn: View {
    @ObservedObject var model: AppModel
    let status: TodoStatus
    var showsHeading = true
    @State private var occupied: [CGRect] = []
    private var inputSpace: String { "board-" + status.rawValue }
    private var tasks: [Entry] { model.taskColumns[status.rawValue] ?? [] }
    private var displayed: [Entry] { status == .completed ? Array(tasks.prefix(model.completedLimit)) : tasks }
    var body: some View {
        TaskDropArea(onDrop: { model.changeTask($0, status: status.rawValue) }) {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeading {
                    HStack(spacing: 8) {
                        Text(status.label).font(.system(size: 13, weight: .medium))
                        Text("\(tasks.count)").font(NotoDesign.caption).monospacedDigit().foregroundStyle(.secondary)
                            .contentTransition(.numericText()).animation(NotoMotion.animation(.feedback), value: tasks.count)
                        Spacer()
                    }.frame(height: 28)
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if displayed.isEmpty {
                            Button("添加任务") { model.quickCreateTask(status: status.rawValue) }
                                .buttonStyle(QuietButtonStyle()).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 24).excludeFromBlankInput(in: inputSpace)
                        }
                        ForEach(displayed) { entry in
                            TaskCard(entry: entry, model: model)
                                .excludeFromBlankInput(in: inputSpace).transition(.opacity.combined(with: .scale(scale: 0.985)))
                        }
                        if displayed.count < tasks.count {
                            Button("加载更多") { model.completedLimit += 20 }
                                .buttonStyle(QuietButtonStyle()).font(NotoDesign.caption).padding(.vertical, 10).excludeFromBlankInput(in: inputSpace)
                        }
                    }.padding(2)
                        .animation(NotoMotion.animation(.layout), value: displayed.map(\.id))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .coordinateSpace(name: inputSpace)
            .onPreferenceChange(OccupiedAreas.self) { if $0 != occupied { occupied = $0 } }
            .background(BlankClickObserver(excluded: occupied, floatingRect: nil,
                onDoubleClick: { _ in model.quickCreateTask(status: status.rawValue) }, onOutsideClick: {}))
        }
    }
}

/// 状态切换与重要标记的菜单项：任务菜单与时间线记录菜单共用。
@ViewBuilder func taskStateItems(entry: Entry, model: AppModel) -> some View {
    ForEach(TodoStatus.allCases, id: \.self) { status in
        Button { model.changeTask(entry, status: status.rawValue) } label: {
            if entry.status == status.rawValue { Label(status.label, systemImage: "checkmark") }
            else { Text(status.label) }
        }
    }
    Button(entry.isImportant ? "取消重要" : "标记重要") {
        model.changeTask(entry, priority: entry.isImportant ? "normal" : "important")
    }
}

/// 任务卡与日历行共用的操作菜单：编辑、对话、状态、重要、删除。
struct TaskActionMenu: View {
    let entry: Entry
    @ObservedObject var model: AppModel
    var body: some View {
        Menu {
            Button("编辑任务") { model.beginEditing(entry) }
            Button(entry.hasConversation ? "打开对话" : "与 AI 讨论") { model.openConversation(entry) }.disabled(model.busy)
            taskStateItems(entry: entry, model: model)
            Divider()
            Button("删除任务", role: .destructive) { model.deleteTask(entry) }.disabled(model.busy)
        } label: { ActionIcon("ellipsis") }
            .actionMenuStyle().help("任务操作").accessibilityLabel("任务操作")
    }
}

/// 匹配计数 + 一键清除筛选；看板筛选行共用。
struct FilterStatusRow: View {
    @ObservedObject var model: AppModel
    /// 到期筛选下的专属标题；不传则为「N 条匹配任务」。
    var dueOnlyTitle: String?
    var body: some View {
        HStack {
            Text(model.dueOnly && dueOnlyTitle != nil ? dueOnlyTitle! : "\(model.visibleTasks.count) 条匹配任务")
                .foregroundStyle(.secondary)
            Button("清除筛选") { model.clearFilters() }.buttonStyle(QuietButtonStyle())
        }.font(NotoDesign.caption)
    }
}

/// 星标切换：重要时点亮，普通时置灰。
struct ImportantTaskToggle: View {
    let entry: Entry
    @ObservedObject var model: AppModel
    var body: some View {
        Button { model.changeTask(entry, priority: entry.isImportant ? "normal" : "important") } label: {
            ActionIcon(entry.isImportant ? "star.fill" : "star")
                .foregroundStyle(entry.isImportant ? Color.accentColor : Color.secondary)
        }.buttonStyle(QuietButtonStyle(icon: true))
            .help(entry.isImportant ? "取消重要" : "标记重要")
            .accessibilityLabel(entry.isImportant ? "取消重要" : "标记重要")
    }
}

struct TaskCard: View {
    @State private var hovering = false
    let entry: Entry
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                TaskCompletionButton(entry: entry, model: model)
                TaskCardTitle(entry: entry) { model.beginEditing(entry) }.padding(.top, 4)
            }
            HStack(spacing: 4) {
                if entry.isImportant {
                    ImportantTaskToggle(entry: entry, model: model)
                }
                if let due = entry.due {
                    Text(TaskDates.taskLabel(due, completed: entry.completed))
                        .font(.system(size: 11)).foregroundStyle(entry.isOverdue ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if entry.hasConversation { ConversationShortcut(entry: entry, model: model, compact: true) }
                Spacer(minLength: 0)
                if !entry.hasConversation { ConversationShortcut(entry: entry, model: model, revealed: hovering) }
                TaskActionMenu(entry: entry, model: model)
            }.padding(.leading, 34)
        }
        .padding(12)
        .background(model.highlightedTaskID == entry.id ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { model.beginEditing(entry) }
        .onHover { hovering = $0 }
    }
}
