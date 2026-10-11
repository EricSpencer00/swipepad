import Foundation
import Darwin
import SwipepadCore
func millis(_ start:Double)->Double {(ProcessInfo.processInfo.systemUptime-start)*1000}
func peakBytes()->Int64 {var value=rusage();getrusage(RUSAGE_SELF,&value);return Int64(value.ru_maxrss)}
let beforeMemory=peakBytes(),start=ProcessInfo.processInfo.systemUptime
let words=WordVocabulary.words,lexicon=GestureLexicon(words:words)
let startup=millis(start),afterMemory=peakBytes()
func samples(_ word:String,_ seed:Int,_ variant:Int)->[StrokeSample] {
 let points=StrokeDecoder.resample(Keyboard.path(word),count:[48,96,144][variant]).enumerated().map {i,p in
  let noise=[0.0,0.015,0.035][variant]
  return Point(p.x+noise*sin(Double(i*7+seed)),p.y+noise*cos(Double(i*11+seed)))
 }
 return points.enumerated().map {i,p in StrokeSample(p,time:pow(Double(i)/Double(max(1,points.count-1)),[1.0,0.7,1.6][variant])*1.5,source:.trackpad)}
}

precondition(priorValidationWords.count==400 && Set(priorValidationWords).count==400 && Set(priorValidationWords).isDisjoint(with:legacySupplementalVocabulary),"disjoint word set invalid")
precondition(StrokeDecoder.maximumAcceptedScore==0.06 && StrokeDecoder.minimumCandidateMargin==0.003,"locked policy changed")
precondition(CommonnessPrior.rerank([GestureCandidate(word:"the",score:0.02),GestureCandidate(word:"ruing",score:0.001)],weight:0.002).first?.word=="ruing","prior overrode clear geometric evidence")
for word in ["ring","hung","rink","think"] {for variant in 0..<3 {precondition(lexicon.candidates(samples(word,0,variant)).first==word,"reported noisy word-at-lift candidate regression")}}
var rows:[[String:Any]]=[],latencies:[Double]=[],top1=0,wrong=0,rejected=0,rawTop5=0,acceptedTop5=0
for (index,word) in priorValidationWords.enumerated() {for variant in 0..<3 {
 let raw=samples(word,index,variant),start=ProcessInfo.processInfo.systemUptime
 let ranked=lexicon.rank(raw);latencies.append(millis(start))
 let accepted=StrokeDecoder.accepts(ranked),correct=ranked.first?.word==word
 if ranked.contains(where:{$0.word==word}) {rawTop5 += 1;if accepted {acceptedTop5 += 1}}
 if !accepted {rejected += 1}else if correct {top1 += 1}else {wrong += 1}
 rows.append(["word":word,"variant":variant,"top":ranked.first?.word ?? "NO_MATCH","accepted":accepted,"correct":correct,"score":ranked.first?.score ?? 1,"geometryScore":ranked.first?.geometryScore ?? 1,"commonnessTier":ranked.first.map {WordCommonness.tier($0.word)} ?? 3,"margin":ranked.count>1 ? ranked[1].score-ranked[0].score:0])
}}
let unknown="snibble frozz quimble troggle glimzo blavish cranple nurble wazzup drimpo flungish snarpo plazzim grunple frawm glimmerz cronkish skribble vlem thazzle".components(separatedBy:" ")
var unknownCovered=0,unknownAccepted=0
for (index,word) in unknown.enumerated() {if words.contains(word) {unknownCovered += 1};for variant in 0..<3 {if lexicon.candidates(samples(word,index,variant)).count>0 {unknownAccepted += 1}}}
var complaintRows:[[String:Any]]=[]
for word in ["ring","hung","rink","think"] {for variant in 0..<3 {
 let raw=samples(word,0,variant),ranked=lexicon.rank(raw)
 complaintRows.append(["word":word,"variant":variant,"top":ranked.first?.word ?? "NO_MATCH","accepted":StrokeDecoder.accepts(ranked),"points":raw.map {[$0.point.x,$0.point.y]},"score":ranked.first?.score ?? 1,"geometryScore":ranked.first?.geometryScore ?? 1,"commonnessTier":ranked.first.map {WordCommonness.tier($0.word)} ?? 3,"margin":ranked.count>1 ? ranked[1].score-ranked[0].score:0])
}}
var ambiguity:[[String:Any]]=[]
for word in ["red","reed","god","good","cook","cooked","coffee","book","stopping","stopped"] {
 let raw=samples(word,0,0)
 for loop in [false,true] {
  var traced=raw
  if loop,let pair=zip(Array(word),Array(word.dropFirst())).first(where:{$0.0==$0.1}),let key=Keyboard.keys[pair.0],let index=raw.indices.min(by:{raw[$0].point.distance(key)<raw[$1].point.distance(key)}) {
   let points=(0...16).map {i in Point(key.x+0.035*cos(Double(i)*Double.pi/8),key.y+0.035*sin(Double(i)*Double.pi/8))}
   let all=Array(raw.prefix(index)).map(\.point)+points+Array(raw.dropFirst(index)).map(\.point)
   traced=all.enumerated().map {StrokeSample($0.element,time:Double($0.offset)*0.01,source:.trackpad)}
  }
  let ranked=lexicon.rank(traced)
  ambiguity.append(["word":word,"loop":loop,"accepted":StrokeDecoder.accepts(ranked),"candidates":ranked.map(\.word),"scores":ranked.map(\.score),"points":traced.map {[$0.point.x,$0.point.y]}])
 }
}
func distribution(_ values:[Double])->[String:Double] {let x=values.sorted();guard !x.isEmpty else {return [:]};return ["minimum":x.first!,"median":x[x.count/2],"p95":x[Int(Double(x.count-1)*0.95)],"maximum":x.last!]}
var distributions:[String:Any]=[:]
for label in ["correctAccepted","wrongAccepted","rejected"] {
 let subset=rows.filter {row in let accepted=row["accepted"] as! Bool,correct=row["correct"] as! Bool;return label=="rejected" ? !accepted : (accepted && correct==(label=="correctAccepted"))}
 distributions[label]=["count":subset.count,"score":distribution(subset.map {$0["score"] as! Double}),"margin":distribution(subset.map {$0["margin"] as! Double})]
}
let report:[String:Any]=["syntheticDisjointLexicalValidation":true,"words":priorValidationWords.count,"trials":rows.count,"correctAcceptedTop1":top1,"wrongAccepted":wrong,"rejected":rejected,"rawTop5":rawTop5,"acceptedTop5":acceptedTop5,"rows":rows,"scoreMarginDistributions":distributions,"newUnknownWords":unknown,"unknownCovered":unknownCovered,"unknownAcceptedOf60":unknownAccepted,"complaints":complaintRows,"ambiguityAndLoops":ambiguity,"rankingCallMilliseconds":distribution(latencies),"indexBuildMilliseconds":startup,"peakRSSBytes":peakBytes(),"limits":"New400 word set,100 per commonness tier; disjoint from prior tests/development. Same synthetic geometry generator, not corpus weighted or independent human gesture distributions. Prior/cutoff locked before this evaluation." ]
print(String(data:try! JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]),encoding:.utf8)!)
