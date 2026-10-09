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
    role: "AXTextArea", subrole: .absent, selectedTextSettable: true, secureInput: false),
  "ordinary browser/TextEdit textarea without optional subrole")
check(
  FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("AXUnknown"), selectedTextSettable: true, secureInput: false
  ), "native text area with explicit ordinary subrole")
check(
  FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXUnknown"), selectedTextSettable: true,
    secureInput: false), "ordinary single-line text field")
check(
  FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXSearchField"), selectedTextSettable: true,
    secureInput: false), "ordinary search field")
check(
  !FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXSecureTextField"), selectedTextSettable: true,
    secureInput: false), "password subrole")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("AXSecureTextField"), selectedTextSettable: true,
    secureInput: false), "secure metadata cannot bypass via text area role")
check(
  !FieldPolicy.permits(
    role: "AXTextField", subrole: .absent, selectedTextSettable: true, secureInput: false),
  "single-line missing safety metadata")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .unreadable, selectedTextSettable: true, secureInput: false),
  "AX metadata errors fail closed")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, selectedTextSettable: false, secureInput: false),
  "read-only text area")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, selectedTextSettable: true, secureInput: true),
  "Secure Input still blocks ordinary textarea")
check(
  !FieldPolicy.permits(
    role: "AXButton", subrole: .absent, selectedTextSettable: true, secureInput: false),
  "unrelated control")
check(
  !FieldPolicy.permits(role: nil, subrole: .absent, selectedTextSettable: true, secureInput: false),
  "missing role")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("UnrecognizedSubrole"), selectedTextSettable: true,
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
mock.selectedTextSettable = true
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
