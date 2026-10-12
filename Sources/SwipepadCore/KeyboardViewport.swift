import Foundation

/// The part of the full QWERTY keyboard the pad maps onto, in normalized keyboard coordinates
/// (bottom-left origin). The full keyboard is the default. Recognition still runs on
/// `Keyboard.keys`: strokes are mapped into keyboard space before matching.
public struct KeyboardViewport: Equatable, Sendable {
  public static let full = KeyboardViewport(minX: 0, minY: 0, maxX: 1, maxY: 1)
  /// Smallest crop: three columns wide and one full row tall, so letters stay distinguishable.
  public static let minimumSpan = 0.3
  public let minX: Double, minY: Double, maxX: Double, maxY: Double

  public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var x0 = min(max(minX, 0), 1), x1 = min(max(maxX, 0), 1)
    var y0 = min(max(minY, 0), 1), y1 = min(max(maxY, 0), 1)
    if x1 - x0 < Self.minimumSpan { let c = min(max((x0 + x1) / 2, Self.minimumSpan / 2), 1 - Self.minimumSpan / 2); x0 = c - Self.minimumSpan / 2; x1 = c + Self.minimumSpan / 2 }
    if y1 - y0 < Self.minimumSpan { let c = min(max((y0 + y1) / 2, Self.minimumSpan / 2), 1 - Self.minimumSpan / 2); y0 = c - Self.minimumSpan / 2; y1 = c + Self.minimumSpan / 2 }
    self.minX = x0; self.minY = y0; self.maxX = x1; self.maxY = y1
  }
  /// Stored as [minX, minY, maxX, maxY]; anything malformed falls back to the full keyboard.
  public init(stored: [Double]?) {
    guard let v = stored, v.count == 4, v.allSatisfy(\.isFinite), v[2] > v[0], v[3] > v[1] else { self = .full; return }
    self.init(minX: v[0], minY: v[1], maxX: v[2], maxY: v[3])
  }
  public var stored: [Double] { [minX, minY, maxX, maxY] }
  public var spanX: Double { maxX - minX }
  public var spanY: Double { maxY - minY }
  public var isFull: Bool { self == .full }

  /// Pad point (0...1) to keyboard point.
  public func toKeyboard(_ p: Point) -> Point {
    Point(minX + p.x * spanX, minY + p.y * spanY)
  }
  /// Keyboard point to pad point. Points outside the viewport fall outside 0...1.
  public func toPad(_ k: Point) -> Point {
    Point((k.x - minX) / spanX, (k.y - minY) / spanY)
  }
  /// A key is shown and reachable when its centre lies inside the viewport.
  public func contains(_ key: Point) -> Bool {
    (minX...maxX).contains(key.x) && (minY...maxY).contains(key.y)
  }
  public enum Edge: Sendable, Equatable { case left, right, bottom, top }
  /// The crop edge nearest `p` within `tolerance` (keyboard units), if the pointer is alongside it.
  public func edge(at p: Point, tolerance: Double) -> Edge? {
    let alongY = p.y >= minY - tolerance && p.y <= maxY + tolerance
    let alongX = p.x >= minX - tolerance && p.x <= maxX + tolerance
    let options: [(Edge, Double)] = [
      (.left, abs(p.x - minX)), (.right, abs(p.x - maxX)), (.bottom, abs(p.y - minY)), (.top, abs(p.y - maxY)),
    ]
    return options.filter { edge, distance in
      guard distance <= tolerance else { return false }
      switch edge {
      case .left, .right: return alongY
      case .bottom, .top: return alongX
      }
    }.min { $0.1 < $1.1 }?.0
  }
  /// The viewport after dragging one edge to `value`, never crossing the opposite edge
  /// or leaving the keyboard.
  public func dragging(_ edge: Edge, to value: Double) -> KeyboardViewport {
    switch edge {
    case .left: return KeyboardViewport(minX: min(max(value, 0), maxX - Self.minimumSpan), minY: minY, maxX: maxX, maxY: maxY)
    case .right: return KeyboardViewport(minX: minX, minY: minY, maxX: max(min(value, 1), minX + Self.minimumSpan), maxY: maxY)
    case .bottom: return KeyboardViewport(minX: minX, minY: min(max(value, 0), maxY - Self.minimumSpan), maxX: maxX, maxY: maxY)
    case .top: return KeyboardViewport(minX: minX, minY: minY, maxX: maxX, maxY: max(min(value, 1), minY + Self.minimumSpan))
    }
  }
  /// Maps every sample into keyboard space. Time, phase, source and raw source points are kept.
  public func map(_ samples: [StrokeSample]) -> [StrokeSample] {
    guard !isFull else { return samples }
    return samples.map { StrokeSample(toKeyboard($0.point), time: $0.time, phase: $0.phase, source: $0.source, sourcePoint: $0.sourcePoint) }
  }
}
