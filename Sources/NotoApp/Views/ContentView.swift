import SwiftUI
import AppKit
import NotoCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("datesExpanded") private var datesExpanded = true
    @State private var activeDay: String?
    @State private var searchFocused = false
    @State private var sidebarPreview = false
    @State private var sidebarHoverTask: Task<Void, Never>?
    @Namespace private var navigationSelection
    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 1100
            let showChatOnly = narrow && model.conversationVisible && !model.readingRequested
            HStack(spacing: 0) {
                if !showChatOnly {
                    ScrollViewReader { proxy in
                        HStack(spacing: 0) {
                            if datesExpanded {
                                sidebar(proxy: proxy, height: geometry.size.height)
                                    .transition(.move(edge: .leading).combined(with: .opacity))
                            }
                            VStack(spacing: 0) {
                                ZStack(alignment: .topLeading) {
                                    switch model.mode {
                                    case .calendar: TaskCalendar(model: model).transition(.opacity)
                                    case .board: TaskBoard(model: model).transition(.opacity)
                                    case .notes:
                                        ReadingPane(model: model, activeDay: $activeDay).transition(.opacity)
                                            .onReceive(NotificationCenter.default.publisher(for: .focusComposer)) { _ in
                                                if model.composerPosition == CGPoint(x: 24, y: 40) { proxy.scrollTo("history-top", anchor: .top) }
                                            }
                                            .onChange(of: model.search) { _, _ in
                                                activeDay = model.groups.first?.id; proxy.scrollTo("history-top", anchor: .top)
                                            }
                                    }
                                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .animation(NotoMotion.animation(.navigation), value: model.mode)
                                if !model.message.isEmpty {
                                    feedback.padding(.horizontal, 24).padding(.bottom, 16)
                                        .transition(.opacity.combined(with: .offset(y: 6)))
                                }
                            }.environment(\.blankInputEnabled, !sidebarPreview || datesExpanded)
                        }
                        .overlay(alignment: .topLeading) {
                            if !datesExpanded && !model.settings && !model.taskCreating && model.editing == nil {
                                ZStack(alignment: .topLeading) {
                                    Color.clear.frame(width: 12).contentShape(Rectangle())
                                        .onHover { sidebarHover($0) }
                                        .accessibilityHidden(true)
                                    if sidebarPreview {
                                        sidebar(proxy: proxy, height: geometry.size.height - 68)
                                            .frame(height: max(200, geometry.size.height - 68))
                                            .background(NotoSidebarSurface())
                                            .shadow(color: .black.opacity(0.12), radius: 16, x: 4, y: 4)
                                            .contentShape(RoundedRectangle(cornerRadius: 16))
                                            .onHover { sidebarHover($0) }
                                            .padding(8)
                                            .transition(.opacity.combined(with: .offset(x: -8)))
                                    }
                                }.frame(maxHeight: .infinity, alignment: .topLeading)
                            }
                        }
                    }
                }
                if model.conversationVisible && (!narrow || showChatOnly) {
                    if !narrow { Color.clear.frame(width: 20) }
                    ConversationView(model: model, drafts: model.drafts, compact: narrow)
                        .frame(width: narrow ? geometry.size.width : 380)
                        .transition(.opacity.combined(with: .offset(x: 12)))
                }
            }
            .padding(.top, 52)
            .background(alignment: .leading) {
                if datesExpanded && !showChatOnly {
                    NotoSidebarSurface(radius: 0).frame(width: sidebarWidth)
                        .transition(.opacity)
                }
            }
            .animation(NotoMotion.animation(.layout), value: datesExpanded)
            .animation(NotoMotion.animation(.layout), value: !narrow && model.conversationVisible)
            .animation(NotoMotion.animation(.navigation), value: showChatOnly)
            .animation(NotoMotion.animation(.feedback), value: model.message.isEmpty)
        }
        .onChange(of: datesExpanded) { _, _ in dismissSidebarPreview() }
        .onChange(of: model.mode) { _, _ in dismissSidebarPreview() }
        .onChange(of: model.settings) { _, opened in if opened { dismissSidebarPreview() } }
        .onChange(of: model.taskCreating) { _, _ in dismissSidebarPreview() }
        .onChange(of: model.editing?.id) { _, _ in dismissSidebarPreview() }
        .onDisappear { dismissSidebarPreview() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 12) {
                    Button {
                        datesExpanded.toggle()
                        model.readingRequested = true
                    } label: { ActionIcon("sidebar.left") }
                    .buttonStyle(QuietButtonStyle(icon: true))
                    .help(datesExpanded ? "隐藏侧栏（⌃⌘S）" : "显示侧栏（⌃⌘S）")
                    .accessibilityLabel(datesExpanded ? "隐藏侧栏" : "显示侧栏")
                    Text(model.mode.label).font(.system(size: 15, weight: .semibold))
                }.fixedSize()
            }.integratedToolbarBackground()
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            } else {
                ToolbarItem(placement: .automatic) { Spacer() }
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 13))
                            .foregroundStyle(searchFocused ? Color.accentColor : Color.secondary).accessibilityHidden(true)
                        SearchInput(text: Binding(get: { model.search }, set: { model.setSearch($0) }), placeholder: "搜索", focused: $searchFocused, commitDelay: 0.2)
                    }.padding(.horizontal, 6).frame(width: 180, height: 28)
                        .background(searchFocused ? Color.accentColor.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(searchFocused ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1).allowsHitTesting(false))
                        .animation(NotoMotion.hover, value: searchFocused)
                        .help(model.mode.isTaskView ? "搜索任务与对话（⌘K）" : "搜索记录与对话（⌘K）")
                    Button { model.openQuickConversation() } label: { ActionIcon("bubble.left") }
                        .buttonStyle(QuietButtonStyle(icon: true))
                        .help(model.conversationVisible ? "继续 AI 对话" : "发起 AI 对话")
                        .accessibilityLabel(model.conversationVisible ? "继续 AI 对话" : "AI 对话")
                    Button { model.showComposer() } label: { ActionIcon("plus") }
                        .buttonStyle(QuietButtonStyle(icon: true))
                        .help("新建内容（⌘N）").accessibilityLabel(model.mode.isTaskView ? "新建任务" : "新建记录")
                }.fixedSize()
            }.integratedToolbarBackground()
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear {
            NotoMotion.start()
        }
        .onChange(of: model.mode) { _, mode in
            NSApp.windows.first(where: { $0.identifier?.rawValue == "main" })?.isMovableByWindowBackground = mode == .notes
        }
        .disabled(model.opening)
        .overlay { if model.opening { ProgressView("正在打开记录…").padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) } }
        .background(NotoGlassSurface(radius: 20)).foregroundStyle(.primary)
        .ignoresSafeArea(.container, edges: .top)
        .onExitCommand {
            if model.taskCreating { model.taskCreating = false }
            else if model.editing != nil { model.cancelEditing() }
            else if model.composerPosition != nil { model.composerPosition = nil }
            else if !model.search.isEmpty { model.setSearch("") }
            else { model.closeConversation() }
        }
        .sheet(isPresented: Binding(get: { model.taskCreating || (model.mode.isTaskView && model.editing != nil) }, set: { value in
            if !value { _ = model.leaveUnchangedEditor() }
        })) { TaskEditor(model: model, drafts: model.drafts).presentationBackground(.clear) }
        .sheet(isPresented: $model.settings) { SettingsView(model: model).presentationBackground(.clear) }
        .sheet(isPresented: $model.recentlyDeleted) { RecentlyDeletedView(model: model).presentationBackground(.clear) }
        .task(id: model.message) {
            guard !model.message.isEmpty, !model.isError else { return }
            do {
                try await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, !model.isError else { return }
                model.message = ""
            } catch { }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshIfChanged() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.cancel() }
    }
    private func sidebarHover(_ inside: Bool) {
        sidebarHoverTask?.cancel()
        sidebarHoverTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(inside ? 120 : 300)) }
            catch { return }
            guard !datesExpanded else { return }
            withAnimation(NotoMotion.animation(.navigation)) { sidebarPreview = inside }
        }
    }
    private func dismissSidebarPreview() {
        sidebarHoverTask?.cancel(); sidebarHoverTask = nil
        sidebarPreview = false
    }
    private var sidebarWidth: CGFloat { 168 }
    private func sidebar(proxy: ScrollViewProxy, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ContentMode.allCases) { mode in
                Button { model.switchMode(mode) } label: {
                    HStack(spacing: 10) {
                        SidebarBadge(symbol: mode.icon)
                        Text(mode.label); Spacer()
                    }.padding(.horizontal, 8).frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .background {
                            if model.mode == mode {
                                RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.10))
                                    .matchedGeometryEffect(id: "navigation", in: navigationSelection).allowsHitTesting(false)
                            }
                        }
                }.buttonStyle(NavigationButtonStyle()).help(mode.label).accessibilityLabel(mode.label)
                    .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }.padding(.horizontal, 8)
            if model.mode == .notes && !model.entries.isEmpty {
                Text("日期").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.leading, 20).padding(.top, 22)
                DateRail(model: model, expanded: true, activeDay: activeDay, maxHeight: height, width: sidebarWidth - 8) { id in
                    NotoMotion.perform(.navigation) { activeDay = id; proxy.scrollTo("content-" + id, anchor: .top) }
                }
            } else { Spacer() }
            Button { model.settings = true } label: {
                HStack(spacing: 10) {
                    SidebarBadge(symbol: "gearshape")
                    Text("设置"); Spacer()
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
            }.buttonStyle(NavigationButtonStyle()).help("设置（⌘,）").accessibilityLabel("设置")
        }.font(.system(size: 13)).padding(.bottom, 12)
            .animation(NotoMotion.animation(.navigation), value: model.mode)
            .frame(width: sidebarWidth - 8)
            .padding(4)
    }
    private var feedback: some View {
        HStack(spacing: 10) {
            if model.isError { Image(systemName: "exclamationmark.circle").foregroundStyle(.red) }
            Text(model.message).font(NotoDesign.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if model.convertedTaskID != nil { Button("在看板查看") { model.showConvertedTask() }.buttonStyle(QuietButtonStyle()) }
            if model.undoAvailable { Button("撤销") { model.undo() }.buttonStyle(QuietButtonStyle()).help("撤销上次记录操作（⌘⇧Z）") }
            if model.lastDeletedTaskID != nil { Button("恢复删除") { model.restoreLastDeletedTask() }.buttonStyle(QuietButtonStyle()) }
            Button { model.message = "" } label: { ActionIcon("xmark") }
                .buttonStyle(QuietButtonStyle(icon: true)).accessibilityLabel("关闭操作提示")
        }.font(NotoDesign.caption).padding(10)
            .frame(maxWidth: .infinity)
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder func integratedToolbarBackground() -> some ToolbarContent {
        if #available(macOS 26.0, *) { sharedBackgroundVisibility(.hidden) }
        else { self }
    }
}
