import Foundation

/// Immutable endpoint index and coarse shape shortlist. No user text or training state.
public struct GestureLexicon: Sendable {
  struct Entry: Sendable {let word:String;let points:[Point];let shape:[Point]}
  private let buckets:[String:[Entry]]
  private let usePrior:Bool
  public let count:Int
  public init(words:[String],usePrior:Bool=true) {
    self.usePrior=usePrior
    var index:[String:[Entry]]=[:];var total=0
    for word in Set(words).sorted() {
      guard word.count>=2,let first=word.first,let last=word.last,Keyboard.keys[first] != nil,Keyboard.keys[last] != nil,word.allSatisfy({Keyboard.keys[$0] != nil}) else {continue}
      let points=StrokeDecoder.resample(Keyboard.path(word),count:16)
      guard !points.isEmpty else {continue}
      index[String(first)+String(last),default:[]].append(Entry(word:word,points:points,shape:StrokeDecoder.shape(points)));total += 1
    }
    buckets=index;count=total
  }
  public func rank(_ samples:[StrokeSample],limit:Int=5)->[GestureCandidate] {
    guard samples.count>=3,let first=samples.first,let last=samples.last,
      samples.allSatisfy({$0.source==first.source && $0.time.isFinite && $0.sourcePoint.x.isFinite && $0.sourcePoint.y.isFinite && Keyboard.nearestKey($0.point) != nil}),
      zip(samples,samples.dropFirst()).allSatisfy({$0.time <= $1.time}) else {return []}
    let observed=StrokeDecoder.resample(samples.map(\.point),count:16)
    guard !observed.isEmpty else {return []}
    let shape=StrokeDecoder.shape(observed)
    // Wide start search: a finger can land several keys from the first letter.
    let starts=Keyboard.keys.filter {$0.value.distance(first.point)<=0.5}.map(\.key)
    let ends=Keyboard.keys.filter {$0.value.distance(last.point)<=0.24}.map(\.key)
    var shortlist:[(String,Double)]=[]
    for start in starts {for end in ends {for entry in buckets[String(start)+String(end)] ?? [] {
      let endpoint=(0.4*first.point.distance(entry.points[0])+last.point.distance(entry.points.last!))/1.4
      let aligned=StrokeDecoder.anchored(observed,to:entry.points[0])
      let score=0.65*StrokeDecoder.meanDistance(aligned,entry.points)+0.20*StrokeDecoder.meanDistance(shape,entry.shape)+0.15*endpoint
      shortlist.append((entry.word,score))
    }}}
    shortlist.sort {$0.1 == $1.1 ? $0.0 < $1.0:$0.1 < $1.1}
    // Full raw-path matcher retains loops and exact endpoints on the best coarse shapes.
    let geometric=StrokeDecoder.rank(samples,words:shortlist.prefix(256).map(\.0),limit:max(32,limit))
    return Array((usePrior ? CommonnessPrior.rerank(geometric,weight:CommonnessPrior.weight):geometric).prefix(limit))
  }
  public func candidates(_ samples:[StrokeSample])->[String] {
    let ranking=rank(samples)
    guard StrokeDecoder.accepts(ranking) else {return []}
    return ranking.map(\.word)
  }
}
