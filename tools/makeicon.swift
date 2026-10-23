import AppKit
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// graphite background
NSColor(red: 0x26/255.0, green: 0x2B/255.0, blue: 0x27/255.0, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: px, height: px)).fill()
// mint 2x2 "Hearth" mark
NSColor(red: 0x9a/255.0, green: 0xd7/255.0, blue: 0xb7/255.0, alpha: 1).setFill()
let d = 300.0, gap = 70.0, c = Double(px)/2
for i in 0...1 { for j in 0...1 {
    let x = c - d - gap/2 + Double(i)*(d+gap)
    let y = c - d - gap/2 + Double(j)*(d+gap)
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: d, height: d), xRadius: 56, yRadius: 56).fill()
}}
NSGraphicsContext.restoreGraphicsState()
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
