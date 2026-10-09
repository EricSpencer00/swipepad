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
@MainActor final class SetupStatusRow: NSStackView {
  let symbol = NSImageView()
  let title = NSTextField(labelWithString: "")
  let detail = NSTextField(labelWithString: "")
  init() {
    super.init(frame: .zero)
    orientation = .horizontal; alignment = .centerY; spacing = 8
    symbol.widthAnchor.constraint(equalToConstant: 17).isActive = true
    symbol.heightAnchor.constraint(equalToConstant: 17).isActive = true
    title.font = .systemFont(ofSize: 13)
    detail.font = .systemFont(ofSize: 13); detail.textColor = .secondaryLabelColor
    addArrangedSubview(symbol); addArrangedSubview(title); addArrangedSubview(detail)
    setAccessibilityElement(true); setAccessibilityRole(.group)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
  func update(_ text: String, detail note: String, state: String) {
    title.stringValue = text; detail.stringValue = note
    let name = state == "on" ? "checkmark.circle.fill" : state == "off" ? "xmark.circle.fill" : "circle.dashed"
    symbol.image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
    symbol.contentTintColor = state == "on" ? .systemGreen : state == "off" ? .systemRed : .secondaryLabelColor
    setAccessibilityLabel(text + ". " + note)
  }
}
@MainActor final class SetupView: NSView {
  weak var owner: AppDelegate?
  let heading = NSTextField(labelWithString: "")
  let detail = NSTextField(wrappingLabelWithString: "")
  let rows = (0..<3).map { _ in SetupStatusRow() }
  let stack = NSStackView()
  let primary = NSButton(title: "", target: nil, action: nil)
  let diagnostics = NSStackView()
  let disclosure = NSButton(title: "Diagnostics", target: nil, action: nil)
  var expanded = false
  var previewTrusted: Bool?
  init(owner: AppDelegate) {
    self.owner = owner
    super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 370))
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
    for row in rows { stack.addArrangedSubview(row) }
    let running = NSTextField(labelWithString: "Running: " + Bundle.main.bundleURL.lastPathComponent)
    running.font = .systemFont(ofSize: 11); running.textColor = .secondaryLabelColor
    let location = NSTextField(labelWithString: Bundle.main.bundleURL.path)
    location.font = .systemFont(ofSize: 11); location.textColor = .secondaryLabelColor
    location.lineBreakMode = .byTruncatingMiddle
    location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let identity = NSButton(title: "Show in Finder", target: self, action: #selector(showInFinder))
    identity.bezelStyle = .rounded; identity.font = .systemFont(ofSize: 11)
    identity.setAccessibilityHelp("Reveal this running copy of Swipepad in Finder")
    let identityRow = NSStackView(views: [running, NSView(), identity])
    identityRow.widthAnchor.constraint(equalToConstant: 480).isActive = true
    stack.addArrangedSubview(identityRow)
    stack.addArrangedSubview(location)
    location.widthAnchor.constraint(equalToConstant: 480).isActive = true
    disclosure.bezelStyle = .rounded
    disclosure.imagePosition = .imageLeading
    disclosure.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    disclosure.font = .systemFont(ofSize: 13)
    disclosure.contentTintColor = .labelColor
    disclosure.target = self; disclosure.action = #selector(toggleDiagnostics)
    disclosure.setAccessibilityLabel("Diagnostics")
    disclosure.setAccessibilityValue("Collapsed")
    stack.addArrangedSubview(disclosure)
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
    rows[0].update("Accessibility", detail: trusted ? "on for this app" : "off for this app", state: trusted ? "on" : "off")
    rows[1].update("Double-Command", detail: owner.hotkeySeen ? "seen" : "not tried yet", state: owner.hotkeySeen ? "on" : "waiting")
    rows[2].update("Swipe and insert", detail: owner.lastInsertionSucceeded == true ? "accepted; confirm the word appeared" : "not tried yet", state: "waiting")
    if !trusted {
      heading.stringValue = owner.accessRequested ? "Turn on Swipepad in Settings" : "Allow Accessibility"
      detail.stringValue = owner.accessRequested ? "Enable Swipepad in System Settings → Privacy & Security → Accessibility. This running app still reports access off." : "Accessibility lets Swipepad observe double-Command and insert your chosen word into a text field. It does not read field contents."
      primary.title = owner.accessRequested ? "Open Accessibility Settings" : "Request Access…"
    } else if owner.globalMonitor == nil && previewTrusted == nil {
      heading.stringValue = "Reconnect the shortcut"; detail.stringValue = "Accessibility is on. Reconnect the keyboard listener to try double-Command."; primary.title = "Reconnect"
    } else if !OpenMTManager.systemSupportsMultitouch() {
      heading.stringValue = "No supported trackpad"; detail.stringValue = "Connect a supported Apple trackpad to try physical swipe typing."; primary.title = "Close"
    } else if IsSecureEventInputEnabled() {
      heading.stringValue = "Paused for secure input"; detail.stringValue = "Leave the secure field, then try in a regular text area."; primary.title = "Close"
    } else {
      heading.stringValue = owner.hotkeySeen ? "Double-Command works" : "Ready to try"
      detail.stringValue = "Focus a text field. Use double-Command, lift your fingers, then swipe a word and choose a candidate."
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
    disclosure.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
    disclosure.setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
    fitWindow()
  }
  func fitWindow() {
    layoutSubtreeIfNeeded()
    let height = stack.fittingSize.height + 40
    window?.setContentSize(NSSize(width: 520, height: height))
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
