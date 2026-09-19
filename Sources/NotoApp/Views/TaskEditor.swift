// 任务编辑器：新建与编辑共用一张表单；日期控件是可选截止日期的唯一入口。

import SwiftUI
import NotoCore

struct TaskEditor: View {
    @State private var confirmClose = false
    @ObservedObject var model: AppModel
    @ObservedObject var drafts: TextDrafts
    private var creating: Bool { model.taskCreating }
    private var text: Binding<String> { creating ? $drafts.task : $drafts.edit }
    private var status: Binding<String> { creating ? $model.taskDraftState.status : $model.edit.status }
    private var important: Binding<Bool> { creating ? $model.taskDraftState.important : $model.edit.important }
    private var hasDue: Binding<Bool> { creating ? $model.taskDraftState.hasDue : $model.edit.hasDue }
    private var date: Binding<Date> { creating ? $model.taskDraftState.date : $model.edit.date }
    private func save() { if creating { model.saveNewTask() } else { model.saveEditing() } }
    private func cancel() {
        if !creating && model.editDirty { confirmClose = true }
        else { model.taskCreating = false; model.cancelEditing() }
    }
    private var attributesLabel: String {
        let state = TodoStatus(rawValue: status.wrappedValue)?.label ?? "待开始"
        return status.wrappedValue == "pending" ? (important.wrappedValue ? "重要" : "更多") : state
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(creating ? (model.taskDraftState.restored ? "继续草稿" : "新建任务") : "编辑任务")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button(action: cancel) { ActionIcon("xmark") }
                    .buttonStyle(QuietButtonStyle(icon: true))
                    .help(creating ? "收起，保留草稿（Esc）" : "取消编辑（Esc）")
                    .accessibilityLabel(creating ? "收起新建任务，保留草稿" : "取消编辑")
            }
            Composer(text: text, purpose: .edit, onSubmit: save, onCancel: cancel, placeholder: "想做什么？")
                .frame(minHeight: 48).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18).padding(.bottom, 22)
            if !model.edit.error.isEmpty {
                ErrorLabel(text: model.edit.error).padding(.bottom, 12)
            }
            HStack(spacing: 4) {
                TaskDateControl(hasDue: hasDue, date: date)
                Menu {
                    Toggle("重要任务", isOn: important)
                    Divider()
                    Picker("状态", selection: status) {
                        ForEach(TodoStatus.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }.pickerStyle(.inline)
                } label: {
                    Label(attributesLabel, systemImage: important.wrappedValue ? "star.fill" : "ellipsis")
                        .font(.system(size: 12)).padding(.horizontal, 8).frame(height: 28)
                        .foregroundStyle(important.wrappedValue ? Color.accentColor : Color.secondary)
                }.actionMenuStyle().accessibilityLabel("任务属性")
                    .accessibilityValue("\(TodoStatus(rawValue: status.wrappedValue)?.label ?? "待开始")，\(important.wrappedValue ? "重要" : "普通")")
                    .help("设置重要标记和任务状态")
                Spacer(minLength: 12)
                Button(creating ? "创建" : "保存", action: save)
                    .buttonStyle(QuietButtonStyle(prominent: true)).help("⌘↵ 保存；回车换行")
                    .disabled(text.wrappedValue.isBlank)
            }
        }
        .padding(24).frame(width: 440)
        .background(NotoGlassSurface(radius: 20))
        .interactiveDismissDisabled(model.editDirty || (creating && model.taskDraftDirty))
        .onExitCommand(perform: cancel)
        .unsavedChangesAlert(isPresented: $confirmClose, title: "保存任务修改？",
                             canSave: !text.wrappedValue.isBlank,
                             save: save, discard: { model.cancelEditing() })
    }
}

/// One optional date entry, shared by task creation and editing.
struct TaskDateControl: View {
    @Binding var hasDue: Bool
    @Binding var date: Date
    @State private var open = false
    @State private var choosing = false
    @State private var selectedDate = Date()
    private var label: String {
        guard hasDue else { return "日期" }
        return TaskDates.monthDayFormat(date)
    }
    private func choose(_ value: Date) { date = value; hasDue = true; open = false }
    var body: some View {
        Button { choosing = false; selectedDate = date; open.toggle() } label: {
            Label(label, systemImage: "calendar")
        }.buttonStyle(QuietButtonStyle()).help(hasDue ? "修改或清除截止日期" : "设置截止日期")
            .accessibilityLabel(hasDue ? "截止日期 \(AppModel.dateKey(date))" : "设置截止日期")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("今天") { choose(Date()) }
                    Button("明天") { choose(TaskDates.local.date(byAdding: .day, value: 1, to: Date())!) }
                    Button("选择日期…") { choosing = true }
                    if choosing {
                        DatePicker("截止日期", selection: $selectedDate, displayedComponents: .date).datePickerStyle(.graphical)
                        Button("确定") { choose(selectedDate) }
                    }
                    Color.clear.frame(height: 6)
                    Button("清除日期") { hasDue = false; open = false }.disabled(!hasDue)
                }.buttonStyle(QuietButtonStyle()).padding(12)
            }
    }
}
