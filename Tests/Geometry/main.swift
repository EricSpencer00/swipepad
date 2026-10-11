import AppKit
import SwipepadCore
import TrackpadBridge
// Offscreen source-path checks: no application launch, listener, permission prompt or pointer event.
let delegate=AppDelegate();delegate.liftGraceSeconds=0
var count=0
func check(_ condition:Bool,_ message:String) {precondition(condition,message);count += 1}
let points=[Point(0,0),Point(1,1),Point(0.05,0.8),Point(0.1,0.5),Point(0.2,0.2),Point(0.95,0.8)]
let layouts=[CalibrationRect(x:0,y:0,width:800,height:304),CalibrationRect(x:-1600,y:80,width:1200,height:456)]
for mode in [InputMode.trackpad,.screenOverlay] {
  delegate.strokeSource=mode
  for layout in layouts {
    delegate.overlayFrame=layout;delegate.strokeCalibration=layout
    for point in points {
      let touch=OpenMTTouch();touch.setValue(Float(point.x),forKey:"posX");touch.setValue(Float(point.y),forKey:"posY")
      let actual=delegate.samplePoint(touch)!
      check(actual.normalized.distance(point)<0.000001,"production sample changed with presentation/display geometry")
      check(actual.native==actual.normalized,"source must retain normalized physical contact")
      check(Keyboard.nearestKey(actual.normalized)==Keyboard.nearestKey(point),"first-letter mapping changed")
    }
  }
}
let frozen=layouts[0];delegate.strokeCalibration=frozen;delegate.overlayFrame=layouts[1]
check(delegate.strokeCalibration==frozen,"midstroke layout must stay frozen")
delegate.path=points;delegate.strokeSamples=points.enumerated().map {StrokeSample($0.element,time:Double($0.offset),source:.screenOverlay)}
delegate.renderStroke()
check(delegate.overlayKeyboard.path==points,"renderer must retain every contact and terminal point")
check(!delegate.overlayKeyboard.isFlipped,"canonical physical geometry uses bottom-left view coordinates")
print("Passed \(count) offscreen production mapping checks. No physical callback, hardware Y orientation, focus or insertion tested.")

let priorGuide=UserDefaults.standard.object(forKey:"showGuide")
delegate.panel=GuidePanel(contentRect:NSRect(x:0,y:0,width:600,height:360),styleMask:[.nonactivatingPanel],backing:.buffered,defer:false)
for mode in [InputMode.trackpad,.screenOverlay] {
  delegate.strokeSource=mode
  for show in [false,true] {
    UserDefaults.standard.set(show,forKey:"showGuide");delegate.applyGuideVisibility()
    check(delegate.keyboard.isHidden == (mode == .screenOverlay || !show),"consistent whole-guide visibility")
    check(abs(delegate.panel.contentView!.frame.height - (mode == .trackpad && show ? 360 : 145))<0.1,"hidden guide collapses blank space")
  }
}
if let priorGuide {UserDefaults.standard.set(priorGuide,forKey:"showGuide")} else {UserDefaults.standard.removeObject(forKey:"showGuide")}
check(delegate.keyboard is OverlayKeyboardView,"default guide uses same marker and key highlight renderer")
print("Passed \(count) offscreen production checks, including whole-guide visibility and shared renderer. No UI shown or physical callbacks tested.")

delegate.showFeedback("Focus an editable text area")
check(delegate.feedbackPanel==nil,"missing-field feedback creates no popup")
check(delegate.statusReason=="Focus an editable text area","refusal reason remains inspectable without dismissal")
delegate.cancel("Application changed")
check(!delegate.panel.isVisible && delegate.feedbackPanel==nil,"focus cancellation leaves no window to exit")
print("Passed \(count) offscreen checks including nonintrusive refusal/cancel feedback.")

// Exercise production mode routing without desktop events or AX writes.
delegate.active=true
delegate.strokeToken=7
for reason in ["Application changed","Focus changed","Insertion failed"] {
  delegate.cancel(reason)
  check(delegate.active,"refusal must leave enabled mode on")
  check(delegate.target==nil && delegate.originalSelection==nil,"refusal clears old insertion ownership")
  check(delegate.retiredToken==7,"discarded stroke cannot commit again")
}
let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:10,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:53)!
delegate.handle(escape)
check(!delegate.active,"Escape exits mode and hides guide")
delegate.active=true // Fresh fixture activation, no listener or desktop event.
delegate.stopOrDismiss();delegate.retry()
check(delegate.active,"button actions cannot toggle enabled mode")
check(!delegate.windowShouldClose(delegate.panel),"guide close cannot exit enabled mode")
check(!delegate.insertWord("cat",alternatives:["cat"]),"unowned field cannot receive insertion")
check(delegate.active,"failed insertion must leave mode enabled")
let filter=HotCornerProtection(isActive:{delegate.active},failed:{},escapePressed:{delegate.cancel("OFF")})
for type in [CGEventType.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp] {
  check(filter.blocksClick(type),"all enabled button actions blocked")
}
check(!filter.blocksClick(.mouseMoved),"pointer movement is distinct from button actions")
delegate.toggle()
check(!delegate.active,"toggle exits enabled mode")
check(!filter.blocksClick(.leftMouseDown),"normal clicks restored off")
print("Passed \(count) offscreen checks including sticky production routing; no actual event-tap, physical contact or AX insertion tested.")

for type in [CGEventType.leftMouseDragged,.rightMouseDragged,.otherMouseDragged] {
  delegate.active=true
  check(filter.blocksPointerAction(type),"active orphaned drag suppressed across receiving/overlay boundaries")
  delegate.active=false
  check(!filter.blocksPointerAction(type),"normal drag restored off")
}

// AppKit boundary events are presentation-only. No AX target is relaxed here.
for level in [NSWindow.Level.normal,.floating,.statusBar] {
  let window=NSPanel(contentRect:NSRect(x:0,y:0,width:800,height:304),styleMask:[.nonactivatingPanel],backing:.buffered,defer:true)
  window.level=level;window.contentView=delegate.overlayKeyboard
  delegate.path=points;delegate.strokeSamples=points.enumerated().map {StrokeSample($0.element,time:Double($0.offset),source:.screenOverlay)};delegate.renderStroke()
  let before=delegate.strokeSamples
  for location in [NSPoint(x:-1,y:150),NSPoint(x:400,y:150),NSPoint(x:801,y:150)] {
    for type in [NSEvent.EventType.mouseEntered,.mouseExited] {
      if let event=NSEvent.enterExitEvent(with:type,location:location,modifierFlags:[],timestamp:20,windowNumber:window.windowNumber,context:nil,eventNumber:1,trackingNumber:1,userData:nil) {
        if type == .mouseEntered {delegate.overlayKeyboard.mouseEntered(with:event)} else {delegate.overlayKeyboard.mouseExited(with:event)}
        check(delegate.strokeSamples.count==before.count && delegate.overlayKeyboard.path==points,"window boundary must not alter physical stroke or displayed trace")
      }
    }
  }
}
print("Final checks: \(count). Boundary events are offscreen; no receiving-window hardware or event-tap proof.")

// Construct transport events without posting them or changing desktop focus.
for text in ["auto ","a ","I ","hello ","caf\u{00e9} ","\u{1f600} "] {
  let events=AppDelegate.textEvents(text)!
  for event in [events.0,events.1] {
    var length=0;var units=[UniChar](repeating:0,count:128)
    event.keyboardGetUnicodeString(maxStringLength:units.count,actualStringLength:&length,unicodeString:&units)
    check(String(utf16CodeUnits:units,count:length)==text,"Unicode event must retain exact payload including trailing space")
    check(event.flags.isEmpty,"delivery must not inherit held Command/Option modifiers")
    check(event.getIntegerValueField(.eventSourceUserData)==AppDelegate.ownTextEventTag,"own event marker must avoid cancelling capture")
  }
  let before=delegate.active
  delegate.handle(NSEvent(cgEvent:events.0)!)
  check(delegate.active==before,"own text event must not alter sticky mode")
}
check(AppDelegate.textEvents("")==nil,"empty delivery must not fabricate a keypress")
print("Final transport/mapping checks: \(count). No event posting or receiving-app insertion tested.")
