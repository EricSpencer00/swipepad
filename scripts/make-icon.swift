import AppKit
import Foundation

let root = URL(
  fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets")
let iconset = root.appendingPathComponent("Swipepad.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ pixels: Int) -> Data {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
    bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let transform = AffineTransform(scale: Double(pixels) / 1024)
  (transform as NSAffineTransform).concat()
  NSColor(calibratedRed: 38 / 255, green: 52 / 255, blue: 64 / 255, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 190, yRadius: 190
  ).fill()
  NSColor(calibratedRed: 220 / 255, green: 230 / 255, blue: 237 / 255, alpha: 1).setStroke()
  let pad = NSBezierPath(
    roundedRect: NSRect(x: 190, y: 260, width: 644, height: 504), xRadius: 84, yRadius: 84)
  pad.lineWidth = 34
  pad.stroke()
  NSColor(calibratedRed: 124 / 255, green: 215 / 255, blue: 235 / 255, alpha: 1).setStroke()
  let trail = NSBezierPath()
  trail.move(to: NSPoint(x: 300, y: 398))
  trail.curve(
    to: NSPoint(x: 730, y: 622), controlPoint1: NSPoint(x: 660, y: 654),
    controlPoint2: NSPoint(x: 364, y: 334))
  trail.lineWidth = 58
  trail.lineCapStyle = .round
  trail.stroke()
  NSColor(calibratedRed: 124 / 255, green: 215 / 255, blue: 235 / 255, alpha: 1).setFill()
  NSBezierPath(ovalIn: NSRect(x: 693, y: 585, width: 74, height: 74)).fill()
  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
  try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
  try render(points * 2).write(
    to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try render(1024).write(to: root.appendingPathComponent("logo.png"))
print("Generated original Swipepad placeholder PNG icon sizes.")
