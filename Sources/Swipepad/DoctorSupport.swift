import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Security
import SwipepadCore
import TrackpadBridge

@MainActor extension AppDelegate {
  static let bundleID = "com.ericspencer00.swipepad"
  func doctorReport(live: Bool, excludingPID: pid_t? = nil) -> DoctorReport {
    var input = DoctorInput()
    input.bundled = Bundle.main.bundleURL.pathExtension == "app"
    input.identityMatches = Bundle.main.bundleIdentifier == Self.bundleID
    var code: SecStaticCode?
    if SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
      let code
    {
      input.signatureValid =
        SecStaticCodeCheckValidity(
          code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil)
        == errSecSuccess
      var information: CFDictionary?
      if SecCodeCopySigningInformation(
        code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
        let info = information as? [String: Any]
      {
        input.developerSigned = (info[kSecCodeInfoTeamIdentifier as String] as? String) != nil
      }
    }
    input.ownedInstances =
      NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == Self.bundleID && $0.activationPolicy == .accessory
          && (live || $0.processIdentifier != ProcessInfo.processInfo.processIdentifier)
          && $0.processIdentifier != (excludingPID ?? -1)
      }.count
    input.accessibility = AXIsProcessTrusted()
    input.secureInput = IsSecureEventInputEnabled()
    input.frameworkPresent = FileManager.default.fileExists(
      atPath: "/System/Library/PrivateFrameworks/MultitouchSupport.framework")
    input.deviceAvailable = OpenMTManager.systemSupportsMultitouch()
    input.live = live
    input.monitorInstalled = globalMonitor != nil
    input.globalEventSeen = globalEventSeen
    input.hotkeySeen = hotkeySeen
    input.touchSeen = touchSeen
    input.liftSeen = liftSeen
    input.active = active
    input.focusPreserved = lastFocusPreserved
    input.insertionSucceeded = lastInsertionSucceeded
    if input.accessibility, let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      let field = focused(app.processIdentifier)
    {
      input.fieldFound = true
      let metadata = fieldMetadata(field)
      input.fieldRole = metadata.role
      input.fieldSubrole = metadata.subrole
      input.selectedTextSettable = metadata.writable
      input.fieldSupported = supportedField(field)
    }
    return Doctor.evaluate(input)
  }
  @objc func showSetup() {
    cancel("Setup")
    if setupPanel == nil { buildSetupPanel() }
    refreshDoctor()
    NSApp.activate(ignoringOtherApps: true)
    setupPanel?.makeKeyAndOrderFront(nil)
  }
  func buildSetupPanel() {
    let window = SetupWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 370),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Swipepad Setup"
    window.isReleasedWhenClosed = false
    let view = SetupView(owner: self)
    window.contentView = view
    window.center()
    setupPanel = window
    setupView = view
  }
  func refreshDoctor() {
    setupView?.refresh()
    updateModeIndicator()
  }
  @objc func recheckDoctor() {
    reconnectKeyboard()
    refreshDoctor()
  }
  @objc func requestAccessibility() {
    if AXIsProcessTrusted() {
      recheckDoctor()
      return
    }
    accessRequested = true
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    // Requesting is not granting: always re-read actual trust.
    reconnectKeyboard()
    refreshDoctor()
  }
  @objc func openAccessibilitySettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }
  @objc func resetFromDoctor() {
    cancel("Session reset; focus the intended field and activate again")
    hotkey.cancel()
    lastFocusPreserved = nil
    refreshDoctor()
  }
  @objc func relaunchFromDoctor() {
    guard let executable = Bundle.main.executableURL else { return }
    let helper = Process()
    helper.executableURL = executable
    helper.arguments = ["--relaunch-owned"]
    helper.standardOutput = FileHandle.nullDevice
    helper.standardError = FileHandle.nullDevice
    do { try helper.run() } catch {
      setupView?.detail.stringValue = "Relaunch failed. Use the doctor script."
    }
  }
  @objc func closeSetup() { setupPanel?.orderOut(nil) }
  @objc func setupNotification(_ notification: Notification) { showSetup() }
  func reconnectKeyboard() {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    if AXIsProcessTrusted() {
      globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) {
        [weak self] event in
        guard let self else { return }
        if !IsSecureEventInputEnabled() { self.globalEventSeen = true }
        self.handle(event)
      }
    } else if active {
      cancel("Accessibility access is needed")
    }
    hotkey.cancel()
    updateModeIndicator()
  }
  func updateModeIndicator() {
    guard let button = status?.button else { return }
    let state = active ? "On" : (!AXIsProcessTrusted() || globalMonitor == nil ? "Needs setup" : "Ready")
    button.title = ""
    button.setAccessibilityLabel("Swipepad")
    button.setAccessibilityValue(state)
    button.toolTip = "Swipepad: " + state
    status.menu?.items.first?.title = "Swipepad: " + state
    status.menu?.items.dropFirst().first?.title = active ? "Stop Swiping" : "Start Swiping"
  }

  func installStatusIcon() {
    let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
      let outline = NSBezierPath(
        roundedRect: NSRect(x: 1, y: 2, width: 18, height: 15), xRadius: 3, yRadius: 3)
      NSColor.black.setStroke()
      outline.lineWidth = 1.5
      outline.stroke()
      let trail = NSBezierPath()
      trail.move(to: NSPoint(x: 5, y: 6))
      trail.curve(
        to: NSPoint(x: 15, y: 13), controlPoint1: NSPoint(x: 13, y: 4),
        controlPoint2: NSPoint(x: 7, y: 15))
      trail.lineWidth = 2
      trail.lineCapStyle = .round
      trail.stroke()
      return true
    }
    image.isTemplate = true
    status.button?.image = image
    status.button?.imagePosition = .imageLeading
    status.button?.setAccessibilityLabel("Swipepad")
  }
}

@MainActor extension AppDelegate {
  func relaunchOwned() -> Bool {
    guard Bundle.main.bundleURL.pathExtension == "app",
      Bundle.main.bundleIdentifier == Self.bundleID
    else {
      print("Refusing relaunch: run the built Swipepad app bundle.")
      return false
    }
    let executable = Bundle.main.executableURL?.resolvingSymlinksInPath()
    let others = NSWorkspace.shared.runningApplications.filter {
      $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        && $0.bundleIdentifier == Self.bundleID && $0.activationPolicy == .accessory
        && $0.executableURL?.resolvingSymlinksInPath() == executable
    }
    for app in others {
      guard app.terminate() else {
        print("Owned Swipepad refused graceful Quit; no forced termination attempted.")
        return false
      }
    }
    let deadline = Date().addingTimeInterval(5)
    while others.contains(where: { !$0.isTerminated }), Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    guard others.allSatisfy({ $0.isTerminated }) else {
      print("Owned Swipepad is still closing; relaunch cancelled to avoid duplicates.")
      return false
    }
    let progress = RelaunchProgress()
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    // All existing GUI instances at this path have exited. Force a new GUI
    // instance so Launch Services cannot return this temporary CLI helper.
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) {
      app, error in
      let success =
        error == nil
        && RelaunchPolicy.isDistinctLaunch(
          helperPID: ProcessInfo.processInfo.processIdentifier, resultPID: app?.processIdentifier)
      let message =
        success
        ? "Relaunched one Swipepad app instance; documents and settings were preserved."
        : (error.map { "Relaunch failed: \($0.localizedDescription)" }
          ?? "Launch Services did not return a distinct GUI process; relaunch not confirmed.")
      Task { @MainActor in
        print(message)
        progress.success = success
        progress.done = true
      }
    }
    while !progress.done, Date() < deadline.addingTimeInterval(5) {
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    if !progress.done {
      print("Launch confirmation timed out; check process state before retrying.")
      return false
    }
    return progress.success
  }
}

@MainActor private final class RelaunchProgress {
  var done = false
  var success = false
}

@MainActor extension AppDelegate {
  @objc func doctorNotification(_ notification: Notification) {
    guard let request = notification.userInfo?["request"] as? String,
      UUID(uuidString: request) != nil
    else { return }
    var callerPID: pid_t?
    if let number = notification.userInfo?["pid"] as? NSNumber,
      let caller = NSRunningApplication(processIdentifier: number.int32Value),
      caller.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      caller.bundleIdentifier == Self.bundleID,
      caller.executableURL?.resolvingSymlinksInPath()
        == Bundle.main.executableURL?.resolvingSymlinksInPath()
    {
      callerPID = caller.processIdentifier
    }
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(doctorReport(live: true, excludingPID: callerPID)),
      let json = String(data: data, encoding: .utf8)
    else { return }
    // Structural metadata/boolean stage evidence only. No file writes, text values,
    // key contents, gesture coordinates, permission requests or repair actions.
    DistributedNotificationCenter.default().postNotificationName(
      Notification.Name("com.ericspencer00.swipepad.doctorResponse." + request), object: nil,
      userInfo: ["json": json], deliverImmediately: true)
  }
  func liveDoctorSnapshot() -> DoctorReport? {
    guard
      NSWorkspace.shared.runningApplications.contains(where: {
        $0.bundleIdentifier == Self.bundleID
          && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
      })
    else { return nil }
    let request = UUID().uuidString
    let response = DoctorResponse()
    let center = DistributedNotificationCenter.default()
    let observer = center.addObserver(
      forName: Notification.Name("com.ericspencer00.swipepad.doctorResponse." + request),
      object: nil, queue: .main
    ) { notification in
      let json = notification.userInfo?["json"] as? String
      MainActor.assumeIsolated { response.json = json }
    }
    defer { center.removeObserver(observer) }
    center.postNotificationName(
      Notification.Name("com.ericspencer00.swipepad.doctorRequest"), object: nil,
      userInfo: [
        "request": request, "pid": NSNumber(value: ProcessInfo.processInfo.processIdentifier),
      ], deliverImmediately: true)
    let deadline = Date().addingTimeInterval(3)
    var retryAt = Date().addingTimeInterval(0.2)
    while response.json == nil, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      if response.json == nil && Date() >= retryAt {
        center.postNotificationName(
          Notification.Name("com.ericspencer00.swipepad.doctorRequest"), object: nil,
          userInfo: [
            "request": request, "pid": NSNumber(value: ProcessInfo.processInfo.processIdentifier),
          ], deliverImmediately: true)
        retryAt = Date().addingTimeInterval(0.2)
      }
    }
    guard let json = response.json, let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(DoctorReport.self, from: data)
  }
}
@MainActor private final class DoctorResponse { var json: String? }
