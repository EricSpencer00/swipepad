import AppKit
import SwipepadCore

@MainActor final class OverlayKeyboardView: NSView {
  var path:[Point]=[]
  var opacity:CGFloat=0.55
  override func mouseDown(with event:NSEvent) {} // Absorb presses/taps; never forward into the document.
  override func mouseUp(with event:NSEvent) {}
  override func mouseDragged(with event:NSEvent) {}
  override func draw(_ dirtyRect:NSRect) {
    let workspace=NSWorkspace.shared
    let solid=workspace.accessibilityDisplayShouldReduceTransparency || workspace.accessibilityDisplayShouldIncreaseContrast
    let keyWidth=bounds.width/10*0.86,keyHeight=bounds.height/3*0.68
    for (key,point) in Keyboard.keys {
      let rect=NSRect(x:point.x*bounds.width-keyWidth/2,y:point.y*bounds.height-keyHeight/2,width:keyWidth,height:keyHeight)
      NSColor.controlBackgroundColor.withAlphaComponent(solid ? 1 : opacity).setFill()
      let outline=NSBezierPath(roundedRect:rect,xRadius:10,yRadius:10);outline.fill()
      NSColor.separatorColor.withAlphaComponent(solid ? 1 : 0.7).setStroke();outline.lineWidth=solid ? 2 : 1;outline.stroke()
      let text=String(key).uppercased() as NSString
      let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:min(32,max(18,bounds.width*0.022)),weight:.medium),.foregroundColor:NSColor.labelColor]
      let size=text.size(withAttributes:attributes)
      text.draw(at:NSPoint(x:rect.midX-size.width/2,y:rect.midY-size.height/2),withAttributes:attributes)
    }
    if let first=path.first,path.count>1 {
      let line=NSBezierPath();line.move(to:NSPoint(x:first.x*bounds.width,y:first.y*bounds.height))
      for point in path.dropFirst() {line.line(to:NSPoint(x:point.x*bounds.width,y:point.y*bounds.height))}
      line.lineWidth=solid ? 5 : 4;line.lineCapStyle = .round;line.lineJoinStyle = .round
      NSColor.systemBlue.withAlphaComponent(solid ? 0.9 : 0.65).setStroke();line.stroke()
    }
    if let start=path.first {
      NSColor.systemBlue.withAlphaComponent(0.8).setFill()
      NSBezierPath(ovalIn:NSRect(x:start.x*bounds.width-4,y:start.y*bounds.height-4,width:8,height:8)).fill()
    }
  }
}
@MainActor final class LayoutPreviewView: NSView {
  let canvas=OverlayKeyboardView()
  let controls=NSStackView()
  override init(frame:NSRect) {
    super.init(frame:frame);addSubview(canvas);addSubview(controls)
    controls.orientation = .horizontal;controls.spacing=10;controls.alignment = .centerY
  }
  required init?(coder:NSCoder) {fatalError("init(coder:) unavailable")}
  override func layout() {
    super.layout()
    let width=min(bounds.width-32,max(240,(bounds.height-100)/0.38))
    let height=width*0.38
    canvas.frame=NSRect(x:(bounds.width-width)/2,y:bounds.height-16-height,width:width,height:height)
    controls.frame=NSRect(x:16,y:20,width:bounds.width-32,height:44)
  }
  override func draw(_ dirtyRect:NSRect) {NSColor.windowBackgroundColor.setFill();bounds.fill()}
}
@MainActor extension AppDelegate {
  var inputMode:InputMode { InputMode(rawValue:UserDefaults.standard.string(forKey:"inputMode") ?? "") ?? .trackpad }
  func selectedScreen() -> NSScreen? {
    let cursor=NSEvent.mouseLocation
    return NSScreen.screens.first(where: {$0.frame.contains(cursor)}) ?? NSScreen.main ?? NSScreen.screens.first
  }
  func displayKey(_ screen:NSScreen) -> String {"overlayLayout."+String(describing:screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "default")}
  func defaultOverlayRect(_ screen:NSScreen) -> NSRect {
    let visible=screen.visibleFrame
    let width=min(visible.width*0.80,visible.height*0.65/0.38)
    return NSRect(x:visible.midX-width/2,y:visible.midY-width*0.38/2,width:width,height:width*0.38)
  }
  func overlayRect(_ screen:NSScreen) -> NSRect {
    let visible=screen.visibleFrame
    guard let stored=UserDefaults.standard.array(forKey:displayKey(screen)) as? [Double],
      let rect=CalibrationRect.restoreOverlay(stored,in:CalibrationRect(x:visible.minX,y:visible.minY,width:visible.width,height:visible.height)) else {return defaultOverlayRect(screen)}
    return NSRect(x:rect.x,y:rect.y,width:rect.width,height:rect.height)
  }
  func configureOverlay() {
    guard let screen=selectedScreen() else {cancel("No display available");return}
    let rect=overlayRect(screen)
    overlayFrame=CalibrationRect(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height)
    if overlayPanel==nil {
      let overlay=GuidePanel(contentRect:rect,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
      overlay.isOpaque=false;overlay.backgroundColor = .clear;overlay.hasShadow=false
      overlay.level = .floating;overlay.ignoresMouseEvents=false;overlay.isMovable=false
      overlay.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
      overlay.isReleasedWhenClosed=false;overlay.contentView=overlayKeyboard
      overlayKeyboard.setAccessibilityElement(true);overlayKeyboard.setAccessibilityRole(.group)
      overlayKeyboard.setAccessibilityLabel("Screen overlay keyboard")
      overlayPanel=overlay
    }
    overlayKeyboard.opacity=CGFloat(UserDefaults.standard.double(forKey:"overlayOpacity"))
    overlayKeyboard.path=[];overlayKeyboard.needsDisplay=true
    overlayPanel?.setFrame(rect,display:true);overlayPanel?.orderFrontRegardless()
    guideKeyboardHeight?.constant=0
    panel.setContentSize(NSSize(width:600,height:145))
    let visible=screen.visibleFrame
    let y=rect.minY-175 >= visible.minY ? rect.minY-175 : min(visible.maxY-panel.frame.height,rect.maxY+12)
    panel.setFrameOrigin(NSPoint(x:min(max(visible.minX,rect.midX-panel.frame.width/2),visible.maxX-panel.frame.width),y:y))
  }
  @objc func chooseMode(_ item:NSMenuItem) {
    guard !active,let mode=InputMode(rawValue:item.representedObject as? String ?? "") else {return}
    UserDefaults.standard.set(mode.rawValue,forKey:"inputMode")
    for candidate in status.menu?.items ?? [] where candidate.action == #selector(chooseMode(_:)) {
      candidate.state=(candidate.representedObject as? String)==mode.rawValue ? .on : .off
    }
    updateModeIndicator()
  }
  @objc func showOverlayLayout() {
    presentOverlayLayout(on:selectedScreen())
  }
  func presentOverlayLayout(on selected:NSScreen?) {
    cancel("Overlay layout preview; capture off")
    layoutPanel?.close()
    guard let screen=selected else {return}
    let rect=overlayRect(screen)
    let window=SetupWindow(contentRect:NSRect(x:rect.minX-16,y:rect.minY-84,width:rect.width+32,height:rect.height+100),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
    window.title="Overlay Layout · Capture Off";window.isReleasedWhenClosed=false
    window.minSize=NSSize(width:420,height:260);window.maxSize=screen.visibleFrame.size
    let preview=LayoutPreviewView(frame:NSRect(x:0,y:0,width:rect.width+32,height:rect.height+100))
    preview.canvas.opacity=CGFloat(UserDefaults.standard.double(forKey:"overlayOpacity"))
    preview.controls.addArrangedSubview(NSTextField(labelWithString:"Key opacity"))
    let slider=NSSlider(value:Double(preview.canvas.opacity),minValue:0.25,maxValue:1,target:self,action:#selector(changeOverlayOpacity(_:)))
    slider.widthAnchor.constraint(equalToConstant:100).isActive=true
    preview.controls.addArrangedSubview(slider)
    preview.controls.addArrangedSubview(NSButton(title:"Reset Layout",target:self,action:#selector(resetOverlayLayout)))
    let save=NSButton(title:"Use This Layout",target:self,action:#selector(saveOverlayLayout));save.keyEquivalent="\r"
    preview.controls.addArrangedSubview(save)
    window.contentView=preview;layoutPreview=preview;layoutPanel=window
    NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)
  }
  @objc func changeOverlayOpacity(_ slider:NSSlider) {
    layoutPreview?.canvas.opacity=CGFloat(slider.doubleValue);layoutPreview?.canvas.needsDisplay=true
  }
  @objc func saveOverlayLayout() {
    guard !active,let window=layoutPanel,let preview=layoutPreview,let screen=window.screen else {return}
    preview.layoutSubtreeIfNeeded()
    let rect=window.convertToScreen(preview.canvas.convert(preview.canvas.bounds,to:nil)), visible=screen.visibleFrame
    guard visible.contains(rect),rect.width>=240,rect.height>=90 else {
      let alert=NSAlert();alert.messageText="Move the keyboard fully onto this display";alert.informativeText="Resize or move this preview, then choose Use This Layout.";alert.beginSheetModal(for:window);return
    }
    UserDefaults.standard.set([(rect.minX-visible.minX)/visible.width,(rect.minY-visible.minY)/visible.height,rect.width/visible.width,rect.height/visible.height],forKey:displayKey(screen))
    UserDefaults.standard.set(Double(preview.canvas.opacity),forKey:"overlayOpacity")
    window.close()
  }
  @objc func resetOverlayLayout() {
    guard let screen=layoutPanel?.screen else {return}
    UserDefaults.standard.removeObject(forKey:displayKey(screen))
    presentOverlayLayout(on:screen)
  }
  @objc func displaysChanged() {
    if active {cancel("Display changed; cancelled")}
    overlayPanel?.orderOut(nil)
  }
}
