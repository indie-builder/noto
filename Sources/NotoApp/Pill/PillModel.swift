import SwiftUI
import NotoCore

// 屏幕边缘的数据模型：到期待办摘要 + 悬停/展开状态。
// 数据只在 AppModel 变化后主动推送（refresh），从不轮询数据库。

enum PillElement: Int {
    case today, compose, settings, move
}

struct PillSummary: Equatable {
    let todayOpen: Int
    let todayDone: Int
    let overdue: Int
    let openCount: Int
    let todayItems: [Entry]
    init(todos: [Entry], today: String) {
        let open = todos.filter { $0.status != "completed" }
        todayItems = open.filter { $0.due.map { $0 <= today } ?? false }
        todayOpen = todayItems.count
        overdue = todayItems.filter { $0.due! < today }.count
        todayDone = todos.filter { $0.status == "completed" && $0.due == today }.count
        openCount = open.count
    }
}

extension PillSummary {
    /// 未加载数据时的空摘要。
    static let empty = PillSummary(todos: [], today: "")
}

@MainActor
final class PillModel: ObservableObject {
    @Published var expanded = false
    @Published var isMoving = false
    @Published var hovered: PillElement?
    @Published var edge: PillEdge = .right
    @Published private(set) var summary = PillSummary.empty
    var hasCard: Bool { hovered == .today || hovered == .compose }

    weak var controller: PillController?
    private var lastStore: Store?
    private var lastVersion: Int?
    private var lastDay: String?
    private var refreshTask: Task<Void, Never>?

    func cardHeight(for element: PillElement) -> CGFloat {
        guard element == .today else { return 80 }
        guard summary.todayOpen > 0 else { return 100 }
        let items = summary.todayItems
        return 112 + CGFloat(min(items.count, 3)) * 18 + (items.count > 3 ? 16 : 0)
    }

    /// AppModel 数据变化后主动调用；先比数据版本，版本和日期都没变就不查库。
    func refresh(force: Bool = false) {
        guard let store = controller?.appModel?.store else { return }
        let todayKey = AppModel.dateKey(Date())
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let version = try? await Task.detached(priority: .utility) { try store.dataVersion() }.value
            guard let self, let version, !Task.isCancelled else { return }
            if !force, store === self.lastStore, version == self.lastVersion, todayKey == self.lastDay { return }
            let todos = try? await Task.detached(priority: .utility) { try store.todos(status: "all") }.value
            guard let todos, !Task.isCancelled else { return }
            self.lastStore = store
            self.lastVersion = version
            self.lastDay = todayKey
            self.summary = PillSummary(todos: todos, today: todayKey)
        }
    }
}

/// 元素沿边方向的中点，与 PillController 的命中矩形保持一致。
extension PillElement {
    var extent: CGFloat { extent(for: .right) }
    var centerAlong: CGFloat { centerAlong(for: .right) }
    func extent(for edge: PillEdge) -> CGFloat { self == .today || self == .compose ? (edge.isVertical ? PillMetrics.cell : 44) : 44 }
    func centerAlong(for edge: PillEdge) -> CGFloat {
        switch self {
        case .move: PillMetrics.start
        case .today: PillMetrics.ringCenter(0, edge: edge)
        case .compose: PillMetrics.ringCenter(1, edge: edge)
        case .settings: PillMetrics.start + PillMetrics.length(for: edge)
        }
    }
    func originAlong(for edge: PillEdge) -> CGFloat {
        centerAlong(for: edge) - ((self == .today || self == .compose) && edge.isVertical ? PillMetrics.ring / 2 : 22)
    }
}
