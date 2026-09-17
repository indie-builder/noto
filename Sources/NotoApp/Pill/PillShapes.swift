import SwiftUI

// 剪影：一律先在「右侧凸舌」的规范空间里画路径，再用 PillEdge.contentTransform
// 映射到目标边——四条边共享一份几何，视觉差异只来自坐标变换。
// Adapted from vinzdg/codenotch (MIT; see THIRD-PARTY-NOTICES).

struct NotchSilhouette: Shape {
    var edge: PillEdge

    func path(in rect: CGRect) -> Path {
        canonicalPath(across: edge.isVertical ? rect.width : rect.height,
                      along: edge.isVertical ? rect.height : rect.width)
            .applying(edge.contentTransform(in: rect.size))
    }

    /// 规范路径：宽 = across（0 是自由端、across 是贴边），高 = along。
    /// 两端的翼形曲线从内侧边缘（竖直切线）张开、沿顶部/底边（水平切线）
    /// 汇入贴边——形状向贴边方向张开，像从边框里长出来。
    private func canonicalPath(across: CGFloat, along: CGFloat) -> Path {
        let rect = CGRect(x: 0, y: 0, width: across, height: along)
        let wanted = max(0, min(23.71, rect.width / 2))
        let curl = max(0, min(30.99, rect.height / 2, rect.width - wanted))
        let corner = max(0, min(wanted, (rect.height - 2 * curl) / 2))
        let bodyTop = rect.minY + curl
        let bodyBottom = rect.maxY - curl

        var path = Path()
        // Screen edge, above the body.
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Flare inward and down onto the top edge. Absent when flush: the
        // shape meets the bezel square, as the hardware notch does.
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.minY),
                radius: curl,
                startAngle: .degrees(0), endAngle: .degrees(90),
                clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.minX + corner, y: bodyTop))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyTop + corner),
            radius: corner,
            startAngle: .degrees(270), endAngle: .degrees(180),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom - corner))
        path.addArc(
            center: CGPoint(x: rect.minX + corner, y: bodyBottom - corner),
            radius: corner,
            startAngle: .degrees(180), endAngle: .degrees(90),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - curl, y: bodyBottom))
        // Flare back out to the screen edge.
        if curl > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - curl, y: rect.maxY),
                radius: curl,
                startAngle: .degrees(270), endAngle: .degrees(360),
                clockwise: false
            )
        }
        path.closeSubpath()
        return path
    }
}

/// 卡片尾巴：规范朝右（卡在左、尖端指向药丸），其余方向由变换得到。
/// 尖端与底边两端各一段曲线，起点/终点都平行于卡片边缘，
/// 两个拐角圆滑而尖端保持锐利，并落在悬停元素的环上。
private struct PillTooltipTail: Shape {
    let edge: PillEdge

    func path(in rect: CGRect) -> Path {
        // Canonical control points live in right-edge space (28.2 × 32.7);
        // horizontal edges pass a transposed rect, so build there first.
        let canonicalRect = edge.isVertical ? rect
            : CGRect(origin: rect.origin, size: CGSize(width: rect.height, height: rect.width))
        let tip = CGPoint(x: canonicalRect.maxX, y: canonicalRect.midY)
        let a = CGPoint(x: canonicalRect.minX, y: canonicalRect.minY), b = CGPoint(x: canonicalRect.minX, y: canonicalRect.maxY)
        let aShoulder = CGPoint(x: canonicalRect.minX, y: canonicalRect.minY + canonicalRect.height * 0.25)
        let aTip = CGPoint(x: canonicalRect.maxX - canonicalRect.width * 0.42, y: canonicalRect.midY - canonicalRect.height * 0.12)
        let bTip = CGPoint(x: canonicalRect.maxX - canonicalRect.width * 0.42, y: canonicalRect.midY + canonicalRect.height * 0.12)
        let bShoulder = CGPoint(x: canonicalRect.minX, y: canonicalRect.maxY - canonicalRect.height * 0.25)

        var canonical = Path()
        canonical.move(to: a)
        canonical.addCurve(to: tip, control1: aShoulder, control2: aTip)
        canonical.addCurve(to: b, control1: bTip, control2: bShoulder)
        canonical.closeSubpath()
        return canonical.applying(edge.contentTransform(in: rect.size))
    }

    /// Long in the direction it points, wide across it.
    static func size(for edge: PillEdge) -> CGSize {
        edge.isVertical ? CGSize(width: 28.2, height: 32.7) : CGSize(width: 32.7, height: 28.2)
    }
}

/// The card and its tail as a single outline.
///
/// One glass shape, not two: separate ones each grow their own rim highlight
/// and the seam shows where the tail leaves the card. The tail is stacked
/// against the card exactly the way the view does it, offset along the card's
/// own axis so a slid tail stays inside the glass outline.
struct PillTooltipSilhouette: Shape {
    /// Which side of the notch the card is on, so the tail goes on the other one.
    let edge: PillEdge
    var tailOffset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let tail = PillTooltipTail.size(for: edge)
        let vertical = edge.isVertical
        let cardRect: CGRect
        var tailRect: CGRect
        switch edge {
        case .right, .left:
            let leading = edge == .left
            tailRect = CGRect(x: leading ? rect.minX : rect.maxX - tail.width, y: rect.midY - tail.height / 2, width: tail.width, height: tail.height)
            cardRect = CGRect(x: leading ? rect.minX + tail.width : rect.minX, y: rect.minY, width: rect.width - tail.width, height: rect.height)
        case .top, .bottom:
            let leading = edge == .top
            tailRect = CGRect(x: rect.midX - tail.width / 2, y: leading ? rect.minY : rect.maxY - tail.height, width: tail.width, height: tail.height)
            cardRect = CGRect(x: rect.minX, y: leading ? rect.minY + tail.height : rect.minY, width: rect.width, height: rect.height - tail.height)
        }
        if vertical { tailRect.origin.y += tailOffset } else { tailRect.origin.x += tailOffset }
        return RoundedRectangle(cornerRadius: 18.6, style: .circular)
            .path(in: cardRect)
            .union(PillTooltipTail(edge: edge).path(in: tailRect))
    }
}
