import Foundation

/// The part of the trackpad used as the keyboard, in normalized pad coordinates (0...1).
/// Contacts outside it are ignored. Inside it, points are re-normalized to 0...1.
public struct PadRegion: Equatable, Sendable {
  public static let full = PadRegion(minX: 0, minY: 0, maxX: 1, maxY: 1)
  /// Width to height of the physical trackpad (about 4.3 by 3 inches).
  public static let trackpadWidthToHeight = 1.45
  /// About 71 mm by 36 mm on a trackpad of about 110 mm by 75 mm: an iPhone's width and keyboard height.
  /// Estimates from published sizes, not measured on a device.
  public static let iPhoneSized = PadRegion(minX: 0.175, minY: 0.26, maxX: 0.825, maxY: 0.74)
  /// Half the trackpad's width and height, centred: for small swipes with the hand resting on the pad.
  public static let compact = PadRegion(minX: 0.25, minY: 0.3, maxX: 0.75, maxY: 0.7)
  public static let minimumSpan = 0.3

  /// Named presets used by the Pad Area menu.
  public static func named(_ key: String) -> PadRegion? {
    switch key {
    case "full": return .full
    case "iPhone": return .iPhoneSized
    case "compact": return .compact
    default: return nil
    }
  }
  public static func preset(for region: PadRegion) -> String? {
    ["full": PadRegion.full, "iPhone": .iPhoneSized, "compact": .compact].first { $0.value == region }?.key
  }
  public let minX: Double, minY: Double, maxX: Double, maxY: Double

  public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var x0 = min(max(minX, 0), 1), x1 = min(max(maxX, 0), 1)
    var y0 = min(max(minY, 0), 1), y1 = min(max(maxY, 0), 1)
    if x1 - x0 < Self.minimumSpan { let c = min(max((x0 + x1) / 2, Self.minimumSpan / 2), 1 - Self.minimumSpan / 2); x0 = c - Self.minimumSpan / 2; x1 = c + Self.minimumSpan / 2 }
    if y1 - y0 < Self.minimumSpan { let c = min(max((y0 + y1) / 2, Self.minimumSpan / 2), 1 - Self.minimumSpan / 2); y0 = c - Self.minimumSpan / 2; y1 = c + Self.minimumSpan / 2 }
    self.minX = x0; self.minY = y0; self.maxX = x1; self.maxY = y1
  }
  public init(stored: [Double]?) {
    guard let v = stored, v.count == 4, v.allSatisfy(\.isFinite), v[2] > v[0], v[3] > v[1] else { self = .full; return }
    self.init(minX: v[0], minY: v[1], maxX: v[2], maxY: v[3])
  }
  /// Physical size of the trackpad these estimates are based on, in millimetres.
  public static let trackpadMM = (width: 110.0, height: 75.0)
  /// The area's size on a trackpad of `trackpadMM`. Estimates from published dimensions.
  public var physicalSizeMM: (width: Double, height: Double) {
    (spanX * Self.trackpadMM.width, spanY * Self.trackpadMM.height)
  }
  /// The preset whose area this matches, if any.
  public var matchingPreset: String? {
    ["full", "iPhone", "compact"].first { PadRegion.named($0) == self }
  }
  public enum Corner: Sendable { case topLeft, topRight, bottomLeft, bottomRight }
  /// Dragging one corner moves its two edges. Edges stop at the trackpad and keep the minimum size.
  public func dragging(_ corner: Corner, to p: Point) -> PadRegion {
    let x = min(max(p.x, 0), 1), y = min(max(p.y, 0), 1)
    switch corner {
    case .topLeft: return PadRegion(minX: min(x, maxX - Self.minimumSpan), minY: minY, maxX: maxX, maxY: max(y, minY + Self.minimumSpan))
    case .topRight: return PadRegion(minX: minX, minY: minY, maxX: max(x, minX + Self.minimumSpan), maxY: max(y, minY + Self.minimumSpan))
    case .bottomLeft: return PadRegion(minX: min(x, maxX - Self.minimumSpan), minY: min(y, maxY - Self.minimumSpan), maxX: maxX, maxY: maxY)
    case .bottomRight: return PadRegion(minX: minX, minY: min(y, maxY - Self.minimumSpan), maxX: max(x, minX + Self.minimumSpan), maxY: maxY)
    }
  }
  public var stored: [Double] { [minX, minY, maxX, maxY] }
  public var spanX: Double { maxX - minX }
  public var spanY: Double { maxY - minY }

  public func contains(_ p: Point) -> Bool {
    (minX...maxX).contains(p.x) && (minY...maxY).contains(p.y)
  }
  /// Trackpad point to area point (0...1 inside the area).
  public func toRegion(_ p: Point) -> Point {
    Point((p.x - minX) / spanX, (p.y - minY) / spanY)
  }
  /// Keeps only contacts inside the area, re-normalized. Times, phases and raw source points are kept.
  public func map(_ samples: [StrokeSample]) -> [StrokeSample] {
    guard self != .full else { return samples }
    return samples.filter { contains($0.sourcePoint) }.map {
      StrokeSample(toRegion($0.point), time: $0.time, phase: $0.phase, source: $0.source, sourcePoint: $0.sourcePoint)
    }
  }
}
