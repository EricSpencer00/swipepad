import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import SwipepadCore
import TrackpadBridge

// Real production capture/recognition/continuation handlers; memory-only target and mutation ports.
// No application launch, listener, permission request, event posting, external AX read or write.
final class MemoryInput:AppDelegate {
  let ownedField=AXUIElementCreateApplication(40001)
  let otherField=AXUIElementCreateApplication(40002)
  var pid:pid_t=40001
  var chosenField:AXUIElement?
  var missingFocus=false
  var value=""
  var caret=CFRange(location:0,length:0)
  var role="AXTextArea"
  var subrole=FieldSubrole.absent
  var editable=true
  var delayFirst=false
  var selectedTextWritable=true
  var valueWritable=true
  var rangeWritable=true
  var normalizeSeparator=false
  var trimSeparator=false
  var delayedValuePublication=false
  var rejectCaretSetter=false
  var staleValueOnce:String?
  var loseRangeOnceAfterSelection=false
  var rangeUnavailableOnce=false
  var attributeNamesSet:[String]=[]
  var attemptedWords:[String]=[]
  var acquireCount=0
  var metadataReads=0
  var beforeTargetValidation:(()->Void)?
  override func validTarget()->Bool {beforeTargetValidation?();return super.validTarget()}
  override var currentApplicationPID:pid_t? {pid}
  override func focused(_ pid:pid_t)->AXUIElement? {metadataReads += 1;return missingFocus ? nil:(chosenField ?? ownedField)}
  override func attribute(_ field:AXUIElement,_ name:String)->CFTypeRef? {
    metadataReads += 1
    if name==kAXValueAttribute,let stale=staleValueOnce {staleValueOnce=nil;return stale as CFString}
    return name==kAXValueAttribute ? value as CFString:nil
  }
  override func attributeWritable(_ field:AXUIElement,_ name:String)->Bool {metadataReads += 1;return editable && (name==kAXSelectedTextAttribute ? selectedTextWritable:(name==kAXValueAttribute ? valueWritable:rangeWritable))}
  override func fieldMetadata(_ field:AXUIElement)->(role:String?,subrole:FieldSubrole,writable:Bool) {metadataReads += 1;return (role,subrole,editable)}
  override func selection(_ field:AXUIElement)->CFRange? {metadataReads += 1;if rangeUnavailableOnce {rangeUnavailableOnce=false;return nil};return caret}
  override func acquireTarget()->Bool {acquireCount += 1;return super.acquireTarget()}
  override func setAttribute(_ field:AXUIElement,_ name:String,_ input:CFTypeRef)->AXError {
    guard CFEqual(field,ownedField),editable else {return .cannotComplete}
    attributeNamesSet.append(name)
    if name==kAXSelectedTextAttribute,let text=input as? String,
      let expected=TextReplacement.replacing(value,location:caret.location,length:caret.length,with:text) {
      attemptedWords.append(text);value=expected
      if delayFirst {delayFirst=false} else {caret=CFRange(location:caret.location+text.utf16.count,length:0)}
    } else if name==kAXValueAttribute,let text=input as? String {if delayedValuePublication {staleValueOnce=value};value=text.hasSuffix(" ") && trimSeparator ? String(text.dropLast()):(normalizeSeparator && text.hasSuffix(" ") ? String(text.dropLast())+"\u{00a0}":text)}
    else if name==kAXSelectedTextRangeAttribute,CFGetTypeID(input)==AXValueGetTypeID() {
      if rejectCaretSetter {return .cannotComplete}
      var range=CFRange();guard AXValueGetValue(unsafeDowncast(input,to:AXValue.self),.cfRange,&range) else {return .illegalArgument}
      if delayFirst {delayFirst=false} else {caret=range;if range.length>0 && loseRangeOnceAfterSelection {rangeUnavailableOnce=true}}
    } else {return .attributeUnsupported}
    return .success
  }
  func activate() {
    liftGraceSeconds=0 // Legacy immediate-handler cases; explicit grace cases below exercise the timer.
    active=true;inputProtectionHealthy=true;strokeSource = .screenOverlay;contactGate.reset();frameOrdering.reset(receivedAfter:0)
    gestureLexicon=GestureLexicon(words:["cat","world","test","hello","auto"])
  }
}
var checks=0
func check(_ value:Bool,_ label:String) {precondition(value,label);checks += 1;print("PASS: "+label)}
var time=ProcessInfo.processInfo.systemUptime,frameID:Int32=0
func frame(_ owner:MemoryInput,_ contacts:[(Int32,Point,OpenMTState)]) {
  frameID += 1;time += 0.01
  let event=OpenMTEvent();event.setValue(time,forKey:"timestamp");event.setValue(ProcessInfo.processInfo.systemUptime,forKey:"receivedAt");event.setValue(frameID,forKey:"frameID")
  event.setValue(contacts.map {id,p,state in let touch=OpenMTTouch();touch.setValue(id,forKey:"identifier");touch.setValue(state.rawValue,forKey:"state");touch.setValue(Float(p.x),forKey:"posX");touch.setValue(Float(p.y),forKey:"posY");return touch},forKey:"touches")
  owner.touchFrame(event)
}
func points(_ word:String)->[Point] {
  let centers=word.compactMap {Keyboard.keys[$0]};var result=[centers[0]]
  for (a,b) in zip(centers,centers.dropFirst()) {for i in 1...12 {let t=Double(i)/12;result.append(Point(a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t))}}
  return result
}
func word(_ owner:MemoryInput,_ value:String,id:Int32=1) {
  let p=points(value);for (i,point) in p.enumerated() {frame(owner,[(id,point,i==0 ? .starting:.touching)])};frame(owner,[(id,p.last!,.breaking)])
}
// Session-tap filtering must prevent text-view hover and cursor-region events from
// reaching the receiver. Absolute contact input remains independent of this pointer.
let hoverOwner=MemoryInput();hoverOwner.activate()
let hoverFilter=hoverOwner.cornerProtection
check(hoverFilter.blocksPointerAction(.mouseMoved),"active mouse motion is suppressed before receiving text-view hover")
for w in ["cat","world","auto"] {
 for (i,p) in points(w).enumerated() {
  let hoverEvent=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:CGPoint(x:i%2==0 ? 500:900,y:300),mouseButton:.left)!
  check(hoverFilter.blocksPointerAction(hoverEvent.type),"pointer crossing text region is absorbed while capture is On")
  frame(hoverOwner,[(1,p,i==0 ? .starting:.touching)])
 }
 frame(hoverOwner,[(1,points(w).last!,.breaking)])
}
check(hoverOwner.value=="cat world auto " && hoverOwner.active && hoverOwner.unresolvedWrites.isEmpty,"three words including straight auto continue across filtered pointer crossings")
hoverOwner.cancel("OFF")
check(!hoverFilter.blocksPointerAction(.mouseMoved) && !hoverFilter.blocksPointerAction(.leftMouseDown),"normal pointer and clicks resume outside capture")
for (role,subrole) in [("AXTextArea",FieldSubrole.absent),("AXTextField",.absent),("AXTextField",.named("AXUnknown")),("AXTextField",.named("AXSearchField")),("AXComboBox",.named("AXUnknown"))] {
 let owner=MemoryInput();owner.role=role;owner.subrole=subrole;owner.activate()
 for _ in 0..<3 {for w in ["cat","world","test"] {word(owner,w)}}
 check(owner.value==String(repeating:"cat world test ",count:3),"nine successive words in capability model "+role)
 check(owner.active && !owner.pending && owner.unresolvedWrites.isEmpty,"repeat stays On and resolves each transaction")
 check(owner.captureDiagnostics.writeAttempts==9 && owner.captureDiagnostics.insertions==9,"one attempt and one confirmed insertion per completed word")
 check(owner.acquireCount==9 && owner.caret.location==owner.value.utf16.count,"each new stroke reacquires exact fresh caret")
 check(!owner.waitForLift && owner.finger==nil,"completed lift needs no extra idle frame or candidate click")
}
let valueOnly=MemoryInput();valueOnly.activate();valueOnly.selectedTextWritable=false
word(valueOnly,"cat");word(valueOnly,"world");word(valueOnly,"test")
check(valueOnly.value=="cat world test " && valueOnly.captureDiagnostics.insertions==3,"production whole-value/caret fallback repeats when selected-text is unavailable")
check(valueOnly.attributeNamesSet==Array(repeating:[kAXValueAttribute,kAXSelectedTextRangeAttribute],count:3).flatMap{$0},"fallback performs one value mutation and one caret update per word")
let directOnly=MemoryInput();directOnly.activate();directOnly.valueWritable=false;directOnly.rangeWritable=false
word(directOnly,"cat");word(directOnly,"world")
check(directOnly.value=="cat world " && directOnly.attributeNamesSet==[kAXSelectedTextAttribute,kAXSelectedTextAttribute],"selected-text-only provider still repeats without whole-value capability")
let preferred=MemoryInput();preferred.activate();word(preferred,"cat");word(preferred,"world")
check(preferred.attributeNamesSet==[kAXValueAttribute,kAXSelectedTextRangeAttribute,kAXValueAttribute,kAXSelectedTextRangeAttribute],"production writer selects verified value/caret when both AX backends exist")
let delayed=MemoryInput();delayed.activate();delayed.delayFirst=true
let a=points("cat"),b=points("world")
for (i,p) in a.enumerated() {frame(delayed,[(1,p,i==0 ? .starting:.touching)])}
frame(delayed,[(1,a.last!,.breaking),(2,b[0],.starting)])
check(delayed.pending && delayed.finger==2 && delayed.strokeSamples.first!.point.distance(b[0])<0.000001,"delayed first word plus mixed lift/newtouch preserves second initial letter")
for p in b.dropFirst() {frame(delayed,[(2,p,.touching)])};frame(delayed,[(2,b.last!,.breaking)]);word(delayed,"test",id:3)
check(delayed.value=="cat " && delayed.queuedWords.count==2 && delayed.captureDiagnostics.writeAttempts==1,"two fast next words queue while accepted mutation caret is unresolved")
RunLoop.current.run(until:Date().addingTimeInterval(0.30))
check(delayed.value=="cat " && delayed.unresolvedWrites.count==1,"old caret beyond250ms cannot produce another write")
delayed.caret=CFRange(location:4,length:0)
RunLoop.current.run(until:Date().addingTimeInterval(0.18))
check(delayed.value=="cat world test " && delayed.captureDiagnostics.writeAttempts==3,"late exact caret drains queue once in correct order")
check(!delayed.pending && delayed.unresolvedWrites.isEmpty && delayed.active,"delayed continuation returns ready without turning Off")
word(delayed,"hello",id:3);check(delayed.value=="cat world test hello ","next gesture after drain works with reused contact identifier")
let stale=MemoryInput();stale.activate();stale.delayFirst=true;word(stale,"cat");stale.cancel("Manual input")
word(stale,"world");check(stale.value=="cat " && stale.unresolvedWrites.count==1 && stale.captureDiagnostics.writeAttempts==1,"sticky cancellation preserves unresolved same-field mutation and blocks fresh word")
check(stale.captureDiagnostics.lastTargetRefusal=="unresolvedPreviousWrite","blocked transaction has concrete persistent diagnostic reason")
frame(stale,[]);stale.caret=CFRange(location:4,length:0);word(stale,"world");check(stale.value=="cat world ","settled exact caret permits later fresh stroke once")
let changed=MemoryInput();changed.activate();let p=points("cat")
for point in p.prefix(4) {frame(changed,[(1,point,.touching)])}
frame(changed,[]); // ambiguous activation contact must lift, then start fresh
for point in p.prefix(4) {frame(changed,[(1,point,.starting)])}
changed.chosenField=changed.otherField;frame(changed,[(1,p[5],.touching)]);frame(changed,[(1,p.last!,.breaking)])
check(changed.value.isEmpty && changed.captureDiagnostics.writeAttempts==0 && changed.active,"midstroke field switch cancels with zero writes while mode remains On")
let regressed=MemoryInput();regressed.activate();word(regressed,"cat");regressed.unresolvedWrites.append(AppDelegate.UnresolvedWrite(id:UUID(),field:regressed.otherField,pid:40099,originalRange:CFRange(location:0,length:0),beforeDigest:nil,expectedCaret:4,expectedDigest:nil));regressed.caret=CFRange(location:0,length:0);word(regressed,"world")
check(regressed.value=="cat " && regressed.captureDiagnostics.writeAttempts==1,"stale confirmed caret cannot prepend next word even with unrelated-process uncertainty")
check(regressed.captureDiagnostics.lastTargetRefusal=="verifiedContinuationChanged","confirmed-anchor refusal persists in diagnostics")
regressed.caret=CFRange(location:4,length:0);word(regressed,"world");check(regressed.value=="cat world ","restored verified anchor permits next fresh word without extra idle")
let secure=MemoryInput();secure.activate();secure.role="AXTextField";secure.subrole = .named("AXSecureTextField");word(secure,"cat")
check(secure.value.isEmpty && secure.captureDiagnostics.writeAttempts==0,"secure metadata rejected before any model mutation")
check(!secure.active && !secure.pending && secure.captureDiagnostics.lastTargetRefusal=="secureField","secure context exits capture without relying on blocked Escape delivery")
let secureTransition=MemoryInput();secureTransition.activate();secureTransition.delayFirst=true;word(secureTransition,"cat");let secureUncertainty=secureTransition.unresolvedWrites.first!.id
secureTransition.subrole = .named("AXSecureTextField");check(secureTransition.secureContextActive(),"secure transition detected without reading field text")
secureTransition.exitSecureContext()
check(!secureTransition.active && secureTransition.unresolvedWrites.first?.id==secureUncertainty && secureTransition.captureDiagnostics.writeAttempts==1,"secure exit releases capture and retains accepted uncertain write without replay")
let pidChanged=MemoryInput();pidChanged.activate();check(pidChanged.acquireTarget(),"original model target acquired");pidChanged.pid=40002
check(!pidChanged.identity(pidChanged.ownedField,pid:40001),"identity compares caller original PID even if fake element remains equal")
let rebuilt=MemoryInput();rebuilt.activate();rebuilt.delayFirst=true;word(rebuilt,"cat");rebuilt.chosenField=rebuilt.otherField
check(!rebuilt.permitsResolvedWrite(rebuilt.otherField,pid:40001,range:rebuilt.caret),"replaced/sibling AX reference cannot bypass same-process unresolved write")
check(rebuilt.captureDiagnostics.lastTargetRefusal=="unresolvedOriginalField","changed reference reports original unresolved-field guard")
let failed=MemoryInput();failed.activate();failed.delayFirst=true;word(failed,"cat");failed.cancel("Manual input")
failed.target=failed.ownedField;failed.originalPID=40001;failed.originalSelection=failed.caret
check(!failed.insertWord("world",alternatives:["world"]),"pre-mutation refusal does not accept a new word")
check(!failed.pending && failed.pendingWriteID==nil && failed.unresolvedWrites.count==1,"failed fresh attempt does not bind its poll to an older accepted write")
let during=MemoryInput();during.activate();during.delayFirst=true;word(during,"cat");word(during,"world",id:2)
let third=points("test");for (i,p) in third.prefix(6).enumerated() {frame(during,[(3,p,i==0 ? .starting:.touching)])}
let captured=during.strokeSamples;during.caret=CFRange(location:4,length:0);RunLoop.current.run(until:Date().addingTimeInterval(0.12))
check(!during.pending && during.finger==3 && during.strokeSamples==captured,"late confirmation preserves an in-progress next stroke")
check(during.queuedWords.count==1 && during.captureDiagnostics.writeAttempts==1 && during.value=="cat ","queue cannot drain or rebind target while contact is down")
for p in third.dropFirst(6) {frame(during,[(3,p,.touching)])};frame(during,[(3,third.last!,.breaking)])
check(during.value=="cat world test " && during.captureDiagnostics.writeAttempts==3,"final lift releases queued words in order after in-progress stroke completes")
let generation=MemoryInput();generation.activate();generation.delayFirst=true;word(generation,"cat");generation.cancel("OFF");generation.sessionGeneration += 1;generation.activate();word(generation,"world")
RunLoop.current.run(until:Date().addingTimeInterval(0.12))
check(generation.value=="cat " && generation.unresolvedWrites.count==1,"new activation/late old poll cannot discard or bypass accepted unresolved word")
check(delayed.captureDiagnostics.confirmationIdentityMatches == true && delayed.captureDiagnostics.confirmationCaretMatches == true && delayed.captureDiagnostics.confirmationContentMatches == true,"confirmation exposes boolean receipt evidence without logging text or fingerprints")
let rejectedNext=MemoryInput();rejectedNext.activate();rejectedNext.delayFirst=true;word(rejectedNext,"cat");word(rejectedNext,"world",id:2)
let shortPoint=Point(0.5,0.5);frame(rejectedNext,[(3,shortPoint,.starting)]);frame(rejectedNext,[(3,shortPoint,.touching)])
rejectedNext.caret=CFRange(location:4,length:0);RunLoop.current.run(until:Date().addingTimeInterval(0.12))
check(rejectedNext.queuedWords.count==1 && rejectedNext.finger==3,"queued word waits safely during next short contact")
frame(rejectedNext,[(3,shortPoint,.breaking)])
check(rejectedNext.value=="cat world " && rejectedNext.queuedWords.isEmpty && rejectedNext.captureDiagnostics.writeAttempts==2,"rejected next stroke releases prior valid queued word without needing another gesture")
for failure in ["noMatch","noContact"] {
 let held=MemoryInput();held.activate();held.delayFirst=true;word(held,"cat");word(held,"world",id:2)
 let initial=failure=="noMatch" ? Point(1.2,0.5):Point(0.5,0.5)
 frame(held,[(3,initial,.starting)]);held.caret=CFRange(location:4,length:0);RunLoop.current.run(until:Date().addingTimeInterval(0.12))
 if failure=="noMatch" {frame(held,[(3,Point(1.3,0.7),.touching)]);frame(held,[(3,Point(1.4,0.8),.touching)]);frame(held,[(3,Point(1.4,0.8),.breaking)])}
 else {frame(held,[(3,initial,.hovering)])}
 check(held.value=="cat world " && held.queuedWords.isEmpty && held.captureDiagnostics.writeAttempts==2,"prior valid queue drains after "+failure+" without an invented next word")
}
let escaped=MemoryInput();escaped.activate();let escapedPath=points("cat")
for (i,p) in escapedPath.prefix(5).enumerated() {frame(escaped,[(1,p,i==0 ? .starting:.touching)])}
let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:time,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:53)!
escaped.handle(escape);frame(escaped,[(1,escapedPath.last!,.breaking)])
check(!escaped.active && escaped.value.isEmpty && escaped.finger==nil,"native event handler Escape exits mode and cancels partial stroke")
word(escaped,"world",id:2);check(escaped.value.isEmpty,"contact after Escape cannot write while Off")
escaped.activate();word(escaped,"world",id:3);check(escaped.value=="world ","fresh activation after Escape accepts next word")
let idleEscape=MemoryInput();idleEscape.activate();idleEscape.handle(escape)
check(!idleEscape.active && idleEscape.captureDiagnostics.writeAttempts==0,"Escape exits idle capture without writing")
let pendingEscape=MemoryInput();pendingEscape.activate();pendingEscape.delayFirst=true;word(pendingEscape,"cat");word(pendingEscape,"world",id:2)
let retainedWrite=pendingEscape.unresolvedWrites.first!.id
pendingEscape.handle(escape)
check(!pendingEscape.active && !pendingEscape.pending && pendingEscape.queuedWords.isEmpty && pendingEscape.pendingWriteID==nil,"Escape drops unsent queue and stops polling")
check(pendingEscape.value=="cat " && pendingEscape.unresolvedWrites.first?.id==retainedWrite,"Escape preserves accepted unconfirmed mutation without replay")
pendingEscape.caret=CFRange(location:4,length:0);RunLoop.current.run(until:Date().addingTimeInterval(0.12))
check(pendingEscape.value=="cat " && pendingEscape.captureDiagnostics.writeAttempts==1,"late caret poll after Escape cannot write queued word")
pendingEscape.activate();word(pendingEscape,"test",id:3)
check(pendingEscape.value=="cat test " && pendingEscape.unresolvedWrites.isEmpty,"new activation reconciles exact accepted receipt then writes fresh word only")
let tapEscape=MemoryInput();tapEscape.activate();tapEscape.delayFirst=true;word(tapEscape,"cat");word(tapEscape,"world",id:2)
let tapUncertain=tapEscape.unresolvedWrites.first!.id
check(tapEscape.cornerProtection.handleCaptureKey(.keyDown,keyCode:53) && !tapEscape.active && tapEscape.queuedWords.isEmpty,"capture filter consumes Escape while exiting and dropping unsent words")
check(tapEscape.unresolvedWrites.first?.id==tapUncertain && !tapEscape.cornerProtection.handleCaptureKey(.keyDown,keyCode:53),"consumed Escape preserves uncertain write and normal Escape resumes while Off")
let capacity=MemoryInput();capacity.activate();capacity.delayFirst=true;word(capacity,"cat")
for id in 2...9 {word(capacity,"world",id:Int32(id))}
let overflow=points("test");for (i,p) in overflow.prefix(6).enumerated() {frame(capacity,[(10,p,i==0 ? .starting:.touching)])}
capacity.caret=CFRange(location:4,length:0);RunLoop.current.run(until:Date().addingTimeInterval(0.12))
check(capacity.queuedWords.count==8 && !capacity.pending && capacity.finger==10,"full queue waits for tracked next stroke after prior receipt settles")
for p in overflow.dropFirst(6) {frame(capacity,[(10,p,.touching)])};frame(capacity,[(10,overflow.last!,.breaking)])
check(capacity.value=="cat "+String(repeating:"world ",count:8) && capacity.queuedWords.isEmpty && capacity.captureDiagnostics.writeAttempts==9,"queue-cap refusal releases eight earlier valid words instead of permanent stall")
let protection=MemoryInput();protection.activate();protection.delayFirst=true;word(protection,"cat");let uncertainty=protection.unresolvedWrites.first!.id
protection.cornerProtection.failed()
check(!protection.active && !protection.inputProtectionHealthy && protection.captureDiagnostics.stage=="inputProtectionPaused" && protection.captureDiagnostics.inputProtectionFailures==1,"corner-filter failure turns capture Off and releases ordinary input")
word(protection,"world")
check(protection.value=="cat " && protection.captureDiagnostics.writeAttempts==1 && protection.unresolvedWrites.first?.id==uncertainty,"protection failure cannot write, discard uncertainty or pass new contact into insertion")
check(!protection.validTarget() && !protection.insertWord("world",alternatives:["world"]),"protection failure cannot resume delivery without explicit activation")
let normalized=MemoryInput();normalized.activate();normalized.normalizeSeparator=true
word(normalized,"cat");word(normalized,"world");word(normalized,"auto")
check(normalized.value=="cat\u{00a0}world\u{00a0}auto\u{00a0}" && normalized.captureDiagnostics.insertions==3 && normalized.unresolvedWrites.isEmpty,"exact new-separator NBSP receipt confirms repeated words and rebases exact bytes")
let changedReceipt=MemoryInput();changedReceipt.activate();changedReceipt.delayFirst=true;word(changedReceipt,"cat");let receipt=changedReceipt.unresolvedWrites.first!
changedReceipt.value="bat\u{00a0}";changedReceipt.caret=CFRange(location:4,length:0)
check(!changedReceipt.permitsResolvedWrite(changedReceipt.ownedField,pid:40001,range:changedReceipt.caret,resolvePending:true),"separator alternate never accepts changed letter outside newly generated separator")
changedReceipt.value="cat\u{00a0}";changedReceipt.caret=CFRange(location:3,length:0)
check(!changedReceipt.permitsResolvedWrite(changedReceipt.ownedField,pid:40001,range:changedReceipt.caret,resolvePending:true),"separator alternate still requires exact collapsed UTF16 caret")
let trimmed=MemoryInput();trimmed.activate();trimmed.trimSeparator=true
for _ in 0..<3 {for w in ["cat","world","auto"] {word(trimmed,w)}}
check(trimmed.value==String(repeating:"cat world auto ",count:3).trimmingCharacters(in:.whitespaces) && trimmed.captureDiagnostics.insertions==9 && trimmed.unresolvedWrites.isEmpty,"AX-trimmed generated terminal separator uses leading next-word separation with exact receipt and caret")
check(trimmed.continuationAnchor?.trimmedSeparator==true && trimmed.caret.location==trimmed.value.utf16.count,"trim receipt anchors exact observed caret and bytes")
trimmed.active=false
let last=trimmed.lastOwnedWord!
trimmed.lastOwnedWord=AppDelegate.OwnedWord(field:last.field,pid:last.pid,range:last.range,alternatives:["auto","cat","world"],fingerprint:last.fingerprint,leadingSeparator:last.leadingSeparator)
let alternative=NSButton(title:"cat",target:nil,action:nil);trimmed.selectCandidate(alternative)
check(trimmed.value.hasSuffix("world cat") && trimmed.unresolvedWrites.isEmpty,"trimmed last-word correction replaces owned leading separator plus word")
alternative.title="world";trimmed.selectCandidate(alternative)
check(trimmed.value.hasSuffix("world world") && trimmed.unresolvedWrites.isEmpty,"second trimmed correction resolves exact fresh transaction")
trimmed.cancel("OFF");trimmed.activate();word(trimmed,"cat")
check(trimmed.value.hasSuffix("world world cat") && trimmed.unresolvedWrites.isEmpty,"verified trimmed separator survives exit/reactivation without merging words")
trimmed.cancel("Application changed");word(trimmed,"auto")
check(trimmed.value.hasSuffix("world cat auto"),"confirmed delimiter metadata survives cancellation without preserving stale write authority")
check(!trimmed.leadingSeparatorNeeded(trimmed.otherField,pid:40001,range:trimmed.caret) && !trimmed.leadingSeparatorNeeded(trimmed.ownedField,pid:40002,range:trimmed.caret),"cached delimiter never applies to another PID or field")
let goodCaret=trimmed.caret
check(!trimmed.leadingSeparatorNeeded(trimmed.ownedField,pid:40001,range:CFRange(location:0,length:0)),"cached delimiter ignores changed caret")
trimmed.value += "x"
check(!trimmed.leadingSeparatorNeeded(trimmed.ownedField,pid:40001,range:goodCaret),"cached delimiter ignores any changed full-field content")
let unknownProtection=MemoryInput();unknownProtection.activate();unknownProtection.subrole = .unreadable;word(unknownProtection,"cat")
check(!unknownProtection.active && unknownProtection.captureDiagnostics.writeAttempts==0 && unknownProtection.captureDiagnostics.lastTargetRefusal=="protectionMetadataUnavailable","unreadable protection metadata exits capture with zero writes")
let escapeOwnership=MemoryInput();escapeOwnership.activate();word(escapeOwnership,"cat");escapeOwnership.cornerProtection.handleCaptureKey(.keyDown,keyCode:53)
check(!escapeOwnership.active && escapeOwnership.lastOwnedWord != nil,"Escape retains confirmed correction ownership like doubleCommand")
let correctionError=MemoryInput();correctionError.activate();word(correctionError,"cat");correctionError.cancel("OFF");correctionError.loseRangeOnceAfterSelection=true
let correction=NSButton(title:"cat",target:nil,action:nil);correctionError.selectCandidate(correction)
check(correctionError.value=="cat " && correctionError.caret.location==4 && correctionError.caret.length==0 && correctionError.unresolvedWrites.isEmpty,"prewrite correction refusal restores original collapsed caret instead of leaving old word selected")
let uncertainCorrection=MemoryInput();uncertainCorrection.activate();word(uncertainCorrection,"cat");uncertainCorrection.delayFirst=true;word(uncertainCorrection,"world");let heldTransaction=uncertainCorrection.unresolvedWrites.first!.id
uncertainCorrection.value="cat ";uncertainCorrection.cornerProtection.handleCaptureKey(.keyDown,keyCode:53)
let priorAttributeCount=uncertainCorrection.attributeNamesSet.count;uncertainCorrection.selectCandidate(correction)
check(uncertainCorrection.attributeNamesSet.count==priorAttributeCount && uncertainCorrection.caret.length==0 && uncertainCorrection.unresolvedWrites.first?.id==heldTransaction,"unresolved prior mutation rejects correction before selecting or writing old word")
let utf=MemoryInput();utf.activate();utf.value="😀";utf.caret=CFRange(location:2,length:0);word(utf,"cat");word(utf,"world")
check(utf.value=="😀cat world " && utf.caret.location==12,"repeated insertion rebases UTF16 caret after surrogate pair")
let delayedValue=MemoryInput();delayedValue.activate();delayedValue.trimSeparator=true;delayedValue.delayedValuePublication=true
for _ in 0..<3 {for w in ["cat","world","auto"] {word(delayedValue,w);RunLoop.current.run(until:Date().addingTimeInterval(0.08))}}
check(delayedValue.value==String(repeating:"cat world auto ",count:3).trimmingCharacters(in:.whitespaces) && delayedValue.captureDiagnostics.insertions==9 && delayedValue.unresolvedWrites.isEmpty,"delayed AXValue publication settles exact trimmed receipt before one caret attempt per word")
check(delayedValue.attributeNamesSet.filter {$0==kAXValueAttribute}.count==9 && delayedValue.attributeNamesSet.filter {$0==kAXSelectedTextRangeAttribute}.count==9,"delayed publication never retries text or caret mutations")
let movedWhilePublishing=MemoryInput();movedWhilePublishing.activate();movedWhilePublishing.delayedValuePublication=true
_ = movedWhilePublishing.replaceSelectedText(movedWhilePublishing.ownedField,pid:40001,range:movedWhilePublishing.caret,inserted:"cat ")
let deferredID=movedWhilePublishing.unresolvedWrites.first!.id;movedWhilePublishing.caret=CFRange(location:1,length:0)
_ = movedWhilePublishing.settleDeferredCaret(deferredID)
check(movedWhilePublishing.attributeNamesSet==[kAXValueAttribute] && movedWhilePublishing.unresolvedWrites.count==1,"manual caret change blocks deferred caret placement and retains accepted write without replay")
let caretRejected=MemoryInput();caretRejected.activate();caretRejected.rejectCaretSetter=true
_ = caretRejected.replaceSelectedText(caretRejected.ownedField,pid:40001,range:caretRejected.caret,inserted:"cat ")
let rejectedID=caretRejected.unresolvedWrites.first!.id
for _ in 0..<3 {_ = caretRejected.settleDeferredCaret(rejectedID)}
check(caretRejected.attributeNamesSet==[kAXValueAttribute,kAXSelectedTextRangeAttribute] && caretRejected.unresolvedWrites.count==1,"failed own caret attempt remains guarded and is never repeated")
let graceWords=MemoryInput();graceWords.activate();graceWords.liftGraceSeconds=0.22
word(graceWords,"cat");check(graceWords.captureDiagnostics.writeAttempts==0 && graceWords.deferredLift != nil,"word waits bounded release grace instead of committing an interrupted contact")
word(graceWords,"world");check(graceWords.value=="cat " && graceWords.deferredLift != nil,"distant immediate next word commits old word and preserves separate stroke")
RunLoop.current.run(until:Date().addingTimeInterval(0.26))
check(graceWords.value=="cat world " && graceWords.captureDiagnostics.writeAttempts==2 && graceWords.active,"final release commits once after grace, capture remains On")
frame(graceWords,[]);RunLoop.current.run(until:Date().addingTimeInterval(0.25))
check(graceWords.captureDiagnostics.writeAttempts==2,"empty frames and expired release timer cannot duplicate writes")
for sign in [1.0,-1.0] {
 let bounce=MemoryInput();bounce.activate();bounce.liftGraceSeconds=0.22
 let base=sign>0 ? Point(0.8,0.2):Point(0.2,0.8)
 let first=Point(base.x-sign*0.1,base.y+sign*0.1),end=Point(base.x-sign*0.2,base.y+sign*0.2)
 frame(bounce,[(7,base,.making)]);frame(bounce,[(7,first,.touching)]);frame(bounce,[(7,end,.breaking)])
 let before=bounce.strokeSamples.map(\.point),token=bounce.strokeToken
 let rejoin=Point(end.x-sign*0.005,end.y+sign*0.005),next=Point(end.x-sign*0.015,end.y+sign*0.015)
 frame(bounce,[(8,rejoin,.making)]);frame(bounce,[(8,next,.touching)])
 check(bounce.deferredLift==nil && bounce.finger==8 && bounce.strokeToken==token && bounce.bounceCount==1,"mirrored diagonal contact-ID bounce reconnects same stroke after real directional movement")
 check(bounce.strokeSamples.count==before.count+2 && zip(bounce.strokeSamples.map(\.point),before+[rejoin,next]).allSatisfy({$0.distance($1)<0.000001}),"bounce retains raw release/recontact points without extrapolation")
 bounce.cancel("OFF");RunLoop.current.run(until:Date().addingTimeInterval(0.25))
 check(bounce.captureDiagnostics.writeAttempts==0,"cancel retires pending grace timer without write")
}
let tapSeparate=MemoryInput();tapSeparate.activate();tapSeparate.liftGraceSeconds=0.1
frame(tapSeparate,[(1,Keyboard.keys["a"]!,.making)]);frame(tapSeparate,[(1,Keyboard.keys["a"]!,.breaking)])
frame(tapSeparate,[(2,Keyboard.keys["a"]!,.making)]);frame(tapSeparate,[(2,Keyboard.keys["a"]!,.breaking)])
RunLoop.current.run(until:Date().addingTimeInterval(0.14))
check(tapSeparate.value=="a a ","quick stationary separate letter taps are never bounce-merged")
let cancelGrace=MemoryInput();cancelGrace.activate();cancelGrace.liftGraceSeconds=0.12;word(cancelGrace,"auto");cancelGrace.cancel("OFF")
RunLoop.current.run(until:Date().addingTimeInterval(0.16));check(cancelGrace.captureDiagnostics.writeAttempts==0,"Escape/cancel before grace expiry drops the uncommitted word")
let caretGrace=MemoryInput();caretGrace.activate();caretGrace.liftGraceSeconds=0.12;word(caretGrace,"cat");caretGrace.caret=CFRange(location:1,length:0)
RunLoop.current.run(until:Date().addingTimeInterval(0.16));check(caretGrace.captureDiagnostics.writeAttempts==0,"caret changed during release grace prevents the scheduled word write")
let repeats=MemoryInput();repeats.activate();repeats.liftGraceSeconds=0.22
var moving=Point(0.9,0.1);frame(repeats,[(1,moving,.making)]);moving=Point(0.8,0.2);frame(repeats,[(1,moving,.touching)])
let originalToken=repeats.strokeToken
for id in 2...4 {
 frame(repeats,[(Int32(id-1),moving,.breaking)])
 let first=Point(moving.x-0.005,moving.y+0.005);moving=Point(moving.x-0.02,moving.y+0.02)
 frame(repeats,[(Int32(id),first,.making)]);frame(repeats,[(Int32(id),moving,.touching)])
}
check(repeats.bounceCount==3 && repeats.strokeToken==originalToken,"three repeated contact dropouts reconnect without retiring the stroke token")
frame(repeats,[(4,moving,.breaking)]);frame(repeats,[(5,Point(moving.x-0.005,moving.y+0.005),.making)])
check(repeats.strokeToken>originalToken && repeats.deferredLift==nil,"fourth dropout closes old stroke and starts a distinct bounded retry")
repeats.cancel("OFF")
let buttonOwner=MemoryInput();buttonOwner.activate();let balance=buttonOwner.cornerProtection
check(!balance.handlePointer(.leftMouseUp,button:0),"release of a pre-existing unowned button is never swallowed")
check(balance.handlePointer(.leftMouseDown,button:0) && balance.capturedButtons==[0],"capture owns only swallowed button downs")
buttonOwner.cancel("OFF")
check(!balance.handlePointer(.mouseMoved,button:0) && !balance.handleCaptureKey(.keyDown,keyCode:53),"pointer and normal Escape resume immediately on exit without a warp")
check(balance.handlePointer(.leftMouseDragged,button:0),"drag after swallowed down stays suppressed until its real release")
check(balance.handlePointer(.leftMouseUp,button:0) && balance.capturedButtons.isEmpty,"owned release is consumed once after exit, without a fabricated mouse event")
check(!balance.handlePointer(.leftMouseDown,button:0) && !balance.handlePointer(.leftMouseUp,button:0) && !balance.handlePointer(.leftMouseDragged,button:0),"ordinary post-exit click drag and release all pass through")
buttonOwner.activate();check(balance.handlePointer(.rightMouseDown,button:1) && balance.handlePointer(.otherMouseDown,button:2),"right and auxiliary swallowed buttons tracked independently")
buttonOwner.cancel("OFF");check(balance.handlePointer(.rightMouseUp,button:1) && balance.capturedButtons==[2],"one release cannot clear another held button")
check(balance.handlePointer(.otherMouseUp,button:2) && balance.capturedButtons.isEmpty,"last auxiliary release removes tail filter ownership")
let noFocus=MemoryInput();noFocus.missingFocus=true
check(!noFocus.acquireTarget() && !noFocus.active && noFocus.listener==nil,"missing focused input refuses admission while capture remains Off")
check(!noFocus.cornerProtection.handlePointer(.leftMouseDown,button:0),"refused Off admission leaves ordinary pointer clicks usable")
check(noFocus.captureDiagnostics.firstTargetRefusal=="missingFocusedField" && noFocus.captureDiagnostics.targetAttempts==1 && noFocus.captureDiagnostics.targetAdmissions==0,"first missing-target failure and zero admissions remain structurally observable")
noFocus.missingFocus=false
check(noFocus.acquireTarget() && noFocus.captureDiagnostics.targetAdmissions==1 && noFocus.captureDiagnostics.firstTargetRefusal=="missingFocusedField","later safe target admission does not erase the first failure receipt")
let refusedSecure=MemoryInput();refusedSecure.subrole = .named("AXSecureTextField")
check(!refusedSecure.acquireTarget() && refusedSecure.captureDiagnostics.writeAttempts==0 && !refusedSecure.active,"secure input admission remains Off with zero writes")
print("Passed \(checks) offscreen production repeat-handler checks. Memory-only AX attribute ports with production writer; no real AX/event transport, physical capture, TextEdit or Codex acceptance claim.")

// Lightweight snapshots must not qualify/read/reconcile the field or forget uncertainty.
let light=MemoryInput();light.activate();light.delayFirst=true;word(light,"cat")
light.captureIdentityCache="headless-fixture-identity"
let lightID=light.unresolvedWrites.first!.id,lightRequests=light.captureDiagnostics.axRequests
let lightAttempts=light.captureDiagnostics.writeAttempts,lightAdmissions=light.captureDiagnostics.targetAdmissions,lightReads=light.metadataReads
let snapshot=light.captureStatusReport()
check(snapshot.scope.hasPrefix("Live capture counters") && snapshot.checks.isEmpty && snapshot.runtimeIdentity=="headless-fixture-identity","counter snapshot does not validate signature or rerun doctor qualification")
check(light.metadataReads==lightReads && light.captureDiagnostics.axRequests==lightRequests && light.captureDiagnostics.writeAttempts==lightAttempts && light.captureDiagnostics.targetAdmissions==lightAdmissions && light.unresolvedWrites.first?.id==lightID,"counter snapshot preserves transaction with no AX or admission/write side effects")
check(snapshot.outstandingWrites?.first?.transactionID==lightID.uuidString && snapshot.outstandingWrites?.first?.mutationAccepted==true && snapshot.outstandingWrites?.first?.caretAttemptPending==false,"counter snapshot describes accepted transaction and retired caret attempt without content or digest")
let delayedFrame=MemoryInput();delayedFrame.activate()
let delayedEvent=OpenMTEvent();delayedEvent.setValue(ProcessInfo.processInfo.systemUptime+10000,forKey:"timestamp");delayedEvent.setValue(ProcessInfo.processInfo.systemUptime-0.02,forKey:"receivedAt");delayedEvent.setValue(Int32(1),forKey:"frameID");delayedEvent.setValue([OpenMTTouch](),forKey:"touches")
delayedFrame.touchFrame(delayedEvent)
check(delayedFrame.captureDiagnostics.maximumCallbackDelayMilliseconds>=19,"callback delay uses host receipt clock even when device clock has a different epoch")
let measured=delayedFrame.measureAX {42}
check(measured==42 && delayedFrame.captureDiagnostics.axRequests==1 && delayedFrame.captureDiagnostics.maximumAXMilliseconds>=0,"AX instrumentation preserves request return and records structural duration")
print("PASS additional lightweight diagnostics regressions; total",checks)

let directReceipt=MemoryInput();directReceipt.activate();directReceipt.valueWritable=false;directReceipt.delayFirst=true;word(directReceipt,"cat")
directReceipt.captureIdentityCache="headless-fixture-identity"
check(directReceipt.captureStatusReport().outstandingWrites?.first?.mutationAccepted==true && directReceipt.captureDiagnostics.insertions==0,"selected-text AX acknowledgement is reported separately from unconfirmed insertion")
print("PASS final structural diagnostics checks; total",checks)

let resetEvidence=MemoryInput();resetEvidence.activate();resetEvidence.resetStrokeForRetry("Multiple fingers · lift, then swipe one word")
check(resetEvidence.captureDiagnostics.resetReasons["multipleContacts"]==1,"multicontact reset is separately counted without recording contact coordinates")
resetEvidence.target=resetEvidence.ownedField;resetEvidence.originalPID=resetEvidence.pid;resetEvidence.originalSelection=resetEvidence.caret;resetEvidence.missingFocus=true
check(!resetEvidence.validTarget() && resetEvidence.captureDiagnostics.focusRejection=="focusUnavailable","missing authoritative focus has a structural rejection category")
resetEvidence.cancel("Field changed · next fresh swipe uses the current field")
check(resetEvidence.captureDiagnostics.cancelReasons["focusUnavailable"]==1,"active cancellation records the bounded structural focus category")
resetEvidence.cancel("Keyboard input · next swipe uses the current field")
check(resetEvidence.captureDiagnostics.cancelReasons["keyboardInput"]==1 && resetEvidence.captureDiagnostics.cancelReasons["focusUnavailable"]==1,"later keyboard cancellation does not inherit a previous focus rejection")
resetEvidence.captureDiagnostics.focusRejection="selectionChangedOrUnavailable"
resetEvidence.cancel("Stroke too long; cancelled")
check(resetEvidence.captureDiagnostics.cancelReasons["otherCaptureCancel"]==1 && resetEvidence.captureDiagnostics.cancelReasons["selectionChangedOrUnavailable"]==nil,"unrelated cancellation does not consume stale focus metadata as its cause")
var observing=true,passedScrolls=0
let scrollObserver=HotCornerProtection(isActive:{observing},failed:{},escapePressed:{},observedScroll:{passedScrolls += 1})
check(!scrollObserver.handlePointer(.scrollWheel,button:0) && passedScrolls==1,"active scroll observation passes the event without new suppression")
observing=false
check(!scrollObserver.handlePointer(.scrollWheel,button:0) && passedScrolls==1,"Off scroll events remain unchanged and uncounted")
check(delayedFrame.captureDiagnostics.totalAXMilliseconds>=delayedFrame.captureDiagnostics.maximumAXMilliseconds,"total measured AX time can expose accumulated work")
print("PASS all instrumentation and safe-failure checks; total",checks)

// Contacts observed before cancellation must not reacquire a changed caret.
let graceCancelled=MemoryInput();graceCancelled.activate();graceCancelled.liftGraceSeconds=0.12
word(graceCancelled,"cat",id:1)
let bufferedNext=points("test")
frame(graceCancelled,[(2,bufferedNext[0],.making)])
check(graceCancelled.deferredLift?.candidateSamples.count==1,"nearby next contact is buffered during release grace")
graceCancelled.value="X";graceCancelled.caret=CFRange(location:1,length:0)
RunLoop.current.run(until:Date().addingTimeInterval(0.16))
check(graceCancelled.finger==nil && graceCancelled.target==nil && graceCancelled.waitForLift,"caret cancellation retires buffered contact and retains held-contact lift gate")
for point in bufferedNext.dropFirst() {frame(graceCancelled,[(2,point,.touching)])}
frame(graceCancelled,[(2,bufferedNext.last!,.breaking)])
RunLoop.current.run(until:Date().addingTimeInterval(0.16))
check(graceCancelled.value=="X" && graceCancelled.captureDiagnostics.writeAttempts==0,"old buffered contact cannot write at a new caret after cancellation")
word(graceCancelled,"test",id:3)
RunLoop.current.run(until:Date().addingTimeInterval(0.16))
check(graceCancelled.value=="Xtest " && graceCancelled.captureDiagnostics.writeAttempts==1,"a genuinely fresh post-lift contact can use the new caret once")
graceCancelled.cancel("OFF")
print("PASS buffered-contact cancellation regressions; total",checks)

for route in ["proximity","direction","emptyFrame"] {
  let owner=MemoryInput();owner.activate();owner.liftGraceSeconds=0.12
  word(owner,"cat",id:1);frame(owner,[(2,bufferedNext[0],.making)])
  var validations=0
  owner.beforeTargetValidation={
    validations += 1
    // Model a target change between the frame guard and terminal write guard.
    if validations==2 {owner.value="X";owner.caret=CFRange(location:1,length:0)}
  }
  if route=="proximity" {
    RunLoop.current.run(until:Date().addingTimeInterval(0.08))
    // The original candidate is close, but changing its ID plus a small
    // reach limit can fail proximity; use the expired missing-time budget.
    owner.missingSeconds=0.30
    frame(owner,[(2,bufferedNext[1],.touching)])
  } else if route=="direction" {
    frame(owner,[(2,Point(bufferedNext[0].x-0.04,bufferedNext[0].y),.touching)])
  } else {frame(owner,[])}
  owner.beforeTargetValidation=nil
  check(validations>=2 && owner.finger==nil && owner.target==nil && owner.captureDiagnostics.writeAttempts==0,"\(route) flush cannot replay buffered contact after terminal target rejection")
  owner.cancel("OFF")
}

let bufferedPending=MemoryInput();bufferedPending.activate();bufferedPending.liftGraceSeconds=0.12;bufferedPending.delayFirst=true
word(bufferedPending,"cat",id:1);frame(bufferedPending,[(2,bufferedNext[0],.making)])
for point in bufferedNext.dropFirst() {frame(bufferedPending,[(2,point,.touching)])}
frame(bufferedPending,[(2,bufferedNext.last!,.breaking)])
RunLoop.current.run(until:Date().addingTimeInterval(0.16))
check(bufferedPending.pending && bufferedPending.queuedWords.count==1 && bufferedPending.captureDiagnostics.writeAttempts==1,"legitimate buffered next word is retained while prior accepted write awaits its caret")
bufferedPending.caret=CFRange(location:4,length:0)
RunLoop.current.run(until:Date().addingTimeInterval(0.14))
check(bufferedPending.value=="cat test " && bufferedPending.captureDiagnostics.writeAttempts==2 && bufferedPending.unresolvedWrites.isEmpty,"confirmed prior write drains the legitimate buffered word exactly once")
bufferedPending.cancel("OFF")
print("PASS all deferred replay paths and pending continuation; total",checks)
