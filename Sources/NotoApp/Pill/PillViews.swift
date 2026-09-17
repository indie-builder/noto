// 屏幕边缘的界面：通透或纯黑的贴边凸舌，悬停展开出「到期待办」环和「写一笔」，
// 再悬停到具体元素时弹出带箭头的描述卡。视觉语言对齐 codenotch 的刘海。
//
// 动效质感的关键：窗口尺寸恒定，展开/收起是剪影在窗口内的形变，
// 由 SwiftUI 按帧重绘——不做窗口 frame 动画，避免窗口级缩放的迟滞与抖动。

import SwiftUI
import NotoCore

struct PillRootView: View {
    @ObservedObject var model: PillModel
    @AppStorage("pillSurface") private var surface = "glass"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    private var glassy: Bool { surface == "glass" && !reduceTransparency && PillGlass.available }
    var body: some View {
        GeometryReader { proxy in
            let depth = model.expanded ? PillMetrics.depth(for: model.edge) : PillController.collapsedAcross
            let length = model.expanded ? PillMetrics.length(for: model.edge) : PillController.collapsedLength
            let shape = NotchSilhouette(edge: model.edge)
            ZStack(alignment: .topLeading) {
                ZStack {
                    if glassy {
                        PillGlass(sampleSize: proxy.size).id(model.expanded)
                    }
                    shape.fill(.black).opacity(glassy ? 0 : 1)
                }
                .frame(model.edge.size(along: length, across: depth))
                .overlay(alignment: model.edge.contentAlignment) {
                    PillBarView(model: model)
                        .frame(model.edge.size(along: PillMetrics.length(for: model.edge), across: PillMetrics.depth(for: model.edge)))
                        .opacity(model.expanded ? 1 : 0)
                }
                .clipShape(shape)
                .position(model.edge.point(along: PillController.bodyStart + PillMetrics.length(for: model.edge) / 2, across: depth / 2, in: proxy.size))
                .offset(x: model.edge == .right ? 2 : model.edge == .left ? -2 : 0,
                        y: model.edge == .bottom ? 2 : model.edge == .top ? -2 : 0)
                ForEach([PillElement.move, .settings], id: \.rawValue) { element in
                    Button { model.controller?.activate(element) } label: {
                        PillOrb(edge: model.edge, moving: element == .move,
                                hovered: model.hovered == element || (element == .move && model.isMoving), glassy: glassy)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(element == .move ? "移动屏幕边缘，按住拖动" : "设置")
                        .scaleEffect(model.expanded ? 1 : 1.55)
                        .opacity(model.expanded ? 1 : 0)
                        .position(model.edge.point(along: element.centerAlong(for: model.edge), across: 30.99, in: proxy.size))
                        .allowsHitTesting(model.expanded)
                }
                if model.expanded, model.hasCard, let element = model.hovered {
                    let frame = PillController.cardFrame(edge: model.edge, element: element, height: model.cardHeight(for: element), panelSize: proxy.size)
                    let tailOffset = element.centerAlong(for: model.edge) - (model.edge.isVertical ? frame.midY : frame.midX)
                    PillCardView(model: model, element: element, tailOffset: tailOffset)
                        .frame(frame.size)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.opacity)
                }
            }
            .frame(proxy.size)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86), value: model.hovered)
            .animation(reduceMotion ? nil : PillController.spring, value: model.expanded)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("屏幕边缘")
        .accessibilityValue("未完成 \(model.summary.openCount) 项")
        .accessibilityAction { model.controller?.activate(.today) }
        .environment(\.colorScheme, glassy ? colorScheme : .dark)
    }
}

/// 展开态的主体内容：到期待办环、写一笔、设置。
struct PillBarView: View {
    @ObservedObject var model: PillModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach([PillElement.today, .compose], id: \.rawValue) { element in
                Button { model.controller?.activate(element) } label: {
                    VStack(spacing: 8.1) {
                        ZStack {
                            Circle().stroke(Color.primary.opacity(0.16), lineWidth: 4.66)
                            if element == .today {
                                Circle().stroke(ringColor, lineWidth: 2.4)
                            }
                            Image(systemName: element == .today ? "checklist" : "square.and.pencil")
                                .font(.system(size: 13.8, weight: .regular)).foregroundStyle(.primary)
                        }.frame(width: 35.2, height: 35.2)
                        Text(element == .today ? "\(model.summary.todayOpen)" : "新建")
                            .font(.system(size: element == .today ? 11.4 : 11, weight: .regular)).monospacedDigit()
                    }
                    .frame(model.edge.size(along: element.extent(for: model.edge), across: PillMetrics.depth(for: model.edge)), alignment: .top)
                }.buttonStyle(.plain)
                    .accessibilityLabel(element == .today ? "到期待办，未完成 \(model.summary.todayOpen) 项" : "新建记录")
                    .offset(x: model.edge.isVertical ? 0 : element.originAlong(for: model.edge) - PillController.bodyStart,
                            y: model.edge.isVertical ? element.originAlong(for: model.edge) - PillController.bodyStart : (PillMetrics.depth(for: model.edge) - PillMetrics.cell) / 2)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var ringColor: Color {
        model.summary.todayOpen > 0 ? (model.summary.overdue > 0 ? .orange : .accentColor) : .clear
    }
}

/// 悬停描述卡：白底深字，尾巴指向悬停的元素。
private struct PillCardView: View {
    @AppStorage("pillSurface") private var surface = "glass"
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject var model: PillModel
    let element: PillElement
    let tailOffset: CGFloat
    var body: some View {
        let shape = PillTooltipSilhouette(edge: model.edge, tailOffset: tailOffset)
        // 12pt 内容边距 + 尾巴占据的那一侧再让出 28.2pt。
        let insets = EdgeInsets(top: 12 + (model.edge == .top ? 28.2 : 0),
                                leading: 12 + (model.edge == .left ? 28.2 : 0),
                                bottom: 12 + (model.edge == .bottom ? 28.2 : 0),
                                trailing: 12 + (model.edge == .right ? 28.2 : 0))
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(insets)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if surface == "glass" && !reduceTransparency {
                    if #available(macOS 26.0, *) { Color.clear.glassEffect(.regular, in: shape) }
                    else { shape.fill(.black) }
                } else { shape.fill(.black) }
            }
            .contentShape(shape)
            .onTapGesture { model.controller?.activate(element) }
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        switch element {
        case .today:
            header(icon: "checklist", title: "到期待办")
            if model.summary.todayOpen == 0 {
                Text("暂无到期待办。")
                    .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55)).lineSpacing(3)
            } else {
                HStack {
                    Text("未完成 \(model.summary.todayOpen)")
                    Spacer()
                    if model.summary.overdue > 0 { Text("逾期 \(model.summary.overdue)").foregroundStyle(.orange) }
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach(model.summary.todayItems.prefix(3)) { entry in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill((entry.due ?? "") < AppModel.dateKey(Date()) ? Color.orange : Color.primary.opacity(0.3))
                            .frame(width: 4, height: 4).padding(.top, 4)
                        Text(entry.text).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.85))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                if model.summary.todayItems.count > 3 {
                    Text("还有 \(model.summary.todayItems.count - 3) 项…")
                        .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
            footer("查看任务")
        case .compose:
            header(icon: "square.and.pencil", title: "新建记录")
            Text("记下想法或任务。")
                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.65)).lineSpacing(4)
            Spacer(minLength: 0)
            footer("点击新建记录")
        case .settings, .move:
            EmptyView()
        }
    }

    private func header(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .medium))
            Text(title).font(.system(size: 13.7, weight: .semibold))
            Spacer(minLength: 0)
        }.foregroundStyle(Color.primary.opacity(0.88))
    }

    private func footer(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
    }
}

struct PillOrb: View {
    let edge: PillEdge
    let moving: Bool
    let hovered: Bool
    let glassy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let radius: CGFloat = 76 * PillMetrics.scale
    private let stroke: CGFloat = 18 * PillMetrics.scale
    private var trim: ClosedRange<CGFloat> {
        let lower: CGFloat
        switch edge { case .right: lower = 0.75; case .left, .top: lower = 0.5; case .bottom: lower = 0.25 }
        let start = moving ? ((edge.isVertical ? 0.75 : 1.25) - lower).truncatingRemainder(dividingBy: 1) : lower
        return start...(start + 0.25)
    }
    var body: some View {
        ZStack {
            Group {
                if glassy { PillGlass() } else { Color.black }
            }.frame(width: radius * 2 + stroke, height: radius * 2 + stroke)
                .clipShape(PillArcBand(trim: trim, lineWidth: stroke))
                .opacity(hovered ? 0 : 1).scaleEffect(hovered ? 0.86 : 1)
            Group {
                if glassy { PillGlass(interactive: true) } else { Color.black }
            }.frame(width: 124 * PillMetrics.scale, height: 124 * PillMetrics.scale)
                .clipShape(Circle()).opacity(hovered ? 1 : 0).scaleEffect(hovered ? 1 : 1.1)
            Image(systemName: moving ? "hand.draw" : "gearshape")
                .font(.system(size: 56 * PillMetrics.scale, weight: .regular))
                .opacity(hovered ? 1 : 0).scaleEffect(hovered ? 1 : 0.5)
                .rotationEffect(.degrees(hovered ? 0 : -60))
        }.frame(width: radius * 2 + stroke, height: radius * 2 + stroke)
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.7), value: hovered)
    }
}

/// Uses the production view and in-memory fixture for repeatable visual checks.
struct PillPreviewView: View {
    @ObservedObject var model: PillModel
    @AppStorage("pillSurface") private var surface = "glass"
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Picker("边缘", selection: $model.edge) {
                    ForEach(PillEdge.allCases) { edge in Text(edge.label).tag(edge) }
                }.pickerStyle(.segmented)
                Picker("表面", selection: $surface) { Text("通透").tag("glass"); Text("纯黑").tag("black") }.pickerStyle(.segmented)
            }
            HStack {
                Toggle("展开", isOn: $model.expanded)
                ForEach([PillElement.today, .compose, .settings], id: \.rawValue) { element in
                    Button(element == .today ? "任务详情" : element == .compose ? "录入详情" : "设置详情") { model.expanded = true; model.hovered = element }
                }
            }
            PillRootView(model: model)
            Spacer(minLength: 0)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background(NotoDesign.canvas)
            .onAppear { model.refresh(force: true); model.expanded = true; model.hovered = .today }
    }
}
