import AppKit
import SwiftUI

/// 药丸吸附在哪条屏幕边。默认右侧，⌥ 拖动只沿这条边移动。
/// 本模块把「右侧」当作规范方向：几何先在规范空间里算好，再由
/// contentTransform 映射到实际边——四条边只写一份布局逻辑。
enum PillEdge: String, CaseIterable, Identifiable {
    case left, right, top, bottom

    var id: String { rawValue }
    var label: String {
        switch self { case .left: "左侧"; case .right: "右侧"; case .top: "顶部"; case .bottom: "底部" }
    }
    var isVertical: Bool { self == .left || self == .right }

    /// 面板尺寸：along 沿边方向、across 垂直于边；水平边交换宽高。
    func size(along: CGFloat, across: CGFloat) -> CGSize {
        isVertical ? CGSize(width: across, height: along) : CGSize(width: along, height: across)
    }

    /// 规范（右缘）空间 → 本边面板空间的映射；窗口宽高随边转置。
    func contentTransform(in size: CGSize) -> CGAffineTransform {
        switch self {
        case .right:
            return .identity
        case .left:
            // 水平镜像：贴边从右侧换到左侧。
            return CGAffineTransform(translationX: size.width, y: 0).scaledBy(x: -1, y: 1)
        case .bottom:
            // 转置：贴边从右侧换到底部。
            return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .top:
            // 转置后再垂直镜像，让贴边落在顶部。
            return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
                .concatenating(CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1))
        }
    }

    /// 规范空间里的面板尺寸；水平边取转置。
    func canonicalSize(of size: CGSize) -> CGSize {
        isVertical ? size : CGSize(width: size.height, height: size.width)
    }

    /// 面板内一点：along 从窗口起点、across 从屏幕边算起（SwiftUI 翻转坐标）。
    func point(along: CGFloat, across: CGFloat, in size: CGSize) -> CGPoint {
        switch self {
        case .left: CGPoint(x: across, y: along)
        case .right: CGPoint(x: size.width - across, y: along)
        case .top: CGPoint(x: along, y: across)
        case .bottom: CGPoint(x: along, y: size.height - across)
        }
    }

    /// 剪影在窗口内部的对齐方向。
    var contentAlignment: Alignment {
        switch self { case .right: .topTrailing; case .left, .top: .topLeading; case .bottom: .bottomLeading }
    }
}

// AppKit screen coordinates have a bottom-left origin; panel content is flipped.
// Keep positioning and persistence inverse operations on all four edges.
enum PillPlacement {
    static func nearestEdge(point: CGPoint, screen: CGRect) -> PillEdge {
        let distances: [(PillEdge, CGFloat)] = [(.left, abs(point.x - screen.minX)), (.right, abs(screen.maxX - point.x)), (.top, abs(screen.maxY - point.y)), (.bottom, abs(point.y - screen.minY))]
        return distances.min { $0.1 < $1.1 }!.0
    }
    static func frame(screen: CGRect, size: CGSize, edge: PillEdge, offset: Double, anchor: CGFloat) -> CGRect {
        let along = edge.isVertical ? screen.height : screen.width
        let extent = edge.isVertical ? size.height : size.width
        let position = min(max(CGFloat(offset) * along - anchor, 0), max(0, along - extent))
        // AppKit 屏幕坐标向上为正；贴边位置只能逐边写。
        switch edge {
        case .left: return CGRect(x: screen.minX, y: screen.minY + position, width: size.width, height: size.height).integral
        case .right: return CGRect(x: screen.maxX - size.width, y: screen.minY + position, width: size.width, height: size.height).integral
        case .top: return CGRect(x: screen.minX + position, y: screen.maxY - size.height, width: size.width, height: size.height).integral
        case .bottom: return CGRect(x: screen.minX + position, y: screen.minY, width: size.width, height: size.height).integral
        }
    }
    static func offset(frame: CGRect, screen: CGRect, edge: PillEdge, anchor: CGFloat) -> Double {
        let value = edge.isVertical ? (frame.minY + anchor - screen.minY) / max(1, screen.height) : (frame.minX + anchor - screen.minX) / max(1, screen.width)
        return min(max(value, 0), 1)
    }
}

/// 前台应用是否正在指定屏幕上全屏。
/// 只认「窗口完全覆盖整块屏幕」这一种信号：原生全屏的窗口边界就是整块屏幕。
/// codenotch 原实现还接受「从菜单栏下方开始、贴到屏幕底」的窗口，那会把
/// 最大化（但非全屏）的普通应用误判成全屏，让药丸在最常用的前台场景消失。
enum PillFullscreen {
    static func isFrontmostAppFullScreen(on screen: NSScreen) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }

        // AppKit 坐标（主屏左下为原点）换成 CoreGraphics 坐标（左上为原点）再比较窗口框。
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let bounds = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                            width: screen.frame.width, height: screen.frame.height)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == app.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict)
            else { continue }
            let coversScreen = abs(b.origin.x - bounds.origin.x) <= 4
                && abs(b.origin.y - bounds.origin.y) <= 4
                && abs(b.width - bounds.width) <= 4
                && abs(b.height - bounds.height) <= 4
            if coversScreen { return true }
        }
        return false
    }
}
