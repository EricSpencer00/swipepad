import Foundation

/// Drops single-sample contact-centroid spikes, such as a finger rolling and snapping back.
/// A step much larger than the recent typical step is held back. If the next sample lands
/// near it, the shift is real movement and is accepted. Raw samples are never resampled.
public struct ContactJumpFilter: Sendable {
  /// A step at least this large is always suspicious, however fast the recent swipe was.
  public static let minimumJump = 0.07
  /// A step this many times the recent typical step is suspicious.
  public static let jumpFactor = 2.5
  /// A held-back sample is confirmed when the next one lands this close to it.
  public static let confirmRadius = 0.04

  private var last: Point?
  private var pending: Point?
  private var recentSteps: [Double] = []

  public init() {}

  /// Returns true when the sample belongs in the stroke.
  public mutating func accept(_ p: Point, time: Double) -> Bool {
    guard p.x.isFinite, p.y.isFinite, time.isFinite else { return false }
    guard let previous = last else {
      last = p; return true
    }
    let step = previous.distance(p)
    let typical = median(recentSteps) ?? step
    let isJump = step >= Self.minimumJump && step > Self.jumpFactor * max(typical, 0.01)
    if !isJump {
      pending = nil
      record(step)
      last = p
      return true
    }
    if let held = pending, held.distance(p) < Self.confirmRadius {
      // Two consecutive samples agree on the new place: real movement.
      pending = nil
      record(step)
      last = p
      return true
    }
    pending = p
    return false
  }

  private mutating func record(_ step: Double) {
    recentSteps.append(step)
    if recentSteps.count > 6 { recentSteps.removeFirst() }
  }

  private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}
