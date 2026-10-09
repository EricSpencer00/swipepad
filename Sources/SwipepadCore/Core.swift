import Foundation

public struct Point: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }
  public func distance(_ p: Point) -> Double { hypot(x - p.x, y - p.y) }
}
public enum Keyboard {
  // Layout adapted from SwipeType's MIT keyboard.rs; normalized, bottom-left origin.
  public static let keys: [Character: Point] = {
    var result: [Character: Point] = [:]
    for (row, offset, y) in [
      ("qwertyuiop", 0.0, 0.80), ("asdfghjkl", 0.5, 0.50), ("zxcvbnm", 1.5, 0.20),
    ] {
      for (i, c) in row.enumerated() { result[c] = Point((Double(i) + offset + 0.5) / 10, y) }
    }
    return result
  }()
  public static func path(_ word: String) -> [Point] {
    let points = word.lowercased().compactMap { keys[$0] }
    guard let first = points.first else { return [] }
    var result = [first]
    for p in points.dropFirst() {
      let last = result.last!
      let steps = max(1, Int(ceil(last.distance(p) / 0.025)))
      for s in 1...steps {
        let t = Double(s) / Double(steps)
        result.append(Point(last.x + (p.x - last.x) * t, last.y + (p.y - last.y) * t))
      }
    }
    return result
  }
}
public enum Decoder {
  // Two-row DTW recurrence adapted from SwipeType's MIT dtw.rs.
  public static func distance(_ a: [Point], _ b: [Point]) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return .infinity }
    var previous = Array(repeating: Double.infinity, count: b.count + 1)
    previous[0] = 0
    for p in a {
      var current = Array(repeating: Double.infinity, count: b.count + 1)
      for j in 1...b.count {
        current[j] = p.distance(b[j - 1]) + min(previous[j], previous[j - 1], current[j - 1])
      }
      previous = current
    }
    return previous[b.count] / Double(max(a.count, b.count))
  }
  public static func candidates(_ path: [Point], words: [String]) -> [String] {
    guard path.count >= 2,
      path.allSatisfy({
        $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)
      })
    else { return [] }
    let scored: [(String, Double)] = words.map { word in (word, distance(path, Keyboard.path(word)))
    }
    let ranked = scored.sorted { a, b in
      if a.1 == b.1 { return a.0 < b.0 }
      return a.1 < b.1
    }
    return ranked.prefix(5).map { $0.0 }
  }
}
public struct CommandTap: Sendable {
  public var interval = 0.35
  public var debounce = 0.15
  private var down = false
  private var last: Double?
  private var pressed: Double?
  private var fired = -Double.infinity
  public init() {}
  public mutating func cancel() {
    last = nil
    pressed = nil
  }
  public mutating func update(isDown: Bool, onlyCommand: Bool, time: Double) -> Bool {
    guard onlyCommand else {
      cancel()
      down = isDown
      return false
    }
    guard down != isDown else { return false }
    down = isDown
    if isDown {
      pressed = time
      return false
    }
    guard let start = pressed, time - start < interval else {
      cancel()
      return false
    }
    pressed = nil
    if let last, time - last <= interval, time - fired >= debounce {
      self.last = nil
      fired = time
      return true
    }
    last = time
    return false
  }
}
public enum FocusGuard {
  public static func permits(
    originalPID: Int32, currentPID: Int32, sameElement: Bool, secure: Bool, editable: Bool
  ) -> Bool {
    originalPID == currentPID && sameElement && !secure && editable
  }
}
