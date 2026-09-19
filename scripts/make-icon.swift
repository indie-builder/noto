import AppKit

// 从仓库根目录运行：swift scripts/make-icon.swift <1024×1024 源图 PNG>
// 源图不入库；生成 build/AppIcon.iconset 后还需执行末尾提示的 iconutil 命令。
let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("用法：swift scripts/make-icon.swift <1024×1024 源图 PNG>\n".utf8))
    exit(2)
}
guard let source = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("无法读取源图：\(arguments[1])。需要一张 1024×1024 的 PNG。\n".utf8))
    exit(1)
}
let directory = "build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.imageInterpolation = .high
        let unit = CGFloat(pixels) / 1024
        let frame = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
        NSBezierPath(roundedRect: frame, xRadius: 185 * unit, yRadius: 185 * unit).addClip()
        source.draw(in: frame, from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
print("已生成 \(directory)；继续执行：iconutil -c icns \(directory) -o design/AppIcon.icns")
