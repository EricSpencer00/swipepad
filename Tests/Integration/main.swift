// Test-only executable: synthetic geometry and real candidate clicks.
// Built separately; no fixture endpoint is included in the production binary.
@preconcurrency import AppKit
@preconcurrency import CoreGraphics
@preconcurrency import ApplicationServices
import Foundation
import SwipepadCore
import TrackpadBridge
import Darwin
let delegate = AppDelegate();delegate.liftGraceSeconds=0
delegate.insertionTransport = .accessibility // This legacy fixture qualifies AX insertion.
let app = NSApplication.shared
app.delegate = delegate
guard CommandLine.arguments.count == 2 || (CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--contact-guards-only") else { print("Use scripts/test-integration.sh to create a fresh owned document."); exit(2) }
let document = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
UserDefaults.standard.set(InputMode.trackpad.rawValue,forKey:"inputMode") // Only this separate harness's domain.
var trial = 0
var expected = ""
@MainActor func stop(_ message: String, success: Bool = false) {
  print(message); fflush(stdout)
  if let data=try? JSONEncoder().encode(delegate.captureDiagnostics),let counters=String(data:data,encoding:.utf8) {print("Final structural capture diagnostics: "+counters);fflush(stdout)}
  delegate.cancel("Fixture harness finished")
  app.stop(nil)
  exit(success ? 0 : 2)
}
@MainActor func ownedField() -> AXUIElement? {
  guard let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier == "com.apple.TextEdit", let field = delegate.focused(front.processIdentifier), let windowValue = delegate.attribute(AXUIElementCreateApplication(front.processIdentifier),kAXFocusedWindowAttribute), CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
  let window = unsafeDowncast(windowValue,to:AXUIElement.self)
  guard (delegate.attribute(window,kAXDocumentAttribute) as? String).flatMap(URL.init(string:))?.resolvingSymlinksInPath() == document else { return nil }
  return field
}
@MainActor func frame(_ point: Point?) {
  let event = OpenMTEvent()
  event.setValue(ProcessInfo.processInfo.systemUptime,forKey:"timestamp")
  if let point {
    let touch = OpenMTTouch()
    touch.setValue(1,forKey:"identifier"); touch.setValue(OpenMTState.touching.rawValue,forKey:"state")
    touch.setValue(Float(point.x),forKey:"posX"); touch.setValue(Float(point.y),forKey:"posY")
    event.setValue([touch],forKey:"touches")
  } else { event.setValue([],forKey:"touches") }
  delegate.touchFrame(event)
}
@MainActor func secondaryChecks() {
  guard let field = ownedField(), let baseline = delegate.attribute(field,kAXValueAttribute) as? String else {stop("ABORT: owned field unavailable for cancellation.");return}
  if !delegate.active {delegate.toggle()}
  for point in Keyboard.path("test") {frame(point)}
  frame(nil)
  guard delegate.active && delegate.pending else {stop("FAIL: pending cancellation setup.");return}
  delegate.cancel("Fixture Escape-equivalent cancellation")
  guard !delegate.active, !delegate.panel.isVisible, delegate.attribute(field,kAXValueAttribute) as? String == baseline else {stop("FAIL: cancellation inserted or stayed visible.");return}
  delegate.toggle()
  guard delegate.active && delegate.validTarget() else {stop("FAIL: cancel/reactivate.");return}
  delegate.retry(); frame(nil)
  for point in Keyboard.path("cat") {frame(point)}
  frame(nil)
  guard delegate.pending else {stop("FAIL: Swipe Again could not decode new fixture.");return}
  print("PASS: pending cancel, no insertion, reactivate, Swipe Again replacement fixture.")
  var moved = CFRange(location:0,length:0)
  guard let value = AXValueCreate(.cfRange,&moved), AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,value) == .success else {stop("BLOCKED: cannot set owned caret for range-preservation test.");return}
  guard !delegate.validTarget() else {stop("FAIL: moved caret still accepted by target guard.");return}
  print("PASS: actual same-field caret movement is rejected before insertion.")
  delegate.cancel("Fixture range test complete")
  print("PASS: three actual candidate clicks, exact AX receipt and focus; synthetic gestures only.")
  selectionRegressionChecks()
}
@MainActor func setRange(_ field: AXUIElement, _ location: Int, _ length: Int) -> Bool {
  var range = CFRange(location: location, length: length)
  guard let value = AXValueCreate(.cfRange, &range) else { return false }
  return AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,value) == .success
}
@MainActor func fixturePending() -> Bool {
  delegate.toggle()
  guard delegate.active else { return false }
  if let listener = delegate.listener {OpenMTManager.shared().remove(listener);delegate.listener=nil}
  frame(nil)
  for point in Keyboard.path("hello") {frame(point)}
  frame(nil)
  return delegate.pending
}
@MainActor func selectionRegressionChecks() {
  guard let field = ownedField(), let baseline = delegate.attribute(field,kAXValueAttribute) as? String,
    setRange(field,0,(baseline as NSString).length),
    AXUIElementSetAttributeValue(field,kAXSelectedTextAttribute as CFString,"LEFT 🐈 RIGHT" as CFString) == .success,
    setRange(field,5,2),fixturePending() else {stop("ABORT: owned UTF16 replacement fixture unavailable.");return}
  let chosen = delegate.buttons[0].title
  delegate.buttons[0].performClick(nil)
  let replacement = "LEFT " + chosen + "  RIGHT"
  guard delegate.active,delegate.validTarget(),delegate.originalSelection?.location==5+(chosen+" ").utf16.count,delegate.originalSelection?.length==0,delegate.attribute(field,kAXValueAttribute) as? String == replacement else {stop("FAIL: UTF16 surrogate-pair selection replacement.");return}
  print("PASS: legitimate nonempty UTF16 replacement with verified resulting caret rebasing.")
  delegate.cancel("Fixture UTF16 replacement complete")
  for (name,location,length) in [("location-only",6,0),("length-only",5,1)] {
    guard setRange(field,5,0),fixturePending(),setRange(field,location,length) else {stop("ABORT: changed-range fixture setup.");return}
    let stale = delegate.buttons[0]
    stale.performClick(nil)
    guard !delegate.active, delegate.originalSelection == nil,
      delegate.attribute(field,kAXValueAttribute) as? String == replacement else {stop("FAIL: stale button action inserted after \(name) selection change.");return}
    let reason=delegate.statusReason
    delegate.updateModeIndicator()
    guard let reason,delegate.status.menu?.items.first?.title.contains(reason)==true,delegate.feedbackPanel?.isVisible==true,delegate.feedbackPanel?.canBecomeKey==false else {stop("FAIL: cancellation feedback hidden or overwritten by status refresh.");return}
    print("PASS: stale NSButton action after \(name) rejected with zero write; nonactivating visible reason survives status refresh.")
    guard fixturePending(), delegate.originalSelection?.location == location,
      delegate.originalSelection?.length == length else {stop("FAIL: reactivation did not capture fresh range.");return}
    delegate.retry()
    guard delegate.active,delegate.validTarget() else {stop("FAIL: retry range lifecycle.");return}
    delegate.cancel("Range fixture complete")
  }
  print("PASS: fresh activation and retry retain the intended new selection range.")
  overlayLayoutChecks()
}
@MainActor func nativePolicyChecks() {
  let window = NSWindow(contentRect:NSRect(x:0,y:0,width:420,height:240),styleMask:[.titled,.closable],backing:.buffered,defer:false)
  window.title = "Swipepad owned field policy fixtures"
  let secure = NSSecureTextField(frame:NSRect(x:20,y:170,width:300,height:24))
  let readonly = NSTextView(frame:NSRect(x:20,y:70,width:300,height:60));readonly.string="Owned read-only fixture";readonly.isEditable=false
  let unsupported = NSButton(title:"Owned unsupported button",target:nil,action:nil);unsupported.frame=NSRect(x:20,y:20,width:300,height:30)
  window.contentView?.addSubview(secure);window.contentView?.addSubview(readonly);window.contentView?.addSubview(unsupported)
  window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
  let controls:[(String,NSView)] = [("secure",secure),("read-only",readonly),("unsupported",unsupported)]
  var index = 0
  let timer = Timer(timeInterval:0.15,repeats:true) { _ in MainActor.assumeIsolated {
    if index == 0 {
      guard !delegate.active,!delegate.panel.isVisible,delegate.overlayPanel?.isVisible != true,delegate.originalSelection==nil else {stop("FAIL: owned app switch did not cancel/hide/clear active overlay.");return}
      print("PASS: actual switch from owned TextEdit to owned native fixture window cancels active overlay.")
    }
    if index == controls.count {window.close();stop("PASS: native secure/read-only/unsupported metadata rejection plus synthetic range/insertion regression checks. Hardware not certified.",success:true);return}
    let (name,control) = controls[index];window.makeFirstResponder(control)
    guard let field = delegate.focused(ProcessInfo.processInfo.processIdentifier) else {stop("BLOCKED: native owned fixture focus unavailable.");return}
    let metadata = delegate.fieldMetadata(field)
    let permitted = delegate.supportedField(field)
    print("Native \(name): role=\(metadata.role ?? "nil"), subrole=\(metadata.subrole), writable=\(metadata.writable), permitted=\(permitted)")
    guard !permitted else {stop("FAIL: actual native \(name) field accepted by policy.");return}
    index += 1
  }}
  RunLoop.main.add(timer,forMode:.common)
}
@MainActor func beginTrial() {
  guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { stop("BLOCKED: separate harness lacks existing AX/event-posting access; no prompt requested."); return }
  guard let field = ownedField(), let value = delegate.attribute(field,kAXValueAttribute) as? String, value == expected else { stop("ABORT: owned foreground field or expected contents mismatch."); return }
  trial += 1
  if trial==1 {delegate.toggle()}
  else {guard delegate.active,!delegate.pending,delegate.validTarget(),delegate.captureDiagnostics.trial==1 else {stop("FAIL: next word required another activation.");return}}
  guard delegate.active, delegate.validTarget() else { stop("FAIL: fixture activation did not preserve exact owned target."); return }
  if let listener = delegate.listener { OpenMTManager.shared().remove(listener); delegate.listener = nil }
  for point in Keyboard.path(trial == 2 ? "world" : "hello") { frame(point) }
  frame(nil)
  guard delegate.pending else { stop("FAIL: synthetic gesture produced no pending candidates."); return }
  guard delegate.captureDiagnostics.gateWaitFrames==0 else {stop("FAIL: first gesture still depends on an initial idle callback.");return}
  print("PASS: initial down/move/lift decoded without any synthetic initial idle frame.")
  let index = trial == 2 ? 1 : 0
  let button = delegate.buttons[index]
  guard !button.isHidden else { stop("FAIL: selected candidate control missing."); return }
  let chosen = button.title
  if trial==3 {frame(Point(0.4,0.5));guard delegate.contactGate.contactsPresent,delegate.pending else {stop("FAIL: held-contact candidate tracking.");return}}
  var range = CFRange()
  guard let rangeValue = delegate.attribute(field,kAXSelectedTextRangeAttribute), CFGetTypeID(rangeValue) == AXValueGetTypeID(), AXValueGetValue(unsafeDowncast(rangeValue,to:AXValue.self),.cfRange,&range), range.location >= 0, range.location + range.length <= (value as NSString).length else {stop("ABORT: owned selection range unavailable.");return}
  let expectedReceipt = (value as NSString).replacingCharacters(in:NSRange(location:range.location,length:range.length),with:chosen+" ")
  print("Owned insertion range: \(range.location), \(range.length)")
  print("Trial \(trial): synthetic path; candidate rank \(index+1) = \(chosen); posting actual mouse click."); fflush(stdout)
  Timer.scheduledTimer(withTimeInterval:0.2,repeats:false) { _ in
    MainActor.assumeIsolated {
      guard delegate.validTarget(), ownedField().map({CFEqual($0,field)}) == true else { stop("ABORT: focus changed before candidate click."); return }
      let center = button.convert(NSPoint(x:button.bounds.midX,y:button.bounds.midY),to:nil)
      let screenPoint = delegate.panel.convertPoint(toScreen:center)
      let point = CGPoint(x:screenPoint.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-screenPoint.y)
      guard let down = CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:point,mouseButton:.left), let up = CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:point,mouseButton:.left) else { stop("ABORT: cannot create candidate mouse event."); return }
      down.setIntegerValueField(.mouseEventClickState,value:1)
      up.setIntegerValueField(.mouseEventClickState,value:1)
      down.post(tap:.cghidEventTap)
      let releaseTimer = Timer(timeInterval:0.04,repeats:false) { _ in MainActor.assumeIsolated {
        guard ownedField().map({CFEqual($0,field)}) == true else {stop("ABORT: focus changed before mouse release.");return}
        up.post(tap:.cghidEventTap)
      }}
      RunLoop.main.add(releaseTimer,forMode:.eventTracking)
      RunLoop.main.add(releaseTimer,forMode:.default)
      Timer.scheduledTimer(withTimeInterval:0.2,repeats:false) { _ in
        MainActor.assumeIsolated {
          expected = expectedReceipt
          guard let current = ownedField(), CFEqual(current,field), let result = delegate.attribute(current,kAXValueAttribute) as? String else { stop("FAIL: candidate click stole focus; not reading any other field."); return }
          print("State after click: active=\(delegate.active), pending=\(delegate.pending), focus=\(String(describing:delegate.lastFocusPreserved)), menu=\(delegate.status.menu?.items.first?.title ?? "none"), range=\(String(describing:delegate.selection(current))), original=\(String(describing:delegate.originalSelection))")
          print("Trial \(trial) receipt: \(String(reflecting:result)); expected: \(String(reflecting:expected)); AX accepted: \(delegate.lastInsertionSucceeded == true)"); fflush(stdout)
          guard result==expected,delegate.active,!delegate.pending,delegate.validTarget(),delegate.captureDiagnostics.insertions==trial else {stop("FAIL: actual candidate click did not insert exactly once and rebase safely.");return}
          if trial==3 {
            guard delegate.waitForLift else {stop("FAIL: held candidate-selection contact was rearmed too early.");return}
            frame(Point(0.5,0.5));guard delegate.strokeSamples.isEmpty else {stop("FAIL: held contact started next word.");return}
            physicalLift(Point(0.5,0.5));frame(Point(0.2,0.2))
            guard delegate.strokeSamples.count==1,!delegate.waitForLift else {stop("FAIL: first fresh contact after lift swallowed.");return}
            physicalLift(Point(0.2,0.2));guard !delegate.waitForLift else {stop("FAIL: too-short completed lift required idle callback.");return}
            print("PASS: three words in one activation; held selection contact waits for actual lift; next first contact and too-short rearm work without fabricated idle.")
          }
          if trial < 3 { beginTrial() } else { secondaryChecks() }
        }
      }
    }
  }
}
Timer.scheduledTimer(withTimeInterval:0.3,repeats:false) { _ in MainActor.assumeIsolated {
  guard let textEdit = NSWorkspace.shared.runningApplications.first(where: {$0.bundleIdentifier == "com.apple.TextEdit"}) else {stop("ABORT: TextEdit unavailable."); return}
  guard let appURL = textEdit.bundleURL else {stop("ABORT: TextEdit URL unavailable.");return}
  let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true; configuration.createsNewApplicationInstance = false
  NSWorkspace.shared.open([document],withApplicationAt:appURL,configuration:configuration) { _,error in
    Task { @MainActor in
      guard error == nil else {stop("ABORT: owned document activation failed.");return}
      Timer.scheduledTimer(withTimeInterval:0.2,repeats:false) { _ in MainActor.assumeIsolated {
        guard let field = ownedField(), let baseline = delegate.attribute(field,kAXValueAttribute) as? String else {stop("ABORT: owned activated field unavailable.");return}
        expected = baseline
        if CommandLine.arguments.contains("--contact-guards-only") {overlayContactGuards()} else {beginTrial()}
      }}
    }
  }
} }
app.run()
