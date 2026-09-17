import SwiftUI
import NotoCore

@MainActor
final class NotoApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct NotoApp: App {
    @AppStorage("datesExpanded") private var sidebarExpanded = true
    @NSApplicationDelegateAdaptor(NotoApplicationDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("noto", id: "main") {
            ContentView(model: model)
                .buttonStyle(QuietButtonStyle())
                .frame(minWidth: 620, minHeight: 480)
                .onAppear {
                    NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async {
                        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) ?? NSApp.keyWindow {
                            window.titleVisibility = .hidden
                            window.titlebarAppearsTransparent = true
                            window.titlebarSeparatorStyle = .none
                            window.toolbarStyle = .unified
                            window.styleMask.insert(.fullSizeContentView)
                            window.isMovableByWindowBackground = model.mode == .notes
                            window.backgroundColor = .clear
                            window.isOpaque = false
                        }
                    }
                }
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建内容") { model.showComposer() }.keyboardShortcut("n").disabled(model.chromeLocked)
                Button("提交当前输入") { model.submitFocusedInput() }.keyboardShortcut(.return, modifiers: .command).disabled(model.chromeLocked)
                Button("保存为任务") { model.save(todo: true) }.keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(model.composerPosition == nil || model.chromeLocked)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销文本编辑") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }.keyboardShortcut("z")
                Button("重做文本编辑") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }.keyboardShortcut("z", modifiers: [.command, .option])
                Button("撤销上次记录操作") { model.undo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.undoAvailable || model.chromeLocked)
                Button("恢复上次删除的任务") { model.restoreLastDeletedTask() }.disabled(model.lastDeletedTaskID == nil || model.chromeLocked)
                Button("最近删除…") { model.recentlyDeleted = true }.disabled(model.chromeLocked)
            }
            CommandGroup(after: .toolbar) {
                Button(sidebarExpanded ? "隐藏侧栏" : "显示侧栏") { sidebarExpanded.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .disabled(model.chromeLocked)
                ForEach(ContentMode.allCases) { mode in
                    Button("显示\(mode.label)") { model.switchMode(mode) }.keyboardShortcut(mode.shortcut, modifiers: .command).disabled(model.chromeLocked)
                }
            }
            CommandGroup(after: .textEditing) {
                Button("搜索记录") {
                    guard model.leaveUnchangedEditor() else { return }
                    model.composerPosition = nil
                    model.closeConversation()
                    DispatchQueue.main.async { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                }.keyboardShortcut("k").disabled(model.chromeLocked)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { model.settings = true }.keyboardShortcut(",")
            }
        }
    }
}

extension Notification.Name {
    static let focusComposer = Notification.Name("noto.focusComposer")
    static let focusSearch = Notification.Name("noto.focusSearch")
    static let focusChat = Notification.Name("noto.focusChat")
    static let focusEditor = Notification.Name("noto.focusEditor")
}
