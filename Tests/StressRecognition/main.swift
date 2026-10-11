import Foundation
import SwipepadCore
let words=WordVocabulary.words,lexicon=GestureLexicon(words:WordVocabulary.words)
func stableHash(_ word:String)->UInt64 {word.utf8.reduce(UInt64(1469598103934665603)) {($0 ^ UInt64($1)) &* 1099511628211}}
let common=words.filter {WordCommonness.tier($0)==0}.sorted {stableHash($0)<stableHash($1)}.prefix(1000)
let remaining=words.filter {!common.contains($0)}.sorted {stableHash($0)<stableHash($1)}.prefix(1000)
let corpus=Array(common)+Array(remaining)
let names=["centerBaseline","offsetRightDown","offsetLeftUp","jitter","sparseOffCenterKeys","nonuniformSpeedDwell","roundedCorners","endpointEdgeOffsets"]
func rawPath(_ word:String,_ variant:Int,_ seed:Int)->[StrokeSample] {
 var points=StrokeDecoder.resample(Keyboard.path(word),count:96)
 switch variant {
 case 1:points=points.map {Point($0.x+0.025,$0.y-0.04)}
 case 2:points=points.map {Point($0.x-0.025,$0.y+0.04)}
 case 3:points=points.enumerated().map {i,p in Point(p.x+0.025*sin(Double(i*7+seed)),p.y+0.035*cos(Double(i*11+seed)))}
 case 4:points=word.enumerated().compactMap {i,c in Keyboard.keys[c].map {Point($0.x+0.025*sin(Double(i+seed)),$0.y+0.04*cos(Double(i+seed)))}}
 case 5:
  points=StrokeDecoder.resample(Keyboard.path(word),count:144)
  points=points.enumerated().flatMap {i,p in i%17==0 ? Array(repeating:p,count:5):[p]}
 case 6:
  let original=points;points=original.enumerated().map {i,p in guard i>0,i<original.count-1 else {return p};let a=original[i-1],b=original[i+1];return Point((a.x+2*p.x+b.x)/4,(a.y+2*p.y+b.y)/4)}
 case 7:
  if let first=points.first,let last=points.last {
   points[0]=Point(first.x+0.035,first.y-0.065)
   points[points.count-1]=Point(last.x-0.035,last.y+0.065)
  }
 default:break
 }
 return points.enumerated().map {i,p in StrokeSample(p,time:pow(Double(i)/Double(max(1,points.count-1)),variant==5 ? 2.0:1.0)*1.7,source:.trackpad)}
}
func stats()->[String:Int] { ["trials":0,"rankedTop1":0,"rankedTop5":0,"correctCommit":0,"wrongCommit":0,"refused":0] }
func update(_ result:inout [String:Int],word:String,ranked:[GestureCandidate]) {
 result["trials",default:0] += 1
 if ranked.first?.word==word {result["rankedTop1",default:0] += 1}
 if ranked.contains(where:{$0.word==word}) {result["rankedTop5",default:0] += 1}
 if !StrokeDecoder.accepts(ranked) {result["refused",default:0] += 1}
 else {result[ranked.first?.word==word ? "correctCommit":"wrongCommit",default:0] += 1}
}
var groups:[String:[String:Int]]=[:],failures:[String:[[String:Any]]]=[:],latencies:[Double]=[]
let started=ProcessInfo.processInfo.systemUptime
for (index,word) in corpus.enumerated() {
 for variant in 0..<names.count {
  let raw=rawPath(word,variant,index),original=raw
  let time=ProcessInfo.processInfo.systemUptime,ranked=lexicon.rank(raw)
  latencies.append((ProcessInfo.processInfo.systemUptime-time)*1000)
  precondition(raw==original,"samples changed")
  var group=groups[names[variant]] ?? stats();update(&group,word:word,ranked:ranked);groups[names[variant]]=group
  let level=WordCommonness.tier(word)==0 ? "commonWords":"broaderWords"
  var stratum=groups[level] ?? stats();update(&stratum,word:word,ranked:ranked);groups[level]=stratum
  if ranked.first?.word != word || !StrokeDecoder.accepts(ranked) {
   failures[names[variant],default:[]].append(["word":word,"top":ranked.first?.word ?? "NO_MATCH","accepted":StrokeDecoder.accepts(ranked),"geometry":ranked.first?.geometryScore ?? 1,"adjustedScore":ranked.first?.score ?? 1])
  }
 }
 if index%250==0 {FileHandle.standardError.write(Data("Completed \(index)/\(corpus.count) words\n".utf8))}
}
var special:[[String:Any]]=[]
for word in ["auto","ring","hung","rink","think","type","were","power","tree","all","fall","pull","red","reed","god","good","cook","cooked","stopping"] {
 for variant in 0..<names.count {
  let raw=rawPath(word,variant,0),ranked=lexicon.rank(raw)
  special.append(["word":word,"condition":names[variant],"candidates":ranked.map(\.word),"geometry":ranked.map(\.geometryScore),"adjustedScores":ranked.map(\.score),"accepted":StrokeDecoder.accepts(ranked),"rawPoints":raw.map {[$0.point.x,$0.point.y]}])
 }
 let path=Keyboard.path(word)
 if let a=path.first,let b=path.last,a.distance(b)>0.01 {
  let line=(0..<64).map {i in let t=Double(i)/63;return StrokeSample(Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t),time:t,source:.trackpad)}
  let ranked=lexicon.rank(line)
  special.append(["word":word,"condition":"directLineShortcut","candidates":ranked.map(\.word),"accepted":StrokeDecoder.accepts(ranked),"geometry":ranked.map(\.geometryScore),"rawPoints":line.map {[$0.point.x,$0.point.y]}])
 }
}
latencies.sort()
let output:[String:Any]=["words":corpus,"trials":corpus.count*names.count,"groups":groups,"failureRows":failures,"specialRawCases":special,"rankingMilliseconds":["median":latencies[latencies.count/2],"p95":latencies[Int(Double(latencies.count)*0.95)],"max":latencies.last!],"elapsedSeconds":ProcessInfo.processInfo.systemUptime-started,"limits":"Synthetic stress test, not new held-out calibration or real finger accuracy. No model tuning during this run. No start-origin subtraction, pointer positioning, recentering or snapping. Center baseline is reported separately; production normalized-shape component does not replace absolute geometry. Straight shortcuts can erase required reversals." ]
print(String(data:try! JSONSerialization.data(withJSONObject:output,options:[.sortedKeys,.prettyPrinted]),encoding:.utf8)!)
