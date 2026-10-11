import Foundation
import SwipepadCore
// Frozen original vocabulary for reproducible before/after comparison.
let baseline="a about after again all also am an and any app are as at back be because been before build but by can cat code come day did do does dog done down each email end even for from get give go good got great had has have he hello help her here him his home how i if in into is it its just know last let like little look love made make many may me more most much my need new next no not now of off on one only or other our out over people please right said same see she should so some start still stop such take test than thank that the their them then there these they thing think this time to today too tonight two type typing up us use very want was way we well were what when where which who will with word work world would write yes you your".components(separatedBy:" ")
let expanded=legacySupplementalVocabulary
let evaluation="ring hung rink think bring brink drink sink sing king wing string spring swing thin thick thank hang bang bank sank hand hind hint hunt rung rain rang rank range run runner hunger hungry lung long link ink pink ping pick kick sick silk kind find fine line lime mine mind wind winter finger figure bigger frog food mood moon noon soon spoon book hook cook pool cool school tool fool full pull bull bill fill hill kill mill pill till well fell tell bell sell cell yellow mellow fellow pillow hollow follow red read reed ride ridge rich rice rise risk disk dusk dust rust must mist lost list lift left right light night sight tight might fight flight high sigh".components(separatedBy:" ")
var results:[String:Any]=[:]
for (label,vocabulary) in [("before",baseline),("after",expanded)] {
 let cutoff=label == "before" ? 0.24:0.08
 var maximumCorrectScore=0.0
 var total=0,top1=0,top5=0,rejected=0,confusions:[String:Int]=[:],reports:[String:Any]=[:]
 for (index,word) in evaluation.enumerated() {
  for variant in 0..<6 {
   let density=[32,64,96,128,64,96][variant]
   let path=StrokeDecoder.resample(Keyboard.path(word),count:density).enumerated().map { i,p -> Point in
    let noise=variant == 0 ? 0.0:(variant>=4 ? 0.03:0.012)
    return Point(p.x+noise*sin(Double(i*7+index)),p.y+noise*cos(Double(i*11+index)))
   }
   let samples=path.enumerated().map {i,p in StrokeSample(p,time:Double(i)*[0.004,0.01,0.02,0.05,0.008,0.03][variant],source:.trackpad)}
   let ranking=StrokeDecoder.rank(samples,words:vocabulary)
   let candidates=(ranking.first?.score ?? 1)<cutoff ? ranking.map(\.word):[]
   if ranking.first?.word==word {maximumCorrectScore=max(maximumCorrectScore,ranking[0].score)}
   total += 1;if candidates.first==word {top1 += 1};if candidates.contains(word) {top5 += 1};if candidates.isEmpty {rejected += 1}
   if candidates.first != word {confusions[word+" -> "+(candidates.first ?? "NO_MATCH"),default:0] += 1}
   if index<4 {reports[word+"/"+String(variant)]=candidates}
  }
 }
 results[label]=["trials":total,"top1":top1,"top5":top5,"noMatch":rejected,"confusions":confusions,"reportedWords":reports,"vocabulary":vocabulary.count,"maximumCorrectScore":maximumCorrectScore]
}
// Unrelated full-pad trajectories must be measured, not called words.
var falseAccepts:[String:Int]=[:]
for (label,vocabulary) in [("before",baseline),("after",expanded)] {
 var accepted=0
 for i in 0..<20 {
  let points=(0..<80).map {j in Point(0.5+0.45*sin(Double(j)*0.45+Double(i)),0.5+0.45*cos(Double(j)*0.71+Double(i)))}
  let samples=points.enumerated().map {StrokeSample($0.element,time:Double($0.offset)*0.01,source:.trackpad)}
  if !Recognition.candidates(samples,words:vocabulary).isEmpty {accepted += 1}
 }
 falseAccepts[label]=accepted
}
results["unrelatedSyntheticAcceptedOf20"]=falseAccepts
let unsupported="anchor banana candle carpet coffee copper garden planet purple rabbit rocket silver summer tomato travel turtle velvet water whale zipper".components(separatedBy:" ")
var unsupportedResults:[String:Any]=[:]
for (label,vocabulary) in [("before",baseline),("after",expanded)] {
 let cutoff=label == "before" ? 0.24:0.08
 var accepted=0,confusions:[String:String]=[:],scores:[String:Double]=[:]
 for word in unsupported {
  let samples=Keyboard.path(word).enumerated().map {StrokeSample($0.element,time:Double($0.offset)*0.01,source:.trackpad)}
  let ranked=StrokeDecoder.rank(samples,words:vocabulary)
  scores[word]=ranked.first?.score
  if let top=ranked.first,top.score<cutoff {accepted += 1;confusions[word]=top.word}
 }
 unsupportedResults[label]=["acceptedWrongOf20":accepted,"confusions":confusions,"scores":scores]
}
results["unsupportedWords"]=unsupportedResults
// Separate validation words not used to choose the cutoff or expand the complaint-neighbor set.
let heldOut="about after again because before build code come email even hello help home little love make next only people please should start still today tonight type typing want world write yellow cooking walking talking thinking rings strings drinks wings linked".components(separatedBy:" ")
var heldTotal=0,heldTop1=0,heldTop5=0,heldRejected=0
for (index,word) in heldOut.enumerated() {
 for variant in 0..<3 {
  let points=StrokeDecoder.resample(Keyboard.path(word),count:[40,80,120][variant]).enumerated().map {i,p in Point(p.x+0.02*sin(Double(i*3+index)),p.y+0.02*cos(Double(i*5+index)))}
  let samples=points.enumerated().map {StrokeSample($0.element,time:Double($0.offset)*[0.004,0.02,0.04][variant],source:.trackpad)}
  let ranked=StrokeDecoder.rank(samples,words:expanded)
  let candidates=(ranked.first?.score ?? 1)<0.08 ? ranked.map(\.word):[]
  heldTotal += 1;if candidates.first==word {heldTop1 += 1};if candidates.contains(word) {heldTop5 += 1};if candidates.isEmpty {heldRejected += 1}
 }
}
results["heldOutAfter"]=["words":heldOut.count,"trials":heldTotal,"top1":heldTop1,"top5":heldTop5,"noMatch":heldRejected]


results["limits"]="Generated center paths, deterministic jitter and sampling-density/speed variants only. No real user traces; no accuracy guarantee. Four complaint words plus 118 broader evaluation words; weights were not tuned to this corpus. Adjacent repeated letters can be geometrically ambiguous."
if let after=results["after"] as? [String:Any] {
 precondition(after["top5"] as? Int == after["trials"] as? Int,"broader synthetic corpus lost intended candidate")
 if let cases=after["reportedWords"] as? [String:[String]] {precondition(cases.allSatisfy {$0.value.first == $0.key.components(separatedBy:"/")[0]},"reported-word regression")}
}
let data=try! JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]);print(String(data:data,encoding:.utf8)!)
