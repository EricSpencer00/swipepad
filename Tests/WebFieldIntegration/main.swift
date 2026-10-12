// Prepared owned WebKit fixture from authorized Opus implementation response.
@preconcurrency import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import WebKit
import Foundation
import CoreGraphics
import Darwin
import SwipepadCore
import TrackpadBridge

// Owned two-process fixture. `--host` serves an inline page; the default role drives production
// handlers through real AX. Generated contacts only: no hardware, Chromium or Codex claim.
let labels=["s":"Swipepad owned single line","t":"Swipepad owned textarea","c":"Swipepad owned editable","p":"Swipepad owned prewrap editable",
 "g":"Swipepad owned generated placeholder","h":"Swipepad owned aria placeholder","r":"Swipepad owned transformed input","x":"Swipepad owned removed hint"]
let offscreen=CommandLine.arguments.contains("--offscreen")
let probeKey=CommandLine.arguments.firstIndex(of:"--readback-probe").flatMap {i in CommandLine.arguments.indices.contains(i+1) ? CommandLine.arguments[i+1]:nil}
let page="""
<!doctype html><meta charset=utf-8>
<input id=s aria-label="\(labels["s"]!)" type=text>
<textarea id=t aria-label="\(labels["t"]!)" rows=3 cols=48></textarea>
<div id=c role=textbox aria-multiline=true contenteditable=true aria-label="\(labels["c"]!)" style="border:1px solid #888;min-height:2em"></div>
<div id=p role=textbox aria-multiline=true contenteditable=true aria-label="\(labels["p"]!)" style="border:1px solid #888;min-height:2em;white-space:pre-wrap"></div>
<style>#g:empty::before{content:attr(data-placeholder);color:gray}</style>
<div id=g role=textbox contenteditable=true aria-label="\(labels["g"]!)" data-placeholder="Owned fixture hint"></div>
<div id=h role=textbox contenteditable=true aria-label="\(labels["h"]!)" aria-placeholder="Owned fixture hint"></div>
<div id=r role=textbox contenteditable=true aria-label="\(labels["r"]!)"></div>
<div id=x role=textbox contenteditable=true aria-label="\(labels["x"]!)"></div>
<script>
const altered=document.getElementById('r');
altered.addEventListener('input',()=>{
 const text=altered.textContent;
 if(!text)return;
 altered.textContent=text[0].toUpperCase()+text.slice(1);
 const range=document.createRange();range.selectNodeContents(altered);range.collapse(false);
 const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
});
const hinted=document.getElementById('x');
hinted.addEventListener('beforeinput',(event)=>{
 if(!hinted.dataset.hint)return;
 event.preventDefault();
 delete hinted.dataset.hint;hinted.textContent='';
 const range=document.createRange();range.selectNodeContents(hinted);range.collapse(true);
 const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
 document.execCommand('insertText',false,event.data||'');
});
function seed(id,b64,start,end){
 const text=b64==='-'?'':new TextDecoder().decode(Uint8Array.from(atob(b64),c=>c.charCodeAt(0)));
 const e=document.getElementById(id);e.focus();
 if(id==='t'||id==='s'){e.value=text;e.setSelectionRange(start,end);return true}
 e.textContent=text;
 if(id==='x'&&!text){e.textContent='Owned fixture hint';e.dataset.hint='yes'}
 const n=e.firstChild||e,r=document.createRange();
 r.setStart(n,start);r.setEnd(n,end);const s=getSelection();s.removeAllRanges();s.addRange(r);return true}
</script>
"""

@MainActor final class WebHost:NSObject,WKNavigationDelegate {
 let window=NSWindow(contentRect:NSRect(x:offscreen ? -20000:240,y:offscreen ? -20000:240,width:680,height:360),styleMask:offscreen ? [.borderless]:[.titled,.closable],backing:.buffered,defer:false)
 let web:WKWebView={let c=WKWebViewConfiguration();c.websiteDataStore = .nonPersistent();return WKWebView(frame:NSRect(x:0,y:0,width:680,height:360),configuration:c)}()
 func start() {
  NSApp.setActivationPolicy(offscreen ? .prohibited:.regular)
  window.title="Swipepad Owned Web Fixture";window.contentView=web;web.navigationDelegate=self
  web.loadHTMLString(page,baseURL:nil)
  if offscreen {NSApp.setAccessibilityChildren([window])} else {window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
 }
 func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {window.makeFirstResponder(web);reply("ready")}
 func handle(_ line:String) {
  let parts=line.split(separator:" ").map(String.init)
  if offscreen,parts.count==2,parts[0]=="type",let data=Data(base64Encoded:parts[1]),let text=String(data:data,encoding:.utf8) {
   guard let down=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:0),
    let up=NSEvent.keyEvent(with:.keyUp,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:0) else {reply("bad");return}
   web.keyDown(with:down);web.keyUp(with:up);reply("typed");return
  }
  if parts.count==2,parts[0]=="receipt",labels[parts[1]] != nil {
   web.evaluateJavaScript("(()=>{const e=document.getElementById('\(parts[1])');return e.tagName==='TEXTAREA'||e.tagName==='INPUT'?e.value:e.textContent})()") {result,error in
    MainActor.assumeIsolated {self.reply(error==nil ? "value "+Data((result as? String ?? "").utf8).base64EncodedString():"bad")}
   };return
  }
  guard parts.count==5,parts[0]=="seed",labels[parts[1]] != nil,
    parts[2]=="-" || parts[2].unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || "+/=".unicodeScalars.contains($0)}),
    let start=Int(parts[3]),let end=Int(parts[4]) else {reply("bad");return}
  if !offscreen {NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)}
  window.makeFirstResponder(web)
  web.evaluateJavaScript("seed('\(parts[1])','\(parts[2])',\(start),\(end))") {result,error in
   MainActor.assumeIsolated {self.reply(error==nil && result as? Bool==true ? "ok":"bad")}
  }
 }
 func reply(_ s:String) {print(s);fflush(stdout)}
}

if CommandLine.arguments.contains("--host") {
 let app=NSApplication.shared,host=WebHost()
 FileHandle.standardInput.readabilityHandler={handle in
  let data=handle.availableData
  if data.isEmpty {exit(0)} // Driver closed the pipe: owned fixture ends.
  let lines=String(decoding:data,as:UTF8.self).split(separator:"\n").map(String.init)
  DispatchQueue.main.async {MainActor.assumeIsolated {for line in lines {host.handle(line)}}}
 }
 host.start();app.run()
}

// Virtual contact source only in the owned fixture; production activation uses real hardware.
final class WebFixtureInput:AppDelegate {
 override var feedbackWindowsEnabled:Bool {false}
 override var writeTrackingEnabled:Bool {false} // Disposable fixture never modifies production tracking.
 // Scope every production lookup to this test's exact child, even if desktop focus races.
 override var currentApplicationPID:pid_t? {offscreen ? hostProcess.processIdentifier:(NSWorkspace.shared.frontmostApplication?.processIdentifier==hostProcess.processIdentifier ? hostProcess.processIdentifier:nil)}
 override func focused(_ pid:pid_t)->AXUIElement? {guard pid==hostProcess.processIdentifier,hostProcess.isRunning else {return nil};return offscreen ? findOwned(AXUIElementCreateApplication(pid),key:currentKey):super.focused(pid)}
 override func postText(_ events:(CGEvent,CGEvent),to pid:pid_t) {
  guard offscreen else {super.postText(events,to:pid);return}
  precondition(pid==hostProcess.processIdentifier)
  var length=0;events.0.keyboardGetUnicodeString(maxStringLength:0,actualStringLength:&length,unicodeString:nil)
  var units=[UniChar](repeating:0,count:length);events.0.keyboardGetUnicodeString(maxStringLength:length,actualStringLength:&length,unicodeString:&units)
  toHost.fileHandleForWriting.write(Data(("type "+Data(String(decoding:units,as:UTF16.self).utf8).base64EncodedString()+"\n").utf8))
  guard awaitReply(5)=="typed" else {finish("FAIL: offscreen native event dispatch")}
 }
 override func finishActivation() {
  active=true;inputProtectionHealthy=true;strokeSource = .trackpad
  pending=false;pendingWriteID=nil;queuedWords=[];continuationAnchor=nil
  contactGate.reset();frameOrdering.reset(receivedAfter:0);finger=nil;strokeSamples=[];path=[]
  captureDiagnostics.stage="ready"
 }
}
let owner=WebFixtureInput(),app=NSApplication.shared
owner.liftGraceSeconds=0
owner.insertionTransport = CommandLine.arguments.contains("--accessibility-input") ? .accessibility:.keyboard
if CommandLine.arguments.contains("--preflight") {
 let session=CGSessionCopyCurrentDictionary() as? [String:Any]
 print("Fixture preflight: trusted=\(AXIsProcessTrusted()) postAccess=\(owner.canPostText) locked=\(session?["CGSSessionScreenIsLocked"] as? Bool == true) signature=\(owner.runtimeSignatureValid). No field queries or window launch.")
 exit(0)
}
// No production menu/listener launch or persistent preference changes in the driver.
// Toggle, target checks, recognition and writer run against the exact owned child.
app.setActivationPolicy(.prohibited)
let hostProcess=Process(),toHost=Pipe(),fromHost=Pipe()
let originalFrontmost=NSWorkspace.shared.frontmostApplication
var replies:[String]=[],frameNumber:Int32=0,syntheticTime=ProcessInfo.processInfo.systemUptime,failures=0
var currentKey="s"
func findOwned(_ e:AXUIElement,key:String,depth:Int=0)->AXUIElement? {
 guard depth<12 else {return nil}
 let name=(owner.attribute(e,kAXDescriptionAttribute) as? String) ?? (owner.attribute(e,kAXTitleAttribute) as? String)
 if name==labels[key] {return e}
 for child in owner.attribute(e,kAXChildrenAttribute) as? [AXUIElement] ?? [] {if let found=findOwned(child,key:key,depth:depth+1) {return found}}
 return nil
}
func finish(_ message:String)->Never {
 if let data=try? JSONEncoder().encode(owner.captureStatusReport()),let json=String(data:data,encoding:.utf8) {print("Stored fixture evidence: "+json)}
 owner.cancel("Quit")
 if !offscreen,NSWorkspace.shared.frontmostApplication?.processIdentifier==hostProcess.processIdentifier {originalFrontmost?.activate(options:[])}
 try? toHost.fileHandleForWriting.close()
 RunLoop.current.run(until:Date().addingTimeInterval(0.3));if hostProcess.isRunning {hostProcess.terminate()}
 print(message);print("Limits: WebKit owned page, generated contacts; offscreen=\(offscreen) uses virtual focus and direct own-view native key dispatch, not WindowServer PID posting; no Chromium, Codex or hardware qualification.");fflush(stdout)
 exit(failures==0 && message.hasPrefix("PASS") ? 0:2)
}
func awaitReply(_ seconds:Double)->String? {
 let end=Date().addingTimeInterval(seconds)
 while Date()<end {if !replies.isEmpty {return replies.removeFirst()};RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
 return nil
}
func frame(_ contacts:[(Int32,Point,OpenMTState)]) {
 frameNumber += 1;syntheticTime += 0.01;let event=OpenMTEvent()
 event.setValue(syntheticTime,forKey:"timestamp");event.setValue(ProcessInfo.processInfo.systemUptime,forKey:"receivedAt");event.setValue(frameNumber,forKey:"frameID")
 event.setValue(contacts.map {id,p,state in let t=OpenMTTouch();t.setValue(id,forKey:"identifier");t.setValue(Float(p.x),forKey:"posX");t.setValue(Float(p.y),forKey:"posY");t.setValue(state.rawValue,forKey:"state");return t},forKey:"touches")
 owner.touchFrame(event)
}
func curved(_ word:String)->[Point] {
 let centers=word.compactMap {Keyboard.keys[$0]};var points=[centers[0]]
 for (a,b) in zip(centers,centers.dropFirst()) {let d=max(a.distance(b),0.001);for i in 1...12 {let t=Double(i)/12,k=0.018*sin(t*Double.pi);points.append(Point(a.x+(b.x-a.x)*t-(b.y-a.y)/d*k,a.y+(b.y-a.y)*t+(b.x-a.x)/d*k))}}
 return points
}
func swipe(_ word:String,id:Int32) {let p=curved(word);for (i,point) in p.enumerated() {frame([(id,point,i==0 ? .starting:.touching)])};frame([(id,p.last!,.breaking)])}
func ownedField(_ key:String)->AXUIElement? {
 let pid=hostProcess.processIdentifier
 guard offscreen || NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,let f=owner.focused(pid) else {return nil}
 let name=(owner.attribute(f,kAXDescriptionAttribute) as? String) ?? (owner.attribute(f,kAXTitleAttribute) as? String)
 return name==labels[key] ? f:nil
}
struct Case {let name,field,seed:String;let location,length:Int;let words:[String];let expected:String}
var cases:[Case]=[]
for key in ["s","t","c","p"] {cases += [
 Case(name:key+" empty",field:key,seed:"",location:0,length:0,words:["cat","world","test"],expected:"cat world test "),
 Case(name:key+" append",field:key,seed:"Hello",location:5,length:0,words:["world"],expected:"Hello world "),
 Case(name:key+" middle",field:key,seed:"Hello there.",location:5,length:0,words:["world","cat","test"],expected:"Hello world cat test there."),
 Case(name:key+" punctuation",field:key,seed:"Hello.",location:5,length:0,words:["world"],expected:"Hello world."),
 Case(name:key+" selection",field:key,seed:"Hello old friend.",location:6,length:3,words:["world"],expected:"Hello world friend."),
 Case(name:key+" repeated",field:key,seed:"",location:0,length:0,words:["world","world","auto","world","world","auto"],expected:"world world auto world world auto "),
 Case(name:key+" king",field:key,seed:"",location:0,length:0,words:["king"],expected:"king ")]}
func runCase(_ c:Case) {
 owner.cancel("OFF")
 currentKey=c.field
 if !offscreen,NSWorkspace.shared.frontmostApplication?.processIdentifier != hostProcess.processIdentifier {finish("BLOCKED: user focus changed; owned test stopped without taking focus back")}
 let encoded=c.seed.isEmpty ? "-":Data(c.seed.utf8).base64EncodedString()
 toHost.fileHandleForWriting.write(Data("seed \(c.field) \(encoded) \(c.location) \(c.location+c.length)\n".utf8))
 guard awaitReply(5)=="ok" else {finish("FAIL: owned seed refused for \(c.name)")}
 var target:AXUIElement?;let ready=Date().addingTimeInterval(3)
 while Date()<ready {
  if let f=ownedField(c.field),owner.fieldText(f)==c.seed,let r=owner.selection(f),r.location==c.location,r.length==c.length {target=f;break}
  RunLoop.current.run(until:Date().addingTimeInterval(0.05))
 }
 guard let target else {finish("BLOCKED: owned \(c.name) not exposed as focused field with seeded value/range")}
 owner.toggle()
 let activationDeadline=Date().addingTimeInterval(AppDelegate.focusPublicationWaitSeconds+0.2)
 while !owner.active && owner.captureDiagnostics.stage=="awaitingFocusPublication" && Date()<activationDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
 guard owner.active else {failures += 1;print("\(c.name): activation refused \(owner.captureDiagnostics.lastTargetRefusal ?? "none") · \(owner.captureDiagnostics.inputCapabilities ?? "none")");return}
 if let listener=owner.listener {OpenMTManager.shared().remove(listener);owner.listener=nil}
 for (i,w) in c.words.enumerated() {
  swipe(w,id:Int32(20+i))
  let settle=Date().addingTimeInterval(AppDelegate.acceptedWriteSettleSeconds+0.5)
  while owner.pending && Date()<settle {RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
 }
 let observed=owner.fieldText(target) ?? "<unreadable>"
 toHost.fileHandleForWriting.write(Data("receipt \(c.field)\n".utf8))
 let domReply=awaitReply(5)
 let domValue=domReply.flatMap {$0.hasPrefix("value ") ? Data(base64Encoded:String($0.dropFirst(6))):nil}.flatMap {String(data:$0,encoding:.utf8)}
 let exact=observed==c.expected,spaceEquivalent=observed.replacingOccurrences(of:"\u{00a0}",with:" ")==c.expected
 let own=owner.lastOwnedWord
 let ownTail=own.flatMap {w in w.trailingSeparator ? TextReplacement.replacing(c.expected,location:w.range.location+w.range.length-1,length:1,with:"\u{00a0}"):nil}
 // Independent DOM must equal the AX document and exact scenario output; only
 // the last recorded own trailing separator may be NBSP. No whole-field folding.
 let allowed=observed==c.expected || (ownTail != nil && observed==ownTail)
 let d=owner.captureDiagnostics,pass=allowed && domValue==observed && d.insertions==c.words.count && owner.unresolvedWrites.isEmpty
 print("\(pass ? "PASS":"FAIL") \(c.name): backend=\(d.lastInsertionBackend ?? "none") attempts=\(d.writeAttempts) confirmed=\(d.insertions) exactAX=\(exact) exactDOMMatchesAX=\(domValue==observed) ownTrailingNBSP=\(!exact && allowed) diagnosticSpaceEquivalent=\(!exact && spaceEquivalent) unresolved=\(owner.unresolvedWrites.count) capabilities=\(d.inputCapabilities ?? "none")")
 if !pass {failures += 1}
 if !owner.unresolvedWrites.isEmpty {finish("FAIL: unresolved owned write in \(c.name); remaining cases would be refused by design")}
 owner.cancel("OFF")
}
// Deliberately transformed owned editors expose the same high-level symptom as
// an unresolved real attempt. This diagnoses evidence, not third-party behavior.
func runReadbackProbe(_ key:String) {
 guard offscreen,["g","h","r","x"].contains(key) else {finish("BLOCKED: readback probe is owned and offscreen only")}
 currentKey=key
 toHost.fileHandleForWriting.write(Data("seed \(key) - 0 0\n".utf8))
 guard awaitReply(5)=="ok" else {finish("FAIL: readback seed")}
 var target:AXUIElement?;let ready=Date().addingTimeInterval(3)
 while Date()<ready {if let field=ownedField(key),owner.fieldText(field) != nil,let range=owner.selection(field),range.location==0,range.length==0 {target=field;break};RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
 guard let target,let before=owner.fieldText(target) else {finish("BLOCKED: owned readback field unavailable")}
 func dom()->String? {
  toHost.fileHandleForWriting.write(Data("receipt \(key)\n".utf8))
  return awaitReply(5).flatMap {$0.hasPrefix("value ") ? Data(base64Encoded:String($0.dropFirst(6))):nil}.flatMap {String(data:$0,encoding:.utf8)}
 }
 let beforeDOM=dom(),beforeSource=owner.captureDiagnostics.textEvidenceSource
 let direct=owner.attribute(target,kAXValueAttribute) as? String
 owner.toggle();guard owner.active else {finish("FAIL: readback activation refused")}
 swipe("cat",id:20)
 let afterDeadline=Date().addingTimeInterval(0.3)
 while owner.pending && Date()<afterDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.02))}
 let after=owner.fieldText(target),afterDOM=dom()
 let d=owner.captureDiagnostics
 let changed=key=="r" || key=="x"
 if changed {
  let once=d.writeAttempts==1 && d.insertions==0 && owner.unresolvedWrites.count==1
  let matchedCaret=d.confirmationIdentityMatches==true && d.confirmationCaretMatches==true && d.confirmationContentMatches==false
  swipe("world",id:21)
  let noSecond=owner.captureDiagnostics.writeAttempts==1
  let stopDeadline=Date().addingTimeInterval(AppDelegate.acceptedWriteSettleSeconds+0.5)
  while owner.pending && Date()<stopDeadline {RunLoop.current.run(until:Date().addingTimeInterval(0.05))}
  let retained=owner.unresolvedWrites.count==1 && !owner.active && owner.captureDiagnostics.writeAttempts==1
  let evidence=owner.captureDiagnostics
  let expectedKind=key=="r" ? "insertedTextChanged":"surroundingTextChanged"
  let classified=evidence.confirmationEvidenceKind==expectedKind && evidence.writeBeforeUTF16Length==before.utf16.count && evidence.confirmationObservedUTF16Length==after?.utf16.count
  if !(once && matchedCaret && noSecond && retained && afterDOM==after && classified) {failures += 1}
  print("\(failures==0 ? "PASS":"FAIL") owned readback \(key): beforeAXLength=\(before.utf16.count) beforeDOMLength=\(beforeDOM?.utf16.count ?? -1) beforeSource=\(beforeSource ?? "none") directEqualsRange=\(direct==before) afterAXLength=\(after?.utf16.count ?? -1) afterDOMMatchesAX=\(afterDOM==after) caretMatches=\(matchedCaret) dispatchedOnce=\(once && noSecond) guardRetained=\(retained) classified=\(classified)")
 } else {
  let pass=before.isEmpty && beforeDOM==before && afterDOM==after && d.insertions==1 && owner.unresolvedWrites.isEmpty
  if !pass {failures += 1}
  print("\(pass ? "PASS":"FAIL") owned placeholder \(key): beforeAXLength=\(before.utf16.count) beforeDOMLength=\(beforeDOM?.utf16.count ?? -1) beforeSource=\(beforeSource ?? "none") directEqualsRange=\(direct==before) afterAXLength=\(after?.utf16.count ?? -1) afterDOMMatchesAX=\(afterDOM==after) confirmed=\(d.insertions)")
 }
 finish(failures==0 ? "PASS: owned readback evidence probe":"FAIL: owned readback evidence probe")
}
Timer.scheduledTimer(withTimeInterval:0.3,repeats:false) {_ in MainActor.assumeIsolated {
 let session=CGSessionCopyCurrentDictionary() as? [String:Any]
 guard session?["CGSSessionScreenIsLocked"] as? Bool != true else {finish("BLOCKED: owned GUI fixture requires unlocked coordinated session; no window launched")}
 guard AXIsProcessTrusted(),!owner.secureInputActive,let executable=Bundle.main.executableURL else {finish("BLOCKED: existing Accessibility trust and Secure Input off required; nothing requested")}
 guard owner.insertionTransport != .keyboard || owner.canPostText else {finish("BLOCKED: existing keyboard-delivery access required; nothing requested")}
 fromHost.fileHandleForReading.readabilityHandler={handle in
  let lines=String(decoding:handle.availableData,as:UTF8.self).split(separator:"\n").map(String.init)
  DispatchQueue.main.async {MainActor.assumeIsolated {replies += lines}}
 }
 hostProcess.executableURL=executable;hostProcess.arguments=offscreen ? ["--host","--offscreen"]:["--host"];hostProcess.standardInput=toHost;hostProcess.standardOutput=fromHost
 do {try hostProcess.run()} catch {finish("BLOCKED: owned host launch")}
 guard awaitReply(10)=="ready" else {finish("BLOCKED: owned page not ready")}
 if let probeKey {runReadbackProbe(probeKey)}
 for c in cases {runCase(c)}
 finish(failures==0 ? "PASS: owned WebKit textarea and contenteditable sentence delivery":"FAIL: \(failures) owned web cases")
}}
app.run()
