import Foundation

public enum InputMode: String, Codable, Sendable { case trackpad, screenOverlay }
public enum ContactPhase: String, Codable, Sendable { case began, moved, ended }
public struct StrokeSample: Equatable, Sendable {
  public let point: Point
  public let time: Double
  public let phase: ContactPhase
  public let source: InputMode
  public let sourcePoint: Point
  public init(_ point: Point, time: Double, phase: ContactPhase = .moved, source: InputMode = .screenOverlay, sourcePoint: Point? = nil) {
    self.point = point; self.time = time; self.phase = phase; self.source=source; self.sourcePoint=sourcePoint ?? point
  }
}
/// Screen points, bottom-left origin. Never uses backing pixels or silently clamps a stroke.
public struct CalibrationRect: Equatable, Sendable {
  public var x: Double, y: Double, width: Double, height: Double
  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x=x; self.y=y; self.width=width; self.height=height
  }
  public var isValid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
  public func normalize(_ point: Point) -> Point? {
    guard isValid, point.x.isFinite, point.y.isFinite else { return nil }
    return Point((point.x-x)/width,(point.y-y)/height)
  }
  public func screenPoint(_ point: Point) -> Point { Point(x+point.x*width,y+point.y*height) }
  /// Saved normalized layout uses width and center; height always follows the keyboard aspect.
  /// Bounds fitting applies to layout only, never to captured stroke points.
  public static func restoreOverlay(_ stored:[Double], in visible:CalibrationRect, aspect:Double=0.38) -> CalibrationRect? {
    guard visible.isValid,aspect.isFinite,aspect>0,stored.count==4,
      stored.allSatisfy(\.isFinite),stored[0]>=0,stored[1]>=0,stored[2]>0,stored[3]>0,
      stored[0]+stored[2]<=1.000001,stored[1]+stored[3]<=1.000001 else {return nil}
    let width=min(stored[2]*visible.width,visible.width,visible.height/aspect)
    let height=width*aspect
    guard width>=240,height>=90 else {return nil}
    let center=visible.screenPoint(Point(stored[0]+stored[2]/2,stored[1]+stored[3]/2))
    let x=min(max(visible.x,center.x-width/2),visible.x+visible.width-width)
    let y=min(max(visible.y,center.y-height/2),visible.y+visible.height-height)
    return CalibrationRect(x:x,y:y,width:width,height:height)
  }
}
public struct GestureCandidate: Sendable {
  public let word: String
  public let score: Double
}
/// Original inspectable full-path matcher. Location and normalized shape are scored separately.
/// Geometry does not infer a repeated letter from a pause; localized loops are only a soft cue.
public enum PathMatching: Sendable { case proportional, bandedDTW }
public enum StrokeDecoder {
  public static func resample(_ points: [Point], count: Int = 64) -> [Point] {
    guard count >= 2, let first=points.first, let last=points.last,
      points.allSatisfy({$0.x.isFinite && $0.y.isFinite}) else { return [] }
    var lengths = [0.0]
    for (a,b) in zip(points,points.dropFirst()) { lengths.append(lengths.last!+a.distance(b)) }
    guard let total=lengths.last, total > 0.000001 else {return []}
    var result=[first]; var segment=1
    for index in 1..<(count-1) {
      let distance=total*Double(index)/Double(count-1)
      while segment < lengths.count-1 && lengths[segment] < distance {segment += 1}
      let span=lengths[segment]-lengths[segment-1]
      let fraction=span > 0 ? (distance-lengths[segment-1])/span : 0
      let a=points[segment-1],b=points[segment]
      result.append(Point(a.x+(b.x-a.x)*fraction,a.y+(b.y-a.y)*fraction))
    }
    result.append(last)
    return result
  }
  static func shape(_ points:[Point]) -> [Point] {
    guard !points.isEmpty else {return []}
    let center=Point(points.map(\.x).reduce(0,+)/Double(points.count),points.map(\.y).reduce(0,+)/Double(points.count))
    let extent=max((points.map(\.x).max() ?? 0)-(points.map(\.x).min() ?? 0),(points.map(\.y).max() ?? 0)-(points.map(\.y).min() ?? 0),0.05)
    return points.map {Point(($0.x-center.x)/extent,($0.y-center.y)/extent)}
  }
  static func meanDistance(_ a:[Point],_ b:[Point]) -> Double {
    guard a.count==b.count,!a.isEmpty else {return .infinity}
    return zip(a,b).map {$0.distance($1)}.reduce(0,+)/Double(a.count)
  }
  public static func bandedDistance(_ a:[Point],_ b:[Point],band:Int=8) -> Double {
    guard !a.isEmpty,!b.isEmpty,band>=0 else {return .infinity}
    var previous=Array(repeating:Double.infinity,count:b.count+1);previous[0]=0
    for (index,point) in a.enumerated() {
      var current=Array(repeating:Double.infinity,count:b.count+1)
      let lower=max(1,index+1-band),upper=min(b.count,index+1+band)
      if lower<=upper {
        for column in lower...upper {current[column]=point.distance(b[column-1])+min(previous[column],previous[column-1],current[column-1])}
      }
      previous=current
    }
    return previous[b.count]/Double(max(a.count,b.count))
  }
  static func loopCue(_ raw:[Point],near key:Point) -> Double {
    let local=raw.filter {$0.distance(key)<0.085}
    guard local.count>=5 else {return 0}
    let length=zip(local,local.dropFirst()).map {$0.distance($1)}.reduce(0,+)
    // Require nonzero area, not a dwell or a simple forward/back traversal.
    let area=abs(zip(local,Array(local.dropFirst())+[local[0]]).map {$0.x*$1.y-$1.x*$0.y}.reduce(0,+))/2
    let angles=local.filter {$0.distance(key)>0.015}.map {atan2($0.y-key.y,$0.x-key.x)}
    let winding=zip(angles,angles.dropFirst()).map { a,b -> Double in
      var delta=b-a
      while delta>Double.pi {delta -= 2*Double.pi}
      while delta < -Double.pi {delta += 2*Double.pi}
      return delta
    }.reduce(0,+)
    guard area>0.00035,length>0.10,abs(winding)>4.5 else {return 0}
    return min(0.012,area*2)
  }
  public static func rank(_ samples:[StrokeSample],words:[String],limit:Int=5,matching:PathMatching = .proportional) -> [GestureCandidate] {
    guard samples.count>=3,limit>0,
      samples.allSatisfy({$0.source==samples[0].source && $0.sourcePoint.x.isFinite && $0.sourcePoint.y.isFinite && $0.time.isFinite && $0.point.x.isFinite && $0.point.y.isFinite && (0...1).contains($0.point.x) && (0...1).contains($0.point.y)}),
      zip(samples,samples.dropFirst()).allSatisfy({$0.time <= $1.time}) else {return []}
    let raw=samples.map(\.point), observed=resample(raw)
    guard !observed.isEmpty, let start=raw.first, let end=raw.last else {return []}
    let normalized=shape(observed)
    let scores=words.compactMap {word -> GestureCandidate? in
      guard word.count>=2,word.lowercased().allSatisfy({Keyboard.keys[$0] != nil}) else {return nil}
      let ideal=resample(Keyboard.path(word))
      guard !ideal.isEmpty else {return nil}
      let endpoint=(start.distance(ideal[0])+end.distance(ideal.last!))/2
      // Soft endpoint penalty; no hard first-letter filter or angle snapping.
      let location=matching == .proportional ? meanDistance(observed,ideal) : bandedDistance(observed,ideal)
      let shapeScore=matching == .proportional ? meanDistance(normalized,shape(ideal)) : bandedDistance(normalized,shape(ideal))
      var score=0.65*location+0.20*shapeScore+0.15*endpoint
      let chars=Array(word.lowercased())
      for pair in zip(chars,chars.dropFirst()) where pair.0==pair.1 {
        if let key=Keyboard.keys[pair.0] {score -= loopCue(raw,near:key)}
      }
      return GestureCandidate(word:word,score:score)
    }.sorted {$0.score == $1.score ? $0.word < $1.word : $0.score < $1.score}
    return Array(scores.prefix(limit))
  }
  public static func candidates(_ samples:[StrokeSample],words:[String]) -> [String] {
    let ranked=rank(samples,words:words)
    guard let first=ranked.first,first.score < 0.24 else {return []}
    return ranked.map(\.word)
  }
}
