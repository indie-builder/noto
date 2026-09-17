import AppKit
import SwiftUI

// 无边框、非激活的面板与宿主视图：药丸永远不抢焦点，命中区域由控制器下发。

/// nonactivatingPanel 加 canBecomeKey = false，让瞥一眼待办永远不会抢走当前应用的焦点；
/// statusBar 层级让它盖住普通窗口。
final class PillPanel: NSPanel {
    var contextMenuProvider: (() -> NSMenu?)?
    /// 展开状态下落在元素上的单击。SwiftUI 的视图会自己消费部分事件，这里只接住空白处的点击。
    var onClick: ((CGPoint) -> Void)?
    /// ⌥ 拖动时上报的原始位移增量；松手后由 onDragEnd 持久化。
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var canCarry: ((CGPoint) -> Bool)?
    var onDragStart: ((Bool) -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        title = "Noto 屏幕边缘"
        identifier = NSUserInterfaceItemIdentifier("noto-edge")
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    var isInteracting = false

    // Route chrome gestures before SwiftUI's subviews consume them.
    override func sendEvent(_ event: NSEvent) {
        guard let view = contentView, view.hitTest(event.locationInWindow) != nil else {
            return super.sendEvent(event)
        }
        if event.type == .rightMouseDown, let menu = contextMenuProvider?() {
            isInteracting = true
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            isInteracting = false
        } else if event.type == .leftMouseDown {
            let carry = canCarry?(localPoint(fromWindow: event.locationInWindow)) == true && !event.modifierFlags.contains(.option)
            if event.modifierFlags.contains(.option) || carry {
                isInteracting = true
                onDragStart?(carry)
                trackOptionDrag()
                isInteracting = false
            } else { onClick?(localPoint(fromWindow: event.locationInWindow)) }
        } else { super.sendEvent(event) }
    }

    /// 窗口底边原点换成面板左上原点，与 SwiftUI 的翻转坐标一致。
    private func localPoint(fromWindow point: NSPoint) -> CGPoint {
        guard let size = contentView?.bounds.size else { return .zero }
        return CGPoint(x: point.x, y: size.height - point.y)
    }

    /// 阻塞读取本窗口的事件流直到松手，是 AppKit 自定义拖动的标准做法。
    private func trackOptionDrag() {
        while let event = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            switch event.type {
            case .leftMouseDragged: onDrag?(event.deltaX, -event.deltaY)
            case .leftMouseUp: onDragEnd?(); return
            default: return
            }
        }
    }
}

// A plain content container prevents NSHostingView's ideal size from resizing
// the NSPanel. Adapted from Codenotch's NotchContainerView (MIT).
final class PillContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return subviews.reversed().compactMap { $0.hitTest(local) }.first
    }
}

final class PillHostingView: NSHostingView<PillRootView> {
    var interactiveRects: [CGRect] = []
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRects.contains(where: { $0.contains(local) }) else { return nil }
        return super.hitTest(point)
    }
}
