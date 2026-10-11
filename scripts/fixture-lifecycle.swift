// Local test lifecycle only. Never launches TextEdit, requests access, or discards edits.
import AppKit
import ApplicationServices
import Foundation
import CryptoKit
import Darwin
func attr(_ e:AXUIElement,_ key:String)->CFTypeRef? {var value:CFTypeRef?;guard AXUIElementCopyAttributeValue(e,key as CFString,&value) == .success else {return nil};return value}
func element(_ value:CFTypeRef?)->AXUIElement? {guard let value,CFGetTypeID(value)==AXUIElementGetTypeID() else {return nil};return unsafeDowncast(value,to:AXUIElement.self)}
guard AXIsProcessTrusted() else {print("Fixture lifecycle lacks existing AX; no prompt requested.");exit(2)}
guard let textEdit=NSWorkspace.shared.runningApplications.first(where:{$0.bundleIdentifier=="com.apple.TextEdit"}) else {exit(0)}
let windows=attr(AXUIElementCreateApplication(textEdit.processIdentifier),kAXWindowsAttribute) as? [AXUIElement] ?? []
func document(_ window:AXUIElement)->URL? {(attr(window,kAXDocumentAttribute) as? String).flatMap(URL.init(string:))?.resolvingSymlinksInPath()}
if CommandLine.arguments.contains("--preflight") {
  for window in windows {
    guard let url=document(window) else {continue}
    if url.lastPathComponent.hasPrefix("Swipepad"),url.path.contains("swipepad-") {
      print("BLOCKED: an earlier owned-looking fixture remains open. Preserve and close it before another live run: \(url.path)");exit(3)
    }
  }
  exit(0)
}
guard CommandLine.arguments.count==4,CommandLine.arguments[1]=="--finish" else {print("Use --preflight or --finish exact-owned-document evidence-directory");exit(2)}
let owned=URL(fileURLWithPath:CommandLine.arguments[2]).resolvingSymlinksInPath()
let marker=owned.deletingLastPathComponent().appendingPathComponent(".swipepad-owned")
guard owned.lastPathComponent=="Swipepad Automated Fixture.rtf",FileManager.default.fileExists(atPath:marker.path),
  let window=windows.first(where:{document($0)?.path==owned.path}) else {print("No registered owned fixture window open; nothing closed.");exit(0)}
let folder=URL(fileURLWithPath:CommandLine.arguments[3],isDirectory:true).appendingPathComponent(UUID().uuidString,isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
try FileManager.default.copyItem(at:owned,to:folder.appendingPathComponent("original-on-disk.rtf"))
func textAreas(_ node:AXUIElement,depth:Int=0)->[AXUIElement] {
  guard depth<10 else {return []}
  if attr(node,kAXRoleAttribute) as? String==kAXTextAreaRole {return [node]}
  return (attr(node,kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(100).flatMap {textAreas($0,depth:depth+1)}
}
let areas=textAreas(window)
guard areas.count==1,let text=attr(areas[0],kAXValueAttribute) as? String,document(window)?.path==owned.path else {print("Ambiguous owned buffer; retained window and original backup at \(folder.path)");exit(3)}
try text.write(to:folder.appendingPathComponent("unsaved-contents.txt"),atomically:true,encoding:.utf8)
let edited=(attr(window,kAXEditedAttribute) as? NSNumber)?.boolValue
let receipt:[String:Any]=["document":owned.path,"edited":edited.map {$0 ? "true" : "false"} ?? "unknown","contentsSHA256":SHA256.hash(data:Data(text.utf8)).map {String(format:"%02x",$0)}.joined(),"snapshot":"UTF-8 contents plus original RTF; edited rich document still requires native Save As before closing","windowRetained":edited != false]
try JSONSerialization.data(withJSONObject:receipt,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("receipt.json"))
guard edited==false else {print("CLEANUP REQUIRED: contents preserved at \(folder.path). Save As to a new unique evidence RTF, verify saved URL/Edited cleared, then close only this window. Never Don't Save. Next live run is blocked until it closes.");exit(3)}
guard let close=element(attr(window,kAXCloseButtonAttribute)),document(window)?.path==owned.path,
  AXUIElementPerformAction(close,kAXPressAction as CFString) == .success else {print("Close unavailable; retained owned fixture.");exit(3)}
print("Closed saved registered fixture only; snapshot at \(folder.path)")
