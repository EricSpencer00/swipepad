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
let labels=["t":"Swipepad owned textarea","c":"Swipepad owned editable","p":"Swipepad owned prewrap editable"]
let page="""
<!doctype html><meta charset=utf-8>
<textarea id=t aria-label="\(labels["t"]!)" rows=3 cols=48></textarea>
<div id=c role=textbox aria-multiline=true contenteditable=true aria-label="\(labels["c"]!)" style="border:1px solid #888;min-height:2em"></div>
<div id=p role=textbox aria-multiline=true contenteditable=true aria-label="\(labels["p"]!)" style="border:1px solid #888;min-height:2em;white-space:pre-wrap"></div>
<script>
function seed(id,b64,start,end){
 const text=b64==='-'?'':new TextDecoder().decode(Uint8Array.from(atob(b64),c=>c.charCodeAt(0)));
 const e=document.getElementById(id);e.focus();
 if(id==='t'){e.value=text;e.setSelectionRange(start,end);return true}
 e.textContent=text;const n=e.firstChild||e,r=document.createRange();
 r.setStart(n,start);r.setEnd(n,end);const s=getSelection();s.removeAllRanges();s.addRange(r);return true}
</script>
"""

@MainActor final class WebHost:NSObject,WKNavigationDelegate {
 let window=NSWindow(contentRect:NSRect(x:240,y:240,width:680,height:360),styleMask:[.titled,.closable],backing:.buffered,defer:false)
 let web=WKWebView(frame:NSRect(x:0,y:0,width:680,height:360))
 func start() {
  NSApp.setActivationPolicy(.regular)
  window.title="Swipepad Owned Web Fixture";window.contentView=web;web.navigationDelegate=self
  web.loadHTMLString(page,baseURL:nil);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
 }
 func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {window.makeFirstResponder(web);reply("ready")}
 func handle(_ line:String) {
  let parts=line.split(separator:" ").map(String.init)
  guard parts.count==5,parts[0]=="seed",labels[parts[1]] != nil,
    parts[2]=="-" || parts[2].unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0) || "+/=".unicodeScalars.contains($0)}),
    let start=Int(parts[3]),let end=Int(parts[4]) else {reply("bad");return}
  NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil);window.makeFirstResponder(web)
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
 override func finishActivation() {
  active=true;inputProtectionHealthy=true;strokeSource = .trackpad
  pending=false;pendingWriteID=nil;queuedWords=[];continuationAnchor=nil
  contactGate.reset();frameOrdering.reset(receivedAfter:0);finger=nil;strokeSamples=[];path=[]
  captureDiagnostics.stage="ready"
 }
}
let owner=WebFixtureInput(),app=NSApplication.shared
owner.liftGraceSeconds=0;owner.insertionTransport = .accessibility
app.delegate=owner
UserDefaults.standard.set(true,forKey:"hasLaunched");UserDefaults.standard.set(false,forKey:"showGuide");UserDefaults.standard.set("trackpad",forKey:"inputMode")
let hostProcess=Process(),toHost=Pipe(),fromHost=Pipe()
var replies:[String]=[],frameNumber:Int32=0,syntheticTime=ProcessInfo.processInfo.systemUptime,failures=0
func finish(_ message:String)->Never {
 if let data=try? JSONEncoder().encode(owner.captureStatusReport()),let json=String(data:data,encoding:.utf8) {print("Stored fixture evidence: "+json)}
 owner.cancel("Quit");try? toHost.fileHandleForWriting.close()
 RunLoop.current.run(until:Date().addingTimeInterval(0.3));if hostProcess.isRunning {hostProcess.terminate()}
 print(message);print("Limits: WebKit owned page, generated contacts; no Chromium, Codex or hardware qualification.");fflush(stdout)
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
 guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid,let f=owner.focused(pid) else {return nil}
 let name=(owner.attribute(f,kAXDescriptionAttribute) as? String) ?? (owner.attribute(f,kAXTitleAttribute) as? String)
 return name==labels[key] ? f:nil
}
struct Case {let name,field,seed:String;let location,length:Int;let words:[String];let expected:String}
var cases:[Case]=[]
for key in ["t","c","p"] {cases += [
 Case(name:key+" empty",field:key,seed:"",location:0,length:0,words:["cat","world","test"],expected:"cat world test "),
 Case(name:key+" append",field:key,seed:"Hello",location:5,length:0,words:["world"],expected:"Hello world "),
 Case(name:key+" middle",field:key,seed:"Hello there.",location:5,length:0,words:["world","cat","test"],expected:"Hello world cat test there."),
 Case(name:key+" punctuation",field:key,seed:"Hello.",location:5,length:0,words:["world"],expected:"Hello world."),
 Case(name:key+" selection",field:key,seed:"Hello old friend.",location:6,length:3,words:["world"],expected:"Hello world friend.")]}
func runCase(_ c:Case) {
 owner.cancel("OFF")
 let encoded=c.seed.isEmpty ? "-":Data(c.seed.utf8).base64EncodedString()
 toHost.fileHandleForWriting.write(Data("seed \(c.field) \(encoded) \(c.location) \(c.location+c.length)\n".utf8))
 guard awaitReply(5)=="ok" else {finish("FAIL: owned seed refused for \(c.name)")}
 var target:AXUIElement?;let ready=Date().addingTimeInterval(3)
 while Date()<ready {
  if let f=ownedField(c.field),owner.attribute(f,kAXValueAttribute) as? String==c.seed,let r=owner.selection(f),r.location==c.location,r.length==c.length {target=f;break}
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
 let observed=owner.attribute(target,kAXValueAttribute) as? String ?? "<unreadable>"
 let exact=observed==c.expected,spaceEquivalent=observed.replacingOccurrences(of:"\u{00a0}",with:" ")==c.expected
 let d=owner.captureDiagnostics,pass=exact && d.insertions==c.words.count && owner.unresolvedWrites.isEmpty
 print("\(pass ? "PASS":"FAIL") \(c.name): backend=\(d.lastInsertionBackend ?? "none") attempts=\(d.writeAttempts) confirmed=\(d.insertions) exact=\(exact) nbspOnlyDifference=\(!exact && spaceEquivalent) unresolved=\(owner.unresolvedWrites.count) capabilities=\(d.inputCapabilities ?? "none")")
 if !pass {failures += 1}
 if !owner.unresolvedWrites.isEmpty {finish("FAIL: unresolved owned write in \(c.name); remaining cases would be refused by design")}
 owner.cancel("OFF")
}
Timer.scheduledTimer(withTimeInterval:0.3,repeats:false) {_ in MainActor.assumeIsolated {
 let session=CGSessionCopyCurrentDictionary() as? [String:Any]
 guard session?["CGSSessionScreenIsLocked"] as? Bool != true else {finish("BLOCKED: owned GUI fixture requires unlocked coordinated session; no window launched")}
 guard AXIsProcessTrusted(),!owner.secureInputActive,let executable=Bundle.main.executableURL else {finish("BLOCKED: existing Accessibility trust and Secure Input off required; nothing requested")}
 fromHost.fileHandleForReading.readabilityHandler={handle in
  let lines=String(decoding:handle.availableData,as:UTF8.self).split(separator:"\n").map(String.init)
  DispatchQueue.main.async {MainActor.assumeIsolated {replies += lines}}
 }
 hostProcess.executableURL=executable;hostProcess.arguments=["--host"];hostProcess.standardInput=toHost;hostProcess.standardOutput=fromHost
 do {try hostProcess.run()} catch {finish("BLOCKED: owned host launch")}
 guard awaitReply(10)=="ready" else {finish("BLOCKED: owned page not ready")}
 for c in cases {runCase(c)}
 finish(failures==0 ? "PASS: owned WebKit textarea and contenteditable sentence delivery":"FAIL: \(failures) owned web cases")
}}
app.run()
