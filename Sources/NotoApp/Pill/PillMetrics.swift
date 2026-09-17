import SwiftUI

// 尺寸常量与玻璃材质。原始度量来自 codenotch 设计稿的 Small (0.8) 档。

enum PillMetrics {
    static let scale: CGFloat = 44.0 / 117.0 * 0.8
    static let depth: CGFloat = 186 * scale
    static let curl: CGFloat = 103 * scale
    static let start: CGFloat = 32
    static let ring: CGFloat = 117 * scale
    static let labelGap: CGFloat = 26.9 * scale
    static let labelHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: 27 * (44.0 / 117.0) / 0.714)
        return ceil(font.ascender - font.descender + font.leading) * 0.8
    }()
    static let cell = ring + labelGap + labelHeight
    static let pitch = cell + 83.5 * scale
    static let length = 2 * curl + (69.5 + 50.1) * scale + 2 * cell + 83.5 * scale
    static func depth(for edge: PillEdge) -> CGFloat { edge.isVertical ? depth : (186 - 117) * scale + cell }
    static func length(for edge: PillEdge) -> CGFloat { edge.isVertical ? length : 2 * curl + (69.5 + 50.1) * scale + 2 * ring + 83.5 * scale }
    static func ringCenter(_ index: Int, edge: PillEdge = .right) -> CGFloat {
        start + curl + (edge.isVertical ? 69.5 : (69.5 + 50.1) / 2) * scale + ring / 2
            + CGFloat(index) * (edge.isVertical ? pitch : ring + 83.5 * scale)
    }
}

/// Codenotch samples a full rectangular system-glass surface, then masks it.
/// A separate small glass shape produces different rims and refraction.
struct PillGlass: View {
    var sampleSize = CGSize(width: 100, height: 100)
    var interactive = false
    static var available: Bool { if #available(macOS 26.0, *) { true } else { false } }
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.frame(width: sampleSize.width, height: sampleSize.height)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: Rectangle())
        } else { Color.black }
    }
}

struct PillArcBand: Shape {
    let trim: ClosedRange<CGFloat>
    let lineWidth: CGFloat
    func path(in rect: CGRect) -> Path {
        Circle().trim(from: trim.lowerBound, to: trim.upperBound)
            .path(in: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            .strokedPath(StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
