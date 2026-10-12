@preconcurrency import AppKit
@preconcurrency import WebKit
import Foundation
import Darwin

// Isolated WebKit editing engine probe, no global input, AX, ordered window or user text.
// This explains formatting only; it does not qualify PID keyboard dispatch or hardware.
let page="""
<input id=s><textarea id=t></textarea>
<div id=c contenteditable=true></div>
<div id=p contenteditable=true style="white-space:pre-wrap"></div>
<script>
function probe(){
 const rows=[];
 for(const id of ['s','t','c','p']){
  const e=document.getElementById(id);e.focus();
  if(id==='s'||id==='t'){e.value='';e.setSelectionRange(0,0)}
  else {e.textContent='';const r=document.createRange();r.selectNodeContents(e);r.collapse(false);const s=getSelection();s.removeAllRanges();s.addRange(r)}
  let expected='',previous='';
  for(const word of ['cat ','world ','auto ','world ']){
   const applied=document.execCommand('insertText',false,word);
   expected+=word;const actual=id==='s'||id==='t'?e.value:e.textContent;
   const changes=[];for(let i=0;i<previous.length;i++){if(previous.charCodeAt(i)!==actual.charCodeAt(i)){changes.push([i,previous.charCodeAt(i),actual.charCodeAt(i)])}}
   const spaces=[];const nbsp=[];for(let i=0;i<actual.length;i++){if(actual.charCodeAt(i)===32)spaces.push(i);if(actual.charCodeAt(i)===160)nbsp.push(i)}
   rows.push({id,step:rows.filter(x=>x.id===id).length+1,applied,length:actual.length,spaces,nbsp,previousChanges:changes,lettersAndSpacesMatch:actual.replaceAll('\\u00a0',' ')===expected});previous=actual;
  }
 }
 return rows;
}
</script>
"""
@MainActor final class Probe:NSObject,WKNavigationDelegate {
  let beforePID=NSWorkspace.shared.frontmostApplication?.processIdentifier
  let window=NSWindow(contentRect:NSRect(x:-20000,y:-20000,width:600,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
  let web:WKWebView={let c=WKWebViewConfiguration();c.websiteDataStore = .nonPersistent();return WKWebView(frame:NSRect(x:0,y:0,width:600,height:300),configuration:c)}()
  func start(){window.contentView=web;web.navigationDelegate=self;web.loadHTMLString(page,baseURL:nil)}
  func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){
    web.evaluateJavaScript("probe()") {value,error in MainActor.assumeIsolated {
      guard error==nil,let rows=value as? [[String:Any]],let data=try? JSONSerialization.data(withJSONObject:rows,options:[.sortedKeys]),let json=String(data:data,encoding:.utf8) else {print("FAIL offscreen editing probe");exit(2)}
      print(json)
      let unchanged=self.beforePID==NSWorkspace.shared.frontmostApplication?.processIdentifier
      print("Offscreen=true · windowVisible=\(self.window.isVisible) · foregroundUnchanged=\(unchanged)");fflush(stdout)
      exit(!self.window.isVisible && unchanged ? 0:2)
    }}
  }
}
let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
let probe=Probe();probe.start()
Timer.scheduledTimer(withTimeInterval:20,repeats:false){_ in print("BLOCKED offscreen WebKit timeout; no foreground activity");fflush(stdout);exit(3)}
app.run()
