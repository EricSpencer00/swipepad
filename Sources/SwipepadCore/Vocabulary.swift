import Foundation

/// Licensed broad lexicon only; no handpicked complaint-word additions.
public enum WordVocabulary {
  public static let words = LexiconData.text.components(separatedBy:"\n").filter {!$0.isEmpty}
}
