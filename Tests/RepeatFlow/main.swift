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
  var omitPlainValue=false
  var accessibleValueOverride:String?
  var plainValueError:AXError = .noValue
  var textSuiteReadable=true
  var forcedCharacterCount:Int?
  var truncatedTextSuite=false
  var missingCharacterCount=false
  var afterTextSuiteRead:(()->Void)?
  var fullRangeReads=0
  override func parameterizedText(_ field:AXUIElement,range:CFRange)->String? {
    metadataReads += 1;fullRangeReads += 1
    guard textSuiteReadable,range.location==0,range.length==value.utf16.count else {return nil}
    let snapshot=truncatedTextSuite ? String(value.prefix(1)):value
    afterTextSuiteRead?();afterTextSuiteRead=nil
    return snapshot
  }
  override func characterCount(_ field:AXUIElement)->Int? {
    metadataReads += 1
    // Legacy fixtures model an AXValue-only provider. Text-suite cases explicitly
    // enable a separate authoritative character-count/range implementation.
    guard omitPlainValue || accessibleValueOverride != nil || forcedCharacterCount != nil else {return nil}
    guard !missingCharacterCount else {return nil}
    let count=forcedCharacterCount ?? value.utf16.count
    return count>=0 && count<=1_000_000 ? count:nil
  }
  var valueWritable=true
  var rangeWritable=true
  var normalizeSeparator=false
  var trimSeparator=false
  var delayedValuePublication=false
  var rejectCaretSetter=false
  var acknowledgeSelectedTextWithoutEditing=false
  var selectedTextMutationError:AXError = .success
  var staleValueOnce:String?
  var loseRangeOnceAfterSelection=false
  var rangeUnavailableOnce=false
  var attributeNamesSet:[String]=[]
  var attemptedWords:[String]=[]
  var acquireCount=0
  var metadataReads=0
  var beforeTargetValidation:(()->Void)?
  var afterNextValueRead:(()->Void)?
  var valueSetterOverride:((String)->String)?
  var focusErrors:(application:Int?,system:Int?)=(nil,nil)
  var finishedActivations=0
  var simulatedSecureInput=false
  var simulatedRuntimeSignatureValid=true
  var simulatedPostAccess=true
  var postedTextPIDs:[pid_t]=[]
  var acknowledgePostedTextWithoutEditing=false
  var holdPostedCaret=false
  var trackingPersistenceSucceeds=true
  override func persistWriteTracking()->Bool {trackingPersistenceSucceeds}
  override var runtimeSignatureValid:Bool {simulatedRuntimeSignatureValid}
  override var secureInputActive:Bool {simulatedSecureInput}
  override var canPostText:Bool {simulatedPostAccess}
  override func postText(_ events:(CGEvent,CGEvent),to pid:pid_t) {
    postedTextPIDs.append(pid)
    guard !acknowledgePostedTextWithoutEditing else {return}
    var length=0
    events.0.keyboardGetUnicodeString(maxStringLength:0,actualStringLength:&length,unicodeString:nil)
    var units=[UniChar](repeating:0,count:length)
    events.0.keyboardGetUnicodeString(maxStringLength:length,actualStringLength:&length,unicodeString:&units)
    let text=String(decoding:units,as:UTF16.self)
    guard let replacement=TextReplacement.replacing(value,location:caret.location,length:caret.length,with:text) else {preconditionFailure("invalid fixture event range")}
    attemptedWords.append(text);value=replacement
    if holdPostedCaret {holdPostedCaret=false} else {caret=CFRange(location:caret.location+text.utf16.count,length:0)}
  }
  override func validTarget()->Bool {beforeTargetValidation?();return super.validTarget()}
  override var currentApplicationPID:pid_t? {pid}
  override func focused(_ pid:pid_t)->AXUIElement? {metadataReads += 1;if missingFocus {focusLookupErrors=focusErrors;return nil};return chosenField ?? ownedField}
  override func finishActivation() {finishedActivations += 1;activate()}
  override func attribute(_ field:AXUIElement,_ name:String)->CFTypeRef? {
    metadataReads += 1
    if name==kAXValueAttribute {
      captureDiagnostics.valueReadAXError=Int((omitPlainValue ? plainValueError:.success).rawValue)
      captureDiagnostics.valueReadKind=omitPlainValue ? "nil":"string"
      if omitPlainValue {return nil}
      if let accessibleValueOverride {return accessibleValueOverride as CFString}
    }
    if name==kAXValueAttribute,let stale=staleValueOnce {staleValueOnce=nil;return stale as CFString}
    if name==kAXValueAttribute,let callback=afterNextValueRead {afterNextValueRead=nil;let snapshot=value as CFString;callback();return snapshot}
    return name==kAXValueAttribute ? value as CFString:nil
  }
  override func attributeWritable(_ field:AXUIElement,_ name:String)->Bool {metadataReads += 1;return editable && (name==kAXSelectedTextAttribute ? selectedTextWritable:(name==kAXValueAttribute ? valueWritable:rangeWritable))}
  override func fieldMetadata(_ field:AXUIElement)->(role:String?,subrole:FieldSubrole,writable:Bool) {metadataReads += 1;return (role,subrole,editable)}
  override func selection(_ field:AXUIElement)->CFRange? {metadataReads += 1;if rangeUnavailableOnce {rangeUnavailableOnce=false;return nil};return caret}
  override func acquireTarget()->Bool {acquireCount += 1;return super.acquireTarget()}
  override func setAttribute(_ field:AXUIElement,_ name:String,_ input:CFTypeRef)->AXError {
    guard CFEqual(field,ownedField),editable else {return .cannotComplete}
    attributeNamesSet.append(name)
    if name==kAXSelectedTextAttribute,acknowledgeSelectedTextWithoutEditing {return .success}
    if name==kAXSelectedTextAttribute,let text=input as? String,
      let expected=TextReplacement.replacing(value,location:caret.location,length:caret.length,with:text) {
      attemptedWords.append(text);value=expected
      if delayFirst {delayFirst=false} else {caret=CFRange(location:caret.location+text.utf16.count,length:0)}
    } else if name==kAXValueAttribute,let text=input as? String {if delayedValuePublication {staleValueOnce=value};value=valueSetterOverride?(text) ?? (text.hasSuffix(" ") && trimSeparator ? String(text.dropLast()):(normalizeSeparator && text.hasSuffix(" ") ? String(text.dropLast())+"\u{00a0}":text))}
    else if name==kAXSelectedTextRangeAttribute,CFGetTypeID(input)==AXValueGetTypeID() {
      if rejectCaretSetter {return .cannotComplete}
      var range=CFRange();guard AXValueGetValue(unsafeDowncast(input,to:AXValue.self),.cfRange,&range) else {return .illegalArgument}
      if delayFirst {delayFirst=false} else {caret=range;if range.length>0 && loseRangeOnceAfterSelection {rangeUnavailableOnce=true}}
    } else {return .attributeUnsupported}
    return name==kAXSelectedTextAttribute ? selectedTextMutationError:.success
  }
  func activate() {
    insertionTransport = .accessibility // Explicit AX suite; never post OS events from model tests.
    liftGraceSeconds=0 // Legacy immediate-handler cases; explicit grace cases below exercise the timer.
    active=true;inputProtectionHealthy=true;strokeSource = .screenOverlay;contactGate.reset();frameOrdering.reset(receivedAfter:0)
    gestureLexicon=GestureLexicon(words:["cat","world","test","hello","auto"])
  }
}
var checks=0
func check(_ value:Bool,_ label:String) {precondition(value,label);checks += 1;print("PASS: "+label);fflush(stdout)}
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
check(preferred.attributeNamesSet==[kAXSelectedTextAttribute,kAXSelectedTextAttribute],"production writer prefers selection insertion when both AX backends exist")
let selectedNoOp=MemoryInput();selectedNoOp.activate();selectedNoOp.acknowledgeSelectedTextWithoutEditing=true
word(selectedNoOp,"cat");word(selectedNoOp,"world")
RunLoop.current.run(until:Date().addingTimeInterval(0.30))
check(selectedNoOp.value.isEmpty && selectedNoOp.captureDiagnostics.insertions==0 && selectedNoOp.unresolvedWrites.count==1,"selected-text acknowledgement without content/caret change remains unresolved")
check(selectedNoOp.attributeNamesSet==[kAXSelectedTextAttribute] && selectedNoOp.captureDiagnostics.writeAttempts==1,"no-op selected-text write never falls back to whole-value or retries text")
selectedNoOp.cancel("OFF")
let selectedErrorAfterMutation=MemoryInput();selectedErrorAfterMutation.activate();selectedErrorAfterMutation.selectedTextMutationError = .cannotComplete
word(selectedErrorAfterMutation,"cat")
check(selectedErrorAfterMutation.value=="cat " && selectedErrorAfterMutation.captureDiagnostics.insertions==1 && selectedErrorAfterMutation.unresolvedWrites.isEmpty,"selected-text error after exact observed mutation resolves without retry")
check(selectedErrorAfterMutation.attributeNamesSet==[kAXSelectedTextAttribute],"accepted selected-text mutation followed by error never triggers alternate backend")
selectedErrorAfterMutation.cancel("OFF")
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
let normalized=MemoryInput();normalized.activate();normalized.selectedTextWritable=false;normalized.normalizeSeparator=true
word(normalized,"cat");word(normalized,"world");word(normalized,"auto")
check(normalized.value=="cat\u{00a0}world\u{00a0}auto\u{00a0}" && normalized.captureDiagnostics.insertions==3 && normalized.unresolvedWrites.isEmpty,"exact new-separator NBSP receipt confirms repeated words and rebases exact bytes")
let changedReceipt=MemoryInput();changedReceipt.activate();changedReceipt.delayFirst=true;word(changedReceipt,"cat");let receipt=changedReceipt.unresolvedWrites.first!
changedReceipt.value="bat\u{00a0}";changedReceipt.caret=CFRange(location:4,length:0)
check(!changedReceipt.permitsResolvedWrite(changedReceipt.ownedField,pid:40001,range:changedReceipt.caret,resolvePending:true),"separator alternate never accepts changed letter outside newly generated separator")
changedReceipt.value="cat\u{00a0}";changedReceipt.caret=CFRange(location:3,length:0)
check(!changedReceipt.permitsResolvedWrite(changedReceipt.ownedField,pid:40001,range:changedReceipt.caret,resolvePending:true),"separator alternate still requires exact collapsed UTF16 caret")
let trimmed=MemoryInput();trimmed.activate();trimmed.selectedTextWritable=false;trimmed.trimSeparator=true
for _ in 0..<3 {for w in ["cat","world","auto"] {word(trimmed,w)}}
check(trimmed.value==String(repeating:"cat world auto ",count:3).trimmingCharacters(in:.whitespaces) && trimmed.captureDiagnostics.insertions==9 && trimmed.unresolvedWrites.isEmpty,"AX-trimmed generated terminal separator uses leading next-word separation with exact receipt and caret")
check(trimmed.continuationAnchor?.trimmedSeparator==true && trimmed.caret.location==trimmed.value.utf16.count,"trim receipt anchors exact observed caret and bytes")
trimmed.active=false
let last=trimmed.lastOwnedWord!
trimmed.lastOwnedWord=AppDelegate.OwnedWord(field:last.field,pid:last.pid,range:last.range,alternatives:["auto","cat","world"],fingerprint:last.fingerprint,leadingSeparator:last.leadingSeparator,trailingSeparator:last.trailingSeparator)
let alternative=NSButton(title:"cat",target:nil,action:nil);trimmed.selectCandidate(alternative)
check(trimmed.value.hasSuffix("world cat") && trimmed.unresolvedWrites.isEmpty,"trimmed last-word correction replaces owned leading separator plus word")
alternative.title="world";trimmed.selectCandidate(alternative)
check(trimmed.value.hasSuffix("world world") && trimmed.unresolvedWrites.isEmpty,"second trimmed correction resolves exact fresh transaction")
trimmed.cancel("OFF");trimmed.activate();word(trimmed,"cat")
check(trimmed.value.hasSuffix("world world cat") && trimmed.unresolvedWrites.isEmpty,"verified trimmed separator survives exit/reactivation without merging words")
trimmed.cancel("Application changed");word(trimmed,"auto")
check(trimmed.value.hasSuffix("world cat auto"),"confirmed delimiter metadata survives cancellation without preserving stale write authority")
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
check(utf.value=="😀 cat world " && utf.caret.location==13,"word separation and repeated UTF16 caret preserve surrounding surrogate pair")
let delayedValue=MemoryInput();delayedValue.activate();delayedValue.selectedTextWritable=false;delayedValue.trimSeparator=true;delayedValue.delayedValuePublication=true
for _ in 0..<3 {for w in ["cat","world","auto"] {word(delayedValue,w);RunLoop.current.run(until:Date().addingTimeInterval(0.08))}}
check(delayedValue.value==String(repeating:"cat world auto ",count:3).trimmingCharacters(in:.whitespaces) && delayedValue.captureDiagnostics.insertions==9 && delayedValue.unresolvedWrites.isEmpty,"delayed AXValue publication settles exact trimmed receipt before one caret attempt per word")
check(delayedValue.attributeNamesSet.filter {$0==kAXValueAttribute}.count==9 && delayedValue.attributeNamesSet.filter {$0==kAXSelectedTextRangeAttribute}.count==9,"delayed publication never retries text or caret mutations")
let movedWhilePublishing=MemoryInput();movedWhilePublishing.activate();movedWhilePublishing.selectedTextWritable=false;movedWhilePublishing.delayedValuePublication=true
_ = movedWhilePublishing.replaceSelectedText(movedWhilePublishing.ownedField,pid:40001,range:movedWhilePublishing.caret,inserted:"cat ")
let deferredID=movedWhilePublishing.unresolvedWrites.first!.id;movedWhilePublishing.caret=CFRange(location:1,length:0)
_ = movedWhilePublishing.settleDeferredCaret(deferredID)
check(movedWhilePublishing.attributeNamesSet==[kAXValueAttribute] && movedWhilePublishing.unresolvedWrites.count==1,"manual caret change blocks deferred caret placement and retains accepted write without replay")
let caretRejected=MemoryInput();caretRejected.activate();caretRejected.selectedTextWritable=false;caretRejected.rejectCaretSetter=true
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
check(graceCancelled.value=="X test " && graceCancelled.captureDiagnostics.writeAttempts==1,"a genuinely fresh post-lift contact can use the new caret once")
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


// Existing sentences: fixed expectations, production contact handlers, memory-only fields.
let sentenceCases:[(String,String,Int,Int,String)]=[
 ("append without separator","Hello",5,0,"Hello world "),
 ("append existing separator","Hello ",6,0,"Hello world "),
 ("middle before existing space","Hello there.",5,0,"Hello world there."),
 ("middle after existing space","Hello there.",6,0,"Hello world there."),
 ("before period","Hello.",5,0,"Hello world."),
 ("after comma","Hello, friend",6,0,"Hello, world friend"),
 ("parentheses","Say ()",5,0,"Say (world)"),
 ("straight quotes","Say \"\"",5,0,"Say \"world\""),
 ("curly quotes","Say “”, please",5,0,"Say “world”, please"),
 ("selected word","Hello old friend.",6,3,"Hello world friend."),
 ("selection includes separators","Hello old friend",5,5,"Hello world friend"),
 ("whole selection","Hello old",0,9,"world "),
 ("emoji neighbour","😀",2,0,"😀 world "),
 ("surrogate selection","😀!",0,2,"world!"),
 ("newline suffix","Hello\nthere",5,0,"Hello world\nthere"),
 ("newline prefix","Hello\nthere",6,0,"Hello\nworld there"),
 ("nonbreaking whitespace","Hello\u{00a0}",6,0,"Hello\u{00a0}world "),
 ("before exclamation","Hello!",5,0,"Hello world!")
]
for selectedBackend in [true,false] {
for (label,before,location,length,expected) in sentenceCases {
 let owner=MemoryInput();owner.selectedTextWritable=selectedBackend;owner.activate();owner.value=before;owner.caret=CFRange(location:location,length:length)
 word(owner,"world")
 check(owner.value==expected,"sentence keeps exact surrounding text: "+label)
 check(owner.captureDiagnostics.writeAttempts==1 && owner.captureDiagnostics.insertions==1 && owner.unresolvedWrites.isEmpty,"sentence commits once with exact content/caret: "+label)
 let owned=owner.lastOwnedWord!;owner.cancel("OFF")
 owner.lastOwnedWord=AppDelegate.OwnedWord(field:owned.field,pid:owned.pid,range:owned.range,alternatives:["world","cat","test"],fingerprint:owned.fingerprint,leadingSeparator:owned.leadingSeparator,trailingSeparator:owned.trailingSeparator)
 let replace=NSButton(title:"cat",target:nil,action:nil);owner.selectCandidate(replace)
 let corrected=expected.replacingOccurrences(of:"world",with:"cat")
 check(owner.value==corrected && owner.unresolvedWrites.isEmpty,"correction preserves existing separators/punctuation: "+label)
 replace.title="test";owner.selectCandidate(replace)
 check(owner.value==expected.replacingOccurrences(of:"world",with:"test") && owner.unresolvedWrites.isEmpty,"second correction keeps same separator policy: "+label)
}
}
for (value,location,length) in [("Hello",2,0),("Hello",2,3),("don't",3,0),("well-known",4,0),("e\u{301}",1,0),("👩‍💻",2,0),("🇺🇸",2,0),("\r\n",1,0),("😀",1,0),("abc",4,0),("e\u{301}x",1,1)] {
 let owner=MemoryInput();owner.activate();owner.value=value;owner.caret=CFRange(location:location,length:length)
 check(!owner.acquireTarget(),"partial word/grapheme refuses target before swipe")
 word(owner,"world")
 check(owner.value==value && owner.captureDiagnostics.writeAttempts==0 && owner.unresolvedWrites.isEmpty,"partial word or grapheme refused without mutation at UTF16 \(location)/\(length)")
 owner.cancel("OFF")
}
let sentenceRepeat=MemoryInput();sentenceRepeat.activate();sentenceRepeat.value="Hello there.";sentenceRepeat.caret=CFRange(location:5,length:0)
for w in ["world","cat","test"] {word(sentenceRepeat,w)}
check(sentenceRepeat.value=="Hello world cat test there." && sentenceRepeat.captureDiagnostics.insertions==3,"three lifts build on the live middle caret and preserve suffix")
sentenceRepeat.cancel("OFF")
let sentenceQueued=MemoryInput();sentenceQueued.activate();sentenceQueued.value="Hello there.";sentenceQueued.caret=CFRange(location:5,length:0);sentenceQueued.delayFirst=true
for w in ["world","cat","test"] {word(sentenceQueued,w)}
check(sentenceQueued.value=="Hello world there." && sentenceQueued.captureDiagnostics.writeAttempts==1 && sentenceQueued.queuedWords.count==2,"sentence queue holds later words while first exact caret is delayed")
sentenceQueued.caret=CFRange(location:11,length:0);RunLoop.current.run(until:Date().addingTimeInterval(0.18))
check(sentenceQueued.value=="Hello world cat test there." && sentenceQueued.captureDiagnostics.writeAttempts==3 && sentenceQueued.unresolvedWrites.isEmpty,"queued words plan at verified live caret when drained")
sentenceQueued.cancel("OFF")
let sentenceArrow=MemoryInput();sentenceArrow.activate();sentenceArrow.value="Hello there.";sentenceArrow.caret=CFRange(location:5,length:0);word(sentenceArrow,"world")
let arrow=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:time,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:123)!
sentenceArrow.handle(arrow);sentenceArrow.caret=CFRange(location:sentenceArrow.value.utf16.count,length:0);word(sentenceArrow,"cat")
check(sentenceArrow.value=="Hello world there. cat " && sentenceArrow.captureDiagnostics.insertions==2,"explicit keyboard caret move clears old anchor and replans at fresh caret")
sentenceArrow.cancel("OFF")
let sentenceRace=MemoryInput();sentenceRace.activate();sentenceRace.value="Hello.";sentenceRace.caret=CFRange(location:5,length:0)
check(sentenceRace.acquireTarget(),"sentence race target acquired")
sentenceRace.afterNextValueRead={sentenceRace.value="Hullo."}
_ = sentenceRace.insertWord("world",alternatives:["world"])
check(sentenceRace.value=="Hullo." && sentenceRace.captureDiagnostics.writeAttempts==0 && sentenceRace.unresolvedWrites.isEmpty,"edit between planning and writer snapshot refuses stale plan with zero mutation")
sentenceRace.cancel("OFF")
let sentenceInterrupted=MemoryInput();sentenceInterrupted.activate();sentenceInterrupted.value="Hello.";sentenceInterrupted.caret=CFRange(location:5,length:0)
let interruptedPoints=points("world")
for (i,p) in interruptedPoints.prefix(5).enumerated() {frame(sentenceInterrupted,[(9,p,i==0 ? .starting:.touching)])}
sentenceInterrupted.value="Hullo."
for p in interruptedPoints.dropFirst(5) {frame(sentenceInterrupted,[(9,p,.touching)])};frame(sentenceInterrupted,[(9,interruptedPoints.last!,.breaking)])
check(sentenceInterrupted.value=="Hullo." && sentenceInterrupted.captureDiagnostics.writeAttempts==0 && sentenceInterrupted.unresolvedWrites.isEmpty,"content change during stroke at same caret refuses insertion")
sentenceInterrupted.cancel("OFF")
print("PASS sentence continuation/selection/punctuation/Unicode/interruption checks; total",checks)

let correctionRace=MemoryInput();correctionRace.activate();word(correctionRace,"world");let correctionOwned=correctionRace.lastOwnedWord!;correctionRace.cancel("OFF")
correctionRace.lastOwnedWord=AppDelegate.OwnedWord(field:correctionOwned.field,pid:correctionOwned.pid,range:correctionOwned.range,alternatives:["world","cat"],fingerprint:correctionOwned.fingerprint)
// Edit after the writer first content read; its second check must refuse before allocation.
correctionRace.afterNextValueRead={ correctionRace.afterNextValueRead={ correctionRace.afterNextValueRead={ correctionRace.afterNextValueRead={correctionRace.value += "!"} } } }
let correctionAttempts=correctionRace.captureDiagnostics.writeAttempts
correctionRace.selectCandidate(NSButton(title:"cat",target:nil,action:nil))
check(correctionRace.captureDiagnostics.writeAttempts==correctionAttempts && correctionRace.value=="world !" && correctionRace.unresolvedWrites.isEmpty,"correction snapshot race refuses mutation without retry")
print("PASS post-Opus correction and early boundary checks; total \(checks)")

let boundWriter=MemoryInput();boundWriter.activate();boundWriter.value="Hello";boundWriter.caret=CFRange(location:5,length:0)
check(boundWriter.replaceSelectedText(boundWriter.ownedField,pid:40001,range:boundWriter.caret,inserted:" world ",expectedBefore:"Hullo") == .cannotComplete && boundWriter.unresolvedWrites.isEmpty && boundWriter.attributeNamesSet.isEmpty && boundWriter.captureDiagnostics.writeAttempts==0,"writer refuses stale plan before uncertainty allocation")
boundWriter.cancel("OFF")
let noOpBound=MemoryInput();noOpBound.activate();noOpBound.acknowledgeSelectedTextWithoutEditing=true
word(noOpBound,"cat");word(noOpBound,"world",id:2)
let noOpID=noOpBound.unresolvedWrites.first!.id
check(noOpBound.pending && noOpBound.queuedWords.count==1,"no-op ACK holds next word without sending")
let thirdState=MemoryInput();thirdState.selectedTextWritable=false;thirdState.activate();thirdState.value="Hi";thirdState.caret=CFRange(location:2,length:0)
thirdState.valueSetterOverride={_ in thirdState.caret=CFRange(location:0,length:0);return "Hi?"}
word(thirdState,"world")
let thirdID=thirdState.unresolvedWrites.first!.id
check(thirdState.captureDiagnostics.lastInsertionBackend=="valueAndCaret" && thirdState.captureDiagnostics.lastAXError==0 && thirdState.captureDiagnostics.acceptedMutations==1 && thirdState.captureDiagnostics.insertions==0,"third-state accepted value write has zero confirmed insertions")
check(thirdState.captureDiagnostics.expectedCaret==9 && thirdState.captureDiagnostics.observedCaretLocation==0 && thirdState.captureDiagnostics.confirmationContentMatches==false && thirdState.captureDiagnostics.confirmationBeforeContentMatches==false,"third state mirrors physical structural receipt")
check(thirdState.attributeNamesSet==[kAXValueAttribute],"third state has no caret placement or retry")
RunLoop.current.run(until:Date().addingTimeInterval(AppDelegate.acceptedWriteSettleSeconds+0.45))
for (owner,id,label) in [(noOpBound,noOpID,"no-op ACK"),(thirdState,thirdID,"third state")] {
 check(!owner.active && !owner.pending && owner.queuedWords.isEmpty && owner.unresolvedWrites.map(\.id)==[id],"\(label) bounded stop retains exactly its record")
 check(owner.captureDiagnostics.stage=="acceptedWriteUnresolved" && owner.captureDiagnostics.writeAttempts==1,"\(label) stop diagnosed without resend")
 check(!owner.cornerProtection.blocksPointerAction(.mouseMoved) && !owner.cornerProtection.blocksPointerAction(.leftMouseDown),"\(label) ordinary pointer resumes")
}
check(noOpBound.attributeNamesSet==[kAXSelectedTextAttribute] && thirdState.attributeNamesSet==[kAXValueAttribute],"bounded stop adds no AX mutation")
noOpBound.activate();let refusedBefore=noOpBound.value;word(noOpBound,"test",id:5)
check(noOpBound.value==refusedBefore && noOpBound.captureDiagnostics.writeAttempts==1 && noOpBound.captureDiagnostics.lastTargetRefusal=="unresolvedPreviousWrite","reactivation still refuses pending evidence")
noOpBound.cancel("OFF");thirdState.cancel("OFF")
print("PASS concrete Claude bounded-wait fix; total \(checks)")

check(FocusLookup.isUnpublished(application:-25212,system:-25212) && FocusLookup.isUnpublished(application:-25212,system:nil),"noValue identifies unpublished authoritative focus")
check(!FocusLookup.isUnpublished(application:-25211,system:-25211) && !FocusLookup.isUnpublished(application:-25204,system:-25212) && !FocusLookup.isUnpublished(application:0,system:0),"permission timeout and foreign focus never retry")
check(FocusLookup.kind(application:-25211,system:nil,fieldFound:false)=="accessibilityDisabled" && FocusLookup.kind(application:-25212,system:-25212,fieldFound:false)=="focusNotPublished" && FocusLookup.kind(application:-25204,system:-25204,fieldFound:false)=="providerNotResponding" && FocusLookup.kind(application:0,system:0,fieldFound:false)=="focusOutsideTargetProcess","diagnostics distinguish focus failure causes")
let late=MemoryInput();late.missingFocus=true;late.focusErrors=(-25212,-25212);late.requestActivation()
check(!late.active && late.finishedActivations==0 && late.listener==nil && late.captureDiagnostics.stage=="awaitingFocusPublication" && !late.cornerProtection.blocksPointerAction(.mouseMoved) && !late.cornerProtection.blocksPointerAction(.leftMouseDown),"focus wait has no capture pointer filtering or write")
RunLoop.current.run(until:Date().addingTimeInterval(0.25));late.missingFocus=false
RunLoop.current.run(until:Date().addingTimeInterval(0.25))
check(late.active && late.finishedActivations==1 && late.captureDiagnostics.targetAdmissions==1 && (late.captureDiagnostics.focusPublicationRetries ?? 0)>=1,"later authoritative focus completes same activation once")
check(late.attributeNamesSet.isEmpty && late.captureDiagnostics.writeAttempts==0,"deferred activation never writes")
late.cancel("OFF")
let never=MemoryInput();never.missingFocus=true;never.focusErrors=(-25212,-25212);never.requestActivation()
RunLoop.current.run(until:Date().addingTimeInterval(AppDelegate.focusPublicationWaitSeconds+0.3))
let neverRetries=never.captureDiagnostics.focusPublicationRetries ?? 0
check(!never.active && never.finishedActivations==0 && never.captureDiagnostics.stage=="activationRefused","missing focus is refused after bound")
check(neverRetries>0 && neverRetries<=Int(AppDelegate.focusPublicationWaitSeconds/AppDelegate.focusPublicationRetryInterval)+1,"publication retry count bounded")
RunLoop.current.run(until:Date().addingTimeInterval(0.3))
check(never.captureDiagnostics.focusPublicationRetries==neverRetries,"no retry survives refusal")
let moved=MemoryInput();moved.missingFocus=true;moved.focusErrors=(-25212,-25212);moved.requestActivation();moved.pid=40002;moved.missingFocus=false
RunLoop.current.run(until:Date().addingTimeInterval(0.3))
check(!moved.active && moved.finishedActivations==0 && moved.captureDiagnostics.stage=="activationAbandoned","app switch abandons activation")
let keyed=MemoryInput();keyed.missingFocus=true;keyed.focusErrors=(-25212,-25212);keyed.requestActivation();keyed.handle(escape);keyed.missingFocus=false
RunLoop.current.run(until:Date().addingTimeInterval(0.3))
check(!keyed.active && keyed.finishedActivations==0 && keyed.captureDiagnostics.stage=="activationAbandoned","Escape abandons activation")
let toggled=MemoryInput();toggled.missingFocus=true;toggled.focusErrors=(-25212,-25212);toggled.requestActivation();toggled.toggle();toggled.missingFocus=false
RunLoop.current.run(until:Date().addingTimeInterval(0.3))
check(!toggled.active && toggled.finishedActivations==0 && toggled.captureDiagnostics.stage=="activationAbandoned","second toggle exits wait instead of restarting")
let denied=MemoryInput();denied.missingFocus=true;denied.focusErrors=(-25211,-25211);denied.requestActivation()
RunLoop.current.run(until:Date().addingTimeInterval(0.3))
check(!denied.active && denied.captureDiagnostics.focusLookupKind=="accessibilityDisabled" && (denied.captureDiagnostics.focusPublicationRetries ?? 0)==0,"permission failure refuses immediately")
let group=MemoryInput();group.role="AXGroup";group.requestActivation()
check(!group.active && group.captureDiagnostics.lastTargetRefusal=="unsupportedField" && group.captureDiagnostics.focusLookupKind=="found" && (group.captureDiagnostics.focusPublicationRetries ?? 0)==0,"unsupported control stays distinct from unpublished focus")
let raceActivation=MemoryInput();raceActivation.afterNextValueRead={raceActivation.pid=40002};raceActivation.requestActivation()
check(!raceActivation.active && raceActivation.finishedActivations==0 && raceActivation.captureDiagnostics.stage=="activationAbandoned","app change during admission cannot finish activation")
print("PASS simplified focus publication; total \(checks)")

let plainKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:10000,windowNumber:0,context:nil,characters:"a",charactersIgnoringModifiers:"a",isARepeat:false,keyCode:0)!
let typedDuringWait=MemoryInput();typedDuringWait.missingFocus=true;typedDuringWait.focusErrors=(-25212,-25212);typedDuringWait.requestActivation();typedDuringWait.handle(plainKey);typedDuringWait.missingFocus=false
RunLoop.current.run(until:Date().addingTimeInterval(0.3))
check(!typedDuringWait.active && typedDuringWait.finishedActivations==0 && typedDuringWait.captureDiagnostics.writeAttempts==0,"ordinary typing abandons deferred activation without interception")
print("PASS all focus publication cancellation; total \(checks)")

let nativeSecureModel=MemoryInput();nativeSecureModel.activate();nativeSecureModel.simulatedSecureInput=true;word(nativeSecureModel,"cat")
check(!nativeSecureModel.active && nativeSecureModel.captureDiagnostics.writeAttempts==0 && nativeSecureModel.captureDiagnostics.lastTargetRefusal=="secureInput","sandbox Secure Input still stops capture with zero writes")
print("PASS locked-host independent sandbox; total \(checks)")

let changedBuild=MemoryInput();changedBuild.simulatedRuntimeSignatureValid=false;changedBuild.toggle()
check(!changedBuild.active && changedBuild.metadataReads==0 && changedBuild.captureDiagnostics.stage=="runtimeIdentityChanged" && changedBuild.captureDiagnostics.writeAttempts==0,"changed running build refuses before any field query or permission assumption")
let changedBeforeWrite=MemoryInput();changedBeforeWrite.activate();word(changedBeforeWrite,"cat");let confirmedBeforeChange=changedBeforeWrite.value;let attemptsBeforeChange=changedBeforeWrite.captureDiagnostics.writeAttempts
changedBeforeWrite.simulatedRuntimeSignatureValid=false
_ = changedBeforeWrite.replaceSelectedText(changedBeforeWrite.ownedField,pid:40001,range:changedBeforeWrite.caret,inserted:"world ")
check(!changedBeforeWrite.active && changedBeforeWrite.value==confirmedBeforeChange && changedBeforeWrite.captureDiagnostics.writeAttempts==attemptsBeforeChange,"changed build releases capture before new mutation")
let legacyHealth=try! JSONEncoder().encode(changedBuild.captureStatusReport())
check((try? JSONDecoder().decode(RuntimeHealth.self,from:legacyHealth))==nil,"legacy counters cannot be misreported as live trust health")
print("PASS runtime identity guards; total \(checks)")

// Full-text-suite providers must use the same authoritative snapshot for admission,
// planning, pre-write race checks, confirmations, queues and corrections.
let suite=MemoryInput();suite.omitPlainValue=true;suite.activate()
for w in ["cat","world","auto"] {word(suite,w)}
check(suite.value=="cat world auto " && suite.captureDiagnostics.insertions==3 && suite.unresolvedWrites.isEmpty,"missing AXValue with full text suite repeats through actual production reader")
check(suite.captureDiagnostics.textEvidenceSource=="fullRange" && suite.captureDiagnostics.textEvidenceLength==suite.value.utf16.count && suite.captureDiagnostics.valueReadAXError == -25212,"full-range receipt records only source, length and raw AX error")
suite.cancel("OFF")
let suiteSentence=MemoryInput();suiteSentence.omitPlainValue=true;suiteSentence.value="😀 Hello there.";suiteSentence.caret=CFRange(location:8,length:0);suiteSentence.activate();word(suiteSentence,"world")
check(suiteSentence.value=="😀 Hello world there." && suiteSentence.captureDiagnostics.insertions==1,"full-range UTF16 reader preserves existing surrounding sentence")
suiteSentence.cancel("OFF")
let suiteReplace=MemoryInput();suiteReplace.omitPlainValue=true;suiteReplace.selectedTextWritable=false;suiteReplace.value="Hello old friend.";suiteReplace.caret=CFRange(location:6,length:3);suiteReplace.activate();word(suiteReplace,"world")
check(suiteReplace.value=="Hello world friend." && suiteReplace.unresolvedWrites.isEmpty,"full-range provider supports one verified value/caret replacement")
suiteReplace.cancel("OFF")
let suiteCorrection=MemoryInput();suiteCorrection.omitPlainValue=true;suiteCorrection.activate();word(suiteCorrection,"world");let ownedSuite=suiteCorrection.lastOwnedWord!;suiteCorrection.cancel("OFF")
suiteCorrection.lastOwnedWord=AppDelegate.OwnedWord(field:ownedSuite.field,pid:ownedSuite.pid,range:ownedSuite.range,alternatives:["world","cat","test"],fingerprint:ownedSuite.fingerprint)
suiteCorrection.selectCandidate(NSButton(title:"cat",target:nil,action:nil));suiteCorrection.selectCandidate(NSButton(title:"test",target:nil,action:nil))
check(suiteCorrection.value=="test " && suiteCorrection.unresolvedWrites.isEmpty && suiteCorrection.captureDiagnostics.correctionResult=="confirmed","two full-range corrections replace rather than append and resolve each receipt")
for configure in [
 { (o:MemoryInput) in o.textSuiteReadable=false },
 { (o:MemoryInput) in o.missingCharacterCount=true },
 { (o:MemoryInput) in o.forcedCharacterCount = -1 },
 { (o:MemoryInput) in o.forcedCharacterCount = 1_000_001 },
 { (o:MemoryInput) in o.truncatedTextSuite=true },
 { (o:MemoryInput) in o.afterTextSuiteRead={o.value += "!"} },
] {
 let o=MemoryInput();o.omitPlainValue=true;o.value="Hello";o.caret=CFRange(location:5,length:0);configure(o);o.activate();word(o,"world")
 check(o.captureDiagnostics.writeAttempts==0 && o.unresolvedWrites.isEmpty && o.captureDiagnostics.lastTargetRefusal=="contentEvidenceUnavailable","missing, invalid, truncated or changing full-range evidence refuses with zero writes")
 o.cancel("OFF")
}
for error in [AXError.apiDisabled,.cannotComplete,.notImplemented] {
 let o=MemoryInput();o.omitPlainValue=true;o.plainValueError=error;o.activate();word(o,"cat")
 check(o.captureDiagnostics.writeAttempts==0 && o.fullRangeReads==0,"permission/provider failures never become text-suite fallback")
 o.cancel("OFF")
}
let suiteNoOp=MemoryInput();suiteNoOp.omitPlainValue=true;suiteNoOp.acknowledgeSelectedTextWithoutEditing=true;suiteNoOp.activate();word(suiteNoOp,"cat");word(suiteNoOp,"world")
check(suiteNoOp.value.isEmpty && suiteNoOp.captureDiagnostics.writeAttempts==1 && suiteNoOp.unresolvedWrites.count==1 && suiteNoOp.queuedWords.count==1,"full-range no-op ACK remains a single uncertain mutation with next word unsent")
suiteNoOp.cancel("OFF")
let suiteSecure=MemoryInput();suiteSecure.omitPlainValue=true;suiteSecure.simulatedSecureInput=true;suiteSecure.activate();word(suiteSecure,"cat")
check(suiteSecure.captureDiagnostics.writeAttempts==0 && suiteSecure.fullRangeReads==0,"secure context rejects before any full-range content read")
suiteSecure.cancel("OFF")
print("PASS authoritative text-suite fallback; total \(checks)")

let ordinary=MemoryInput();ordinary.activate();ordinary.insertionTransport = .keyboard;ordinary.acknowledgeSelectedTextWithoutEditing=true
for w in ["cat","world","auto"] {word(ordinary,w)}
check(ordinary.value=="cat world auto " && ordinary.captureDiagnostics.insertions==3 && ordinary.unresolvedWrites.isEmpty,"normal input transport verifies three words despite no-op advertised AX setter")
check(ordinary.postedTextPIDs==[40001,40001,40001] && ordinary.attributeNamesSet.isEmpty && ordinary.captureDiagnostics.lastInsertionBackend=="targetedKeyboard","one PID-targeted dispatch per word with no AX text mutation")
ordinary.cancel("OFF")
let keyboardSuite=MemoryInput();keyboardSuite.omitPlainValue=true;keyboardSuite.value="😀 Hello there.";keyboardSuite.caret=CFRange(location:8,length:0);keyboardSuite.activate();keyboardSuite.insertionTransport = .keyboard;word(keyboardSuite,"world")
check(keyboardSuite.value=="😀 Hello world there." && keyboardSuite.captureDiagnostics.insertions==1 && keyboardSuite.unresolvedWrites.isEmpty,"keyboard dispatch uses full-range snapshot for sentence plan and independent receipt")
keyboardSuite.cancel("OFF")
let postDenied=MemoryInput();postDenied.activate();postDenied.insertionTransport = .keyboard;postDenied.simulatedPostAccess=false;word(postDenied,"cat")
check(postDenied.postedTextPIDs.isEmpty && postDenied.captureDiagnostics.writeAttempts==0 && postDenied.attributeNamesSet.isEmpty,"missing existing event permission refuses without requesting or alternate mutation")
postDenied.cancel("OFF")
let keyboardNoOp=MemoryInput();keyboardNoOp.activate();keyboardNoOp.insertionTransport = .keyboard;keyboardNoOp.acknowledgePostedTextWithoutEditing=true;word(keyboardNoOp,"cat");word(keyboardNoOp,"world")
check(keyboardNoOp.value.isEmpty && keyboardNoOp.postedTextPIDs==[40001] && keyboardNoOp.unresolvedWrites.count==1 && keyboardNoOp.queuedWords.count==1,"unconfirmed keyboard delivery has one dispatch and no retry or AX fallback")
keyboardNoOp.cancel("OFF")
let postChanged=MemoryInput();postChanged.activate();postChanged.insertionTransport = .keyboard;check(postChanged.acquireTarget(),"keyboard target acquired before focus race");postChanged.pid=40002
_ = postChanged.insertWord("cat",alternatives:["cat"])
check(postChanged.postedTextPIDs.isEmpty && postChanged.attributeNamesSet.isEmpty && postChanged.captureDiagnostics.writeAttempts==0,"focus switch before lift cannot send events to another application")
postChanged.cancel("OFF")
print("PASS PID-scoped input dispatch ports; total \(checks)")

let delayedCorrection=MemoryInput();delayedCorrection.activate();word(delayedCorrection,"world");let delayedOwned=delayedCorrection.lastOwnedWord!;delayedCorrection.cancel("OFF")
delayedCorrection.lastOwnedWord=AppDelegate.OwnedWord(field:delayedOwned.field,pid:delayedOwned.pid,range:delayedOwned.range,alternatives:["world","cat","test"],fingerprint:delayedOwned.fingerprint)
delayedCorrection.insertionTransport = .keyboard;delayedCorrection.holdPostedCaret=true
delayedCorrection.selectCandidate(NSButton(title:"cat",target:nil,action:nil))
check(delayedCorrection.value=="cat " && delayedCorrection.unresolvedWrites.count==1 && delayedCorrection.captureDiagnostics.correctionResult=="awaitingReceipt","asynchronous correction waits after one dispatch with no second write")
delayedCorrection.caret=CFRange(location:4,length:0);RunLoop.current.run(until:Date().addingTimeInterval(0.06))
check(delayedCorrection.unresolvedWrites.isEmpty && delayedCorrection.captureDiagnostics.correctionResult=="confirmed" && delayedCorrection.lastOwnedWord?.range.length==4,"exact late correction receipt resolves and rebases provenance")
delayedCorrection.selectCandidate(NSButton(title:"test",target:nil,action:nil))
check(delayedCorrection.value=="test " && delayedCorrection.unresolvedWrites.isEmpty && delayedCorrection.postedTextPIDs==[40001,40001],"second keyboard correction replaces the owned word instead of appending")
print("PASS asynchronous correction receipts; total \(checks)")

let cancelledCorrection=MemoryInput();cancelledCorrection.activate();word(cancelledCorrection,"world");let cancelledOwned=cancelledCorrection.lastOwnedWord!;cancelledCorrection.cancel("OFF")
cancelledCorrection.lastOwnedWord=AppDelegate.OwnedWord(field:cancelledOwned.field,pid:cancelledOwned.pid,range:cancelledOwned.range,alternatives:["world","cat"],fingerprint:cancelledOwned.fingerprint)
cancelledCorrection.insertionTransport = .keyboard;cancelledCorrection.holdPostedCaret=true;cancelledCorrection.selectCandidate(NSButton(title:"cat",target:nil,action:nil));let cancelledWrite=cancelledCorrection.unresolvedWrites.first!.id
cancelledCorrection.cancel("OFF");cancelledCorrection.caret=CFRange(location:4,length:0)
RunLoop.current.run(until:Date().addingTimeInterval(0.06))
check(cancelledCorrection.unresolvedWrites.map(\.id)==[cancelledWrite] && cancelledCorrection.postedTextPIDs==[40001],"cancelled correction poll cannot resolve or resend a later receipt")
check(cancelledCorrection.permitsResolvedWrite(cancelledCorrection.ownedField,pid:40001,range:cancelledCorrection.caret,resolvePending:true) && cancelledCorrection.unresolvedWrites.isEmpty,"subsequent exact same-field receipt can safely resolve cancelled correction without another mutation")
print("PASS correction cancellation tokens; total \(checks)")

let placeholder=MemoryInput();placeholder.accessibleValueOverride="Owned input placeholder";placeholder.activate();placeholder.insertionTransport = .keyboard
for w in ["cat","world","auto"] {word(placeholder,w)}
check(placeholder.value=="cat world auto " && placeholder.captureDiagnostics.insertions==3 && placeholder.unresolvedWrites.isEmpty,"contradictory accessible placeholder is never copied into the document or expected receipt")
check(placeholder.captureDiagnostics.textEvidenceSource=="fullRange" && placeholder.postedTextPIDs==[40001,40001,40001],"full authoritative range resolves placeholder discrepancy across repeat keyboard delivery")
placeholder.cancel("OFF")
print("PASS contradictory accessible-value evidence; total \(checks)")

let delayedAXCorrection=MemoryInput();delayedAXCorrection.selectedTextWritable=false;delayedAXCorrection.activate();word(delayedAXCorrection,"world");let delayedAXOwned=delayedAXCorrection.lastOwnedWord!;delayedAXCorrection.cancel("OFF")
delayedAXCorrection.lastOwnedWord=AppDelegate.OwnedWord(field:delayedAXOwned.field,pid:delayedAXOwned.pid,range:delayedAXOwned.range,alternatives:["world","cat"],fingerprint:delayedAXOwned.fingerprint)
delayedAXCorrection.delayedValuePublication=true;delayedAXCorrection.selectCandidate(NSButton(title:"cat",target:nil,action:nil))
RunLoop.current.run(until:Date().addingTimeInterval(0.06))
check(delayedAXCorrection.value=="cat " && delayedAXCorrection.caret.location==4 && delayedAXCorrection.caret.length==0 && delayedAXCorrection.unresolvedWrites.isEmpty && delayedAXCorrection.captureDiagnostics.correctionResult=="confirmed","delayed value-only correction settles its caret once after exact content without another text write")
print("PASS deferred AX correction receipt; total \(checks)")

let carried=MemoryInput();carried.carriedWriteGuards=[OutstandingWriteReport(pid:40001,bundleIdentifier:nil,expectedCaret:2,transactionID:UUID().uuidString,mutationAccepted:true)];carried.activate();word(carried,"cat")
check(carried.captureDiagnostics.writeAttempts==0 && carried.attributeNamesSet.isEmpty && carried.captureDiagnostics.lastTargetRefusal=="preservedUnconfirmedWrite","restart-carried unknown write blocks original process without text replay")
carried.cancel("OFF")
check(carried.outstandingWriteReports().count==1,"ordinary cancellation preserves carried metadata guard")
let storageFailed=MemoryInput();storageFailed.activate();storageFailed.trackingPersistenceSucceeds=false;word(storageFailed,"cat")
check(storageFailed.attributeNamesSet.isEmpty && storageFailed.postedTextPIDs.isEmpty && storageFailed.captureDiagnostics.writeAttempts==0 && !storageFailed.writeTrackingReadable,"tracking persistence failure refuses BEFORE any mutation")
storageFailed.cancel("OFF")
print("PASS restart guard and durability port; total \(checks)")
