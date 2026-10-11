@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import SwipepadCore
import TrackpadBridge
import Foundation
import Darwin
let owner=AppDelegate(),app=NSApplication.shared
owner.liftGraceSeconds=0 // Immediate-commit fixtures; grace has separate handler tests.
owner.insertionTransport = .accessibility // This fixture explicitly qualifies the AX backend.
app.delegate=owner
let document=URL(fileURLWithPath:CommandLine.arguments[1]).resolvingSymlinksInPath()
precondition(document.lastPathComponent=="Swipepad Automated Fixture.rtf" && document.deletingLastPathComponent().lastPathComponent.hasPrefix("swipepad-integration.") && FileManager.default.fileExists(atPath:document.deletingLastPathComponent().appendingPathComponent(".swipepad-owned").path))
UserDefaults.standard.set(true,forKey:"hasLaunched");UserDefaults.standard.set(true,forKey:"showGuide");UserDefaults.standard.set("trackpad",forKey:"inputMode")
var number:Int32=0,count=0
var syntheticTime=ProcessInfo.processInfo.systemUptime
func stop(_ message:String,_ success:Bool=false)->Never {print(message);print("Checks: \(count). Generated contacts with native AX; no hardware claim.");if let data=try? JSONEncoder().encode(owner.captureDiagnostics),let json=String(data:data,encoding:.utf8) {print("Capture diagnostics: "+json)};fflush(stdout);owner.cancel("Quit");exit(success ? 0:2)}
func check(_ condition:Bool,_ message:String) {guard condition else {stop("FAIL: "+message)};count += 1;print("PASS: "+message);fflush(stdout)}
func field()->AXUIElement? {
 guard let front=NSWorkspace.shared.frontmostApplication,front.bundleIdentifier=="com.apple.TextEdit",let f=owner.focused(front.processIdentifier),let w=owner.attribute(AXUIElementCreateApplication(front.processIdentifier),kAXFocusedWindowAttribute),CFGetTypeID(w)==AXUIElementGetTypeID() else {return nil}
 let window=unsafeDowncast(w,to:AXUIElement.self)
 guard (owner.attribute(window,kAXDocumentAttribute) as? String).flatMap(URL.init(string:))?.resolvingSymlinksInPath()==document else {return nil};return f
}
func text()->String {guard let f=field(),let value=owner.attribute(f,kAXValueAttribute) as? String else {stop("ABORT: exact owned field unavailable")};return value}
func setRange(_ location:Int,_ length:Int=0) {guard let f=field() else {stop("ABORT: range scope")};var range=CFRange(location:location,length:length);let v=AXValueCreate(.cfRange,&range)!;check(AXUIElementSetAttributeValue(f,kAXSelectedTextRangeAttribute as CFString,v) == .success,"owned selection set")}
@discardableResult func frame(_ contacts:[(Int32,Point,OpenMTState)],timestamp:Double?=nil,receivedAt:Double?=nil)->OpenMTEvent {
 number += 1;syntheticTime += 0.01;let event=OpenMTEvent(),now=ProcessInfo.processInfo.systemUptime
 event.setValue(timestamp ?? syntheticTime,forKey:"timestamp");event.setValue(receivedAt ?? now,forKey:"receivedAt");event.setValue(number,forKey:"frameID")
 event.setValue(contacts.map {id,p,state in let t=OpenMTTouch();t.setValue(id,forKey:"identifier");t.setValue(Float(p.x),forKey:"posX");t.setValue(Float(p.y),forKey:"posY");t.setValue(state.rawValue,forKey:"state");return t},forKey:"touches");owner.touchFrame(event);return event
}
func curved(_ word:String)->[Point] {
 let centers=word.compactMap {Keyboard.keys[$0]};var points=[centers[0]]
 for (a,b) in zip(centers,centers.dropFirst()) {let d=max(a.distance(b),0.001);for i in 1...12 {let t=Double(i)/12,k=0.018*sin(t*Double.pi);points.append(Point(a.x+(b.x-a.x)*t-(b.y-a.y)/d*k,a.y+(b.y-a.y)*t+(b.x-a.x)/d*k))}}
 return points
}
func word(_ value:String,id:Int32=1) {let p=curved(value);for (i,point) in p.enumerated() {frame([(id,point,i==0 ? .starting:.touching)])};frame([(id,p.last!,.breaking)])}
func detach() {check(owner.listener != nil,"production physical listener registered");OpenMTManager.shared().remove(owner.listener!);owner.listener=nil}
var hotkeyClock=1000.0
func doubleCommand() {
  hotkeyClock += 2
  for (offset,flags) in [(0.0,NSEvent.ModifierFlags.command),(0.05,[]),(0.15,.command),(0.20,[])] {
    let event=NSEvent.keyEvent(with:.flagsChanged,location:.zero,modifierFlags:flags,timestamp:hotkeyClock+offset,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:55)!
    owner.handle(event)
  }
}
func delayedWriteChecks() {
  let baseline=text(),attempts=owner.captureDiagnostics.writeAttempts;setRange((baseline as NSString).length)
  guard owner.acquireTarget(),let f=field(),let original=owner.originalSelection else {stop("FAIL: delayed fixture target")}
  check(owner.replaceSelectedText(f,pid:owner.originalPID,range:original,inserted:"cat ") == .success,"production mutation accepts first word before caret lag")
  let write=owner.unresolvedWrites.last!;setRange(original.location)
  owner.beginCaretWait(write,original:original,inserted:"cat ",alternatives:["cat"])
  let w=curved("world"),t=curved("test")
  for (i,point) in w.enumerated() {frame([(50,point,i==0 ? .starting:.touching)])}
  frame([(50,w.last!,.breaking),(51,t[0],.starting)])
  check(owner.finger==51 && owner.strokeSamples.first!.point.distance(t[0])<0.000001,"pending mixed lift/newtouch preserves exact first contact")
  for point in t.dropFirst() {frame([(51,point,.touching)])};frame([(51,t.last!,.breaking)])
  RunLoop.current.run(until:Date().addingTimeInterval(0.35))
  check(owner.active && owner.pending && owner.queuedWords.count==2,"late caret retains two complete fast gestures while enabled")
  check(owner.captureDiagnostics.writeAttempts==attempts+1 && owner.captureDiagnostics.pendingWords==3,"pending words distinct from accepted mutation; no extra write attempt")
  check(text()==baseline+"cat ","stale original caret beyond250ms causes zero additional writes")
  setRange(write.expectedCaret)
  RunLoop.current.run(until:Date().addingTimeInterval(0.30))
  check(!owner.pending && owner.queuedWords.isEmpty,"expected caret/content releases ordered delivery")
  check(owner.captureDiagnostics.writeAttempts==attempts+3,"exactly one mutation attempt per ordered word")
  check(text()==baseline+"cat world test ","queued words deliver once at verified boundaries without toggle-off")
  let before=text();setRange((before as NSString).length);check(owner.acquireTarget(),"next delayed target")
  let start=owner.originalSelection!
  check(owner.replaceSelectedText(f,pid:owner.originalPID,range:start,inserted:"cat ") == .success,"second accepted mutation")
  let unresolved=owner.unresolvedWrites.last!;setRange(start.location)
  owner.beginCaretWait(unresolved,original:start,inserted:"cat ",alternatives:["cat"])
  doubleCommand();check(!owner.active,"double-Command exits during pending write")
  doubleCommand();check(owner.active,"double-Command reenters cleanly");detach()
  word("world",id:52);RunLoop.current.run(until:Date().addingTimeInterval(0.30))
  check(text()==before+"cat " && !owner.unresolvedWrites.isEmpty,"toggle/new trial cannot bypass unresolved mutation or late poll")
  setRange(unresolved.expectedCaret);word("world",id:53)
  check(text()==before+"cat world ","next fresh gesture writes once after expected state settles")
  // Generic sticky refusal also preserves an already-mutated transaction.
  let last=text();setRange((last as NSString).length);check(owner.acquireTarget(),"fallback-failure lifecycle target")
  let origin=owner.originalSelection!
  check(owner.replaceSelectedText(f,pid:owner.originalPID,range:origin,inserted:"test ") == .success,"accepted mutation before postwrite failure")
  let ambiguous=owner.unresolvedWrites.last!;setRange(origin.location);owner.cancel("Postwrite caret failure")
  word("cat",id:54)
  check(owner.active && text()==last+"test ","postwrite failure retains uncertainty and suppresses stale-boundary nextword")
  setRange(ambiguous.expectedCaret);word("cat",id:55)
  check(text()==last+"test cat ","confirmed mutation boundary allows later fresh word")
}
// Prepared native cases; compilation alone does not qualify AX delivery.
func sentenceChecks() {
 let cases:[(String,Int,Int,String)]=[
  ("Hello",5,0,"Hello world "),("Hello there",5,0,"Hello world there"),
  ("Hello.",5,0,"Hello world."),("Hello old friend",6,3,"Hello world friend"),
  ("(old)",1,3,"(world)"),("😀 old!",3,3,"😀 world!")]
 for (seed,location,length,expected) in cases {
  owner.cancel("Quit")
  guard let f=field() else {stop("ABORT: sentence fixture lost owned field")}
  check(AXUIElementSetAttributeValue(f,kAXValueAttribute as CFString,seed as CFString) == .success && text()==seed,"owned sentence seed verified")
  setRange(location,length);owner.toggle();detach();word("world")
  check(text()==expected && owner.unresolvedWrites.isEmpty,"native fixed sentence expectation: punctuation/selection/Unicode")
  owner.cancel("Quit")
 }
}
func run() {
 guard AXIsProcessTrusted(),CGPreflightPostEventAccess(),field() != nil else {stop("BLOCKED: existing permission/exact owned focus")}
 let baseline=text();setRange((baseline as NSString).length);owner.toggle();check(owner.active,"activate once");detach()
 let activationText=text()
 func press(_ letter:Character,fresh:Bool=true,duration:Double=0.35) {let point=Keyboard.keys[letter]!;frame([(10,point,fresh ? .making:.touching)]);syntheticTime += duration;frame([(10,point,.breaking)])}
 press("a",fresh:false);check(text()==activationText,"activation-held stationary contact cannot type a letter")
 let hoverPoint=Keyboard.keys["a"]!;frame([(10,hoverPoint,.starting)]);frame([(10,hoverPoint,.hovering)]);check(text()==activationText,"starting-to-hover without actual contact cannot auto-write")

 for (i,w) in ["cat","world","test"].enumerated() {word(w,id:Int32(i+1));check(owner.active && owner.lastOwnedWord != nil && owner.captureDiagnostics.insertions==i+1,"lift commits word and verifies next caret")}
 let initialSeparator=baseline.last.map { !$0.isWhitespace } ?? false
 check(text()==baseline+(initialSeparator ? " ":"")+"cat world test ","three curved words one activation, zero candidate clicks, exact spacing")
 let beforeLetters=text()
 var letterExpected=beforeLetters
 for (key,duration) in [(Character("a"),0.05),(Character("i"),0.15),(Character("a"),0.35),(Character("i"),2.0)] {press(key,duration:duration);letterExpected += key=="i" ? "I ":"a ";check(text()==letterExpected,"fresh tap/hold commits once without duration gate")}
 press("a",fresh:false,duration:0.05);letterExpected += "a ";check(text()==letterExpected,"known lift makes touching-only next tap fresh without pause")
 let aiStart=Keyboard.keys["a"]!,aiEnd=Keyboard.keys["i"]!
 frame([(10,aiStart,.touching)]);frame([(10,aiStart,.breaking),(11,aiEnd,.touching)]);frame([(11,aiEnd,.breaking)])
 letterExpected += "a I ";check(text()==letterExpected,"mixed lift and next tap commits separated single letters")
 check(owner.lastOwnedWord != nil && owner.captureDiagnostics.insertions==10,"a/I own writes safely rebase exact collapsed caret")
 let before=text();frame([(3,curved("test").last!,.breaking)]);frame([(3,curved("test").last!,.lingering)]);frame([]);frame([]);check(text()==before,"repeated breaking/lingering/empty frames cannot duplicate writes")
 let cat=curved("cat"),world=curved("world")
 for p in cat {frame([(4,p,.touching)])}
 let terminal=frame([(4,cat.last!,.breaking),(5,world[0],.starting)])
 check(owner.strokeSamples.count==1 && owner.finger==5,"breaking + new down separates strokes in same callback")
 owner.touchFrame(terminal);check(owner.strokeSamples.count==1,"duplicate mixed callback rejected")
 for p in world.dropFirst() {frame([(5,p,.touching)])};frame([(5,world.last!,.breaking)])
 check(text()==before+"cat world ","mixed frame commits both separated words exactly once")
 let contaminated=text();for p in cat.prefix(8) {frame([(6,p,.touching)])};frame([(6,cat[8],.touching),(7,Point(0.5,0.5),.touching)]);frame([])
 check(text()==contaminated,"multi-touch contaminated stroke writes nothing")
 word("cat",id:6);check(text()==contaminated+"cat ","reused ID first fresh contact after real lift accepted")
 let short=text();frame([(8,Point(0.5,0.5),.touching)]);frame([(8,Point(0.5,0.5),.breaking)]);check(text()==short && !owner.waitForLift,"short tap writes nothing and rearms without idle")
 frame([(8,Point(0.2,0.2),.touching)]);frame([(9,Point(0.4,0.5),.touching)]);frame([]);check(text()==short,"contact ID change without old terminal rejects contaminated stroke")
 frame([(9,Point(1.1,0.2),.touching)]);frame([(9,Point(0.4,0.7),.touching)]);frame([(9,Point(0.6,0.8),.breaking)]);check(text()==short && !owner.waitForLift,"out-of-range/no-match rejects without blocking next word")
 word("world",id:9);check(text()==short+"world ","next contact after failed stroke commits immediately")
 let old=frame([],receivedAt:0);check(owner.captureDiagnostics.droppedFrames>0,"previous epoch receipt rejected")
 owner.toggle();owner.toggle();detach();owner.touchFrame(old);check(owner.strokeSamples.isEmpty,"cancel/reactivate rejects queued old event")
 frame([],timestamp:-1);check(owner.strokeSamples.isEmpty,"out-of-order timestamp cannot begin a word")
 let coldFresh=text();press("a",duration:0.05);check(text()==coldFresh+"a ","cold fresh making tap works without an idle frame");word("cat");check(owner.lastOwnedWord != nil,"last inserted word has safe correction provenance")
 delayedWriteChecks();word("cat")
 let own=owner.lastOwnedWord!,correction=owner.buttons[1];check(correction.isHidden,"alternatives hidden while capture on")
 check(own.alternatives.count>1,"last word has a genuine alternate")
 let chosen=own.alternatives[1],prior=text();owner.cancel("OFF")
 check(!owner.active && owner.listener==nil && !owner.panel.isVisible,"stop releases capture and hides guide");owner.showLastCorrection();check(!correction.isHidden && correction.title==chosen,"correction view exposes recorded alternate");owner.panel.contentView?.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.10))
 let center=owner.panel.convertPoint(toScreen:correction.convert(NSPoint(x:correction.bounds.midX,y:correction.bounds.midY),to:nil))
 let p=CGPoint(x:center.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-center.y)
 let down=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:p,mouseButton:.left)!,up=CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:p,mouseButton:.left)!
 down.setIntegerValueField(.mouseEventClickState,value:1);up.setIntegerValueField(.mouseEventClickState,value:1); print("Native button hit: \(correction.bounds); frame: \(owner.panel.frame); visible: \(owner.panel.isVisible); screenPoint: \(center); screens: \(NSScreen.screens.map {$0.frame}); buttonWindow: \(correction.convert(NSPoint(x:correction.bounds.midX,y:correction.bounds.midY),to:nil)); hit: \(owner.panel.contentView?.hitTest(owner.panel.contentView!.convert(correction.convert(NSPoint(x:correction.bounds.midX,y:correction.bounds.midY),to:nil),from:nil)) === correction)")
 let expected=(prior as NSString).replacingCharacters(in:NSRange(location:own.range.location,length:own.range.length),with:chosen+" ")
 _ = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseUp]) {e in print("Native mouse event received: \(e.type.rawValue), window: \(e.window === owner.panel)");return e}
 print("LIMIT: native correction is qualified as NSButton action only; no mouse events posted into the desktop.")
 Timer.scheduledTimer(withTimeInterval:0.3,repeats:false) {_ in MainActor.assumeIsolated {finishCorrection(expected:expected,correction:correction)}}
}
func finishCorrection(expected:String,correction:NSButton) {
 if let own=owner.lastOwnedWord {let c=owner.selection(own.field);print("Correction guard: hidden=\(correction.isHidden), identity=\(owner.identity(own.field,pid:own.pid)), observed=\(c?.location ?? -1)/\(c?.length ?? -1), expected=\(own.range.location+own.range.length), content=\(owner.fingerprint(own.field)==own.fingerprint), candidate=\(own.alternatives.contains(correction.title)), finger=\(owner.finger == nil)")}

 print("Correction action observed: \(text()==expected); state: \(owner.label.stringValue); target retained: \(owner.lastOwnedWord != nil)");if text() != expected {print("Native NSButton action; no posted mouse input.");correction.performClick(nil)};RunLoop.current.run(until:Date().addingTimeInterval(0.20));print("Correction result: matches=\(text()==expected), active=\(owner.active), status=\(owner.label.stringValue), unresolved=\(owner.unresolvedWrites.count), chosen=\(correction.title)");check(text()==expected && !owner.active,"native NSButton correction replaces last owned word+space, never appends")
 check(owner.unresolvedWrites.isEmpty,"successful correction retires its confirmed transaction")
 let secondOwn=owner.lastOwnedWord!,beforeSecond=text(),secondWord=secondOwn.alternatives[0]
 let expectedSecond=(beforeSecond as NSString).replacingCharacters(in:NSRange(location:secondOwn.range.location,length:secondOwn.range.length),with:secondWord+" ")
 owner.showLastCorrection();let secondButton=owner.buttons[0];secondButton.performClick(nil)
 RunLoop.current.run(until:Date().addingTimeInterval(0.15))
 check(text()==expectedSecond && owner.lastOwnedWord != nil,"same owned word accepts a second alternative without append")
 check(owner.unresolvedWrites.isEmpty,"second correction also retires confirmed transaction")
 setRange(0);let unchanged=text(),attempts=owner.captureDiagnostics.writeAttempts;owner.selectCandidate(correction);check(text()==unchanged && owner.lastOwnedWord==nil && owner.captureDiagnostics.writeAttempts==attempts,"stale caret correction writes nothing")
 setRange((unchanged as NSString).length);owner.toggle();detach();word("cat");let recorded=owner.lastOwnedWord!;owner.cancel("OFF");setRange(0)
 let ownedField=field()!;check(AXUIElementSetAttributeValue(ownedField,kAXSelectedTextAttribute as CFString,"X" as CFString) == .success,"owned external-edit fixture")
 setRange(recorded.range.location+recorded.range.length);let changed=text();owner.selectCandidate(owner.buttons[1]);check(text()==changed,"manual content change rejects correction even with restored caret")
 setRange((changed as NSString).length);owner.toggle();detach();word("cat");let beforeSwitch=text()
 let stroke=curved("world");frame([(30,stroke[0],.starting)]);frame([(30,stroke[1],.touching)])
 let wrong=CFRange(location:0,length:0);var copy=wrong;let v=AXValueCreate(.cfRange,&copy)!;_ = AXUIElementSetAttributeValue(ownedField,kAXSelectedTextRangeAttribute as CFString,v)
 for point in stroke.dropFirst(2) {frame([(30,point,.touching)])};frame([(30,stroke.last!,.breaking)])
 check(owner.active && text()==beforeSwitch,"midstroke caret change discards write while enabled")
 setRange((beforeSwitch as NSString).length);word("world");check(owner.active && text()==beforeSwitch+"world ","next fresh stroke reacquires safe field without toggle")
 sentenceChecks()
 stop("PASS: production lift lifecycle, auto-write, safe correction and caret regression",true)
}
Timer.scheduledTimer(withTimeInterval:0.3,repeats:false) {_ in MainActor.assumeIsolated {
 guard let url=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.apple.TextEdit") else {stop("BLOCKED: TextEdit")}
 let config=NSWorkspace.OpenConfiguration();config.activates=true;config.createsNewApplicationInstance=false
 NSWorkspace.shared.open([document],withApplicationAt:url,configuration:config) {_,error in Task {@MainActor in
 guard error==nil else {stop("BLOCKED: owned open")};Timer.scheduledTimer(withTimeInterval:0.4,repeats:false) {_ in MainActor.assumeIsolated {run()}}
 }}
}}
app.run()
