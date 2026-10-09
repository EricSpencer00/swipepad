// Separate harness only: cursor/contact fixtures, real native panel clicks and owned AX receipts.
@preconcurrency import AppKit
@preconcurrency import CoreGraphics
@preconcurrency import ApplicationServices
import Foundation
import SwipepadCore
import TrackpadBridge

@MainActor var overlayTrial=0
@MainActor func later(_ delay:Double=0.04,_ action:@escaping @MainActor ()->Void) {
  let timer=Timer(timeInterval:delay,repeats:false) {_ in MainActor.assumeIsolated {action()}}
  RunLoop.main.add(timer,forMode:.default);RunLoop.main.add(timer,forMode:.eventTracking)
}
@MainActor func screenEventPoint(_ point:Point)->CGPoint {
  CGPoint(x:point.x,y:(NSScreen.screens.first?.frame.maxY ?? 0)-point.y)
}
@MainActor func mouseClick(_ point:Point,scope:@escaping @MainActor ()->Bool,then:@escaping @MainActor ()->Void) {
  guard scope(),CGPreflightPostEventAccess(),
    let down=CGEvent(mouseEventSource:nil,mouseType:.leftMouseDown,mouseCursorPosition:screenEventPoint(point),mouseButton:.left),
    let up=CGEvent(mouseEventSource:nil,mouseType:.leftMouseUp,mouseCursorPosition:screenEventPoint(point),mouseButton:.left) else {stop("ABORT: owned native click scope unavailable.");return}
  down.setIntegerValueField(.mouseEventClickState,value:1);up.setIntegerValueField(.mouseEventClickState,value:1)
  down.post(tap:.cghidEventTap)
  later {guard scope() else {stop("ABORT: native click lost owned scope before release.");return};up.post(tap:.cghidEventTap);later(0.12,then)}
}
@MainActor func moveCursor(_ point:Point,then:@escaping @MainActor ()->Void) {
  guard ownedField() != nil,CGPreflightPostEventAccess(),
    let event=CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:screenEventPoint(point),mouseButton:.left) else {stop("ABORT: owned cursor fixture scope unavailable.");return}
  event.post(tap:.cghidEventTap)
  later(0.02) {
    guard ownedField() != nil else {stop("ABORT: cursor fixture lost owned document.");return}
    let actual=NSEvent.mouseLocation
    guard Point(actual.x,actual.y).distance(point)<1.5 else {stop("FAIL: AppKit/CGEvent screen coordinate disagreement.");return}
    then()
  }
}
@MainActor func activateOwned(_ action:@escaping @MainActor ()->Void) {
  guard let textEdit=NSWorkspace.shared.runningApplications.first(where:{$0.bundleIdentifier=="com.apple.TextEdit"}),let url=textEdit.bundleURL else {stop("ABORT: TextEdit unavailable for owned overlay trial.");return}
  let config=NSWorkspace.OpenConfiguration();config.activates=true;config.createsNewApplicationInstance=false
  NSWorkspace.shared.open([document],withApplicationAt:url,configuration:config) {_,error in Task {@MainActor in
    guard error==nil else {stop("ABORT: owned overlay document activation failed.");return}
    later(0.2) {guard ownedField() != nil else {stop("ABORT: owned overlay document focus missing.");return};action()}
  }}
}
@MainActor func overlayLayoutChecks() {
  guard let field=ownedField(),let baseline=delegate.attribute(field,kAXValueAttribute) as? String else {stop("ABORT: owned field unavailable before layout.");return}
  let item=NSMenuItem(title:"Screen Overlay Mode",action:nil,keyEquivalent:"");item.representedObject=InputMode.screenOverlay.rawValue
  delegate.chooseMode(item)
  guard delegate.inputMode == .screenOverlay,UserDefaults.standard.string(forKey:"inputMode")==InputMode.screenOverlay.rawValue else {stop("FAIL: selectable overlay persistence.");return}
  delegate.showOverlayLayout()
  later(0.2) {
    guard let window=delegate.layoutPanel,let preview=delegate.layoutPreview,let screen=window.screen,
      window.canBecomeKey,window.styleMask.contains(.resizable),!delegate.active,delegate.overlayPanel?.isVisible != true else {stop("FAIL: ordinary capture-off layout window.");return}
    window.setContentSize(NSSize(width:700,height:390))
    window.setFrameOrigin(NSPoint(x:screen.visibleFrame.minX+40,y:screen.visibleFrame.minY+60))
    window.layoutIfNeeded();preview.layoutSubtreeIfNeeded()
    guard abs(preview.canvas.bounds.height/preview.canvas.bounds.width-0.38)<0.000001 else {stop("FAIL: resized preview keyboard aspect.");return}
    let saved=window.convertToScreen(preview.canvas.convert(preview.canvas.bounds,to:nil))
    guard screen.visibleFrame.contains(saved),let save=preview.controls.arrangedSubviews.compactMap({$0 as? NSButton}).first(where:{$0.title=="Use This Layout"}) else {stop("FAIL: calibration save fixture bounds/control.");return}
    let center=window.convertPoint(toScreen:save.convert(NSPoint(x:save.bounds.midX,y:save.bounds.midY),to:nil))
    print("Layout native Save control: bounds=\(save.bounds), frame=\(save.frame), screen center=\(center), canvas=\(saved)");fflush(stdout)
    later(0.25) {mouseClick(Point(center.x,center.y),scope:{NSWorkspace.shared.frontmostApplication?.processIdentifier==ProcessInfo.processInfo.processIdentifier}) {
      UserDefaults.standard.synchronize()
      let restored=delegate.overlayRect(screen)
      print("Layout receipt: visible=\(window.isVisible), saved=\(saved), restored=\(restored), stored=\(String(describing:UserDefaults.standard.array(forKey:delegate.displayKey(screen))))");fflush(stdout)
      guard !window.isVisible,abs(restored.minX-saved.minX)<0.01,abs(restored.minY-saved.minY)<0.01,
        abs(restored.width-saved.width)<0.01,abs(restored.height-saved.height)<0.01,
        UserDefaults.standard.array(forKey:delegate.displayKey(screen)) != nil else {stop("FAIL: actual layout button did not persist 1:1 keyboard geometry.");return}
      print("PASS: ordinary layout preview resized with aspect 0.38; native Save click persists/restores 1:1 geometry with capture off.")
      activateOwned {
        guard let current=ownedField(),CFEqual(current,field),delegate.attribute(current,kAXValueAttribute) as? String==baseline else {stop("FAIL: layout altered owned text.");return}
        overlayCandidateTrial()
      }
    }}
  }
}
@MainActor func overlayStart()->Bool {
  delegate.toggle()
  guard delegate.active,delegate.validTarget(),delegate.strokeSource == .screenOverlay,
    delegate.overlayPanel?.isVisible == true,delegate.overlayFrame?.isValid == true else {return false}
  if let listener=delegate.listener {OpenMTManager.shared().remove(listener);delegate.listener=nil}
  frame(nil)
  return true
}
@MainActor func feedOverlay(_ points:[Point],index:Int=0,then:@escaping @MainActor ()->Void) {
  guard let calibration=delegate.overlayFrame,delegate.active,delegate.validTarget() else {stop("ABORT: overlay fixture lost calibration/target.");return}
  if index==points.count {frame(nil);then();return}
  moveCursor(calibration.screenPoint(points[index])) {
    // Deliberately unrelated physical position proves this mode samples cursor geometry.
    frame(Point(0.01,0.02))
    guard delegate.active,let last=delegate.strokeSamples.last,
      last.source == .screenOverlay,last.point.distance(points[index])<0.005 else {stop("FAIL: overlay used physical coordinates or lost cursor sample.");return}
    feedOverlay(points,index:index+1,then:then)
  }
}
@MainActor func overlayCandidateTrial() {
  guard let field=ownedField(),let baseline=delegate.attribute(field,kAXValueAttribute) as? String,
    let range=delegate.selection(field),overlayStart(),let calibration=delegate.overlayFrame else {stop("FAIL: native overlay trial activation.");return}
  overlayTrial += 1
  moveCursor(calibration.screenPoint(Point(0.4,0.5))) {
    guard delegate.strokeSamples.isEmpty,delegate.finger==nil,delegate.validTarget() else {stop("FAIL: pointer movement alone started a stroke.");return}
    feedOverlay(Keyboard.path(overlayTrial==2 ? "world" : "hello")) {
      guard delegate.pending,!delegate.strokeSamples.isEmpty,
        delegate.overlayKeyboard.path==delegate.strokeSamples.map(\.point),
        delegate.strokeSamples.first?.phase == .began,delegate.strokeSamples.last?.phase == .ended else {stop("FAIL: completed overlay trail/sample mismatch.");return}
      let index=overlayTrial==2 ? 1 : 0,button=delegate.buttons[overlayTrial==2 ? 1 : 0]
      guard !button.isHidden else {stop("FAIL: overlay candidate missing.");return}
      let chosen=button.title
      let receipt=(baseline as NSString).replacingCharacters(in:NSRange(location:range.location,length:range.length),with:chosen+" ")
      mouseClick(calibration.screenPoint(Point(0.25,0.82)),scope:{ownedField().map({CFEqual($0,field)})==true}) {
        guard delegate.active,delegate.pending,delegate.validTarget(),
          delegate.attribute(field,kAXValueAttribute) as? String==baseline,
          delegate.selection(field)?.location==range.location,delegate.selection(field)?.length==range.length else {stop("FAIL: overlay body click reached underlying text/caret/focus.");return}
        let center=delegate.panel.convertPoint(toScreen:button.convert(NSPoint(x:button.bounds.midX,y:button.bounds.midY),to:nil))
        mouseClick(Point(center.x,center.y),scope:{ownedField().map({CFEqual($0,field)})==true}) {
          guard let current=ownedField(),CFEqual(current,field),
            delegate.attribute(current,kAXValueAttribute) as? String==receipt,
            !delegate.active,!delegate.panel.isVisible,delegate.overlayPanel?.isVisible == false else {stop("FAIL: overlay candidate click receipt/focus/once-only cancellation.");return}
          print("PASS: overlay trial \(overlayTrial), native body absorption + candidate rank \(index+1) click; exact owned receipt and focus preserved; synthetic cursor/contact trace.")
          if overlayTrial<3 {overlayCandidateTrial()} else {overlayEndpointAndEscape()}
        }
      }
    }
  }
}
@MainActor func overlayEndpointAndEscape() {
  guard let field=ownedField(),let baseline=delegate.attribute(field,kAXValueAttribute) as? String,
    overlayStart(),let calibration=delegate.overlayFrame else {stop("FAIL: overlay endpoint activation.");return}
  let points=Keyboard.path("hello")
  // Hold the last move one distinct point short; lift at the actual final key.
  feedOverlay(Array(points.dropLast())) {
    // feedOverlay lifted already: start afresh for the endpoint-specific fixture.
    delegate.retry();frame(nil)
    feedWithoutLift(Array(points.dropLast())) {
      let before=delegate.overlayKeyboard.path.last
      moveCursor(calibration.screenPoint(points.last!)) {
        frame(nil)
        guard delegate.pending,let final=delegate.strokeSamples.last,final.phase == .ended,
          before != final.point,delegate.overlayKeyboard.path.last==final.point,
          delegate.overlayKeyboard.path==delegate.strokeSamples.map(\.point) else {stop("FAIL: final lift endpoint not rendered.");return}
        print("PASS: distinct lift endpoint rendered identically to decoder input.")
        guard let down=CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:true),let up=CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:false) else {stop("ABORT: cannot create Escape event.");return}
        guard ownedField().map({CFEqual($0,field)})==true else {stop("ABORT: Escape lost owned field.");return}
        down.post(tap:.cghidEventTap);later(0.02) {up.post(tap:.cghidEventTap);later(0.2) {
          guard !delegate.active,!delegate.panel.isVisible,delegate.overlayPanel?.isVisible == false,
            ownedField().map({CFEqual($0,field)})==true,delegate.attribute(field,kAXValueAttribute) as? String==baseline else {stop("FAIL: actual global synthetic Escape cancellation/focus/no-write.");return}
          print("PASS: overlay pending cancelled by native synthetic Escape; both panels hidden; owned field unchanged.")
          overlayRetryAndBounds()
        }}
      }
    }
  }
}
@MainActor func feedWithoutLift(_ points:[Point],index:Int=0,then:@escaping @MainActor ()->Void) {
  guard let calibration=delegate.overlayFrame else {stop("ABORT: endpoint calibration missing.");return}
  if index==points.count {then();return}
  moveCursor(calibration.screenPoint(points[index])) {frame(Point(0.01,0.02));feedWithoutLift(points,index:index+1,then:then)}
}
@MainActor func overlayRetryAndBounds() {
  guard let field=ownedField(),let baseline=delegate.attribute(field,kAXValueAttribute) as? String,overlayStart(),let calibration=delegate.overlayFrame else {stop("FAIL: overlay retry activation.");return}
  feedWithoutLift([Point(0.2,0.8),Point(0.4,0.5)]) {
    moveCursor(calibration.screenPoint(Point(1.02,0.5))) {
      frame(Point(0.01,0.02));frame(nil)
      guard delegate.pending,delegate.buttons.allSatisfy(\.isHidden),delegate.label.stringValue.contains("Outside keyboard"),delegate.attribute(field,kAXValueAttribute) as? String==baseline else {stop("FAIL: outside overlay stroke not explicitly rejected.");return}
      delegate.retry();frame(nil)
      feedOverlay(Keyboard.path("cat")) {
        guard delegate.pending,delegate.validTarget(),delegate.buttons.contains(where:{!$0.isHidden}) else {stop("FAIL: overlay retry after bounds rejection.");return}
        delegate.showOverlayLayout()
        guard !delegate.active,!delegate.panel.isVisible,delegate.overlayPanel?.isVisible == false,
          delegate.strokeSamples.isEmpty,delegate.originalSelection==nil else {stop("FAIL: opening layout did not cancel/clear capture.");return}
        delegate.layoutPanel?.close()
        print("PASS: overlay out-of-bounds retry, reactivation, layout-opening cancellation and capture clearing.")
        activateOwned {overlayContactGuards()}
      }
    }
  }
}
@MainActor func contactFrame(_ identifiers:[Int32]) {
  let event=OpenMTEvent();event.setValue(ProcessInfo.processInfo.systemUptime,forKey:"timestamp")
  event.setValue(identifiers.map {id in
    let touch=OpenMTTouch();touch.setValue(id,forKey:"identifier");touch.setValue(OpenMTState.touching.rawValue,forKey:"state")
    touch.setValue(Float(0.01),forKey:"posX");touch.setValue(Float(0.02),forKey:"posY");return touch
  },forKey:"touches")
  delegate.touchFrame(event)
}
@MainActor func overlayContactGuards() {
  guard overlayStart(),let calibration=delegate.overlayFrame else {stop("FAIL: contact guard activation.");return}
  moveCursor(calibration.screenPoint(Point(0.2,0.8))) {
    contactFrame([1]);contactFrame([2])
    guard delegate.active,delegate.waitForLift,delegate.finger==nil,delegate.strokeSamples.isEmpty else {stop("FAIL: changed contact did not reset overlay stroke.");return}
    frame(nil);contactFrame([1,2])
    guard delegate.active,delegate.waitForLift,delegate.finger==nil,delegate.strokeSamples.isEmpty else {stop("FAIL: multi-contact did not reset overlay stroke.");return}
    frame(nil)
    feedWithoutLift([Point(0.2,0.8),Point(0.4,0.5)]) {
      let item=NSMenuItem(title:"Trackpad Mode",action:nil,keyEquivalent:"");item.representedObject=InputMode.trackpad.rawValue
      delegate.chooseMode(item)
      guard delegate.inputMode == .screenOverlay,delegate.strokeSource == .screenOverlay,
        delegate.strokeCalibration==calibration,delegate.validTarget() else {stop("FAIL: mode/calibration changed within active stroke.");return}
      print("PASS: changed-contact/multi-contact reset and fresh idle gating; mode/calibration remain frozen during active overlay stroke.")
      nativePolicyChecks() // Switching to this owned app must cancel the still-active overlay.
    }
  }
}
