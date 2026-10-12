import Foundation

/// How a decided word reaches the focused field.
public enum InsertionRoute: Equatable, Sendable {
  /// Verified accessibility write, for native text fields that expose their contents.
  case accessibility
  /// Real key presses to the focused app, for web-based editors (Claude, Slack, browsers).
  /// Accessibility writes there are accepted but do not reliably show up, so they can't be confirmed.
  case keystroke

  public static func choose(insideWebArea: Bool) -> InsertionRoute {
    insideWebArea ? .keystroke : .accessibility
  }
}

/// Undo of the last typed word: delete it with Backspace, then offer the next candidates.
public enum UndoPlan {
  /// The word plus the space typed after it.
  public static func backspaceCount(for word: String) -> Int { word.count + 1 }

  /// The remaining candidates in ranked order, without the word that was just undone.
  public static func alternatives(after typed: String, from ranked: [String]) -> [String] {
    ranked.filter { $0 != typed }
  }
}
