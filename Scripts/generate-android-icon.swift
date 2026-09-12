import AppKit

// 用法：swift Scripts/generate-android-icon.swift <素材图> <android/app/src/main/res 目录>
// 从鲸鱼娘插画合成安卓启动图标（白底圆形 + 蓝色描边徽章，四角透明），
// 规格与 windows/assets/whale-girl-main.png 母版一致：
//   圆形外径 ≈ 98% 画布、环色 RGB(30,74,220)、环厚 ≈ 2% 画布、角色高 ≈ 77% 画布
// 输出 mipmap-mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi 五档 ic_launcher.png

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("用法: swift Scripts/generate-android-icon.swift <素材图> <res目录>\n".data(using: .utf8)!)
    exit(1)
}
let srcPath = args[1]
let resDir = URL(fileURLWithPath: args[2], isDirectory: true)
guard let srcImage = NSImage(contentsOfFile: srcPath),
      let srcData = FileManager.default.contents(atPath: srcPath),
      let srcRep = NSBitmapImageRep(data: srcData) else {
    FileHandle.standardError.write("无法读取素材图: \(srcPath)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - 1. 统计素材中非白内容的包围盒（角色本体）

let sw = srcRep.pixelsWide, sh = srcRep.pixelsHigh
var minX = sw, maxX = -1, minY = sh, maxY = -1
for y in 0..<sh {
    for x in 0..<sw {
        guard let c = srcRep.colorAt(x: x, y: y), c.alphaComponent > 0.3 else { continue }
        if c.redComponent > 0.93 && c.greenComponent > 0.93 && c.blueComponent > 0.93 { continue }
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX > minX && maxY > minY else {
    FileHandle.standardError.write("素材图中未找到非白内容\n".data(using: .utf8)!)
    exit(1)
}
let boxW = CGFloat(maxX - minX + 1), boxH = CGFloat(maxY - minY + 1)

// 角色各像素到包围盒中心的最大距离（用于保证缩放后完全落在白圆内）
let centerSrc = CGPoint(x: (CGFloat(minX) + boxW / 2), y: (CGFloat(minY) + boxH / 2))
var maxRadial: CGFloat = 0
var y = minY
while y <= maxY {
    var x = minX
    while x <= maxX {
        if let c = srcRep.colorAt(x: x, y: y), c.alphaComponent > 0.3,
           !(c.redComponent > 0.93 && c.greenComponent > 0.93 && c.blueComponent > 0.93) {
            let dx = CGFloat(x) - centerSrc.x, dy = CGFloat(y) - centerSrc.y
            maxRadial = max(maxRadial, sqrt(dx * dx + dy * dy))
        }
        x += 2
    }
    y += 2
}

// MARK: - 2. 在高分辨率母版上合成徽章

let master: CGFloat = 1024
let outerR = master * 0.98 / 2          // 蓝环外缘半径
let ringW = master * 0.0205             // 环厚
let innerR = outerR - ringW             // 白圆半径

// 角色缩放：目标高 77% 画布；若最远点会压到白圆边缘则再收紧（留 3.5% 余量）
var scale = master * 0.771 / boxH
if maxRadial > 0 {
    scale = min(scale, innerR * 0.965 / maxRadial)
}
let drawW = boxW * scale, drawH = boxH * scale
// 角色包围盒中心放在画布 (0.5, 0.484)：与旧版图标一致（角色视觉重心略偏上）
let drawRect = NSRect(x: master * 0.5 - drawW / 2,
                      y: master * (1 - 0.484) - drawH / 2,
                      width: drawW,
                      height: drawH)
// 素材包围盒 → NSImage 坐标（NSImage 原点在左下，像素测量原点在左上）
let srcRect = NSRect(x: CGFloat(minX),
                     y: CGFloat(sh) - CGFloat(maxY + 1),
                     width: boxW,
                     height: boxH)

let image = NSImage(size: NSSize(width: master, height: master))
image.lockFocus()

// 蓝环（整圆填蓝，再叠白圆）
NSColor(calibratedRed: 30.0 / 255, green: 74.0 / 255, blue: 220.0 / 255, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: master / 2 - outerR, y: master / 2 - outerR,
                            width: outerR * 2, height: outerR * 2)).fill()
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: master / 2 - innerR, y: master / 2 - innerR,
                            width: innerR * 2, height: innerR * 2)).fill()

// 角色（素材自带白底，与白圆融为一体）
srcImage.draw(in: drawRect, from: srcRect, operation: .sourceOver, fraction: 1)

image.unlockFocus()

// MARK: - 3. 输出各密度 PNG

let densities: [(String, Int)] = [
    ("mipmap-mdpi", 48),
    ("mipmap-hdpi", 72),
    ("mipmap-xhdpi", 96),
    ("mipmap-xxhdpi", 144),
    ("mipmap-xxxhdpi", 192),
]

for (dir, size) in densities {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    ctx?.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    image.draw(in: NSRect(origin: .zero, size: rep.size))
    NSGraphicsContext.restoreGraphicsState()
    let out = resDir.appendingPathComponent(dir).appendingPathComponent("ic_launcher.png")
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: out)
    print("✅ \(dir)/ic_launcher.png (\(size)×\(size))")
}
print("🎉 安卓图标已生成到 \(resDir.path)")
