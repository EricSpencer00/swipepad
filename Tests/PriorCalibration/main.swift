import Foundation
import Darwin
import SwipepadCore
func millis(_ start:Double)->Double {(ProcessInfo.processInfo.systemUptime-start)*1000}
func peakBytes()->Int64 {var value=rusage();getrusage(RUSAGE_SELF,&value);return Int64(value.ru_maxrss)}
let beforeMemory=peakBytes(),start=ProcessInfo.processInfo.systemUptime
let words=WordVocabulary.words,lexicon=GestureLexicon(words:words,usePrior:false)
let startup=millis(start),afterMemory=peakBytes()
let common="anchor banana candle carpet coffee copper garden planet purple rabbit rocket silver summer tomato travel turtle velvet water whale zipper learn learning learned learns walk walked walking walks talk talked talking talks played player playing plays study studied studies studying write writing written writer happy happier happiest slowly quick quickly keyboard computer message sentence address number window mouse finger trackpad cursor wrong correct work worked working works book books booking cook cooking cooked letter letters repeated repeat meeting meetings swimming running dropped stopping hello goodbye tomorrow yesterday beautiful family friend friends phone light night bright think ring hung rink drink bring bank help thanks please".components(separatedBy:" ")
// Frozen systematic lexical validation sample. Not used for index/weight/cutoff development.
let previousDevelopment="abloom accentuating acquired adjuster aerial agnostics alined amazed analogs annually anyway apprehensiveness aria ascribing asteroid audible avoirdupois backstop bandier barreled beachheads befoul benevolent bickered birthers bleacher blowguns boisterous bordering brains bridegroom brownies bulletin bursar caches cambering canyons carjackings casualness caverns chaffinch charting chicken chopping circumflex clayier closures cockscomb collectables commemorated competitiveness concertinaed confirmation consecration contemplative conversing cormorants costumes covered crayons critique crushing curlew dactylics davenports decathlons deepest deigns demoralize depredations desperate devolving dig dirties discord disinfect disquiet dither doilies dowager drenched ductile dyspepsia edicts electives embedded enact engaged enthusing equators estimations exacting exhaustion exploitation extremists fallacies fatigues ferments filched firs flashlights floodlit foams foreboding fornicating fraternizes frizzier fungicidal gallbladder gasolene genome gigolo gloaming goldenest gramophone gregariously growls gunwales half hansoms hats heated heralded hijacked holdovers hookey houseboats humus hyphenate ilk impartially impracticality incidentally indelible inert ingenuous inquisition insufferably interlock intransitive ionosphere jackknife jigsawed jug keyboard km laddies larger lazily legitimating librarians linebackers livings longer lubricate macho makings mannered martin matzohs meetings merinos microsecond minaret miscellanies misstates molars moodier motliest muleteer mutants nationalize neonatal nighthawks nonhazardous nourishment obfuscates octane only orderings outcropping ovaries overpower oxbows palmy paralyze particulates patties peeper percolated persists phasing pickerel pinioned plainer plights poked poodle posterity pray prejudge preteens privatizing programing proposer prowlers pummelled pussyfooting queasiest racketeered randomized rawboned rebellions recompile redistributed refocussing reheat reluctantly reorged republican respectful retook revises riffles rob rotting rumbling sags sandpapering savvy schizoids scrapes seabeds seemly sentimentalize sexes shearing shivering shrewish sieves sinker skivvying sleighs slums snap snuffs solstices souses specifying spitball sprawling squirmed stargazer stepbrothers stockpiled strangulation stubbiest sublimer sucking sundries surceased swashbucklers syllabuses tad tarmac tech tender thalamus thoroughbred ticking tireder tonsuring tout transducer travesty trinity trunk turtledoves udders uncharted underlines unfair unites unread untidier uptake validly veneers vicing visors vulgarize warblers wattle weirdest whinnying wildcats wisher woolly wrings yoghurts".components(separatedBy:" ")
func samples(_ word:String,_ seed:Int,_ variant:Int)->[StrokeSample] {
 let points=StrokeDecoder.resample(Keyboard.path(word),count:[48,96,144][variant]).enumerated().map {i,p in
  let noise=[0.0,0.015,0.035][variant]
  return Point(p.x+noise*sin(Double(i*7+seed)),p.y+noise*cos(Double(i*11+seed)))
 }
 return points.enumerated().map {i,p in StrokeSample(p,time:pow(Double(i)/Double(max(1,points.count-1)),[1.0,0.7,1.6][variant])*1.5,source:.trackpad)}
}

let development=common + previousDevelopment + disjointWords
let unknown="blorf quazzle snorple flibber drong frink glorp wugging plim trazz zunk sproing klong brindlezz morp flonk gribble smurg splonk vazzle glimvex snarfle zorbax quindle flompy smol yeet brung skrunk froople chomly nargle wibble quarm ploon drimble twazz foobar bazqux zerm".components(separatedBy:" ")
var policies:[String:[String:Int]]=[:]
for (label,corpus) in [("valid",development),("unknown",unknown)] {
 for (index,word) in corpus.enumerated() {for variant in 0..<3 {
  let geometric=lexicon.rank(samples(word,index,variant),limit:32)
  for weight in [0.0,0.001,0.002,0.003] {
   let ranked=CommonnessPrior.rerank(geometric,weight:weight)
   for cutoff in [0.04,0.06,0.08] {for margin in [0.0,0.001,0.003] {
    let key=String(weight)+"/"+String(cutoff)+"/"+String(margin)
    let accepted=(ranked.first?.geometryScore ?? 1)<cutoff && (ranked.count<2 || ranked[1].score-ranked[0].score>=margin)
    if label=="unknown" {if accepted {policies[key,default:[:]]["unknownAccepts",default:0] += 1}}
    else {let metric=accepted ? (ranked.first?.word==word ? "correct":"wrong"):"rejected";policies[key,default:[:]][metric,default:0] += 1}
   }}
  }
 }}
}
let output:[String:Any]=["developmentOnly":true,"validTrials":development.count*3,"unknownTrials":unknown.count*3,"policies":policies,"priorCap":0.006,"geometryCandidates":32]
print(String(data:try! JSONSerialization.data(withJSONObject:output,options:[.sortedKeys,.prettyPrinted]),encoding:.utf8)!)
