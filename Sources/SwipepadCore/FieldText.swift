import Foundation

/// Raw AXError values from HIServices/AXError.h. Kept here so SwipepadCore stays free of
/// ApplicationServices; the app passes `AXError.rawValue` straight through.
public enum AccessibilityErrorCode {
  public static let cannotComplete = -25204
  public static let attributeUnsupported = -25205
  public static let apiDisabled = -25211
  public static let noValue = -25212
  public static let parameterizedAttributeUnsupported = -25213
}

/// What one Accessibility provider reported about a focused field's text. Each field is a raw
/// read result; `FieldText.resolve` decides whether any of them can be trusted as document text.
public struct FieldTextProbe: Equatable, Sendable {
  /// AXValue as a String. nil when absent, not a String, or unreadable.
  public var value: String?
  /// AXError raw value from the AXValue read. nil when that read did not happen.
  public var valueError: Int?
  /// AXNumberOfCharacters, already validated as a non-negative count.
  public var characterCount: Int?
  /// AXNumberOfCharacters re-read after the full-range read. Must still equal `characterCount`.
  public var characterCountAfterRead: Int?
  /// AXStringForRange over 0..<characterCount. nil when the provider refuses that read.
  public var fullRangeText: String?
  /// AXError raw value from the full-range read. nil when that read did not happen.
  public var fullRangeError: Int?
  /// Non-empty AXPlaceholderValue. Hint text: never document text by itself.
  public var placeholder: String?

  public init(
    value: String? = nil, valueError: Int? = nil, characterCount: Int? = nil,
    characterCountAfterRead: Int? = nil, fullRangeText: String? = nil,
    fullRangeError: Int? = nil, placeholder: String? = nil
  ) {
    self.value = value
    self.valueError = valueError
    self.characterCount = characterCount
    self.characterCountAfterRead = characterCountAfterRead
    self.fullRangeText = fullRangeText
    self.fullRangeError = fullRangeError
    self.placeholder = placeholder
  }
}

/// Chooses the document text for a field from providers that disagree with each other.
///
/// Fields differ in what they expose: some omit AXValue, some report a placeholder as their
/// value, some omit the character count, some refuse the full-range read. This policy accepts
/// only evidence that agrees with an authoritative count, and refuses anything it cannot verify.
public enum FieldText {
  public enum Source: Equatable, Sendable {
    /// Text returned by AXStringForRange over the provider's full, verified character count.
    case fullRange
    /// AXValue, accepted because no full-range text was available and the count (if any) agrees.
    case value
  }

  public struct Evidence: Equatable, Sendable {
    public let text: String
    public let source: Source
    /// True when AXValue equals the placeholder and no character count verified it. That value
    /// may be an empty field's hint, or authored text that happens to match the hint. Insertion
    /// at the caret can still proceed and is checked by exact receipts. A whole-value rewrite
    /// must not use this evidence, because it would publish the hint as document text.
    public let placeholderAmbiguous: Bool
  }

  /// AXValue errors that mean "no value here" rather than "the provider failed to answer".
  private static let absentValueErrors: Set<Int> = [
    0, AccessibilityErrorCode.noValue, AccessibilityErrorCode.attributeUnsupported,
  ]
  /// Full-range read errors that permit falling back to AXValue. Any other error refuses.
  private static let absentRangeErrors: Set<Int> = [
    AccessibilityErrorCode.noValue, AccessibilityErrorCode.parameterizedAttributeUnsupported,
    AccessibilityErrorCode.attributeUnsupported,
  ]

  /// Whether an AXValue read result may be used at all. Permission and provider failures are not
  /// absence, so they refuse before any other read; in particular, no text-suite fallback runs.
  public static func permitsValueRead(error: Int?) -> Bool {
    guard let error else { return true }
    return absentValueErrors.contains(error)
  }

  public static func resolve(_ probe: FieldTextProbe) -> Evidence? {
    guard permitsValueRead(error: probe.valueError) else { return nil }
    if let count = probe.characterCount {
      if let text = probe.fullRangeText {
        // Full-range text is authoritative only when it has exactly the reported UTF-16 count and
        // the count is stable across the read. Partial or context-only ranges are never used.
        guard text.utf16.count == count, probe.characterCountAfterRead == count else { return nil }
        return Evidence(text: text, source: .fullRange, placeholderAmbiguous: false)
      }
      guard let error = probe.fullRangeError, absentRangeErrors.contains(error) else { return nil }
    }
    // Without a count, AXValue is unverified. A reported count must agree with it, so a count of
    // zero never accepts a non-empty value.
    guard let text = probe.value else { return nil }
    if let count = probe.characterCount, count != text.utf16.count { return nil }
    let ambiguous = probe.characterCount == nil && probe.placeholder == text
    return Evidence(text: text, source: .value, placeholderAmbiguous: ambiguous)
  }
}
