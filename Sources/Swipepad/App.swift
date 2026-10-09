import AppKit
import ApplicationServices
import Carbon
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
        String(key).uppercased().draw(
          at: NSPoint(x: rect.midX - 7, y: rect.midY - 10),
          withAttributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.labelColor,
          ])
      }
    }
    if let first = path.first {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: first.x * bounds.width, y: first.y * bounds.height))
      for p in path.dropFirst() {
        line.line(to: NSPoint(x: p.x * bounds.width, y: p.y * bounds.height))
      }
      NSColor.systemBlue.setStroke()
      line.lineWidth = 3
      line.stroke()
    }
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  var status: NSStatusItem!
  var panel: GuidePanel!
  let keyboard = KeyboardView(frame: NSRect(x: 20, y: 100, width: 560, height: 210))
  let label = NSTextField(labelWithString: "OFF — Double-tap Command in a text field")
  var buttons: [NSButton] = []
  var hotkey = CommandTap()
  var monitors: [Any] = []
  var listener: OpenMTListener?
  var active = false
  var target: AXUIElement?
  var originalPID: pid_t = 0
  var finger: Int32?
  var path: [Point] = []
  var pending = false
  var waitForLift = false
  // Original small vocabulary; no external dictionary/data dependency.
  let words =
    "a about after again all also am an and any app are as at back be because been before build but by can cat code come day did do does dog done down each email end even for from get give go good got great had has have he hello help her here him his home how i if in into is it its just know last let like little look love made make many may me more most much my need new next no not now of off on one only or other our out over people please right said same see she should so some start still stop such take test than thank that the their them then there these they thing think this time to today too tonight two type typing up us use very want was way we well were what when where which who will with word work world would write yes you your"
    .components(separatedBy: " ")
  func applicationDidFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.register(defaults: [
      "showGuide": true, "interval": 0.35, "debounce": 0.15,
    ])
    hotkey.interval = UserDefaults.standard.double(forKey: "interval")
    hotkey.debounce = UserDefaults.standard.double(forKey: "debounce")
    NSApp.setActivationPolicy(.accessory)
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.title = "Swipepad OFF"
    let menu = NSMenu()
    menu.addItem(
      withTitle: "Swipepad — experimental physical trackpad typing", action: nil, keyEquivalent: "")
    menu.addItem(withTitle: "Activate / Cancel", action: #selector(toggle), keyEquivalent: "")
    menu.addItem(
      withTitle: "Show keyboard guide", action: #selector(toggleGuide), keyEquivalent: ""
    ).state = UserDefaults.standard.bool(forKey: "showGuide") ? .on : .off
    menu.addItem(withTitle: "Hotkey timing…", action: #selector(timing), keyEquivalent: "")
    menu.addItem(withTitle: "Permission status…", action: #selector(permissions), keyEquivalent: "")
    menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
    for item in menu.items { item.target = self }
    status.menu = menu
    panel = GuidePanel(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
      styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.title = "Swipepad · physical trackpad · Escape cancels"
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.center()
    panel.contentView?.addSubview(keyboard)
    label.frame = NSRect(x: 20, y: 320, width: 560, height: 22)
    panel.contentView?.addSubview(label)
    for i in 0..<5 {
      let b = NSButton(title: "", target: self, action: #selector(selectCandidate(_:)))
      b.tag = i
      b.frame = NSRect(x: 20 + i * 112, y: 55, width: 108, height: 30)
      b.isHidden = true
      buttons.append(b)
      panel.contentView?.addSubview(b)
    }
    let retry = NSButton(title: "Swipe again", target: self, action: #selector(retry))
    retry.frame = NSRect(x: 20, y: 15, width: 130, height: 28)
    panel.contentView?.addSubview(retry)
    let cancel = NSButton(title: "Cancel", target: self, action: #selector(toggle))
    cancel.frame = NSRect(x: 450, y: 15, width: 130, height: 28)
    panel.contentView?.addSubview(cancel)
    // No permission requests: only install monitors if existing access is granted.
    if AXIsProcessTrusted() {
      if let m = NSEvent.addGlobalMonitorForEvents(
        matching: [.flagsChanged, .keyDown], handler: { [weak self] event in self?.handle(event) })
      {
        monitors.append(m)
      }
    }
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
  func supportedField(_ element: AXUIElement) -> Bool {
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
    return FieldPolicy.permits(
      role: role, subrole: subrole, selectedTextSettable: writable,
      secureInput: IsSecureEventInputEnabled())
  }
  func validTarget() -> Bool {
    guard !IsSecureEventInputEnabled(), let target,
      let app = NSWorkspace.shared.frontmostApplication,
      let current = focused(app.processIdentifier)
    else { return false }
    return FocusGuard.permits(
      originalPID: originalPID, currentPID: app.processIdentifier,
      sameElement: CFEqual(target, current), secure: IsSecureEventInputEnabled(),
      editable: supportedField(current))
  }
  @objc func toggle() {
    if active {
      cancel("OFF")
      return
    }
    guard AXIsProcessTrusted() else {
      permissions()
      return
    }
    guard !IsSecureEventInputEnabled() else { return }
    guard let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      let field = focused(app.processIdentifier), supportedField(field)
    else {
      status.button?.title = "Swipepad: unsupported field"
      return
    }
    originalPID = app.processIdentifier
    target = field
    active = true
    pending = false
    waitForLift = true
    path = []
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
    status.button?.title = "Swipepad ON"
    label.stringValue = "ON · Slide one finger; lift, then click a candidate to insert"
    keyboard.showKeys = UserDefaults.standard.bool(forKey: "showGuide")
    keyboard.path = []
    keyboard.needsDisplay = true
    buttons.forEach { $0.isHidden = true }
    panel.orderFrontRegardless()
  }
  @objc func touchFrame(_ event: OpenMTEvent) {
    // Bridge dispatches callbacks to main before invoking this selector.
    guard active, !pending, validTarget() else {
      if active && !validTarget() { cancel("Focus changed — cancelled") }
      return
    }
    let touches = (event.touches as? [OpenMTTouch] ?? []).filter {
      $0.state == .touching || $0.state == .making || $0.state == .starting
    }
    if waitForLift {
      if touches.isEmpty { waitForLift = false }
      return
    }
    if touches.count > 1 {
      waitForLift = true
      path = []
      finger = nil
      label.stringValue = "Use one finger; lift all fingers and try again"
      return
    }
    if let touch = touches.first {
      if finger == nil {
        finger = touch.identifier
        path = []
      }
      guard finger == touch.identifier else {
        path = []
        finger = nil
        return
      }
      let p = Point(Double(touch.posX), Double(touch.posY))
      if path.last.map({ $0.distance(p) > 0.005 }) ?? true {
        if path.count < 512 { path.append(p) }
      }
      keyboard.path = path
      keyboard.needsDisplay = true
    } else if finger != nil {
      finger = nil
      guard path.count >= 3, let first = path.first,
        path.contains(where: { first.distance($0) > 0.06 })
      else {
        path = []
        return
      }
      let candidates = Decoder.candidates(path, words: words)
      pending = !candidates.isEmpty
      for (i, b) in buttons.enumerated() {
        b.isHidden = i >= candidates.count
        if i < candidates.count { b.title = candidates[i] }
      }
      label.stringValue = "Review candidates · click the intended word · Swipe again to correct"
    }
  }
  @objc func selectCandidate(_ sender: NSButton) {
    guard active, pending, !sender.isHidden, validTarget(), let target else {
      cancel("Insertion cancelled: focus changed")
      return
    }
    // Targeted Accessibility write; no clipboard mutation or broadcast key events.
    let result = AXUIElementSetAttributeValue(
      target, kAXSelectedTextAttribute as CFString, (sender.title + " ") as CFString)
    cancel(result == .success ? "Inserted · OFF" : "Field rejected insertion · OFF")
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
    keyboard.path = []
    keyboard.needsDisplay = true
    buttons.forEach { $0.isHidden = true }
    label.stringValue = "ON · Slide one finger; lift, then choose a word"
  }
  func cancel(_ reason: String) {
    active = false
    pending = false
    if let listener { OpenMTManager.shared().remove(listener) }
    listener = nil
    target = nil
    path = []
    finger = nil
    keyboard.path = []
    buttons.forEach {
      $0.title = ""
      $0.isHidden = true
    }
    panel?.orderOut(nil)
    status?.button?.title = "Swipepad OFF"
    status?.button?.toolTip = reason
    status?.menu?.items.first?.title = "Swipepad: " + reason
    label.stringValue = reason
  }
  @objc func appChanged() {
    if active { cancel("Application changed") }
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
  @objc func permissions() {
    let alert = NSAlert()
    alert.messageText = "Swipepad permission status"
    alert.informativeText =
      "Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted"). Required for double-Command observation and targeted text insertion. Swipepad never requests access automatically. Grant only if you choose in System Settings → Privacy & Security → Accessibility, then restart. Global key observation can also depend on Input Monitoring on your macOS version. No permission will be changed here."
    alert.runModal()
  }
  @objc func quit() {
    cancel("Quit")
    NSApp.terminate(nil)
  }
  func applicationWillTerminate(_ notification: Notification) {
    cancel("Quit")
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
  }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
