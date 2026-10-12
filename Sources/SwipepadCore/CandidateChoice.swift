import Foundation

/// What to do with a ranked list of candidate words.
public enum CandidateDecision: Equatable, Sendable {
  case commit(String)
  case choose([String])
  case none
}

/// Turns the recognizer's ranking into a decision. A clear winner is typed. A close call types
/// nothing and offers the top few words, which the user picks with a tap on the top strip.
public enum CandidateChoice {
  /// Relative score gap between the best and second-best candidate that counts as a clear winner.
  /// Measured on synthetic swipes: 1.0 holds back 59 of 70 wrong top words and 38 of 215 right ones.
  public static let commitMargin = 1.0
  public static let maximumChoices = 3
  /// Lowest y of the top strip in pad coordinates (bottom-left origin). Taps here pick a shown word.
  public static let stripBottom = 0.84

  public static func decide(_ ranked: [GestureCandidate]) -> CandidateDecision {
    guard let first = ranked.first else { return .none }
    guard ranked.count > 1 else { return .commit(first.word) }
    let margin = (ranked[1].score - first.score) / max(abs(first.score), 1e-6)
    if margin >= commitMargin { return .commit(first.word) }
    return .choose(ranked.prefix(maximumChoices).map(\.word))
  }

  /// Which shown choice a touch picks: the strip is split into equal thirds (or fewer parts).
  public static func choiceIndex(for start: Point, count: Int) -> Int? {
    guard count > 0, start.y >= stripBottom, (0...1).contains(start.x) else { return nil }
    return min(count - 1, Int(start.x * Double(count)))
  }
}
