import AppKit
import ApplicationServices
import Foundation
import Darwin
import SwipepadCore
import TrackpadBridge

// Offscreen, prohibited-activation, self-owned native controls. AX reads/writes and
// receiver text storage are real. Focus/PID ownership and contact frames are test
// ports: this does not qualify global focus, physical contacts or another app.
final class TextSuiteView:NSTextView {
  override func accessibilityValue()->String? {nil}
}
final class PlaceholderValueView:NSTextView {
  override func accessibilityValue()->String? {"Owned input placeholder"}
}
final class NativeInput:AppDelegate {
  override var feedbackWindowsEnabled:Bool {false}
  var owned:AXUIElement?
  var contentReads=0
  override func fieldText(_ field:AXUIElement)->String? {contentReads += 1;return super.fieldText(field)}
  // A virtual application identity avoids admission's intentional self-app guard.
  // No event posting or application lookup/launch is performed for this identity.
  override var currentApplicationPID:pid_t? {Int32.max}
  override func focused(_ pid:pid_t)->AXUIElement? {pid==Int32.max ? owned:nil}
  override var runtimeSignatureValid:Bool {true} // Unbundled fixture, not an installed identity test.
  override func replaceSelectedText(_ field:AXUIElement,pid:pid_t,range:CFRange,inserted:String,expectedBefore:String?=nil)->AXError {
    precondition(insertionTransport == .accessibility && owned.map {CFEqual($0,field)} == true)
    return super.replaceSelectedText(field,pid:pid,range:range,inserted:inserted,expectedBefore:expectedBefore)
  }
  func begin() {
    insertionTransport = .accessibility
    active=true;inputProtectionHealthy=true;strokeSource = .trackpad;liftGraceSeconds=0
    contactGate.reset();frameOrdering.reset(receivedAfter:0)
    gestureLexicon=GestureLexicon(words:["cat","world","auto"])
  }
}
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
let window=NSWindow(contentRect:NSRect(x:-20000,y:-20000,width:500,height:250),styleMask:[.borderless],backing:.buffered,defer:false)
let container=NSView(frame:window.contentView!.bounds)
let plain=NSTextView(frame:NSRect(x:10,y:10,width:450,height:80))
let suite=TextSuiteView(frame:NSRect(x:10,y:100,width:450,height:80))
let placeholder=PlaceholderValueView(frame:NSRect(x:10,y:190,width:450,height:50))
plain.setAccessibilityIdentifier("swipepad-native-plain")
suite.setAccessibilityIdentifier("swipepad-native-suite")
placeholder.setAccessibilityIdentifier("swipepad-native-placeholder")
container.addSubview(plain);container.addSubview(suite);container.addSubview(placeholder);window.contentView=container
app.setAccessibilityChildren([window])
let owner=NativeInput()
var checks=0,frameNumber:Int32=0,clock=ProcessInfo.processInfo.systemUptime
func check(_ condition:Bool,_ label:String) {
  guard condition else {print("FAIL: "+label);fflush(stdout);exit(2)}
  checks += 1;print("PASS: "+label);fflush(stdout)
}
func find(_ field:AXUIElement,id:String,depth:Int=0)->AXUIElement? {
  guard depth<10 else {return nil}
  var identifier:CFTypeRef?
  _=AXUIElementCopyAttributeValue(field,kAXIdentifierAttribute as CFString,&identifier)
  if identifier as? String==id {return field}
  var children:CFTypeRef?
  _=AXUIElementCopyAttributeValue(field,kAXChildrenAttribute as CFString,&children)
  for child in children as? [AXUIElement] ?? [] {
    if let result=find(child,id:id,depth:depth+1) {return result}
  }
  return nil
}
func frame(_ point:Point,id:Int32,state:OpenMTState) {
  clock += 0.01;frameNumber += 1
  let event=OpenMTEvent(),touch=OpenMTTouch()
  event.setValue(clock,forKey:"timestamp");event.setValue(ProcessInfo.processInfo.systemUptime,forKey:"receivedAt");event.setValue(frameNumber,forKey:"frameID")
  touch.setValue(id,forKey:"identifier");touch.setValue(Float(point.x),forKey:"posX");touch.setValue(Float(point.y),forKey:"posY");touch.setValue(state.rawValue,forKey:"state")
  event.setValue([touch],forKey:"touches");owner.touchFrame(event)
}
func swipe(_ word:String,id:Int32) {
  let centers=word.compactMap {Keyboard.keys[$0]}
  frame(centers[0],id:id,state:.starting)
  for (a,b) in zip(centers,centers.dropFirst()) {
    for i in 1...12 {let t=Double(i)/12;frame(Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t),id:id,state:.touching)}
  }
  frame(centers.last!,id:id,state:.breaking)
}
Timer.scheduledTimer(withTimeInterval:0.1,repeats:false) {_ in MainActor.assumeIsolated {
  guard !owner.secureInputActive else {print("BLOCKED: Secure Input active; no native field touched");fflush(stdout);exit(3)}
  let root=AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
  for (view,id,source) in [(plain,"swipepad-native-plain","fullRange"),(suite,"swipepad-native-suite","fullRange"),(placeholder,"swipepad-native-placeholder","fullRange")] {
    guard let field=find(root,id:id) else {print("BLOCKED: owned offscreen control not exposed");exit(3)}
    owner.owned=field
    owner.insertionTransport = .keyboard
    let reads=owner.contentReads
    _=owner.fieldMetadata(field)
    check(owner.contentReads==reads,"native metadata qualification never reads receiver contents")
    if view === suite {
      check(owner.attribute(field,kAXValueAttribute)==nil && owner.captureDiagnostics.valueReadAXError == -25212,"native provider genuinely omits AXValue")
    }
    for (seed,range,words,expected,endCaret) in [
      ("",NSRange(location:0,length:0),["cat","world","auto"],"cat world auto ",15),
      ("Hello there.",NSRange(location:5,length:0),["world","cat"],"Hello world cat there.",15),
      ("😀 old friend.",NSRange(location:3,length:3),["world"],"😀 world friend.",8),
    ] {
      owner.cancel("OFF");view.string=seed;view.setSelectedRange(range);owner.begin()
      check(owner.acquireTarget(),"owned native \(source) field admitted at exact range")
      check(owner.captureDiagnostics.textEvidenceSource==source,"native reader selected the advertised authoritative source")
      let baseline=owner.captureDiagnostics.insertions
      for (i,word) in words.enumerated() {swipe(word,id:Int32(10+i))}
      check(view.string==expected,"independent native text storage matches exact sentence after generated contacts")
      check(owner.captureDiagnostics.insertions-baseline==words.count && owner.unresolvedWrites.isEmpty,"native AX mutations have exact content/caret receipts with no uncertainty")
      check(view.selectedRange()==NSRange(location:endCaret,length:0),"independent native caret is exactly at the inserted word boundary")
    }
    owner.cancel("OFF")
  }
  check(!window.isVisible,"native receiving checks never ordered a window or changed desktop focus")
  print("PASS \(checks) offscreen native AX receiving checks. Virtual focus/generated contacts; no hardware, global focus, Codex or all-app claim.");fflush(stdout);exit(0)
}}
app.run()
