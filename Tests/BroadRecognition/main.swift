import Foundation
import Darwin
import SwipepadCore
func millis(_ start:Double)->Double {(ProcessInfo.processInfo.systemUptime-start)*1000}
func peakBytes()->Int64 {var value=rusage();getrusage(RUSAGE_SELF,&value);return Int64(value.ru_maxrss)}
let beforeMemory=peakBytes(),start=ProcessInfo.processInfo.systemUptime
let words=WordVocabulary.words,lexicon=GestureLexicon(words:words)
let startup=millis(start),afterMemory=peakBytes()
let common="anchor banana candle carpet coffee copper garden planet purple rabbit rocket silver summer tomato travel turtle velvet water whale zipper learn learning learned learns walk walked walking walks talk talked talking talks played player playing plays study studied studies studying write writing written writer happy happier happiest slowly quick quickly keyboard computer message sentence address number window mouse finger trackpad cursor wrong correct work worked working works book books booking cook cooking cooked letter letters repeated repeat meeting meetings swimming running dropped stopping hello goodbye tomorrow yesterday beautiful family friend friends phone light night bright think ring hung rink drink bring bank help thanks please".components(separatedBy:" ")
// Frozen systematic lexical validation sample. Not used for index/weight/cutoff development.
let sampled="abloom accentuating acquired adjuster aerial agnostics alined amazed analogs annually anyway apprehensiveness aria ascribing asteroid audible avoirdupois backstop bandier barreled beachheads befoul benevolent bickered birthers bleacher blowguns boisterous bordering brains bridegroom brownies bulletin bursar caches cambering canyons carjackings casualness caverns chaffinch charting chicken chopping circumflex clayier closures cockscomb collectables commemorated competitiveness concertinaed confirmation consecration contemplative conversing cormorants costumes covered crayons critique crushing curlew dactylics davenports decathlons deepest deigns demoralize depredations desperate devolving dig dirties discord disinfect disquiet dither doilies dowager drenched ductile dyspepsia edicts electives embedded enact engaged enthusing equators estimations exacting exhaustion exploitation extremists fallacies fatigues ferments filched firs flashlights floodlit foams foreboding fornicating fraternizes frizzier fungicidal gallbladder gasolene genome gigolo gloaming goldenest gramophone gregariously growls gunwales half hansoms hats heated heralded hijacked holdovers hookey houseboats humus hyphenate ilk impartially impracticality incidentally indelible inert ingenuous inquisition insufferably interlock intransitive ionosphere jackknife jigsawed jug keyboard km laddies larger lazily legitimating librarians linebackers livings longer lubricate macho makings mannered martin matzohs meetings merinos microsecond minaret miscellanies misstates molars moodier motliest muleteer mutants nationalize neonatal nighthawks nonhazardous nourishment obfuscates octane only orderings outcropping ovaries overpower oxbows palmy paralyze particulates patties peeper percolated persists phasing pickerel pinioned plainer plights poked poodle posterity pray prejudge preteens privatizing programing proposer prowlers pummelled pussyfooting queasiest racketeered randomized rawboned rebellions recompile redistributed refocussing reheat reluctantly reorged republican respectful retook revises riffles rob rotting rumbling sags sandpapering savvy schizoids scrapes seabeds seemly sentimentalize sexes shearing shivering shrewish sieves sinker skivvying sleighs slums snap snuffs solstices souses specifying spitball sprawling squirmed stargazer stepbrothers stockpiled strangulation stubbiest sublimer sucking sundries surceased swashbucklers syllabuses tad tarmac tech tender thalamus thoroughbred ticking tireder tonsuring tout transducer travesty trinity trunk turtledoves udders uncharted underlines unfair unites unread untidier uptake validly veneers vicing visors vulgarize warblers wattle weirdest whinnying wildcats wisher woolly wrings yoghurts".components(separatedBy:" ")
func samples(_ word:String,_ seed:Int,_ variant:Int)->[StrokeSample] {
 let points=StrokeDecoder.resample(Keyboard.path(word),count:[48,96,144][variant]).enumerated().map {i,p in
  let noise=[0.0,0.015,0.035][variant]
  return Point(p.x+noise*sin(Double(i*7+seed)),p.y+noise*cos(Double(i*11+seed)))
 }
 return points.enumerated().map {i,p in StrokeSample(p,time:pow(Double(i)/Double(max(1,points.count-1)),[1.0,0.7,1.6][variant])*1.5,source:.trackpad)}
}
var tradeoffs:[String:[String:Int]]=[:]
var groups:[String:Any]=[:],latencies:[Double]=[],failures:[String:Int]=[:]
for (label,corpus) in [("commonAndMorphology",common),("systematicLexicalValidation",sampled)] {
 var trials=0,top1=0,top5=0,noMatch=0,covered=0
 for (index,word) in corpus.enumerated() {
  if words.contains(word) {covered += 1}
  for variant in 0..<3 {
   let raw=samples(word,index,variant),original=raw
   let started=ProcessInfo.processInfo.systemUptime
   let ranking=lexicon.rank(raw);latencies.append(millis(started))
   let candidates=StrokeDecoder.accepts(ranking) ? ranking.map(\.word):[]
   for cutoff in [0.04,0.06,0.08] {
    let name=String(cutoff),accepted=(ranking.first?.score ?? 1)<cutoff
    tradeoffs[name,default:[:]]["trials",default:0] += 1
    if !accepted {tradeoffs[name,default:[:]]["rejected",default:0] += 1}
    else if ranking.first?.word==word {tradeoffs[name,default:[:]]["correctTop1",default:0] += 1}
    else {tradeoffs[name,default:[:]]["wrongTop1",default:0] += 1}
   }
   precondition(raw==original,"recognizer mutated raw samples")
   trials += 1;if candidates.first==word {top1 += 1};if candidates.contains(word) {top5 += 1};if candidates.isEmpty {noMatch += 1}
   if candidates.first != word {failures[word+" -> "+(candidates.first ?? "NO_MATCH"),default:0] += 1}
  }
 }
 groups[label]=["words":corpus.count,"covered":covered,"trials":trials,"top1":top1,"top5":top5,"noMatch":noMatch]
}
let invented=["blorf","quazzle","snorple","flibber","drong","frink","glorp","wugging","plim","trazz","zunk","sproing","klong","brindlezz","morp","flonk","gribble","smurg","splonk","vazzle"]
var oovAccepted=0,oovCoverage=0
for (i,w) in invented.enumerated() {
 if words.contains(w) {oovCoverage += 1}
 let ranking=lexicon.rank(samples(w,i,0))
 if (ranking.first?.score ?? 1)<StrokeDecoder.maximumAcceptedScore {oovAccepted += 1}
 for cutoff in [0.04,0.06,0.08] {if (ranking.first?.score ?? 1)<cutoff {tradeoffs[String(cutoff),default:[:]]["inventedFalseAcceptsOf20",default:0] += 1}}
}
var unrelatedAccepted=0
for i in 0..<20 {
 let raw=(0..<80).map {j in StrokeSample(Point(0.5+0.45*sin(Double(j)*0.45+Double(i)),0.5+0.45*cos(Double(j)*0.71+Double(i))),time:Double(j)*0.01,source:.trackpad)}
 if !lexicon.candidates(raw).isEmpty {unrelatedAccepted += 1}
}
// Compare pruning with full-scoring oracle for six unseen words; no UI or mutation.
var oracleAgreement=0
let oracleWords=["banana","garden","computer","swimming","written","beautiful"] + Array(sampled.prefix(20))
for w in oracleWords {
 let raw=samples(w,0,1)
 if lexicon.rank(raw).first?.word == StrokeDecoder.rank(raw,words:words).first?.word {oracleAgreement += 1}
}
latencies.sort()
precondition(lexicon.count>60_000,"broad vocabulary unexpectedly missing")
for word in ["ring","hung","rink","think"] {for variant in 0..<3 {precondition(lexicon.rank(samples(word,0,variant)).first?.word==word,"synthetic complaint ranking regression; acceptance may refuse an ambiguity")}}
precondition((groups["systematicLexicalValidation"] as? [String:Int])?["top5"] ?? 0 >= 700,"synthetic lexical candidates regressed")
let data:[String:Any]=["lexiconWords":lexicon.count,"indexBuildMilliseconds":startup,"peakRSSBytes":peakBytes(),"indexPeakRSSDeltaBytes":afterMemory-beforeMemory,"rankingCallMilliseconds":["p50":latencies[latencies.count/2],"p95":latencies[Int(Double(latencies.count)*0.95)],"maximum":latencies.last!],"groups":groups,"scoreOnlyCutoffTradeoffs":tradeoffs,"failures":failures,"inventedOOV":["trials":20,"actuallyInVocabulary":oovCoverage,"accepted":oovAccepted],"unrelatedAcceptedOf20":unrelatedAccepted,"pruningOracle":["trials":oracleWords.count,"top1Agreement":oracleAgreement],"limits":"Synthetic lexical validation with overlapping words and shared development generator; not independent gesture distributions or physical user gestures, calibrated confidence or corpus-weighted general English accuracy. RSS is process high-water mark. No frequency prior. Single letters separate tap path. Does not cover punctuation/apostrophes/non-ASCII/proper names." ]
print(String(data:try! JSONSerialization.data(withJSONObject:data,options:[.sortedKeys,.prettyPrinted]),encoding:.utf8)!)
