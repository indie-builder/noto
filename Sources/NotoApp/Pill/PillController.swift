// 屏幕边缘的控制器：液态玻璃 / 纯黑表面，悬停展开「今日任务」「写一笔」，
// 两端弧线负责移动与设置，悬停待办 / 录入时出现玻璃描述卡；不抢焦点。
//
// 稳定性的关键：窗口尺寸固定为最大展开态、位置只在启动/换边/拖动/换屏时变化，
// 悬停只驱动窗口内部剪影的 SwiftUI 形变——窗口级的 frame 动画是发抖的根源。
// 非激活面板、⌥ 拖动贴边、光标监视与全屏检测的窗口机制改编自 codenotch（MIT License，© vinzdg）
// https://github.com/vinzdg/codenotch

import AppKit
import SwiftUI
import NotoCore

@MainActor
final class PillController: NSObject {
    // 几何常量（面板点）。across = 离屏幕边框的进深，along = 沿边方向。
    // 窗口固定为最大展开尺寸，悬停只改变内部剪影，不再改变窗口框。
    static let collapsedAcross: CGFloat = 26 * PillMetrics.scale
    static let collapsedLength: CGFloat = 210 * PillMetrics.scale
    static let barLength: CGFloat = PillMetrics.length + 64
    static let bodyLength: CGFloat = PillMetrics.length
    static let bodyStart: CGFloat = PillMetrics.start
    static let cardGap: CGFloat = 10.5
    static let cardAcross: CGFloat = 254.2
    /// 悬停卡沿边方向的宽度（水平边时即卡的宽度）。
    static let cardAlong: CGFloat = 226
    /// 悬停卡在进深方向的最大占用（含尾巴）；水平边按它预留窗口。
    static let cardAcrossLimit: CGFloat = 272

    /// 展开/收起共用的弹簧；窗口框纹丝不动，只有剪影在窗口内形变。
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)

    static func windowSize(for edge: PillEdge) -> CGSize {
        edge.size(along: ceil(PillMetrics.length(for: edge) + 64), across: ceil(PillMetrics.depth(for: edge) + cardGap + (edge.isVertical ? cardAcross : cardAcrossLimit)))
    }

    /// 光标离开后收起的宽限。
    private let foldGrace: TimeInterval = 0.5

    let model = PillModel()
    private(set) weak var appModel: AppModel?
    private(set) var panel: PillPanel?
    private var hosting: PillHostingView?
    var showWindow: (() -> Void)?
    private var pollTimer: Timer?
    private var foldWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private var mouseMonitors: [Any] = []
    private let defaults: UserDefaults
    private var started = false
    private var tick = 0
    private let monitorLock = NSLock()
    private var lastCursorEventAt: TimeInterval = 0

    init(appModel: AppModel, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appModel = appModel
        super.init()
        model.controller = self
        model.edge = savedEdge
    }

    deinit {
        pollTimer?.invalidate()
        foldWork?.cancel()
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private var edge: PillEdge { model.edge }
    private var savedEdge: PillEdge { PillEdge(rawValue: defaults.string(forKey: "pillEdge") ?? "") ?? .right }
    private var alwaysExpanded: Bool { defaults.string(forKey: "pillVisibility") == "always" }
    private var enabled: Bool { defaults.object(forKey: "pillEnabled") as? Bool ?? true }

    /// 凸舌中点在沿边方向上的落点（占屏长比例）。
    private var offset: CGFloat {
        get { defaults.object(forKey: "pillOffset." + edge.rawValue) as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: "pillOffset." + edge.rawValue) }
    }

    func start() {
        guard !started else { return }
        started = true
        func observe(_ name: Notification.Name, _ handle: @escaping (PillController) -> Void) {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in guard let self else { return }; handle(self) }
            })
        }
        observe(UserDefaults.didChangeNotification) { $0.syncWithSettings() }
        observe(NSWorkspace.activeSpaceDidChangeNotification) { $0.updateForFullscreen() }
        observe(NSWorkspace.didActivateApplicationNotification) { $0.updateForFullscreen() }
        observe(NSApplication.didChangeScreenParametersNotification) { $0.syncWithSettings() }
        // 光标不会为了停在原地而产生事件，所以低频轮询兜底；全局监视器负责快速响应移动。
        // 数据不在这里轮询：AppModel 数据变化后主动推送（见 PillModel.refresh）。
        startPollTimer()
        // 高频鼠标事件先在投递线程节流，再跳 MainActor，避免每帧多次 hop。
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            self.monitorLock.lock()
            let skip = event.timestamp - self.lastCursorEventAt < 1.0 / 90.0
            if !skip { self.lastCursorEventAt = event.timestamp }
            self.monitorLock.unlock()
            guard !skip else { return }
            Task { @MainActor in self.cursorMoved() }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in handler(event); return event }) {
            mouseMonitors.append(local)
        }
        syncWithSettings()
    }

    private func startPollTimer() {
        guard pollTimer == nil else { return }
        pollTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        pollTimer?.tolerance = 0.2
        if let pollTimer { RunLoop.main.add(pollTimer, forMode: .common) }
    }

    // MARK: - 面板生命周期

    private func syncWithSettings() {
        guard !model.isMoving else { return }
        if model.edge != savedEdge { setExpanded(false, animate: false) }
        model.edge = savedEdge
        if enabled {
            if panel == nil { createPanel() }
            startPollTimer()
            let glassy = defaults.string(forKey: "pillSurface") != "black" && PillGlass.available && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            panel?.appearance = glassy ? nil : NSAppearance(named: .darkAqua)
            reposition()
            updateForFullscreen()
            model.refresh(force: true)
            if alwaysExpanded, panel?.isVisible == true { setExpanded(true, animate: false) }
            cursorMoved()
        } else {
            pollTimer?.invalidate(); pollTimer = nil
            panel?.orderOut(nil)
            panel = nil
            hosting = nil
            setExpanded(false, animate: false)
        }
    }

    private func createPanel() {
        let size = Self.windowSize(for: edge)
        let panel = PillPanel(contentRect: CGRect(origin: .zero, size: size))
        let container = PillContainerView(frame: CGRect(origin: .zero, size: size))
        let hosting = PillHostingView(rootView: PillRootView(model: model))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.sizingOptions = []
        container.addSubview(hosting)
        panel.contentView = container
        self.hosting = hosting
        panel.onClick = { [weak self] local in self?.handleClick(local: local) }
        panel.contextMenuProvider = { [weak self] in self?.makeMenu() }
        panel.onDrag = { [weak self] dx, dy in self?.drag(byDx: dx, dy: dy) }
        panel.canCarry = { [weak self] local in self?.model.expanded == true && self?.elementRect(.move).contains(local) == true }
        panel.onDragStart = { [weak self] carry in
            self?.cancelFold()
            self?.model.isMoving = carry
        }
        panel.onDragEnd = { [weak self] in
            guard let self else { return }
            self.defaults.set(self.edge.rawValue, forKey: "pillEdge")
            self.persistOffset()
            self.model.isMoving = false
            self.syncWithSettings()
        }
        self.panel = panel
    }

    private func currentScreen() -> NSScreen? {
        if let panel, panel.isVisible,
           let hit = NSScreen.screens.first(where: { panel.frame.intersects($0.frame) }) {
            return hit
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - 定位：across = 离屏幕边框的进深，along = 沿边方向；本地坐标左上为原点。
    // 命中矩形一律先在「右侧」规范空间里计算，再映射到实际边。

    private var anchor: CGFloat { edge.isVertical ? Self.windowSize(for: edge).height - Self.bodyStart - PillMetrics.length(for: edge) / 2 : Self.bodyStart + PillMetrics.length(for: edge) / 2 }

    private func reposition() {
        guard let panel, let screen = currentScreen() else { return }
        panel.setFrame(PillPlacement.frame(screen: screen.frame, size: Self.windowSize(for: edge), edge: edge, offset: offset, anchor: anchor), display: true)
    }

    func resetPosition() { offset = 0.5; reposition() }

    private var barDepth: CGFloat { PillMetrics.depth(for: edge) }

    private var tabRect: CGRect {
        rect(across: 0, along: Self.bodyStart + (PillMetrics.length(for: edge) - Self.collapsedLength) / 2, depth: Self.collapsedAcross, length: Self.collapsedLength)
    }

    private var barRect: CGRect {
        rect(across: 0, along: 0, depth: barDepth, length: PillMetrics.length(for: edge) + 64)
    }

    /// 展开卡与药丸条之间的桥接热区，悬停经过时不收起。
    private var bridgeRect: CGRect {
        rect(across: barDepth, along: 0, depth: Self.cardGap, length: PillMetrics.length(for: edge) + 64)
    }

    /// 悬停卡框：连同尾巴在「右侧」规范空间里布局（尾巴贴边），再由 contentTransform
    /// 映射到实际边——四条边一份代码；沿边方向夹在窗口内并对准悬停元素。
    static func cardFrame(edge: PillEdge, element: PillElement, height: CGFloat, panelSize: CGSize) -> CGRect {
        let across = edge.isVertical ? cardAcross : height + 28.2
        let along = edge.isVertical ? height : cardAlong
        let canonical = edge.canonicalSize(of: panelSize)
        let gap = PillMetrics.depth(for: edge) + cardGap
        let origin = min(max(element.centerAlong(for: edge) - along / 2, 0), max(0, canonical.height - along))
        return CGRect(x: canonical.width - gap - across, y: origin, width: across, height: along)
            .applying(edge.contentTransform(in: panelSize))
    }
    private var cardRect: CGRect {
        Self.cardFrame(edge: edge, element: model.hovered ?? .today, height: model.cardHeight(for: model.hovered ?? .today), panelSize: Self.windowSize(for: edge))
    }

    /// 规范（右缘）矩形 = 贴边在 x 最大侧；水平边先转置成规范尺寸，再映射回实际面板。
    private func rect(across: CGFloat, along: CGFloat, depth: CGFloat, length: CGFloat) -> CGRect {
        let size = Self.windowSize(for: edge)
        let canonicalSize = edge.canonicalSize(of: size)
        let canonical = CGRect(x: canonicalSize.width - across - depth, y: along, width: depth, height: length)
        return canonical.applying(edge.contentTransform(in: size))
    }

    private func elementRect(_ element: PillElement) -> CGRect {
        rect(across: 3, along: element.originAlong(for: edge),
             depth: barDepth - 6, length: element.extent(for: edge))
    }

    /// 药丸条上命中的元素；命中矩形与 PillViews 的布局共用同一套沿边几何。
    private func element(at local: CGPoint) -> PillElement? {
        [PillElement.today, .compose, .settings, .move].first { elementRect($0).contains(local) }
    }

    func hoverTarget(at local: CGPoint) -> PillElement? {
        if model.hasCard && (cardRect.contains(local) || bridgeRect.contains(local)) { return model.hovered }
        guard barRect.contains(local) else { return nil }
        return element(at: local)
    }

    // MARK: - 光标监视与悬停

    private func poll() {
        tick += 1
        if panel?.isVisible == true { cursorMoved() }
        // 通知之外的兜底检查：全屏状态 5 秒一次；跨午夜 60 秒一次（refresh 内部按版本/日期去重）。
        if tick.isMultiple(of: 10) { updateForFullscreen() }
        if tick.isMultiple(of: 120) { model.refresh() }
    }

    private func localCursor() -> CGPoint? {
        guard let panel else { return nil }
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
    }

    private func cursorMoved() {
        guard let panel, panel.isVisible, !panel.isInteracting else { return }
        let local = localCursor() ?? CGPoint(x: -1, y: -1)

        if !model.expanded {
            // 收起态：光标碰到凸舌即展开。
            let tabHit = tabRect.insetBy(dx: -10, dy: -8)
            hosting?.interactiveRects = [tabHit]
            panel.ignoresMouseEvents = !tabHit.contains(local)
            if tabHit.contains(local) { setExpanded(true, animate: true) }
            return
        }

        let overBar = barRect.contains(local)
        let overCard = model.hasCard && cardRect.contains(local)
        let overBridge = model.hasCard && bridgeRect.contains(local)
        hosting?.interactiveRects = model.hasCard ? [barRect, cardRect] : [barRect]
        panel.ignoresMouseEvents = !(overBar || overCard)

        let target = hoverTarget(at: local)
        if target != model.hovered {
            withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.15)) { model.hovered = target }
        }

        if overBar || overCard || overBridge {
            cancelFold()
        } else if !alwaysExpanded, foldWork == nil {
            scheduleFold()
        }
    }

    private func cancelFold() {
        foldWork?.cancel()
        foldWork = nil
    }

    private func scheduleFold() {
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, self.panel?.isInteracting != true else { return }
                self.foldWork = nil
                self.setExpanded(false, animate: true)
            }
        }
        foldWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + foldGrace, execute: work)
    }

    /// 接触即展开；收起由 cursorMoved 里的宽限计时负责。
    /// 只切换模型状态——剪影形变交给 SwiftUI，窗口框纹丝不动。
    private func setExpanded(_ wanted: Bool, animate: Bool) {
        cancelFold()
        guard wanted ? !model.expanded : (model.expanded || model.hovered != nil) else { return }
        let change = {
            self.model.expanded = wanted
            if !wanted { self.model.hovered = nil }
        }
        if animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(Self.spring, change)
        } else {
            change()
        }
        if wanted {
            model.refresh(force: true)
            cursorMoved()
        }
    }

    // MARK: - 点击与动作

    private func handleClick(local: CGPoint) {
        guard model.expanded else { setExpanded(true, animate: true); return }
        activate(model.hasCard && cardRect.contains(local) ? model.hovered : element(at: local))
    }

    func activate(_ element: PillElement?) {
        switch element {
        case .today:
            openMainWindow()
            appModel?.showDueTasks()
        case .compose:
            openComposer()
        case .settings:
            openMainWindow()
            appModel?.settings = true
        case .move:
            if let view = panel?.contentView { makeMenu().popUp(positioning: nil, at: CGPoint(x: view.bounds.midX, y: view.bounds.midY), in: view) }
        case nil:
            break
        }
    }

    /// 借主窗口的录入框写一笔；药丸自身不做文本输入，保持永不抢焦点。
    func openComposer() {
        fold()
        showWindow?()
        activateMainWindow()
        appModel?.switchMode(.notes)
        if appModel?.mode == .notes { appModel?.showComposer() }
    }

    func openMainWindow() {
        fold()
        showWindow?()
        activateMainWindow()
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func fold() {
        cancelFold()
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.22)) {
            model.expanded = alwaysExpanded
            model.hovered = nil
        }
    }

    // MARK: - ⌥ 拖动

    /// AppKit 坐标向上为正，deltaY 直接加在 minY 上。
    private func drag(byDx dx: CGFloat, dy: CGFloat) {
        guard let panel, let screen = currentScreen() else { return }
        if model.isMoving {
            let mouse = NSEvent.mouseLocation
            let target = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? screen
            model.edge = PillPlacement.nearestEdge(point: mouse, screen: target.frame)
            let f = target.frame
            let fraction = edge.isVertical ? (mouse.y - f.minY) / f.height : (mouse.x - f.minX) / f.width
            panel.setFrame(PillPlacement.frame(screen: f, size: Self.windowSize(for: edge), edge: edge, offset: fraction, anchor: anchor), display: true)
            return
        }
        let f = screen.frame
        var frame = panel.frame
        if edge.isVertical {
            frame.origin.y = min(max(frame.origin.y + dy, f.minY), f.maxY - frame.height)
        } else {
            frame.origin.x = min(max(frame.origin.x + dx, f.minX), f.maxX - frame.width)
        }
        panel.setFrame(frame, display: true)
    }

    private func persistOffset() {
        guard let panel, let screen = currentScreen(), panel.isVisible else { return }
        offset = PillPlacement.offset(frame: panel.frame, screen: screen.frame, edge: edge, anchor: anchor)
    }

    // MARK: - 全屏与右键菜单

    private func updateForFullscreen() {
        guard enabled, let panel else { return }
        let fullscreen = currentScreen().map { PillFullscreen.isFrontmostAppFullScreen(on: $0) } ?? false
        if fullscreen {
            if panel.isVisible {
                setExpanded(false, animate: false)
                panel.orderOut(nil)
            }
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
            hosting?.interactiveRects = [tabRect.insetBy(dx: -10, dy: -8)]
            panel.ignoresMouseEvents = true
            if alwaysExpanded { setExpanded(true, animate: false) }
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("打开 Noto", #selector(openMain)))
        menu.addItem(item("新建记录", #selector(composeMenu)))
        let submenu = NSMenu()
        submenu.title = "位置"
        for candidate in PillEdge.allCases {
            let row = NSMenuItem(title: candidate.label, action: #selector(changeEdge(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = candidate.rawValue
            row.state = candidate == edge ? .on : .off
            row.isEnabled = true
            submenu.addItem(row)
        }
        let edgeItem = NSMenuItem()
        edgeItem.title = "位置"
        edgeItem.submenu = submenu
        menu.addItem(edgeItem)
        menu.addItem(.separator())
        menu.addItem(item("隐藏屏幕边缘", #selector(hideMenu)))
        return menu
    }

    @objc private func openMain() { openMainWindow() }
    @objc private func composeMenu() { openComposer() }
    @objc private func hideMenu() { defaults.set(false, forKey: "pillEnabled") }
    @objc private func changeEdge(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        defaults.set(raw, forKey: "pillEdge")
        syncWithSettings()
    }
}
