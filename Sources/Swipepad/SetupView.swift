import AppKit
import ApplicationServices
import Carbon
import TrackpadBridge

final class SetupWindow: NSWindow {
  override func cancelOperation(_ sender: Any?) { close() }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" { close(); return true }
    return super.performKeyEquivalent(with: event)
  }
}
@MainActor final class SetupView: NSView {
  weak var owner: AppDelegate?
  let heading = NSTextField(labelWithString: "")
  let detail = NSTextField(wrappingLabelWithString: "")
  let rows = (0..<3).map { _ in NSTextField(labelWithString: "") }
  let primary = NSButton(title: "", target: nil, action: nil)
  let diagnostics = NSStackView()
  let disclosure = NSButton(title: "Diagnostics", target: nil, action: nil)
  var expanded = false
  var previewTrusted: Bool?
  init(owner: AppDelegate) {
    self.owner = owner
    super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 370))
    let stack = NSStackView()
    stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: topAnchor, constant: 20), stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)])
    let icon = NSImageView()
    icon.image = NSImage(named: NSImage.applicationIconName)
    icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
    heading.font = .systemFont(ofSize: 21, weight: .semibold)
    detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
    let titles = NSStackView(views: [heading, detail]); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 6
    let header = NSStackView(views: [icon, titles]); header.spacing = 14; header.alignment = .top
    stack.addArrangedSubview(header)
    for row in rows { row.font = .systemFont(ofSize: 13); stack.addArrangedSubview(row) }
    let identity = NSButton(title: "Running app · Show in Finder", target: self, action: #selector(showInFinder))
    identity.bezelStyle = .inline; identity.font = .systemFont(ofSize: 11)
    identity.toolTip = Bundle.main.bundleURL.path
    stack.addArrangedSubview(identity)
    disclosure.setButtonType(.pushOnPushOff); disclosure.bezelStyle = .disclosure
    disclosure.target = self; disclosure.action = #selector(toggleDiagnostics)
    stack.addArrangedSubview(NSStackView(views: [disclosure, NSTextField(labelWithString: "Diagnostics")]))
    diagnostics.orientation = .vertical; diagnostics.alignment = .leading; diagnostics.spacing = 8; diagnostics.isHidden = true
    stack.addArrangedSubview(diagnostics)
    let actions: [(String, Selector)] = [("Check Again", #selector(AppDelegate.recheckDoctor)), ("Open Accessibility Settings", #selector(AppDelegate.openAccessibilitySettings)), ("Reset Session", #selector(AppDelegate.resetFromDoctor)), ("Relaunch Swipepad", #selector(AppDelegate.relaunchFromDoctor))]
    for (title, action) in actions { diagnostics.addArrangedSubview(NSButton(title: title, target: owner, action: action)) }
    diagnostics.addArrangedSubview(NSButton(title: "Copy Report", target: self, action: #selector(copyReport)))
    for (title, key, value) in [("Tap interval (s)", "interval", owner.hotkey.interval), ("Debounce (s)", "debounce", owner.hotkey.debounce)] {
      let field = NSTextField(string: String(value)); field.identifier = NSUserInterfaceItemIdentifier(key); field.target = self; field.action = #selector(saveTiming(_:)); field.widthAnchor.constraint(equalToConstant: 70).isActive = true
      diagnostics.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: title), field]))
    }
    let spacer = NSView(); let footer = NSStackView(views: [spacer, primary]); footer.distribution = .fill
    primary.bezelStyle = .rounded; primary.keyEquivalent = "\r"; primary.target = self; primary.action = #selector(nextAction)
    stack.addArrangedSubview(footer)
    footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    refresh()
  }
  override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
  required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
  func refresh() {
    guard let owner else { return }
    let trusted = previewTrusted ?? AXIsProcessTrusted()
    rows[0].stringValue = trusted ? "✓  Accessibility is on for this app" : "○  Accessibility is off for this app"
    rows[1].stringValue = owner.hotkeySeen ? "✓  Double-Command seen" : "○  Double-Command · not tried yet"
    rows[2].stringValue = owner.lastInsertionSucceeded == true ? "○  Insertion accepted · confirm the word appeared" : "○  Swipe and insert · not tried yet"
    if !trusted {
      heading.stringValue = owner.accessRequested ? "Turn on Swipepad in Settings" : "Allow Accessibility"
      detail.stringValue = owner.accessRequested ? "Enable Swipepad in System Settings → Privacy & Security → Accessibility. This running app still reports access off." : "Use double-Command to start, then choose a word to insert in your text field."
      primary.title = owner.accessRequested ? "Open Accessibility Settings" : "Request Access…"
    } else if owner.globalMonitor == nil && previewTrusted == nil {
      heading.stringValue = "Reconnect the shortcut"; detail.stringValue = "Accessibility is on. Reconnect the keyboard listener to try double-Command."; primary.title = "Reconnect"
    } else if !OpenMTManager.systemSupportsMultitouch() {
      heading.stringValue = "No supported trackpad"; detail.stringValue = "Connect a supported Apple trackpad to try physical swipe typing."; primary.title = "Close"
    } else if IsSecureEventInputEnabled() {
      heading.stringValue = "Paused for secure input"; detail.stringValue = "Leave the secure field, then try in a regular text area."; primary.title = "Close"
    } else {
      heading.stringValue = owner.hotkeySeen ? "Double-Command works" : "Ready to try"
      detail.stringValue = "Focus a regular text area. Tap Command twice, lift your fingers, then swipe a word and choose a candidate."
      primary.title = "Close and Try"
    }
  }
  @objc func nextAction() {
    guard let owner else { return }
    switch primary.title {
    case "Request Access…": owner.requestAccessibility()
    case "Open Accessibility Settings": owner.openAccessibilitySettings()
    case "Reconnect": owner.recheckDoctor()
    default: owner.closeSetup()
    }
  }
  @objc func toggleDiagnostics() {
    expanded.toggle(); diagnostics.isHidden = !expanded
    window?.setContentSize(NSSize(width: 520, height: expanded ? 650 : 370))
  }
  @objc func showInFinder() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
  @objc func copyReport() {
    guard let report = owner?.doctorReport(live: true).text else { return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string)
  }
  @objc func saveTiming(_ field: NSTextField) {
    guard let owner, let key = field.identifier?.rawValue, let value = Double(field.stringValue), (key == "interval" ? 0.2...0.8 : 0.1...1.0).contains(value) else { NSSound.beep(); return }
    if key == "interval" { owner.hotkey.interval = value } else { owner.hotkey.debounce = value }
    UserDefaults.standard.set(value, forKey: key); owner.hotkey.cancel()
  }
}
