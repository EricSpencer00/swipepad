import Foundation
import SwipepadCore

var count = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ name: String) {
  guard condition() else { fatalError("FAIL: \(name)") }
  count += 1
}
check(Keyboard.keys.count == 26, "26 QWERTY keys")
check(Keyboard.keys["q"]!.y > Keyboard.keys["z"]!.y, "bottom-left coordinate orientation")
check(Keyboard.keys["q"]!.x < Keyboard.keys["p"]!.x, "left/right geometry")
check(
  Keyboard.keys.values.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) },
  "bounded normalized keys")
for word in ["hello", "world", "test", "cat", "typing"] {
  check(
    Decoder.candidates(Keyboard.path(word), words: ["hello", "world", "test", "cat", "typing"])
      .first == word, "synthetic exact path \(word)")
}
check(Decoder.candidates([], words: ["hello"]).isEmpty, "empty gesture")
check(
  Decoder.candidates([Point(.nan, 0), Point(0, 0)], words: ["hello"]).isEmpty, "nonfinite input")
check(Decoder.candidates([Point(-1, 0), Point(0, 0)], words: ["hello"]).isEmpty, "out of bounds")
check(Decoder.distance([], Keyboard.path("hello")).isInfinite, "empty DTW")
var h = CommandTap()
check(!h.update(isDown: true, onlyCommand: true, time: 0), "first down")
check(!h.update(isDown: true, onlyCommand: true, time: 0.01), "repeated down")
check(!h.update(isDown: false, onlyCommand: true, time: 0.05), "first release")
check(!h.update(isDown: true, onlyCommand: true, time: 0.15), "second down")
check(h.update(isDown: false, onlyCommand: true, time: 0.2), "double Command fires")
check(!h.update(isDown: false, onlyCommand: true, time: 0.21), "repeated release")
h = CommandTap()
_ = h.update(isDown: true, onlyCommand: true, time: 0)
h.cancel()
check(!h.update(isDown: false, onlyCommand: true, time: 0.1), "shortcut invalidates tap")
h = CommandTap()
_ = h.update(isDown: true, onlyCommand: true, time: 0)
check(!h.update(isDown: false, onlyCommand: true, time: 1), "held modifier")
h = CommandTap()
_ = h.update(isDown: true, onlyCommand: true, time: 0)
_ = h.update(isDown: false, onlyCommand: true, time: 0.05)
_ = h.update(isDown: true, onlyCommand: false, time: 0.1)
check(!h.update(isDown: false, onlyCommand: true, time: 0.2), "additional modifier cancels")
h = CommandTap()
h.debounce = 1
for (down, t) in [(true, 0.0), (false, 0.05), (true, 0.1), (false, 0.15)] {
  _ = h.update(isDown: down, onlyCommand: true, time: t)
}
_ = h.update(isDown: true, onlyCommand: true, time: 0.2)
_ = h.update(isDown: false, onlyCommand: true, time: 0.25)
_ = h.update(isDown: true, onlyCommand: true, time: 0.3)
check(
  !h.update(isDown: false, onlyCommand: true, time: 0.35),
  "debounce prevents rapid second activation")
check(
  FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: true, secure: false, editable: true),
  "same safe field")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 2, sameElement: true, secure: false, editable: true), "changed app")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: false, secure: false, editable: true),
  "changed field")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: true, secure: true, editable: true), "secure field")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: true, secure: false, editable: false),
  "unsettable field")
// Regression: observed Brave AXTextArea, subrole attributeUnsupported, selectedText writable.
check(
  FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, insertionSettable: true, secureInput: false),
  "ordinary browser/TextEdit textarea without optional subrole")
check(
  FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("AXUnknown"), insertionSettable: true, secureInput: false
  ), "native text area with explicit ordinary subrole")
check(
  FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXUnknown"), insertionSettable: true,
    secureInput: false), "ordinary single-line text field")
check(
  FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXSearchField"), insertionSettable: true,
    secureInput: false), "ordinary search field")
check(
  !FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXSecureTextField"), insertionSettable: true,
    secureInput: false), "password subrole")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("AXSecureTextField"), insertionSettable: true,
    secureInput: false), "secure metadata cannot bypass via text area role")
check(
  FieldPolicy.permits(
    role: "AXTextField", subrole: .absent, insertionSettable: true, secureInput: false),
  "ordinary single-line optional subrole absent")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .unreadable, insertionSettable: true, secureInput: false),
  "AX metadata errors fail closed")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, insertionSettable: false, secureInput: false),
  "read-only text area")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, insertionSettable: true, secureInput: true),
  "Secure Input still blocks ordinary textarea")
check(
  !FieldPolicy.permits(
    role: "AXButton", subrole: .absent, insertionSettable: true, secureInput: false),
  "unrelated control")
check(
  !FieldPolicy.permits(role: nil, subrole: .absent, insertionSettable: true, secureInput: false),
  "missing role")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("UnrecognizedSubrole"), insertionSettable: true,
    secureInput: false), "unknown subrole fail closed")
var mock = DoctorInput()
mock.bundled = true
mock.identityMatches = true
mock.signatureValid = true
mock.accessibility = true
mock.frameworkPresent = true
mock.deviceAvailable = true
mock.live = true
mock.monitorInstalled = true
mock.fieldFound = true
mock.fieldSupported = true
mock.fieldRole = "AXTextArea"
mock.fieldSubrole = .absent
mock.targetedInsertionSettable = true
check(
  Doctor.evaluate(mock).state == "Ready to test",
  "doctor ready preflight does not imply physical e2e")
check(
  Doctor.evaluate(mock).checks.first(where: { $0.id == "insertion" })?.status == .waiting,
  "doctor never infers insertion from writable metadata")
check(
  Doctor.evaluate(mock).checks.first(where: { $0.id == "keyboard" })?.status == .waiting,
  "doctor waits for keyboard observation")
check(
  Doctor.evaluate(mock).checks.allSatisfy { !$0.repair.isEmpty },
  "each doctor stage supplies an explicit repair or manual step")
var failed = mock
failed.accessibility = false
check(Doctor.evaluate(failed).state == "Setup needed", "doctor missing permission setup state")
check(
  Doctor.evaluate(failed).checks.first(where: { $0.id == "accessibility" })?.status == .fail,
  "doctor denied AX permission")
failed = mock
failed.ownedInstances = 2
check(Doctor.evaluate(failed).state == "Setup needed", "doctor duplicate owned processes")
failed = mock
failed.bundled = false
check(
  Doctor.evaluate(failed).checks.first(where: { $0.id == "bundle" })?.status == .fail,
  "doctor bare executable")
failed = mock
failed.signatureValid = false
check(
  Doctor.evaluate(failed).checks.first(where: { $0.id == "signing" })?.status == .fail,
  "doctor invalid signature")
failed = mock
failed.frameworkPresent = false
check(
  Doctor.evaluate(failed).checks.first(where: { $0.id == "trackpad" })?.status == .fail,
  "doctor private framework missing")
failed = mock
failed.deviceAvailable = false
check(Doctor.evaluate(failed).state == "Setup needed", "doctor no default touch device")
failed = mock
failed.secureInput = true
check(
  Doctor.evaluate(failed).checks.first(where: { $0.id == "secure-input" })?.status == .fail,
  "doctor Secure Input blocks")
failed = mock
failed.fieldSupported = false
check(
  Doctor.evaluate(failed).checks.first(where: { $0.id == "field" })?.status == .fail,
  "doctor unsupported field repair")
failed = mock
failed.live = true
failed.monitorInstalled = false
check(Doctor.evaluate(failed).state == "Setup needed", "doctor unavailable live monitor")
mock.live = true
mock.monitorInstalled = true
mock.globalEventSeen = true
mock.hotkeySeen = true
mock.touchSeen = true
mock.liftSeen = true
mock.focusPreserved = true
mock.insertionSucceeded = true
for id in ["keyboard", "hotkey", "touch-lift", "focus", "insertion"] {
  check(
    Doctor.evaluate(mock).checks.first(where: { $0.id == id })?.status == .pass,
    "doctor mocked observation \(id)")
}
mock.focusPreserved = false
mock.insertionSucceeded = false
check(
  Doctor.evaluate(mock).checks.first(where: { $0.id == "focus" })?.status == .fail,
  "doctor wrong focus is not success")
check(
  Doctor.evaluate(mock).checks.first(where: { $0.id == "insertion" })?.status == .fail,
  "doctor AX insertion rejection")
let machine = try JSONEncoder().encode(Doctor.evaluate(mock))
let decoded = try JSONDecoder().decode(DoctorReport.self, from: machine)
check(
  decoded.schemaVersion == 1 && decoded.checks.count == 12,
  "doctor machine-readable schema roundtrip")
var callerTrusted = DoctorInput()
callerTrusted.accessibility = true
check(
  Doctor.evaluate(callerTrusted).checks.first(where: { $0.id == "accessibility" })?.status
    == .warning, "doctor caller trust cannot stand in for GUI permission")
check(
  !RelaunchPolicy.isDistinctLaunch(helperPID: 100, resultPID: 100),
  "relaunch refuses CLI self-acknowledgement")
check(
  !RelaunchPolicy.isDistinctLaunch(helperPID: 100, resultPID: nil),
  "relaunch requires actual process acknowledgement")
check(
  RelaunchPolicy.isDistinctLaunch(helperPID: 100, resultPID: 200),
  "relaunch accepts distinct GUI process")
var preflight = mock
preflight.live = false
check(
  Doctor.evaluate(preflight).state.hasPrefix("Preflight only"),
  "doctor absent live snapshot never presents GUI ready state")

// Original full-path overlay matcher: synthetic regression evidence only.
func sampled(_ points:[Point], step:Double=0.01) -> [StrokeSample] {
  points.enumerated().map {StrokeSample($0.element,time:Double($0.offset)*step)}
}
let fixtureWords=["cat","cot","tap","pat","there","test","god","good","hello","world","typing"]
for word in ["cat","cot","tap","pat","there","test","hello","world","typing"] {
  check(StrokeDecoder.rank(sampled(Keyboard.path(word)),words:fixtureWords).first?.word==word,"overlay exact proportional path \(word)")
}
let rect=CalibrationRect(x:-1200,y:180,width:960,height:360)
check(rect.normalize(rect.screenPoint(Point(0.2,0.8)))!.distance(Point(0.2,0.8))<0.000001,"negative-origin secondary-display point transform")
check(rect.normalize(Point(-1300,180))!.x<0,"unclamped outside geometry")
check(CalibrationRect(x:0,y:0,width:0,height:1).normalize(Point(0,0))==nil,"zero calibration rejected")
check(CalibrationRect(x:0,y:.nan,width:1,height:1).normalize(Point(0,0))==nil,"nonfinite calibration rejected")
let original=Keyboard.path("cat")
for scale in [0.5,1.0,2.0] {
  let scaled=CalibrationRect(x:-300,y:50,width:800*scale,height:300*scale)
  let normalized=original.map {scaled.normalize(scaled.screenPoint($0))!}
  check(StrokeDecoder.rank(sampled(normalized),words:fixtureWords).first?.word=="cat","screen-point scale and Retina-independent ranking \(scale)")
}
for sampleCount in [10,20,40] {
  let points=StrokeDecoder.resample(Keyboard.path("there"),count:sampleCount)
  check(StrokeDecoder.rank(sampled(points),words:fixtureWords).first?.word=="there","arc-length density invariant revisit \(sampleCount)")
}
let endpoints=StrokeDecoder.resample(original)
let savedLayout=[0.15,0.30,0.70,0.266]
for visible in [CalibrationRect(x:0,y:0,width:1200,height:800),CalibrationRect(x:-800,y:100,width:800,height:1200),CalibrationRect(x:0,y:0,width:1900,height:600)] {
  let restored=CalibrationRect.restoreOverlay(savedLayout,in:visible)!
  check(abs(restored.height/restored.width-0.38)<0.000001,"saved overlay aspect survives nonuniform display change")
  check(restored.x>=visible.x && restored.y>=visible.y && restored.x+restored.width<=visible.x+visible.width+0.000001 && restored.y+restored.height<=visible.y+visible.height+0.000001,"restored overlay fits changed display bounds")
}
check(CalibrationRect.restoreOverlay([0,0,2,1],in:rect)==nil,"invalid saved overlay rejected")
check(endpoints.first==original.first && endpoints.last==original.last,"explicit endpoints preserved")
check(StrokeDecoder.rank(sampled(original,step:0.02),words:fixtureWords).first?.word==StrokeDecoder.rank(sampled(original,step:0.005),words:fixtureWords).first?.word,"speed invariant shape matching")
let noisy=original.enumerated().map {Point($0.element.x+0.004*sin(Double($0.offset)), $0.element.y+0.004*cos(Double($0.offset)))}
check(StrokeDecoder.rank(sampled(noisy),words:fixtureWords).first?.word=="cat","deterministic jitter retains mid-path cat")
var shifted=original; shifted[0].x += 0.025;shifted[shifted.count-1].y += 0.025
check(StrokeDecoder.rank(sampled(shifted),words:fixtureWords).first?.word=="cat","broad endpoints accept quarter-key-width shifts")
let ambiguous=StrokeDecoder.rank(sampled(Keyboard.path("god")),words:["god","good"])
check(ambiguous.count==2 && abs(ambiguous[0].score-ambiguous[1].score)<0.000001,"god/good ordinary path has equal geometry")
var dwell=sampled(Keyboard.path("god"))
if let index=dwell.firstIndex(where: {$0.point.distance(Keyboard.keys["o"]!)<0.005}) {
  let point=dwell[index].point,time=dwell[index].time
  dwell.insert(StrokeSample(point,time:time),at:index)
  dwell=dwell.enumerated().map {StrokeSample($0.element.point,time:Double($0.offset)*0.01+($0.offset>index ? 0.2 : 0))}
}
let paused=StrokeDecoder.rank(dwell,words:["god","good"])
check(paused.count==2 && abs(paused[0].score-paused[1].score)<0.000001,"pause alone does not force repeated O")
var looped=Keyboard.path("god")
if let index=looped.firstIndex(where:{$0.distance(Keyboard.keys["o"]!)<0.005}) {
  let center=Keyboard.keys["o"]!
  let loop=(0...16).map { i in Point(center.x+0.03*cos(Double(i)*2*Double.pi/16),center.y+0.03*sin(Double(i)*2*Double.pi/16)) }
  looped.insert(contentsOf:loop,at:index)
}
let loopRanking=StrokeDecoder.rank(sampled(looped),words:["god","good"])
check(loopRanking.first?.word=="good","localized loop softly supports repeated letter")
check(loopRanking.count==2,"loop retains ambiguous alternate")
check(StrokeDecoder.rank([],words:fixtureWords).isEmpty,"overlay empty path rejected")
check(StrokeDecoder.rank(sampled([Point(0.1,0.1),Point(.nan,0.2),Point(0.3,0.3)]),words:fixtureWords).isEmpty,"overlay NaN rejected")
check(StrokeDecoder.rank(sampled([Point(-0.1,0.1),Point(0.2,0.2),Point(0.3,0.3)]),words:fixtureWords).isEmpty,"overlay outside point rejected without clamp")
check(StrokeDecoder.rank(sampled(Array(repeating:Point(0.3,0.3),count:10)),words:fixtureWords).isEmpty,"zero-length overlay rejected")
var reversedTime=sampled(original);reversedTime[2]=StrokeSample(original[2],time:-1)
check(StrokeDecoder.rank(reversedTime,words:fixtureWords).isEmpty,"nonmonotonic raw times rejected")

var mixed=sampled(original)
mixed[1]=StrokeSample(mixed[1].point,time:mixed[1].time,source:.trackpad)
check(StrokeDecoder.rank(mixed,words:fixtureWords).isEmpty,"mixed pointer/touch samples rejected")
let native=StrokeSample(Point(0.5,0.5),time:4,phase:.ended,source:.screenOverlay,sourcePoint:Point(-900,430))
check(native.sourcePoint==Point(-900,430) && native.time==4 && native.phase == .ended,"raw screen coordinates time and phase preserved")
for word in ["cat","cot","tap","pat","there","test","hello","world","typing"] {
  check(StrokeDecoder.rank(sampled(Keyboard.path(word)),words:fixtureWords,matching:.bandedDTW).first?.word==word,"banded DTW comparator exact fixture \(word)")
}
var unrelated=Keyboard.path("god")
let center=Keyboard.keys["g"]!
unrelated.insert(contentsOf:(0...16).map {i in Point(center.x+0.03*cos(Double(i)*2*Double.pi/16),center.y+0.03*sin(Double(i)*2*Double.pi/16))},at:1)
let unrelatedRank=StrokeDecoder.rank(sampled(unrelated),words:["god","good"])
check(abs(unrelatedRank[0].score-unrelatedRank[1].score)<0.000001,"unrelated loop cannot imply repeated O")
let benchmarkPath=sampled(Keyboard.path("there"))
for (label,matching) in [("proportional",PathMatching.proportional),("banded DTW",.bandedDTW)] {
  let start=Date()
  for _ in 0..<30 {_=StrokeDecoder.rank(benchmarkPath,words:fixtureWords,matching:matching)}
  print("Synthetic 11-word decoder benchmark \(label): \(String(format:"%.3f",Date().timeIntervalSince(start)*1000/30)) ms per rank; not hardware accuracy or production latency.")
}
print("Passed \(count) synthetic core checks. No physical touches or text insertion tested.")
var diagnostic=CaptureDiagnostics();diagnostic.trial=1;diagnostic.states=["4":3];diagnostic.samples=8
let encodedCapture=try! JSONEncoder().encode(diagnostic)
check((try! JSONDecoder().decode(CaptureDiagnostics.self,from:encodedCapture)).samples==8,"structural per-trial capture counters roundtrip")
check(!String(data:encodedCapture,encoding:.utf8)!.contains("\"point\"") && !String(data:encodedCapture,encoding:.utf8)!.contains("\"sourcePoint\""),"capture report omits gesture coordinates")
print("Passed \(count) total checks including physical capture diagnostic policy.")

for (point,key) in [(Point(0,1),Character("q")),(Point(1,1),Character("p")),(Point(0,0),Character("z")),(Point(1,0),Character("m"))] {
  check(Keyboard.nearestKey(point)==key,"whole pad corner maps deterministically to \(key)")
}
for (key,point) in Keyboard.keys {check(Keyboard.nearestKey(point)==key,"canonical staggered center \(key)")}
check(Keyboard.nearestKey(Point(-0.01,0.5))==nil,"outside pad rejected without clamp")
let frozenRect=CalibrationRect(x:-900,y:30,width:1000,height:380)
for point in [Point(0,0),Point(1,1),Point(0.05,0.8),Point(0.1,0.5),Point(0.2,0.2)] {
  check(frozenRect.normalize(frozenRect.screenPoint(point))!.distance(point)<1e-12,"full pad forward/inverse geometry")
}
check(frozenRect.screenPoint(Point(0,0))==Point(-900,30) && frozenRect.screenPoint(Point(1,1))==Point(100,410),"independent axis scaling fills entire keyboard")
print("Passed \(count) total checks; physical orientation and callback delivery remain hardware tests.")

var gate=ContactGate()
gate.rearm();check(!gate.waitingForLift,"cold rearm needs no idle callback")
gate.observe(activeContacts:1);gate.rearm();check(gate.waitingForLift,"held contact must lift before rearm")
gate.observe(activeContacts:0);gate.rearm();check(!gate.waitingForLift,"completed lift rearms immediately")
gate.observe(activeContacts:2);gate.rearm();check(gate.waitingForLift,"multi-contact reset retains lift safety")
gate.observe(activeContacts:0);gate.observe(activeContacts:1);check(!gate.waitingForLift,"first contact after actual lift is accepted")
check(InsertionContinuation.permits(originalLocation:5,insertedUTF16Count:7,resultLocation:12,resultLength:0,sameTarget:true),"verified UTF16 replacement caret can rebase")
check(!InsertionContinuation.permits(originalLocation:5,insertedUTF16Count:7,resultLocation:13,resultLength:0,sameTarget:true),"external moved caret cannot rebase")
check(!InsertionContinuation.permits(originalLocation:5,insertedUTF16Count:7,resultLocation:12,resultLength:1,sameTarget:true),"nonempty resulting selection cannot rebase")
check(!InsertionContinuation.permits(originalLocation:5,insertedUTF16Count:7,resultLocation:12,resultLength:0,sameTarget:false),"changed app/field cannot rebase")
check(!InsertionContinuation.permits(originalLocation:Int.max,insertedUTF16Count:1,resultLocation:0,resultLength:0,sameTarget:true),"caret overflow rejected")
let sharedTrace=Keyboard.path("hello")
let guideSamples=sharedTrace.enumerated().map {StrokeSample($0.element,time:Double($0.offset),source:.trackpad)}
let overlaySamples=sharedTrace.enumerated().map {StrokeSample($0.element,time:Double($0.offset),source:.screenOverlay)}
check(Recognition.candidates(guideSamples,words:["hello","help","world"])==Recognition.candidates(overlaySamples,words:["hello","help","world"]),"guide presentation cannot change recognition")
print("Passed \(count) core checks including held-contact rearm and verified insertion continuation.")

let curveRaw=[Point(0,0),Point(0.3,0.8),Point(0.7,0.3),Point(1,1)]
let curves=RenderCurve.segments(curveRaw)
check(curves.first?.start==curveRaw.first && curves.last?.end==curveRaw.last,"render curve preserves endpoints")
for c in curves {for i in 0...10 {let p=c.point(at:Double(i)/10);check(p.x >= min(c.start.x,c.control.x,c.end.x)-1e-12 && p.x <= max(c.start.x,c.control.x,c.end.x)+1e-12 && p.y >= min(c.start.y,c.control.y,c.end.y)-1e-12 && p.y <= max(c.start.y,c.control.y,c.end.y)+1e-12,"bounded interpolation without overshoot")}}
let reversalRaw=[Point(0,0),Point(1,0),Point(0,0)]
check(RenderCurve.segments(reversalRaw).contains(where:{$0.end==Point(1,0)}),"render reversal reaches exact turning point")
let loopRaw=[Point(0.2,0.2),Point(0.8,0.2),Point(0.8,0.8),Point(0.2,0.8),Point(0.2,0.2)]
check(RenderCurve.segments(loopRaw).first?.start==RenderCurve.segments(loopRaw).last?.end,"render loop remains closed")
var ordering=FrameOrdering();ordering.reset(receivedAfter:10)
check(!ordering.accept(receivedAt:9,timestamp:20,frame:1,deviceID:1),"queued previous session frame rejected")
check(ordering.accept(receivedAt:11,timestamp:20,frame:2,deviceID:1),"fresh frame accepted")
check(!ordering.accept(receivedAt:12,timestamp:20,frame:2,deviceID:1),"duplicate frame rejected")
check(!ordering.accept(receivedAt:12,timestamp:19,frame:3,deviceID:1),"out of order timestamp rejected")
check(!ordering.accept(receivedAt:12,timestamp:21,frame:3,deviceID:2),"different device frame rejected")
print("Passed \(count) total core checks including bounded render curves and frame ordering.")

func letterPress(_ key:Character,duration:Double=0.35,offset:Point=Point(0,0))->[StrokeSample] {
 let c=Keyboard.keys[key]!,p=Point(c.x+offset.x,c.y+offset.y)
 return [StrokeSample(p,time:10,phase:.began,source:.trackpad),StrokeSample(p,time:10+duration,phase:.ended,source:.trackpad)]
}

for duration in [0.05,0.15,0.35,2.0] {
 check(Recognition.singleLetter(letterPress("a",duration:duration),freshContact:true)=="a","fresh A tap/hold has no time gate")
 check(Recognition.singleLetter(letterPress("i",duration:duration),freshContact:true)=="I","fresh I tap/hold capitalized without time gate")
}
check(Recognition.singleLetter(letterPress("a"),freshContact:false)==nil,"activation-held letter rejected")
check(Recognition.singleLetter(letterPress("a",offset:Point(0.04,0)),freshContact:true)=="a","A tap near key boundary accepted")
check(Recognition.singleLetter(letterPress("a",offset:Point(0.051,0)),freshContact:true)==nil,"tap across A/S boundary cannot guess a")
check(Recognition.singleLetter(letterPress("z"),freshContact:true)==nil,"non-AI tap rejected")
check(Recognition.singleLetter([],freshContact:true)==nil,"empty single letter rejected")
var jitter=letterPress("a");jitter[1]=StrokeSample(Point(0.12,0.52),time:10.35,phase:.ended,source:.trackpad)
check(Recognition.singleLetter(jitter,freshContact:true)=="a","same-key modest jitter accepted")
let moving=[StrokeSample(Point(0.08,0.46),time:1,source:.trackpad),StrokeSample(Point(0.12,0.54),time:2,source:.trackpad)]
check(Recognition.singleLetter(moving,freshContact:true)==nil,"meaningfully moving failed stroke cannot become a letter")
var backwards=letterPress("a");backwards.reverse()
check(Recognition.singleLetter(backwards,freshContact:true)==nil,"backward letter time rejected")
check([Recognition.singleLetter(letterPress("a",duration:0.05),freshContact:true),Recognition.singleLetter(letterPress("a",duration:0.05),freshContact:true)]==["a","a"],"repeated quick letters independently recognized")
var freshGate=ContactGate();check(!freshGate.observedLift,"cold activation has no invented lift")
freshGate.observe(activeContacts:1);check(!freshGate.observedLift,"already held contact does not invent lift")
freshGate.noteLift();check(freshGate.observedLift,"mixed terminal establishes fresh next contact")
freshGate.reset();check(!freshGate.observedLift,"reactivation clears known lift")
freshGate.observe(activeContacts:0);check(freshGate.observedLift,"real empty contact frame establishes freshness")
print("Passed \(count) core checks including untimed single-letter taps and freshness.")

check(Recognition.singleLetter(letterPress("i",duration:0.05,offset:Point(-0.04,0)),freshContact:true)=="I","quick I tap near key edge accepted")
check(Recognition.singleLetter(letterPress("i",offset:Point(-0.051,0)),freshContact:true)==nil,"I/U boundary crossing rejected")
let tooMuchMotion=(0..<10).map {i in StrokeSample(Point(i%2==0 ? 0.08:0.12,0.50),time:Double(i),source:.trackpad)}
check(Recognition.singleLetter(tooMuchMotion,freshContact:true)==nil,"moving same-key failed loop cannot become letter fallback")
print("Passed \(count) final core checks with A/I key edges and moving-loop rejection.")

check(TextReplacement.replacing("abc",location:1,length:1,with:"I ")=="aI c","value fallback replaces selected span")
check(TextReplacement.replacing("😀abc",location:2,length:0,with:"a ")=="😀a abc","value fallback uses UTF16 caret")
check(TextReplacement.replacing("😀abc",location:0,length:2,with:"I ")=="I abc","value fallback replaces full surrogate pair")
check(TextReplacement.replacing("😀abc",location:1,length:0,with:"x")==nil,"surrogate-interior caret rejected")
check(TextReplacement.replacing("abc",location:4,length:0,with:"x")==nil,"out-of-range value fallback rejected")
check(TextReplacement.replacing("abc",location:1,length:Int.max,with:"x")==nil,"overflowing selected span rejected")
for value in ["e\u{301}","👩‍💻","🇺🇸","\r\n"] {
  let split=value=="👩‍💻" || value=="🇺🇸" ? 2:1
  check(TextReplacement.replacing(value,location:split,length:0,with:"x")==nil,"replacement refuses interior of extended grapheme")
}
let planned:[(String,Int,Int,String)]=[
  ("Hello",5,0," world "),("Hello ",6,0,"world "),
  ("Hello there",5,0," world"),("Hello there",6,0,"world "),
  ("Hello.",5,0," world"),("Say ()",5,0,"world"),
  ("Say \"\"",5,0,"world"),("Say “”,",5,0,"world"),
  ("Say \"hello\"",11,0," world "),("¿",1,0,"world "),("¡",1,0,"world "),
  ("foo/",4,0," world "),("@",1,0," world "),("\u{fffc}",1,0," world "),
  ("Hello old friend",6,3,"world"),("Hello old friend",5,5," world "),
  ("Hello\nnext",5,0," world"),("Hello\u{00a0}",6,0,"world ")]
for (value,location,length,expected) in planned {
  check((try? WordInsertion.plan(value,location:location,length:length,word:"world").get())?.text==expected,"word plan uses existing boundaries and preserves exterior")
}
check(WordInsertion.plan("Hello",location:2,length:0,word:"world") == .failure(.partialWord),"word plan refuses completion/split guess inside word")
check(WordInsertion.plan("Hello",location:2,length:3,word:"world") == .failure(.partialWord),"word plan refuses selection edge inside word")
check(WordInsertion.plan("don't",location:3,length:0,word:"world") == .failure(.partialWord),"apostrophe joining a word is not an insertion boundary")
check(WordInsertion.plan("well-known",location:4,length:0,word:"world") == .failure(.partialWord),"hyphen joining a word is not an insertion boundary")
check(WordInsertion.plan("",location:0,length:0,word:"") == .failure(.invalidWord),"empty insertion word refused")
check(WordInsertion.plan("",location:0,length:0,word:"two words") == .failure(.invalidWord),"multiword token refused")
check(WordInsertion.plan("abc",location:Int.max,length:1,word:"world") == .failure(.invalidRange),"overflowing word-plan location refused")
check(try! WordInsertion.plan("50%",location:2,length:0,word:"world").get().text==" world","percent suffix uses closing-punctuation spacing policy")
let display=DisplayBounds(x:0,y:0,width:1000,height:700)
for point in [Point(0,0),Point(999,0),Point(0,699),Point(999,699)] {
 let safe=CornerAvoidance.redirected(point,displays:[display]);check(safe != point,"active corner redirects pointer")
 check(safe.x>=36 && safe.x<=964 && safe.y>=36 && safe.y<=664,"redirect stays inside same display")
 check(CornerAvoidance.redirected(point,displays:[display],enabled:[])==point,"unconfigured corners unchanged")
}
check(CornerAvoidance.redirected(Point(0,350),displays:[display])==Point(0,350),"ordinary edge pointing unchanged")
check(CornerAvoidance.redirected(Point(500,350),displays:[display])==Point(500,350),"ordinary interior pointing unchanged")
let secondary=DisplayBounds(x:-800,y:-600,width:800,height:600)
check(CornerAvoidance.redirected(Point(-800,-600),displays:[secondary])==Point(-764,-564),"negative display origin respected")
check(CornerAvoidance.redirected(Point(999,699),displays:[display],enabled:[.topLeft])==Point(999,699),"only configured corner is filtered")
print("Passed \(count) core checks including guarded value replacement and corner geometry.")

let diagonal=[StrokeSample(Point(0.8,0.2),time:0),StrokeSample(Point(0.7,0.3),time:0.05),StrokeSample(Point(0.6,0.4),time:0.1,phase:.ended)]
for mirrored in [false,true] {
 let trace=diagonal.map {StrokeSample(mirrored ? Point(1-$0.point.x,1-$0.point.y):$0.point,time:$0.time,phase:$0.phase)}
 let end=trace.last!.point,delta=mirrored ? 1.0:-1.0
 let first=Point(end.x+delta*0.005,end.y-delta*0.005),next=Point(end.x+delta*0.015,end.y-delta*0.015)
 check(LiftGrace.nearby(trace,point:first,elapsed:0.04,idChanged:true,bounces:0,missing:0,grace:0.22),"both handed diagonal bounces spatially eligible")
 check(LiftGrace.directionContinues(trace,first:first,next:next)==true,"both handed bounce headings continue")
 check(LiftGrace.directionContinues(trace,first:first,next:end)==false,"reverse-direction next word is not joined")
 check(!LiftGrace.nearby(trace,point:first,elapsed:0.18,idChanged:false,bounces:0,missing:0,grace:0.22),"late recontact is new word")
 check(!LiftGrace.nearby(trace,point:first,elapsed:0.04,idChanged:false,bounces:3,missing:0,grace:0.22),"repeated bounce count bounded")
 check(!LiftGrace.nearby(trace,point:first,elapsed:0.04,idChanged:false,bounces:1,missing:0.28,grace:0.22),"cumulative missing-contact duration bounded")
 check(!LiftGrace.nearby(trace,point:Point(0.05,0.9),elapsed:0.04,idChanged:false,bounces:0,missing:0,grace:0.22),"distant fresh contact is new word")
}
print("Passed \(count) core checks including mirrored bounded release grace.")

check(FocusLookup.isUnpublished(application:FocusLookup.noValue,system:FocusLookup.noValue),"both focus roots report unpublished state")
check(!FocusLookup.isUnpublished(application:FocusLookup.apiDisabled,system:FocusLookup.noValue),"disabled API is not delayed focus")
check(!FocusLookup.isUnpublished(application:FocusLookup.noValue,system:0),"foreign successful system focus is not delayed target focus")
check(FocusLookup.kind(application:0,system:nil,fieldFound:true)=="found","authoritative owned field classified found")
check(FocusLookup.kind(application:FocusLookup.cannotComplete,system:nil,fieldFound:false)=="providerNotResponding","provider timeout classified separately")
print("Passed \(count) core checks with authoritative focus classifications.")

// MARK: Keyboard end-to-end: synthetic swipes through the same recognizer the app uses.
func keyboardStroke(_ path: [Point], step: Double = 0.01) -> [StrokeSample] {
  path.enumerated().map { StrokeSample($0.element, time: Double($0.offset) * step) }
}
func neighbour(of key: Character, dx: Double) -> Character? {
  guard let p = Keyboard.keys[key] else { return nil }
  let target = Point(p.x + dx, p.y)
  return Keyboard.nearestKey(target).flatMap { $0 == key ? nil : $0 }
}
func jittered(_ path: [Point], amount: Double, seed: Double) -> [Point] {
  path.enumerated().map { i, p in
    Point(min(max(p.x + sin(Double(i + 1) * 12.9898 + seed) * amount, 0), 1),
          min(max(p.y + cos(Double(i + 1) * 78.233 + seed) * amount, 0), 1))
  }
}
let e2eWords = ["hello", "world", "keyboard", "swipe", "type", "quick", "brown", "fox", "jump",
  "zebra", "trackpad", "gesture", "hover", "quiet", "bottom", "apple", "water", "green", "house",
  "listen", "silent", "people", "thanks", "mouse", "pizza", "tower", "power", "vacuum"]
let e2eLexicon = GestureLexicon(words: e2eWords, usePrior: false)
func rankedWords(_ samples: [StrokeSample]) -> [String] { e2eLexicon.rank(samples, limit: 5).map(\.word) }

// Full keyboard, exact swipes: every word is the top candidate.
for word in e2eWords {
  check(rankedWords(keyboardStroke(Keyboard.path(word))).first == word, "e2e exact swipe top-1 \(word)")
}
// Full keyboard, a wrong first letter (the finger started on a neighbouring key): the intended word stays in the top 3.
var wrongStart = 0
for word in e2eWords {
  guard let first = word.first, let n = neighbour(of: first, dx: 0.1) ?? neighbour(of: first, dx: -0.1) else { continue }
  let path = Keyboard.path(String(n) + word.dropFirst())
  if Array(rankedWords(keyboardStroke(path)).prefix(3)).contains(word) { wrongStart += 1 }
}
check(wrongStart == e2eWords.count, "e2e neighbour-key start still finds the intended word (\(wrongStart)/\(e2eWords.count))")
// Full keyboard, hand jitter of ~1 mm-scale wobble: still the top candidate.
var jitterHits = 0
for word in e2eWords {
  if rankedWords(keyboardStroke(jittered(Keyboard.path(word), amount: 0.008, seed: 3))).first == word { jitterHits += 1 }
}
check(jitterHits >= e2eWords.count * 9 / 10, "e2e jittered swipes top-1 (\(jitterHits)/\(e2eWords.count))")

// Viewport: crop, round-trip, and recognition through the crop.
let crop = KeyboardViewport(minX: 0.25, minY: 0, maxX: 0.95, maxY: 1)
check(KeyboardViewport(minX: 0.5, minY: 0.5, maxX: 0.51, maxY: 0.51).spanX >= KeyboardViewport.minimumSpan, "viewport enforces minimum span")
check(KeyboardViewport(stored: [0.1, 0.2, 0.3]) == .full, "malformed stored viewport falls back to full keyboard")
check(KeyboardViewport(stored: crop.stored) == crop, "viewport round-trips through storage")
let k = Keyboard.keys["g"]!
check(crop.toKeyboard(crop.toPad(k)).distance(k) < 1e-9, "viewport pad/keyboard round trip")
check(crop.contains(k) && !crop.contains(Keyboard.keys["q"]!), "viewport shows only keys inside the crop")
check(Keyboard.nearestKey(crop.toKeyboard(crop.toPad(Keyboard.keys["a"]!))) == "a", "tap inside crop maps to the right key")
var cropHits = 0, cropWords = 0
for word in e2eWords where word.allSatisfy({ crop.contains(Keyboard.keys[$0]!) }) {
  cropWords += 1
  let padPath = Keyboard.path(word).map(crop.toPad)
  if rankedWords(crop.map(keyboardStroke(padPath))).first == word { cropHits += 1 }
}
check(cropWords > 0 && cropHits == cropWords, "e2e swipes inside a cropped keyboard (\(cropHits)/\(cropWords))")
print("Passed \(count) checks including keyboard end-to-end swipes.")
// Lenient start: the finger lands two, three or four keys from the first letter and the word still wins.
for dx in [0.2, 0.3, 0.4] {
  var hits = 0, total = 0
  for word in e2eWords {
    guard let first = word.first, let n = neighbour(of: first, dx: dx) ?? neighbour(of: first, dx: -dx) else { continue }
    total += 1
    if Array(rankedWords(keyboardStroke(Keyboard.path(String(n) + word.dropFirst()))).prefix(3)).contains(word) { hits += 1 }
  }
  check(total > 0 && hits == total, "e2e start \(dx) away still finds the intended word (\(hits)/\(total))")
}
print("Passed \(count) checks including lenient starts and keyboard crop.")

// MARK: Customer scenarios (red first): how people actually swipe, and how they crop the keyboard.

// Crop edges: the edge under the pointer is found and dragging clamps to the keyboard.
let cropEdges = KeyboardViewport(minX: 0.2, minY: 0.1, maxX: 0.8, maxY: 0.9)
check(cropEdges.edge(at: Point(0.2, 0.5), tolerance: 0.01) == .left, "grab the left edge")
check(cropEdges.edge(at: Point(0.8, 0.5), tolerance: 0.01) == .right, "grab the right edge")
check(cropEdges.edge(at: Point(0.5, 0.1), tolerance: 0.01) == .bottom, "grab the bottom edge")
check(cropEdges.edge(at: Point(0.5, 0.9), tolerance: 0.01) == .top, "grab the top edge")
check(cropEdges.edge(at: Point(0.5, 0.5), tolerance: 0.01) == nil, "middle of the crop grabs nothing")
check(cropEdges.edge(at: Point(0.2, 0.05), tolerance: 0.01) == nil, "a point beside the frame grabs nothing")
let draggedLeft = cropEdges.dragging(.left, to: 0.75)
check(abs(draggedLeft.minX - (0.8 - KeyboardViewport.minimumSpan)) < 1e-9, "dragging the left edge past the right edge stops at the minimum width")
check(cropEdges.dragging(.left, to: -0.5).minX == 0, "dragging the left edge past the keyboard stops at the keyboard edge")
check(cropEdges.dragging(.top, to: 1.5).maxY == 1, "dragging the top edge past the keyboard stops at the keyboard edge")
check(cropEdges.dragging(.right, to: 0.5).maxX == 0.5, "dragging the right edge shrinks the crop")
check(KeyboardViewport.full.edge(at: Point(0, 0.5), tolerance: 0.01) == .left, "the full keyboard still has grabbable edges")

// Full keyboard stays untouched by the crop code.
let fullSample = [StrokeSample(Point(0.3, 0.4), time: 0.1, source: .screenOverlay, sourcePoint: Point(0.25, 0.4))]
check(KeyboardViewport.full.map(fullSample) == fullSample, "full keyboard leaves strokes identical")

// Fast swipe: a quick flick sends few samples, but the word is still there.
let fastWords = ["hello", "water", "house", "people", "keyboard"]
for word in fastWords {
  let sparse = Keyboard.path(word).enumerated().filter { $0.offset % 6 == 0 }.map(\.element) + [Keyboard.path(word).last!]
  check(rankedWords(keyboardStroke(sparse, step: 0.02)).prefix(3).contains(word), "customer: fast flick finds \(word)")
}
// Slow swipe with pauses: repeated samples where the finger sat still.
for word in ["green", "listen", "silent", "quiet"] {
  var slow: [Point] = []
  for p in Keyboard.path(word) { slow.append(contentsOf: Array(repeating: p, count: 3)) }
  check(rankedWords(keyboardStroke(slow)).first == word, "customer: slow swipe with pauses finds \(word)")
}
// Index-finger roll: a short back-and-forth in the middle of a swipe still finds the word.
for word in ["trackpad", "gesture", "mouse"] {
  var path = Keyboard.path(word)
  let mid = path.count / 2
  let roll = path[mid].x < 0.9 ? Point(path[mid].x + 0.03, path[mid].y) : Point(path[mid].x - 0.03, path[mid].y)
  path.insert(roll, at: mid)
  check(Array(rankedWords(keyboardStroke(path)).prefix(5)).contains(word), "customer: index-finger roll still finds \(word)")
}
// Doubled letters (loops) are not lost when the start is off.
for word in ["hello", "pizza", "tower", "apple"] {
  guard let first = word.first, let n = neighbour(of: first, dx: 0.2) ?? neighbour(of: first, dx: -0.2) else { continue }
  check(Array(rankedWords(keyboardStroke(Keyboard.path(String(n) + word.dropFirst()))).prefix(5)).contains(word), "customer: doubled-letter \(word) with an off start")
}
// Cropped keyboard: a customer who cropped to the right half still types what they swipe there.
let rightHalf = KeyboardViewport(minX: 0.5, minY: 0, maxX: 1, maxY: 1)
for word in ["quiet", "pizza", "tower", "power", "vacuum", "mouse", "hover"] where word.allSatisfy({ rightHalf.contains(Keyboard.keys[$0]!) }) {
  let padPath = Keyboard.path(word).map(rightHalf.toPad)
  check(rankedWords(rightHalf.map(keyboardStroke(padPath))).first == word, "customer: swipe in the right-half crop types \(word)")
}
// Gibberish should not be typed as a real word from a single zig-zag.
let zigzag = (0..<12).map { Point(Double($0 % 2) * 0.9 + 0.05, Double($0) / 12) }
_ = rankedWords(keyboardStroke(zigzag)) // must return without trapping on a scribble
check(true, "customer: zig-zag scribble does not crash the recognizer")
print("Passed \(count) checks including customer scenarios.")
let commonWords = ["the", "and", "that", "have", "for", "not", "with", "you", "this", "but", "from", "they",
  "say", "her", "she", "will", "one", "all", "would", "there", "their", "what", "about", "which", "when",
  "make", "like", "time", "just", "know", "people", "into", "year", "good", "some", "could", "them",
  "other", "than", "then", "look", "only", "come", "over", "think", "also", "back", "after", "work",
  "first", "well", "even", "want", "because", "these", "give", "most", "keyboard", "trackpad", "swipe"]
// Slow measurements (real lexicon, tuning split). Run with SWIPE_TUNE=1; they print but do not gate.
if ProcessInfo.processInfo.environment["SWIPE_TUNE"] != nil {
// Benchmark on the real lexicon (not the small test list): common words, realistic wobble and starts.
let fullLexicon = GestureLexicon(words: WordVocabulary.words)
var benchTop1 = 0, benchTop3 = 0
for word in commonWords {
  let wobbled = jittered(Keyboard.path(word), amount: 0.01, seed: 5)
  let ranked = fullLexicon.rank(keyboardStroke(wobbled), limit: 5).map(\.word)
  if ranked.first == word { benchTop1 += 1 }
  if ranked.prefix(3).contains(word) { benchTop3 += 1 }
}
print("Benchmark, real lexicon, \(commonWords.count) common words: top-1 \(benchTop1), top-3 \(benchTop3).")
var offTop3 = 0, offTotal = 0
for word in commonWords {
  guard let first = word.first, let n = neighbour(of: first, dx: 0.3) ?? neighbour(of: first, dx: -0.3) else { continue }
  offTotal += 1
  let wobbled = jittered(Keyboard.path(String(n) + word.dropFirst()), amount: 0.01, seed: 9)
  if fullLexicon.rank(keyboardStroke(wobbled), limit: 5).map(\.word).prefix(3).contains(word) { offTop3 += 1 }
}
print("Benchmark, real lexicon, start three keys off: top-3 \(offTop3)/\(offTotal).")
// MARK: Tuning harness (experiment): train on half the words, report validation separately.
let tuneWords = commonWords + ["because", "before", "great", "little", "right", "old", "same", "tell", "very", "still", "try", "learn", "change", "help", "live", "turn", "start", "might", "move", "again", "under", "never", "around", "during", "home", "night", "under", "water", "house", "world", "school", "family", "country", "student", "group", "problem", "system", "answer", "number", "music", "letter", "river", "pizza", "tower", "power", "vacuum", "mouse", "hover", "quiet", "green", "listen", "silent", "apple", "thanks", "bottom", "zebra", "quick", "brown", "jump", "fox", "gesture", "hello", "typing"]
let tuneDedup = Array(Set(tuneWords)).sorted().filter { $0.count >= 3 && $0.allSatisfy { Keyboard.keys[$0] != nil } }
let tuneTrain = tuneDedup.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
let tuneVal = tuneDedup.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
let tuneLexicon = GestureLexicon(words: WordVocabulary.words)
func tuneScore(_ words: [String]) -> Double {
  var hits = 0, total = 0
  for word in words {
    let path = Keyboard.path(word)
    let scenarios: [[Point]] = [
      jittered(path, amount: 0.01, seed: 5),
      Array(path.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)) + [path.last!],
      { () -> [Point] in
        guard let f = word.first, let n = neighbour(of: f, dx: 0.2) ?? neighbour(of: f, dx: -0.2) else { return path }
        return jittered(Keyboard.path(String(n) + word.dropFirst()), amount: 0.01, seed: 9)
      }(),
    ]
    for s in scenarios {
      total += 1
      if tuneLexicon.rank(keyboardStroke(s), limit: 5).map(\.word).prefix(3).contains(word) { hits += 1 }
    }
  }
  return Double(hits) / Double(max(total, 1))
}
print(String(format: "TUNE train=%.4f val=%.4f words=%d/%d", tuneScore(tuneTrain), tuneScore(tuneVal), tuneTrain.count, tuneVal.count))
}

// MARK: Roll jumps (red first): a contact centroid that spikes and snaps back must not hook the trail or the recognizer.
do {
  // Steady swipe, one step every 10 ms; a single sample jumps up 0.2 and returns on the next frame.
  var f = ContactJumpFilter()
  var accepted: [Point] = []
  let steady = (0..<12).map { Point(0.9 - Double($0) * 0.05, 0.1 + Double($0) * 0.04) }
  for (i, p) in steady.enumerated() {
    let spiked = i == 6 ? Point(p.x, p.y + 0.2) : p
    if f.accept(spiked, time: Double(i) * 0.01) { accepted.append(spiked) }
  }
  check(!accepted.contains(Point(0.6, 0.54)), "roll spike is not drawn or scored")
  check(accepted.count >= steady.count - 1, "only the spike is dropped, the swipe is kept")

  // A genuinely fast flick keeps its samples: consecutive large steps confirm each other.
  var g = ContactJumpFilter()
  var flick: [Point] = []
  for i in 0..<6 {
    let p = Point(0.9 - Double(i) * 0.12, 0.1 + Double(i) * 0.12)
    if g.accept(p, time: Double(i) * 0.01) { flick.append(p) }
  }
  check(flick.count == 6, "a real fast flick keeps every sample")

  // A sustained shift (two samples at the new place) is real movement, not a spike.
  var h = ContactJumpFilter()
  var shifted: [Point] = []
  let path = [Point(0.2, 0.2), Point(0.22, 0.22), Point(0.24, 0.24), Point(0.6, 0.6), Point(0.61, 0.61), Point(0.62, 0.62)]
  for (i, p) in path.enumerated() where h.accept(p, time: Double(i) * 0.01) { shifted.append(p) }
  check(shifted.contains(Point(0.61, 0.61)) && shifted.contains(Point(0.62, 0.62)), "a sustained shift is kept")
}
// Recognition with a roll spike in the middle of a bottom-right to top-left swipe still finds the word.
do {
  let rollWords = ["mouse", "zebra", "hover", "quiet", "power"]
  var hits = 0
  for word in rollWords {
    var path = Keyboard.path(word)
    let mid = path.count / 2
    path[mid] = Point(path[mid].x, min(path[mid].y + 0.18, 1))
    var filter = ContactJumpFilter()
    var kept: [Point] = []
    for (i, p) in path.enumerated() where filter.accept(p, time: Double(i) * 0.01) { kept.append(p) }
    if rankedWords(keyboardStroke(kept)).prefix(3).contains(word) { hits += 1 }
  }
  check(hits == rollWords.count, "customer: roll spike filtered, bottom-right swipes still type (\(hits)/\(rollWords.count))")
}
print("Passed \(count) checks including roll-jump filtering.")

// MARK: Pad area (red first): use only part of the trackpad as the keyboard; contacts outside are ignored.
do {
  check(PadRegion.full.map(keyboardStroke(Keyboard.path("hello"))) == keyboardStroke(Keyboard.path("hello")), "full pad area leaves contacts unchanged")
  let phone = PadRegion.iPhoneSized
  check(phone.contains(Point(0.5, 0.3)) && !phone.contains(Point(0.05, 0.9)), "iPhone-sized area ignores contacts outside it")
  check(phone.toRegion(Point(phone.minX, phone.minY)).distance(Point(0, 0)) < 1e-9 && phone.toRegion(Point(phone.maxX, phone.maxY)).distance(Point(1, 1)) < 1e-9, "area corners map to keyboard corners")
  let phoneAspect = (phone.spanY / phone.spanX) / PadRegion.trackpadWidthToHeight
  check(abs(phoneAspect - 0.5) < 0.02, "iPhone-sized area has a phone keyboard proportion (\(phoneAspect))")
  check(PadRegion(stored: phone.stored) == phone, "pad area round-trips through storage")
  check(PadRegion(stored: [0, 0, 0.001, 0.001]).spanX >= PadRegion.minimumSpan, "pad area enforces a minimum size")
  // Typing through a smaller area still recognizes the word.
  for word in ["hello", "water", "quiet"] {
    let inArea = Keyboard.path(word).map { Point(phone.minX + $0.x * phone.spanX, phone.minY + $0.y * phone.spanY) }
    check(rankedWords(phone.map(keyboardStroke(inArea))).prefix(3).contains(word), "customer: swipe in the iPhone-sized area types \(word)")
  }
}
print("Passed \(count) checks including pad areas.")
// Confidence measurement (gated): margin between the best and second-best candidate, split by whether the best was right.
if ProcessInfo.processInfo.environment["SWIPE_MARGIN"] != nil {
  let marginWords = Array(Set(commonWords + ["because", "before", "great", "little", "right", "tell", "change", "start", "might", "home", "water", "house", "world", "school", "answer", "number", "music", "letter", "river", "pizza", "tower", "power", "quiet", "green", "listen", "silent", "apple", "thanks", "bottom", "zebra", "quick", "brown", "jump", "fox", "hello", "typing"])).sorted().filter { $0.count >= 3 }
  let marginLexicon = GestureLexicon(words: WordVocabulary.words)
  var rightMargins: [Double] = [], wrongMargins: [Double] = []
  for word in marginWords {
    let path = Keyboard.path(word)
    var streams: [[Point]] = [path, jittered(path, amount: 0.01, seed: 5)]
    if let f = word.first, let n = neighbour(of: f, dx: 0.2) ?? neighbour(of: f, dx: -0.2) {
      streams.append(jittered(Keyboard.path(String(n) + word.dropFirst()), amount: 0.01, seed: 9))
    }
    for s in streams {
      let ranked = marginLexicon.rank(keyboardStroke(s), limit: 5)
      guard let best = ranked.first else { continue }
      let second = ranked.count > 1 ? ranked[1].score : best.score + 1
      let margin = (second - best.score) / max(abs(best.score), 1e-6)
      if best.word == word { rightMargins.append(margin) } else { wrongMargins.append(margin) }
    }
  }
  func quantile(_ v: [Double], _ q: Double) -> Double { let s = v.sorted(); return s.isEmpty ? .nan : s[min(s.count - 1, Int(q * Double(s.count)))] }
  print(String(format: "MARGIN right n=%d p10=%.4f p50=%.4f", rightMargins.count, quantile(rightMargins, 0.1), quantile(rightMargins, 0.5)))
  print(String(format: "MARGIN wrong n=%d p50=%.4f p90=%.4f", wrongMargins.count, quantile(wrongMargins, 0.5), quantile(wrongMargins, 0.9)))
  for t in [0.25, 0.5, 1.0, 2.0] {
    print(String(format: "MARGIN T=%.2f: wrong held back %d/%d, right held back %d/%d", t, wrongMargins.filter { $0 < t }.count, wrongMargins.count, rightMargins.filter { $0 < t }.count, rightMargins.count))
  }
  let threshold = quantile(rightMargins, 0.1)
  let wrongBelow = wrongMargins.filter { $0 < threshold }.count
  print(String(format: "MARGIN threshold(p10 of right)=%.4f: wrong below=%d/%d, right below=%d/%d", threshold, wrongBelow, wrongMargins.count, rightMargins.filter { $0 < threshold }.count, rightMargins.count))
}

// MARK: Candidate choice (red first): commit a clear winner; offer up to three when the top two are close.
do {
  check(CandidateChoice.decide([]) == .none, "no candidates means nothing is typed")
  check(CandidateChoice.decide([GestureCandidate(word: "hello", score: 0.5, geometryScore: 0.5)]) == .commit("hello"), "a lone candidate is committed")
  let clear = [GestureCandidate(word: "hello", score: 1.0, geometryScore: 1.0), GestureCandidate(word: "hallo", score: 3.0, geometryScore: 3.0)]
  check(CandidateChoice.decide(clear) == .commit("hello"), "a clear winner is typed without asking")
  let close = (0..<4).map { GestureCandidate(word: ["hello", "hallo", "hells", "help"][$0], score: 1.0 + Double($0) * 0.1, geometryScore: 1.0) }
  check(CandidateChoice.decide(close) == .choose(["hello", "hallo", "hells"]), "a close call offers the top three and types nothing")
  check(CandidateChoice.choiceIndex(for: Point(0.1, 0.92), count: 3) == 0, "left third of the top strip picks the first choice")
  check(CandidateChoice.choiceIndex(for: Point(0.5, 0.92), count: 3) == 1, "middle third picks the second choice")
  check(CandidateChoice.choiceIndex(for: Point(0.9, 0.92), count: 3) == 2, "right third picks the third choice")
  check(CandidateChoice.choiceIndex(for: Point(0.5, 0.5), count: 3) == nil, "touches below the strip do not pick a choice")
  check(CandidateChoice.choiceIndex(for: Point(0.5, 0.92), count: 0) == nil, "no choices means nothing to pick")
}
print("Passed \(count) checks including candidate choice.")

// MARK: Insertion route and undo (red first): web editors such as Claude's composer get real key presses.
do {
  check(InsertionRoute.choose(insideWebArea: true) == .keystroke, "text inside a web editor is typed with key presses")
  check(InsertionRoute.choose(insideWebArea: false) == .accessibility, "native text fields keep the verified accessibility route")
  check(UndoPlan.backspaceCount(for: "hello") == 6, "undo deletes the word and its trailing space")
  check(UndoPlan.alternatives(after: "hello", from: ["hello", "hallo", "hells"]) == ["hallo", "hells"], "undo offers the next candidates in order")
  check(UndoPlan.alternatives(after: "hello", from: ["hello"]).isEmpty, "undo with no runner-up offers nothing")
}
print("Passed \(count) checks including insertion route and undo.")

// MARK: Customer: short common words must type on the full word list (they were held back before).
do {
  let shortLexicon = GestureLexicon(words: WordVocabulary.words)
  for word in ["hi", "hello"] {
    let top = shortLexicon.rank(keyboardStroke(Keyboard.path(word)), limit: 5).first?.word
    check(top == word, "customer: \(word) types as the top word on the full word list (got \(top ?? "nothing"))")
  }
}
print("Passed \(count) checks including short words.")

// MARK: Pad presets: compact area is smaller than the iPhone-sized area and stays on the pad.
do {
  let compact = PadRegion.compact
  check(compact.spanX < PadRegion.iPhoneSized.spanX && compact.spanY < PadRegion.iPhoneSized.spanY, "compact area is smaller than the iPhone-sized area")
  check(compact.minX >= 0 && compact.maxX <= 1 && compact.minY >= 0 && compact.maxY <= 1, "compact area stays on the trackpad")
  check(compact.contains(Point(0.5, 0.5)) && !compact.contains(Point(0.02, 0.02)), "compact area is centred")
}
print("Passed \(count) checks including pad presets.")
