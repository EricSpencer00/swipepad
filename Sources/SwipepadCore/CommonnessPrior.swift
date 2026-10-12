import Foundation
/// SCOWL-derived coarse commonness penalty. Geometry remains primary.
public enum CommonnessPrior {
  public static let weight = 0.002
  public static func rerank(_ candidates:[GestureCandidate],weight:Double)->[GestureCandidate] {
    candidates.map {candidate in
      GestureCandidate(word:candidate.word,score:candidate.geometryScore+min(0.006,max(0,weight)*Double(WordCommonness.tier(candidate.word))),geometryScore:candidate.geometryScore)
    }.sorted {$0.score == $1.score ? $0.word < $1.word:$0.score < $1.score}
  }
}
