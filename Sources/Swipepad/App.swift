import AppKit
import ApplicationServices
import Carbon
import Foundation
import SwipepadCore
import TrackpadBridge

final class GuidePanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
@MainActor final class KeyboardView: NSView {
  var path: [Point] = []
  var showKeys = true
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    if showKeys {
      for (key, p) in Keyboard.keys {
        let rect = NSRect(
          x: p.x * bounds.width - 21, y: p.y * bounds.height - 21, width: 42, height: 42)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        let glyph = String(key).uppercased() as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = glyph.size(withAttributes: attributes)
        glyph.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
      }
    }
    if let first = path.first {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: first.x * bounds.width, y: first.y * bounds.height))
      for p in path.dropFirst() {
        line.line(to: NSPoint(x: p.x * bounds.width, y: p.y * bounds.height))
      }
      NSColor.controlAccentColor.setStroke()
      line.lineWidth = 3
      line.stroke()
    }
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
  var status: NSStatusItem!
  var panel: GuidePanel!
  lazy var keyboard = KeyboardView(frame: NSRect(x: 20, y: 100, width: 560, height: 210))
  lazy var label = NSTextField(labelWithString: "OFF — Double-tap Command in a text field")
  var buttons: [NSButton] = []
  var guideKeyboardHeight:NSLayoutConstraint?
  var overlayPanel:GuidePanel?
  let overlayKeyboard=OverlayKeyboardView()
  var overlayFrame:CalibrationRect?
  var strokeCalibration:CalibrationRect?
  var strokeSamples:[StrokeSample]=[]
  var strokeSource:InputMode = .trackpad
  var layoutPanel:NSWindow?
  var layoutPreview:LayoutPreviewView?
  var hotkey = CommandTap()
  var monitors: [Any] = []
  var globalMonitor: Any?
  var globalEventSeen = false
  var hotkeySeen = false
  var touchSeen = false
  var liftSeen = false
  var lastFocusPreserved: Bool?
  var lastInsertionSucceeded: Bool?
  var setupPanel: NSWindow?
  var setupView: SetupView?
  var accessRequested = false
  var setupHeading: NSTextField?
  var doctorText: NSTextView?
  var lastTrusted = false
  var listener: OpenMTListener?
  var active = false
  var target: AXUIElement?
  var originalPID: pid_t = 0
  var originalSelection: CFRange?
  var finger: Int32?
  var path: [Point] = []
  var pending = false
  var waitForLift = false
  // Original small vocabulary; no external dictionary/data dependency.
  let words =
    "a about after again all also am an and any app are as at back be because been before build but by can cat code come day did do does dog done down each email end even for from get give go good got great had has have he hello help her here him his home how i if in into is it its just know last let like little look love made make many may me more most much my need new next no not now of off on one only or other our out over people please right said same see she should so some start still stop such take test than thank that the their them then there these they thing think this time to today too tonight two type typing up us use very want was way we well were what when where which who will with word work world would write yes you your"
    .components(separatedBy: " ")
  func validateMenuItem(_ menuItem:NSMenuItem) -> Bool {
    menuItem.action == #selector(chooseMode(_:)) ? !active : true
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.register(defaults: [
      "showGuide": true, "interval": 0.35, "debounce": 0.15, "inputMode": "trackpad", "overlayOpacity": 0.55,
    ])
    hotkey.interval = UserDefaults.standard.double(forKey: "interval")
    hotkey.debounce = UserDefaults.standard.double(forKey: "debounce")
    NSApp.setActivationPolicy(.accessory)
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    installStatusIcon()
    status.button?.title = ""
    let menu = NSMenu()
    menu.addItem(
      withTitle: "Swipepad: Off", action: nil, keyEquivalent: "")
    menu.addItem(withTitle: "Start Swiping", action: #selector(toggle), keyEquivalent: "")
    menu.addItem(
      withTitle: "Show Keyboard Guide", action: #selector(toggleGuide), keyEquivalent: ""
    ).state = UserDefaults.standard.bool(forKey: "showGuide") ? .on : .off
    menu.addItem(.separator())
    for (title,mode) in [("Trackpad Mode",InputMode.trackpad),("Screen Overlay Mode",.screenOverlay)] {
      let item=menu.addItem(withTitle:title,action:#selector(chooseMode(_:)),keyEquivalent:"")
      item.representedObject=mode.rawValue;item.state=inputMode==mode ? .on : .off
    }
    menu.addItem(withTitle:"Overlay Layout…",action:#selector(showOverlayLayout),keyEquivalent:"")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Setup…", action: #selector(showSetup), keyEquivalent: "")
    menu.addItem(withTitle: "Quit Swipepad", action: #selector(quit), keyEquivalent: "q")
    for item in menu.items { item.target = self }
    status.menu = menu
    panel = GuidePanel(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
      styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = "Swipepad"
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    panel.center()
    let guide = NSStackView()
    guide.orientation = .vertical; guide.alignment = .leading; guide.spacing = 14
    guide.translatesAutoresizingMaskIntoConstraints = false
    panel.contentView?.addSubview(guide)
    if let content = panel.contentView {
      NSLayoutConstraint.activate([guide.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), guide.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), guide.topAnchor.constraint(equalTo: content.topAnchor, constant: 16), guide.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)])
    }
    label.font = .systemFont(ofSize: 15, weight: .semibold)
    guide.addArrangedSubview(label)
    keyboard.setAccessibilityElement(true)
    keyboard.setAccessibilityRole(.group)
    keyboard.setAccessibilityLabel("Trackpad keyboard guide")
    guide.addArrangedSubview(keyboard)
    keyboard.widthAnchor.constraint(equalTo: guide.widthAnchor).isActive = true
    guideKeyboardHeight=keyboard.heightAnchor.constraint(equalToConstant:210)
    guideKeyboardHeight?.isActive=true
    let candidates = NSStackView(); candidates.spacing = 8
    for i in 0..<5 {
      let button = NSButton(title: "", target: self, action: #selector(selectCandidate(_:)))
      button.tag = i; button.bezelStyle = .rounded; button.isHidden = true
      buttons.append(button); candidates.addArrangedSubview(button)
    }
    guide.addArrangedSubview(candidates)
    let retry = NSButton(title: "Swipe Again", target: self, action: #selector(retry))
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(toggle))
    let footer = NSStackView(views: [retry, NSView(), cancel, NSTextField(labelWithString: "Esc")])
    footer.spacing = 8
    guide.addArrangedSubview(footer)
    footer.widthAnchor.constraint(equalTo: guide.widthAnchor).isActive = true
    reconnectKeyboard()
    lastTrusted = AXIsProcessTrusted()
    if let m = NSEvent.addLocalMonitorForEvents(
      matching: [.flagsChanged, .keyDown],
      handler: { [weak self] event in
        self?.handle(event)
        return event
      })
    {
      monitors.append(m)
    }
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(appChanged), name: NSWorkspace.didActivateApplicationNotification,
      object: nil)
    Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        if let self, self.active, !self.validTarget() { self.cancel("Focus changed — cancelled") }
      }
    }
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(setupNotification(_:)),
      name: Notification.Name("com.ericspencer00.swipepad.showSetup"), object: nil)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(doctorNotification(_:)),
      name: Notification.Name("com.ericspencer00.swipepad.doctorRequest"), object: nil)
    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        let trusted = AXIsProcessTrusted()
        if trusted != self.lastTrusted {
          self.lastTrusted = trusted
          self.reconnectKeyboard()
        }
        self.updateModeIndicator()
        if self.setupPanel?.isVisible == true { self.refreshDoctor() }
      }
    }
    NotificationCenter.default.addObserver(self,selector:#selector(displaysChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
    let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
    UserDefaults.standard.set(true, forKey: "hasLaunched")
    if (firstLaunch && !AXIsProcessTrusted()) || CommandLine.arguments.contains("--setup") { showSetup() }
  }
  func handle(_ e: NSEvent) {
    if IsSecureEventInputEnabled() {
      hotkey.cancel()
      if active { cancel("Secure Input active") }
      return
    }
    if e.type == .keyDown {
      hotkey.cancel()
      if e.keyCode == 53 { cancel("Cancelled") }
      return
    }
    let modifiers = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([
      .capsLock, .numericPad, .function,
    ])
    if hotkey.update(
      isDown: modifiers.contains(.command), onlyCommand: modifiers.isEmpty || modifiers == .command,
      time: e.timestamp)
    {
      hotkeySeen = true
      toggle()
    }
  }
  func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value
  }
  func focused(_ pid: pid_t) -> AXUIElement? {
    guard let value = attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
  }
  func fieldMetadata(_ element: AXUIElement) -> (
    role: String?, subrole: FieldSubrole, writable: Bool
  ) {
    let role = attribute(element, kAXRoleAttribute) as? String
    var value: CFTypeRef?
    let subroleResult = AXUIElementCopyAttributeValue(
      element, kAXSubroleAttribute as CFString, &value)
    let subrole: FieldSubrole
    if subroleResult == .success, let name = value as? String {
      subrole = .named(name)
    } else if subroleResult == .attributeUnsupported || subroleResult == .noValue {
      subrole = .absent
    } else {
      subrole = .unreadable
    }
    var settable: DarwinBoolean = false
    let writable =
      AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
      == .success && settable.boolValue
    return (role, subrole, writable)
  }
  func supportedField(_ element: AXUIElement) -> Bool {
    let metadata = fieldMetadata(element)
    return FieldPolicy.permits(
      role: metadata.role, subrole: metadata.subrole, selectedTextSettable: metadata.writable,
      secureInput: IsSecureEventInputEnabled())
  }
  func selection(_ element: AXUIElement) -> CFRange? {
    guard let value = attribute(element, kAXSelectedTextRangeAttribute),
      CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range),
      range.location >= 0, range.length >= 0 else { return nil }
    return range
  }
  func validTarget() -> Bool {
    guard !IsSecureEventInputEnabled(), let target,
      let app = NSWorkspace.shared.frontmostApplication,
      let current = focused(app.processIdentifier)
    else {
      if active { lastFocusPreserved = false }
      return false
    }
    let permitted = FocusGuard.permits(
      originalPID: originalPID, currentPID: app.processIdentifier,
      sameElement: CFEqual(target, current), secure: IsSecureEventInputEnabled(),
      editable: supportedField(current))
      && originalSelection.map { original in
        selection(current).map { $0.location == original.location && $0.length == original.length } ?? false
      } == true
    if active { lastFocusPreserved = permitted }
    return permitted
  }
  @objc func toggle() {
    if active {
      cancel("OFF")
      return
    }
    guard AXIsProcessTrusted() else {
      updateModeIndicator()
      status?.menu?.items.first?.title = "Swipepad: setup needed — open Setup & Doctor"
      return
    }
    guard !IsSecureEventInputEnabled() else {
      cancel("Secure Input active")
      return
    }
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      let field = focused(app.processIdentifier), supportedField(field)
    else {
      updateModeIndicator()
      status?.menu?.items.first?.title = "Swipepad: focus a supported text area"
      return
    }
    guard let range = selection(field) else {
      cancel("Field does not expose a safe insertion range")
      return
    }
    originalSelection = range
    originalPID = app.processIdentifier
    target = field
    active = true
    pending = false
    waitForLift = true
    path = []
    strokeSamples=[];strokeSource=inputMode;strokeCalibration=nil
    finger = nil
    guard OpenMTManager.systemSupportsMultitouch() else {
      cancel("No supported trackpad")
      return
    }
    listener = OpenMTManager.shared().addListener(
      withTarget: self, selector: #selector(touchFrame(_:)))
    guard listener != nil else {
      cancel("Trackpad capture unavailable")
      return
    }
    updateModeIndicator()
    setupPanel?.orderOut(nil)
    label.stringValue = "Lift all fingers · then swipe one word"
    keyboard.showKeys = UserDefaults.standard.bool(forKey: "showGuide")
    keyboard.path = []
    keyboard.needsDisplay = true
    buttons.forEach { $0.isHidden = true }
    if strokeSource == .screenOverlay {
      configureOverlay()
    } else {
      guideKeyboardHeight?.constant=210
      panel.setContentSize(NSSize(width:600,height:360))
      panel.center()
    }
    guard active else {return}
    panel.orderFrontRegardless()
  }
  @objc func touchFrame(_ event: OpenMTEvent) {
    // Bridge dispatches callbacks to main before invoking this selector.
    guard active, !pending, validTarget() else {
      if active && !validTarget() { cancel("Focus changed — cancelled") }
      return
    }
    touchSeen = true
    let touches = (event.touches as? [OpenMTTouch] ?? []).filter {
      $0.state == .touching || $0.state == .making || $0.state == .starting
    }
    if waitForLift {
      if touches.isEmpty { waitForLift = false; label.stringValue = "Ready · slide one finger, then lift" }
      return
    }
    if touches.count > 1 {
      resetStrokeForRetry("Use one finger · lift all fingers to retry")
      return
    }
    if let touch = touches.first {
      if finger == nil {
        finger=touch.identifier;path=[];strokeSamples=[]
        strokeCalibration=overlayFrame // frozen for this contact; preview cannot resize it.
        if strokeSource == .screenOverlay {
          let cursor=NSEvent.mouseLocation
          guard let initial=strokeCalibration?.normalize(Point(cursor.x,cursor.y)), (0...1).contains(initial.x), (0...1).contains(initial.y) else {
            finger=nil;waitForLift=true
            label.stringValue="Place cursor on first key · lift, then swipe"
            return
          }
        }
      }
      guard finger==touch.identifier else {
        resetStrokeForRetry("Contact changed · lift all fingers to retry")
        return
      }
      guard let sample=samplePoint(touch) else {cancel("Calibration unavailable");return}
      appendSample(sample.normalized,time:event.timestamp,phase:strokeSamples.isEmpty ? .began : .moved,sourcePoint:sample.native)
      label.stringValue="Swiping · lift to see words"
      renderStroke()
    } else if finger != nil {
      liftSeen=true
      let end:Point?
      let nativeEnd:Point?
      if strokeSource == .screenOverlay {
        let cursor=NSEvent.mouseLocation
        nativeEnd=Point(cursor.x,cursor.y)
        end=strokeCalibration?.normalize(nativeEnd!)
      } else {
        end=path.last
        nativeEnd=strokeSamples.last?.sourcePoint
      }
      if let end {appendSample(end,time:event.timestamp,phase:.ended,sourcePoint:nativeEnd)}
      finger=nil
      guard active else {return}
      if strokeSamples.contains(where:{!(0...1).contains($0.point.x) || !(0...1).contains($0.point.y)}) {
        pending=true;buttons.forEach{$0.isHidden=true}
        label.stringValue="Outside keyboard · choose Swipe Again to retry"
        return
      }
      guard path.count>=3,let first=path.first,path.contains(where:{first.distance($0)>0.06}) else {
        resetStrokeForRetry("Stroke too short · lift, then swipe a word")
        return
      }
      let candidates=strokeSource == .screenOverlay ? StrokeDecoder.candidates(strokeSamples,words:words) : Decoder.candidates(path,words:words)
      pending=true // no-match also freezes input until an explicit retry.
      for (index,button) in buttons.enumerated() {
        button.isHidden=index>=candidates.count
        if index<candidates.count {
          button.title=candidates[index]
          button.setAccessibilityLabel("Insert "+candidates[index])
          button.setAccessibilityHelp("Candidate \(index+1) of \(candidates.count)")
        }
      }
      label.stringValue=candidates.isEmpty ? "No match · choose Swipe Again to retry" : "Choose a word · click to insert in your text field"
    }
  }
  func samplePoint(_ touch:OpenMTTouch) -> (normalized:Point,native:Point)? {
    if strokeSource == .trackpad {
      let point=Point(Double(touch.posX),Double(touch.posY));return (point,point)
    }
    let cursor=NSEvent.mouseLocation, native=Point(cursor.x,cursor.y)
    guard let normalized=strokeCalibration?.normalize(native) else {return nil}
    return (normalized,native)
  }
  func appendSample(_ point:Point,time:Double,phase:ContactPhase,sourcePoint:Point? = nil) {
    guard strokeSamples.count<4096 else {cancel("Stroke too long; cancelled");return}
    strokeSamples.append(StrokeSample(point,time:time,phase:phase,source:strokeSource,sourcePoint:sourcePoint))
    // Original trackpad matcher retains its spacing; overlay geometry keeps every frame.
    if strokeSource == .screenOverlay || phase == .ended || path.last.map({$0.distance(point)>0.005}) ?? true {path.append(point)}
  }
  func renderStroke() {
    keyboard.path=path;keyboard.needsDisplay=true
    overlayKeyboard.path=strokeSamples.map(\.point);overlayKeyboard.needsDisplay=true
  }
  func resetStrokeForRetry(_ message:String) {
    waitForLift=true;path=[];strokeSamples=[];finger=nil;strokeCalibration=nil
    renderStroke();label.stringValue=message
  }
  @objc func selectCandidate(_ sender: NSButton) {
    guard active, pending, !sender.isHidden, validTarget(), let target else {
      cancel("Insertion cancelled: focus changed")
      return
    }
    // Targeted Accessibility write; no clipboard mutation or broadcast key events.
    let result = AXUIElementSetAttributeValue(
      target, kAXSelectedTextAttribute as CFString, (sender.title + " ") as CFString)
    lastInsertionSucceeded = result == .success
    cancel(result == .success ? "Insertion request accepted · check your text field" : "Field rejected insertion · OFF")
  }
  @objc func retry() {
    guard active, validTarget() else {
      cancel("Focus changed")
      return
    }
    pending = false
    waitForLift = true
    path = []
    finger = nil
    strokeSamples=[];strokeCalibration=nil;overlayKeyboard.path=[];overlayKeyboard.needsDisplay=true
    keyboard.path = []
    keyboard.needsDisplay = true
    buttons.forEach { $0.isHidden = true }
    label.stringValue = "Lift all fingers · then swipe one word"
  }
  func cancel(_ reason: String) {
    active = false
    pending = false
    if let listener { OpenMTManager.shared().remove(listener) }
    listener = nil
    target = nil
    originalSelection = nil
    path = []
    finger = nil
    keyboard.path = []
    buttons.forEach {
      $0.title = ""
      $0.isHidden = true
    }
    panel?.orderOut(nil)
    overlayPanel?.orderOut(nil);overlayKeyboard.path=[];overlayKeyboard.needsDisplay=true
    strokeSamples=[];strokeCalibration=nil;overlayFrame=nil
    updateModeIndicator()
    status?.button?.toolTip = reason
    status?.menu?.items.first?.title = "Swipepad: " + reason
    label.stringValue = reason
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === panel {
      cancel("Cancelled")
      return false
    }
    return true
  }
  @objc func appChanged() {
    if active {
      lastFocusPreserved = false
      cancel("Application changed")
    }
    hotkey.cancel()
  }
  @objc func toggleGuide(_ sender: NSMenuItem) {
    let show = !UserDefaults.standard.bool(forKey: "showGuide")
    UserDefaults.standard.set(show, forKey: "showGuide")
    sender.state = show ? .on : .off
    keyboard.showKeys = show
    keyboard.needsDisplay = true
  }
  @objc func timing() {
    cancel("Settings")
    let alert = NSAlert()
    alert.messageText = "Double-Command timing"
    alert.informativeText =
      "Enter tap interval (0.2–0.8) and debounce (0.1–1.0), separated by a comma. Shortcuts cancel the sequence."
    let field = NSTextField(string: "\(hotkey.interval), \(hotkey.debounce)")
    field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      let values = field.stringValue.split(separator: ",").compactMap {
        Double($0.trimmingCharacters(in: .whitespaces))
      }
      if values.count == 2, (0.2...0.8).contains(values[0]), (0.1...1.0).contains(values[1]) {
        hotkey.interval = values[0]
        hotkey.debounce = values[1]
        UserDefaults.standard.set(values[0], forKey: "interval")
        UserDefaults.standard.set(values[1], forKey: "debounce")
      }
    }
  }
  @objc func quit() {
    cancel("Quit")
    NSApp.terminate(nil)
  }
  func applicationWillTerminate(_ notification: Notification) {
    cancel("Quit")
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
  }
}
