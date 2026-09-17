import SwiftUI
import AppKit
import NotoCore

// 时间线阅读窗格：按日分组的记录流、悬浮新建录入、空白处双击新建。

struct ReadingPane: View {
    @ObservedObject var model: AppModel
    @Binding var activeDay: String?
    @State private var occupied: [CGRect] = []
    @State private var composerSize = CGSize(width: 480, height: 180)
    var body: some View {
        GeometryReader { geometry in
            let width = max(260, min(480, geometry.size.width - 32))
            let origin = CGPoint(
                x: min(max(16, model.composerPosition?.x ?? 24), max(16, geometry.size.width - width - 16)),
                y: min(max(16, model.composerPosition?.y ?? 40), max(16, geometry.size.height - composerSize.height - 16)))
            let floatingRect = model.composerPosition == nil ? nil : CGRect(origin: origin, size: CGSize(width: width, height: composerSize.height))
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.entries.isEmpty && model.editing == nil {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(model.search.isEmpty ? "留下一点今天。" : "没有找到相关记录").font(.system(size: 17, weight: .medium))
                                Text(model.search.isEmpty ? "想法、任务，先记下来。" : "试试其他关键词。")
                                    .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(5)
                                if !model.search.isEmpty {
                                    Button("清空搜索") { model.setSearch("") }.buttonStyle(QuietButtonStyle()).font(NotoDesign.caption)
                                } else {
                                    Button("新建记录") { model.showComposer() }.buttonStyle(QuietButtonStyle(prominent: true)).help("新建记录（⌘N）")
                                }
                            }.excludeFromBlankInput()
                        } else {
                            if !model.search.isEmpty {
                                HStack {
                                    Text("搜索结果").font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    Text("\(model.entries.count)\(model.hasMore ? "+" : "") 条记录").font(NotoDesign.caption).foregroundStyle(.secondary)
                                }.padding(.bottom, 24).excludeFromBlankInput()
                            }
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(model.groups) { group in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 12) {
                                            Text(group.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                        }.excludeFromBlankInput()
                                        LazyVStack(spacing: 1) {
                                            ForEach(group.entries) { entry in EntryRow(entry: entry, model: model).excludeFromBlankInput().transition(.opacity) }
                                        }
                                    }.id("content-" + group.id)
                                        .background(GeometryReader { frame in
                                            // 1pt 量化：sub-pt 滚动抖动不触发 preference 聚合。
                                            Color.clear.preference(key: DayPositions.self, value: [group.id: frame.frame(in: .named("history")).minY.rounded(.down)])
                                        })
                                }
                                if model.hasMore {
                                    Button("加载更多") { model.loadMore() }
                                        .buttonStyle(QuietButtonStyle()).font(NotoDesign.caption).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12).excludeFromBlankInput()
                                        .onAppear { model.loadMore() }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading).padding(.horizontal, 24)
                    .padding(.top, 24).padding(.bottom, 100).id("history-top").frame(maxWidth: .infinity)
                    .animation(NotoMotion.animation(.layout), value: model.entries.map(\.id))
                }
                .coordinateSpace(name: "history")
                .onPreferenceChange(DayPositions.self) { positions in
                    let current = Set(model.groups.map(\.id))
                    let sorted = positions.filter { current.contains($0.key) }.sorted { $0.value < $1.value }
                    let candidate = (sorted.last(where: { $0.value <= 12 }) ?? sorted.first)?.key
                    if candidate != activeDay { activeDay = candidate }
                }
                if model.composerPosition != nil {
                    NewContentInput(model: model, drafts: model.drafts)
                        .frame(width: width)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { composerSize = $0 }
                        .offset(x: origin.x, y: origin.y)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .animation(NotoMotion.animation(.layout), value: model.composerPosition)
            .coordinateSpace(name: "reading")
            .onPreferenceChange(OccupiedAreas.self) { if $0 != occupied { occupied = $0 } }
            .background(BlankClickObserver(excluded: occupied, floatingRect: floatingRect,
                onDoubleClick: { model.showComposer(at: $0) }, onOutsideClick: { model.composerPosition = nil }))
        }
    }
}

/// 悬浮在阅读窗格上的新建录入卡。
private struct NewContentInput: View {
    @ObservedObject var model: AppModel
    @ObservedObject var drafts: TextDrafts
    private var empty: Bool { drafts.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("新建记录").font(NotoDesign.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.composerPosition = nil } label: { ActionIcon("xmark") }
                    .buttonStyle(QuietButtonStyle(icon: true)).accessibilityLabel("收起录入，保留草稿")
            }
            Composer(text: $drafts.composer, purpose: .newContent, onSubmit: { model.save() }, onCancel: { model.composerPosition = nil })
                .frame(minHeight: 48)
            if model.busy { Text("AI 正在回复，你可以继续保存记录。").font(NotoDesign.caption).foregroundStyle(.secondary) }
            HStack(spacing: 6) {
                Button("与 AI 讨论") { model.ask() }.disabled(model.busy)
                Spacer(minLength: 0)
                Menu { Button("保存为任务") { model.save(todo: true) } } label: {
                    ActionIcon("chevron.down")
                }.actionMenuStyle().help("其他保存方式").accessibilityLabel("其他保存方式")
                Button("保存") { model.save() }.buttonStyle(QuietButtonStyle(prominent: true)).help("保存记录（⌘↵）；回车换行")
            }.font(NotoDesign.caption).buttonStyle(QuietButtonStyle()).disabled(empty)
        }.padding(16)
            .background(NotoDesign.canvas, in: RoundedRectangle(cornerRadius: NotoDesign.radius))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 5)
    }
}

private struct DayPositions: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
