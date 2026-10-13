import AppKit
import ApplicationServices
import Carbon
import CryptoKit
import Foundation
import SwipepadCore
import TrackpadBridge

final class GuidePanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
@MainActor final class KeyboardView: OverlayKeyboardView { var showKeys=true }
@MainActor class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation, NSMenuDelegate {
  enum InsertionTransport { case keyboard, accessibility }
  // Ordinary text entry goes through the receiving application's input pipeline.
  // An advertised AX setter can acknowledge without editing a controlled composer.
  // Select one transport before mutation; never fall back after dispatch.
  var insertionTransport:InsertionTransport = .keyboard
  static let ownTextEventTag:Int64 = 0x53575044545854
  var status: NSStatusItem!
  var panel: GuidePanel!
  lazy var keyboard = KeyboardView(frame: NSRect(x: 20, y: 100, width: 560, height: 210))
  lazy var label = NSTextField(wrappingLabelWithString: "OFF — Double-tap Command in a text field")
  var buttons: [NSButton] = []
  var guideKeyboardHeight:NSLayoutConstraint?
  var overlayPanel:GuidePanel?
  let overlayKeyboard=OverlayKeyboardView()
  var overlayFrame:CalibrationRect?
  var strokeCalibration:CalibrationRect?
  var strokeSamples:[StrokeSample]=[]
  var strokeSource:InputMode = .trackpad
  var activationScreen:NSScreen?
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
  var inputProtectionHealthy=true
  var target: AXUIElement?
  var originalPID: pid_t = 0
  var originalSelection: CFRange?
  var originalContentDigest:Data?
  var finger: Int32?
  var path: [Point] = []
  var pending = false
  // Structural readback diagnostics never authorize or resolve a write. Digests
  // remain in memory with the existing transaction; only counts/booleans escape.
  struct MutationEvidence {
    let beforeLength:Int,expectedLength:Int,insertedLength:Int,prefixLength:Int,suffixLength:Int
    let insertedDigests:[Data],prefixDigest:Data,suffixDigest:Data
    static func digest(_ units:[UInt16])->Data {units.withUnsafeBytes {Data(SHA256.hash(data:Data($0)))}}
    init(before:String,range:CFRange,inserted:String) {
      let units=Array(before.utf16)
      beforeLength=units.count;insertedLength=inserted.utf16.count
      expectedLength=units.count-range.length+insertedLength;prefixLength=range.location;suffixLength=units.count-range.location-range.length
      insertedDigests=[Self.digest(Array(inserted.utf16))]+(inserted.hasSuffix(" ") ? [Self.digest(Array((String(inserted.dropLast())+"\u{00a0}").utf16))]:[])
      prefixDigest=Self.digest(Array(units.prefix(prefixLength)))
      suffixDigest=Self.digest(Array(units.suffix(suffixLength)))
    }
    func compare(_ observed:String,location:Int)->(inserted:Bool,prefix:Bool,suffix:Bool) {
      let units=Array(observed.utf16),end=location+insertedLength
      let span=location>=0 && end<=units.count ? insertedDigests.contains(Self.digest(Array(units[location..<end]))):false
      let prefix=prefixLength<=units.count && Self.digest(Array(units.prefix(prefixLength)))==prefixDigest
      // Compare the unchanged suffix at the expected insertion boundary, rather
      // than accepting a matching suffix at some other position in the document.
      let suffix=end<=units.count && units.count-end==suffixLength && Self.digest(Array(units.suffix(suffixLength)))==suffixDigest
      return (span,prefix,suffix)
    }
  }
  struct UnresolvedWrite {let id:UUID;let field:AXUIElement;let pid:pid_t;let originalRange:CFRange;let beforeDigest:Data?;let expectedCaret:Int;let expectedDigest:Data?;var separatorDigest:Data?=nil;var trimmedSeparator=false;var trimmedDigest:Data?=nil;var deferredCaret=false;var mutationAccepted=false;var receiptDigests:[Data]=[];var generatedTrailingSeparator=false;var evidence:MutationEvidence?=nil;var originalBundleIdentifier:String?=nil}
  var unresolvedWrites:[UnresolvedWrite]=[]
  var carriedWriteGuards:[OutstandingWriteReport]=[]
  var writeTrackingReadable=true
  var writeTrackingEnabled:Bool {Bundle.main.bundleIdentifier==Self.bundleID && Bundle.main.bundleURL.pathExtension=="app"}
  static let trackingKey="unconfirmedWriteGuards.v1"
  var trackingURL:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Swipepad/UnconfirmedWrites.json")}
  func loadWriteTracking() {
    guard writeTrackingEnabled else {return}
    guard FileManager.default.fileExists(atPath:trackingURL.path) else {return}
    guard let data=try? Data(contentsOf:trackingURL) else {writeTrackingReadable=false;return}
    guard let records=try? JSONDecoder().decode([OutstandingWriteReport].self,from:data),records.allSatisfy({$0.pid>0 && $0.expectedCaret>=0 && $0.transactionID.flatMap(UUID.init(uuidString:)) != nil}) else {writeTrackingReadable=false;return}
    carriedWriteGuards=records
  }
  func trackingBlocks(_ pid:pid_t)->Bool { !writeTrackingReadable || carriedWriteGuards.contains {$0.pid==pid} }
  @discardableResult func persistWriteTracking()->Bool {
    guard writeTrackingEnabled else {return true}
    guard writeTrackingReadable,let data=try? JSONEncoder().encode(outstandingWriteReports()) else {return false}
    do {
      try FileManager.default.createDirectory(at:trackingURL.deletingLastPathComponent(),withIntermediateDirectories:true)
      try data.write(to:trackingURL,options:.atomic)
      return try Data(contentsOf:trackingURL)==data
    } catch {return false}
  }
  func importWriteTracking(_ path:String)->Bool {
    guard writeTrackingEnabled,runtimeSignatureValid,let data=try? Data(contentsOf:URL(fileURLWithPath:path)),data.count<262144,
      let report=try? JSONDecoder().decode(DoctorReport.self,from:data),report.scope.hasPrefix("Live capture counters"),let records=report.outstandingWrites,
      records.allSatisfy({$0.pid>0 && $0.expectedCaret>=0 && $0.transactionID.flatMap(UUID.init(uuidString:)) != nil}) else {return false}
    loadWriteTracking();guard writeTrackingReadable else {return false}
    let known=Set(carriedWriteGuards.compactMap(\.transactionID))
    carriedWriteGuards += records.filter {!known.contains($0.transactionID ?? "")}
    return persistWriteTracking()
  }
  struct WriteReviewSelection {let generation:Int;let record:OutstandingWriteReport}
  var writeReviewGeneration=0
  var writeReviewMenu:NSMenu?
  func writeReviewName(_ record:OutstandingWriteReport)->String {
    let running=NSRunningApplication(processIdentifier:record.pid)
    if let bundle=record.bundleIdentifier,running?.bundleIdentifier==bundle,let name=running?.localizedName {return name}
    return record.bundleIdentifier ?? "Unidentified app"
  }
  func populateWriteReviewMenu(_ menu:NSMenu) {
    writeReviewGeneration += 1;menu.removeAllItems();menu.autoenablesItems=false
    let records=outstandingWriteReports()
    for record in records {
      guard let id=record.transactionID else {continue}
      let item=NSMenuItem(title:writeReviewName(record)+" · PID \(record.pid) · \(id.prefix(8))…",action:#selector(reviewWriteTracking(_:)),keyEquivalent:"")
      let selection=WriteReviewSelection(generation:writeReviewGeneration,record:record)
      item.target=self;item.representedObject=selection;item.toolTip="Application: \(record.bundleIdentifier ?? "unknown") · Process: \(record.pid) · Record: \(id)"
      item.isEnabled=reviewRecord(selection) != nil
      menu.addItem(item)
    }
    if menu.items.isEmpty {let empty=NSMenuItem(title:"No unconfirmed writes",action:nil,keyEquivalent:"");empty.isEnabled=false;menu.addItem(empty)}
  }
  func menuNeedsUpdate(_ menu:NSMenu) {
    if let review=writeReviewMenu,menu===review || menu===status?.menu {populateWriteReviewMenu(review)}
  }
  func reviewRecord(_ selection:WriteReviewSelection)->OutstandingWriteReport? {
    guard !active,writeTrackingReadable,selection.generation==writeReviewGeneration,
      let id=selection.record.transactionID else {return nil}
    let matches=outstandingWriteReports().filter {$0.transactionID==id}
    guard matches.count==1,let record=matches.first else {return nil}
    let selected=selection.record
    guard record.pid==selected.pid,record.bundleIdentifier==selected.bundleIdentifier,
      record.expectedCaret==selected.expectedCaret,record.mutationAccepted==selected.mutationAccepted,
      record.caretAttemptPending==selected.caretAttemptPending else {return nil}
    return record
  }
  func confirmWriteReview(_ selection:WriteReviewSelection)->Bool {
    let record=selection.record
    let alert=NSAlert();alert.messageText="A previous write is unconfirmed"
    alert.informativeText="Check and save the unsent draft in \(writeReviewName(record)) before clearing this write's tracking.\n\nApplication: \(record.bundleIdentifier ?? "unknown")\nProcess: \(record.pid)\nRecord: \(record.transactionID ?? "unavailable")\n\nClearing changes no draft text and never replays the word. Other records remain protected."
    alert.addButton(withTitle:"Keep protection");alert.addButton(withTitle:"Clear this write's tracking")
    return alert.runModal() == .alertSecondButtonReturn
  }
  @discardableResult func completeWriteReview(_ selection:WriteReviewSelection,confirmed:Bool)->Bool {
    guard confirmed,let record=reviewRecord(selection),let id=record.transactionID else {return false}
    let carriedBefore=carriedWriteGuards,unresolvedBefore=unresolvedWrites
    carriedWriteGuards.removeAll {$0.transactionID==id};unresolvedWrites.removeAll {$0.id.uuidString==id}
    guard persistWriteTracking() else {
      carriedWriteGuards=carriedBefore;unresolvedWrites=unresolvedBefore;writeTrackingReadable=false
      writeReviewGeneration += 1;updateModeIndicator();return false
    }
    writeReviewGeneration += 1;updateModeIndicator();return true
  }
  @objc func reviewWriteTracking(_ sender:NSMenuItem) {
    guard let selection=sender.representedObject as? WriteReviewSelection,reviewRecord(selection) != nil else {return}
    // The alert runs a modal loop: a record can resolve or change while it is open.
    // Revalidate the exact snapshot after the explicit decision; never choose first.
    _=completeWriteReview(selection,confirmed:confirmWriteReview(selection))
  }
  var strokeCancellationGeneration=0
  var sessionGeneration=0
  var correctionPollToken=0
  var pendingWriteID:UUID?
  struct QueuedWord {let word:String;let alternatives:[String];let field:AXUIElement;let pid:pid_t}
  var queuedWords:[QueuedWord]=[]
  var continuationAnchor:UnresolvedWrite?
  var contactGate=ContactGate()
  var waitForLift:Bool {get {contactGate.waitingForLift} set {contactGate.waitingForLift=newValue}}
  struct OwnedWord {let field:AXUIElement,pid:pid_t;let range:CFRange;let alternatives:[String];let fingerprint:Data;var leadingSeparator=false;var trailingSeparator=true}
  var lastOwnedWord:OwnedWord?
  var lastCompletedSamples:[StrokeSample]=[]
  struct UninsertedSuggestion {let field:AXUIElement,pid:pid_t;let range:CFRange;let digest:Data;let choices:[String]}
  var lastSuggestion:UninsertedSuggestion?
  var lastSwipeChoices:[String]=[]
  var suggestionWriteID:UUID?
  var frameOrdering=FrameOrdering()
  var liftGraceSeconds=LiftGrace.defaultSeconds
  struct GraceContact {let id:Int32,point:Point,time:Double,state:OpenMTState}
  struct DeferredLift {let id:Int32,hostTime:Double,token:Int;var candidate:GraceContact?;var candidateSamples:[GraceContact]=[];var candidateHostTime:Double?}
  var deferredLift:DeferredLift?
  var liftTimerGeneration=0
  var bounceCount=0,missingSeconds=0.0
  var strokeToken=0,retiredToken=0
  var strokeFreshContact=false,strokeActualContact=false
  var statusReason:String?
  var feedbackPanel:GuidePanel?
  var feedbackGeneration=0
  lazy var cornerProtection=HotCornerProtection(isActive:{[weak self] in self?.active == true},failed:{[weak self] in self?.pauseForInputProtectionFailure()},escapePressed:{[weak self] in self?.hotkey.cancel();self?.cancel("OFF")},observedScroll:{[weak self] in self?.captureDiagnostics.scrollEventsPassed += 1})
  var captureDiagnostics=CaptureDiagnostics()
  var captureIdentityCache:String?
  var focusLookupErrors:(application:Int?,system:Int?)=(nil,nil)
  // OS-backed in production; sandbox ports control this flag without changing the OS.
  var secureInputActive:Bool {IsSecureEventInputEnabled()}
  var runtimeSignatureValid:Bool {checkRuntimeSignature()}
  var canPostText:Bool {CGPreflightPostEventAccess()}
  var feedbackWindowsEnabled:Bool {true}
  let words = WordVocabulary.words
  lazy var gestureLexicon = GestureLexicon(words:words)
  func validateMenuItem(_ menuItem:NSMenuItem) -> Bool {
    if menuItem.action == #selector(reviewWriteTracking(_:)) {return (menuItem.representedObject as? WriteReviewSelection).flatMap {reviewRecord($0)} != nil}
    return menuItem.action == #selector(showLastCorrection) ? (!active && lastOwnedWord != nil) : (menuItem.action == #selector(chooseMode(_:)) ? !active : true)
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    loadWriteTracking()
    _ = captureRuntimeIdentity() // Cache immutable running-build identity while Off.
    _ = gestureLexicon // Build the immutable index while Off, before any capture/listener work.
    _ = WordCommonness.tier("zzzz") // Warm all commonness sets before active capture.
    UserDefaults.standard.register(defaults: [
      "showGuide": true, "interval": 0.35, "debounce": 0.15, "inputMode": "trackpad", "overlayOpacity": 0.55,"liftGrace":LiftGrace.defaultSeconds,
    ])
    liftGraceSeconds=min(0.4,max(0,UserDefaults.standard.double(forKey:"liftGrace")))
    hotkey.interval = UserDefaults.standard.double(forKey: "interval")
    hotkey.debounce = UserDefaults.standard.double(forKey: "debounce")
    NSApp.setActivationPolicy(.accessory)
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    installStatusIcon()
    status.isVisible=true
    status.button?.title = "Swipepad"
    let menu = NSMenu()
    menu.addItem(
      withTitle: "Swipepad: Off", action: nil, keyEquivalent: "")
    menu.addItem(withTitle: "Start Swiping ⌘⌘", action: #selector(toggle), keyEquivalent: "")
    menu.addItem(
      withTitle: "Show Keyboard Guide", action: #selector(toggleGuide), keyEquivalent: ""
    ).state = UserDefaults.standard.bool(forKey: "showGuide") ? .on : .off
    menu.addItem(.separator())
    for (title,mode) in [("Keyboard Guide: In Panel",InputMode.trackpad),("Keyboard Guide: On Screen",.screenOverlay)] {
      let item=menu.addItem(withTitle:title,action:#selector(chooseMode(_:)),keyEquivalent:"")
      item.representedObject=mode.rawValue;item.state=inputMode==mode ? .on : .off
    }
    menu.addItem(withTitle:"On-Screen Guide Layout…",action:#selector(showOverlayLayout),keyEquivalent:"")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Correct Last Word…", action: #selector(showLastCorrection), keyEquivalent: "")
    menu.addItem(withTitle:"Last Swipe Suggestions…",action:#selector(showSwipeSuggestions),keyEquivalent:"")
    let review=NSMenuItem(title:"Review Unconfirmed Writes",action:nil,keyEquivalent:"")
    let reviewSubmenu=NSMenu();reviewSubmenu.delegate=self;writeReviewMenu=reviewSubmenu
    populateWriteReviewMenu(reviewSubmenu);review.submenu=reviewSubmenu;menu.addItem(review);menu.delegate=self
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
    label.widthAnchor.constraint(equalTo:guide.widthAnchor).isActive=true
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
        guard let self,self.active else {return}
        if self.secureContextActive() {self.exitSecureContext();return}
        if !self.pending,self.target != nil,!self.validTarget() {self.cancel("Focus changed — cancelled")}
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
        if self.active && !self.runtimeSignatureValid {self.stopForChangedBuild();return}
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
    if e.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.ownTextEventTag {return}
    if e.type == .keyDown {
      hotkey.cancel();abandonActivation()
      if e.keyCode == 53 {if active {cancel("OFF")} else {lastOwnedWord=nil;cancel("Cancelled")}}
      else {lastOwnedWord=nil;if active {cancel("Keyboard input · next swipe uses the current field")} else {panel?.orderOut(nil)}}
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
  func measureAX<T>(_ request:()->T)->T {
    let start=ProcessInfo.processInfo.systemUptime
    defer {
      captureDiagnostics.axRequests += 1
      let elapsed=(ProcessInfo.processInfo.systemUptime-start)*1000
      captureDiagnostics.totalAXMilliseconds += elapsed
      captureDiagnostics.maximumAXMilliseconds=max(captureDiagnostics.maximumAXMilliseconds,elapsed)
    }
    return request()
  }
  func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result=measureAX({AXUIElementCopyAttributeValue(element,name as CFString,&value)})
    if name==kAXValueAttribute {
      captureDiagnostics.valueReadAXError=Int(result.rawValue)
      captureDiagnostics.valueReadKind=value==nil ? "nil":(value is String ? "string":(value is NSAttributedString ? "attributedString":"other"))
    }
    guard result == .success else {return nil}
    return value
  }
  func parameterizedText(_ field:AXUIElement,range:CFRange)->String? {
    var copy=range
    guard let parameter=AXValueCreate(.cfRange,&copy) else {return nil}
    var value:CFTypeRef?
    let result=measureAX({AXUIElementCopyParameterizedAttributeValue(field,kAXStringForRangeParameterizedAttribute as CFString,parameter,&value)})
    captureDiagnostics.rangeTextAXError=Int(result.rawValue)
    guard result == .success else {return nil}
    return value as? String
  }
  func characterCount(_ field:AXUIElement)->Int? {
    guard let value=attribute(field,kAXNumberOfCharactersAttribute),CFGetTypeID(value)==CFNumberGetTypeID(),let number=value as? NSNumber else {return nil}
    let count=number.intValue
    guard count>=0,count<=1_000_000,number.doubleValue==Double(count) else {return nil}
    return count
  }
  // Gathers the raw reads for one field; FieldText.resolve decides what they prove. Providers
  // differ (AXValue omitted, placeholder reported as value, count or range refused), so every
  // read stays here and every acceptance rule stays in SwipepadCore where checks can lock it in.
  func textEvidence(_ field:AXUIElement)->FieldText.Evidence? {
    captureDiagnostics.textEvidenceSource=nil;captureDiagnostics.textEvidenceLength=nil;captureDiagnostics.rangeTextAXError=nil
    captureDiagnostics.textEvidenceValueLength=nil;captureDiagnostics.textEvidenceCharacterCount=nil;captureDiagnostics.textEvidenceValueMatchesRange=nil
    captureDiagnostics.textEvidenceMatchesPlaceholder=nil
    captureDiagnostics.valueReadAXError=nil;captureDiagnostics.valueReadKind=nil
    let direct=attribute(field,kAXValueAttribute) as? String
    captureDiagnostics.textEvidenceValueLength=direct?.utf16.count
    // A permission or provider failure refuses here, before any count or text-suite read.
    guard FieldText.permitsValueRead(error:captureDiagnostics.valueReadAXError) else {return nil}
    var probe=FieldTextProbe(value:direct,valueError:captureDiagnostics.valueReadAXError)
    probe.characterCount=characterCount(field)
    probe.placeholder=(attribute(field,kAXPlaceholderValueAttribute as String) as? String).flatMap {$0.isEmpty ? nil:$0}
    captureDiagnostics.textEvidenceCharacterCount=probe.characterCount
    if let count=probe.characterCount {
      // Prefer the provider's full range to its AXValue. The two can share a length, so
      // length agreement alone is never enough; resolve() also re-checks the count.
      probe.fullRangeText=parameterizedText(field,range:CFRange(location:0,length:count))
      probe.fullRangeError=captureDiagnostics.rangeTextAXError
      if probe.fullRangeText != nil {probe.characterCountAfterRead=characterCount(field)}
    }
    guard let evidence=FieldText.resolve(probe) else {return nil}
    captureDiagnostics.textEvidenceMatchesPlaceholder=probe.placeholder.map {$0==evidence.text}
    if evidence.source == .fullRange {captureDiagnostics.textEvidenceValueMatchesRange=direct.map {$0==evidence.text}}
    captureDiagnostics.textEvidenceSource=evidence.source == .fullRange ? "fullRange":"value"
    captureDiagnostics.textEvidenceLength=evidence.text.utf16.count
    return evidence
  }
  func fieldText(_ field:AXUIElement)->String? {textEvidence(field)?.text}
  var currentApplicationPID:pid_t? {NSWorkspace.shared.frontmostApplication?.processIdentifier}
  func attributeWritable(_ element:AXUIElement,_ name:String)->Bool {
    var writable:DarwinBoolean=false
    return measureAX({AXUIElementIsAttributeSettable(element,name as CFString,&writable)}) == .success && writable.boolValue
  }
  func setAttribute(_ element:AXUIElement,_ name:String,_ value:CFTypeRef)->AXError {
    measureAX({AXUIElementSetAttributeValue(element,name as CFString,value)})
  }
  func focused(_ pid: pid_t) -> AXUIElement? {
    focusLookupErrors=(nil,nil)
    func read(_ root:AXUIElement, system:Bool)->AXUIElement? {
      var value:CFTypeRef?
      let result=measureAX({AXUIElementCopyAttributeValue(root,kAXFocusedUIElementAttribute as CFString,&value)})
      if system {focusLookupErrors.system=Int(result.rawValue)}
      else {focusLookupErrors.application=Int(result.rawValue)}
      guard result == .success,let value,CFGetTypeID(value)==AXUIElementGetTypeID() else {return nil}
      let field=unsafeDowncast(value,to:AXUIElement.self)
      var fieldPID:pid_t=0
      guard measureAX({AXUIElementGetPid(field,&fieldPID)}) == .success,fieldPID==pid else {return nil}
      return field
    }
    if let field=read(AXUIElementCreateApplication(pid),system:false) {return field}
    // Some providers publish authoritative focus only through the system root.
    // Never accept another process's field or infer focus from an editable descendant.
    return read(AXUIElementCreateSystemWide(),system:true)
  }
  func fieldMetadata(_ element: AXUIElement) -> (
    role: String?, subrole: FieldSubrole, writable: Bool
  ) {
    let role = attribute(element, kAXRoleAttribute) as? String
    var value: CFTypeRef?
    let subroleResult = measureAX({AXUIElementCopyAttributeValue(
      element, kAXSubroleAttribute as CFString, &value)})
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
      measureAX({AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)})
      == .success && settable.boolValue
    var valueSettable:DarwinBoolean=false,rangeSettable:DarwinBoolean=false
    let valueWritable=measureAX({AXUIElementIsAttributeSettable(element,kAXValueAttribute as CFString,&valueSettable)}) == .success && valueSettable.boolValue
    let rangeWritable=measureAX({AXUIElementIsAttributeSettable(element,kAXSelectedTextRangeAttribute as CFString,&rangeSettable)}) == .success && rangeSettable.boolValue
    // Metadata checks never read field contents. Admission checks the authoritative
    // content/caret only AFTER rejecting secure, read-only and unsupported fields.
    let insertable = InsertionCapability.available(
      editable: attribute(element,"AXEditable") as? Bool,
      selectedTextWritable: writable,
      valueAndRangeWritable: valueWritable && rangeWritable,
      keyboardPathAvailable: insertionTransport == .keyboard && canPostText)
    return (role, subrole, insertable)
  }
  func supportedField(_ element: AXUIElement) -> Bool {
    let metadata = fieldMetadata(element)
    return FieldPolicy.permits(
      role: metadata.role, subrole: metadata.subrole, insertionSettable: metadata.writable,
      secureInput: secureInputActive)
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
    guard !active || inputProtectionHealthy else {return false}
    if pending,let target,let range=selection(target) {return identity(target,pid:originalPID) && permitsPendingCapture(target,pid:originalPID,range:range)}
    guard !secureInputActive, let target,
      let pid = currentApplicationPID,
      let current = focused(pid)
    else {
      if active { lastFocusPreserved = false;captureDiagnostics.focusRejection="focusUnavailable" }
      return false
    }
    let permitted = FocusGuard.permits(
      originalPID: originalPID, currentPID: pid,
      sameElement: CFEqual(target, current), secure: secureInputActive,
      editable: supportedField(current))
      && originalSelection.map { original in
        selection(current).map { $0.location == original.location && $0.length == original.length } ?? false
      } == true
    if !permitted,active {
      captureDiagnostics.focusRejection = pid != originalPID ? "appChanged" :
        (!CFEqual(target,current) ? "fieldChanged" : (!supportedField(current) ? "unsupportedField" : "selectionChangedOrUnavailable"))
    }
    if active { lastFocusPreserved = permitted }
    return permitted
  }
  func protectionContextReason()->String? {
    if secureInputActive {return "secureInput"}
    guard let pid=currentApplicationPID,let field=focused(pid) else {return nil}
    switch fieldMetadata(field).subrole {
    case .named("AXSecureTextField"):return "secureField"
    case .unreadable:return "protectionMetadataUnavailable"
    default:return nil
    }
  }
  func secureContextActive()->Bool {protectionContextReason() != nil}
  func exitSecureContext() {
    let reason=protectionContextReason() ?? "secureInput"
    lastOwnedWord=nil
    cancel("OFF")
    recordTargetRefusal(reason)
    showFeedback(reason=="protectionMetadataUnavailable" ? "Protection metadata unavailable · swiping stopped":"Password or Secure Input · swiping stopped")
  }
  @objc func toggle() {
    correctionPollToken += 1
    let wasWaiting = !active && captureDiagnostics.stage=="awaitingFocusPublication"
    abandonActivation();sessionGeneration += 1
    if wasWaiting {return}
    if active {
      cancel("OFF")
      return
    }
    lastOwnedWord=nil
    statusReason=nil;feedbackPanel?.orderOut(nil);panel?.orderOut(nil);overlayPanel?.orderOut(nil)
    lastSuggestion=nil;lastSwipeChoices=[]
    let trial=captureDiagnostics.trial+1
    captureDiagnostics=CaptureDiagnostics();captureDiagnostics.trial=trial
    captureDiagnostics.mode=inputMode.rawValue;captureDiagnostics.stage="activating";captureDiagnostics.liftGraceSeconds=liftGraceSeconds
    guard runtimeSignatureValid else {stopForChangedBuild();return}
    guard AXIsProcessTrusted() else {
      captureDiagnostics.stage="activationRefused";captureDiagnostics.result="accessibilityRequired"
      updateModeIndicator()
      showFeedback("Accessibility required · open Setup to connect Swipepad")
      showActivationRefusal(statusReason ?? "Accessibility required · typing stayed off")
      return
    }
    guard insertionTransport != .keyboard || canPostText else {
      captureDiagnostics.stage="activationRefused";captureDiagnostics.result="keyboardPostAccessUnavailable"
      showFeedback("Keyboard delivery access unavailable · typing stayed off")
      showActivationRefusal(statusReason ?? "Keyboard delivery unavailable · typing stayed off")
      return
    }
    if secureContextActive() {exitSecureContext();showActivationRefusal(statusReason ?? "Secure input · typing stayed off");return}
    // Refuse before installing capture or suppressing pointer input. A non-text
    // double-Command must leave ordinary input usable without a dismissal click.
    requestActivation()
  }
  func stopForChangedBuild() {
    cancel("OFF");lastOwnedWord=nil
    captureDiagnostics.stage="runtimeIdentityChanged";captureDiagnostics.result="Running code differs from app bundle"
    showFeedback("App changed while running · quit and relaunch the intended signed build")
    if NSApp != nil {showActivationRefusal(statusReason ?? "App changed while running")}
  }
  static let focusPublicationRetryInterval=0.1
  static let focusPublicationWaitSeconds=1.5
  var activationRetryToken=0
  func abandonActivation() {
    activationRetryToken += 1
    guard !active,captureDiagnostics.stage=="awaitingFocusPublication" else {return}
    target=nil;originalSelection=nil;originalContentDigest=nil
    captureDiagnostics.stage="activationAbandoned";statusReason=nil
    updateModeIndicator()
  }
  // Capture stays Off until authoritative focus passes the unchanged admission guards.
  func requestActivation(deadline:Double?=nil) {
    guard runtimeSignatureValid else {stopForChangedBuild();return}
    let pid=currentApplicationPID,token=activationRetryToken
    let limit=deadline ?? ProcessInfo.processInfo.systemUptime+Self.focusPublicationWaitSeconds
    guard acquireTarget() else {
      target=nil;originalSelection=nil;originalContentDigest=nil
      if let pid,FocusLookup.isUnpublished(application:captureDiagnostics.applicationFocusAXError,system:captureDiagnostics.systemFocusAXError),
        ProcessInfo.processInfo.systemUptime+Self.focusPublicationRetryInterval<=limit {
        captureDiagnostics.stage="awaitingFocusPublication"
        DispatchQueue.main.asyncAfter(deadline:.now()+Self.focusPublicationRetryInterval) {[weak self] in
          guard let self,self.activationRetryToken==token else {return}
          guard !self.active,self.currentApplicationPID==pid else {self.abandonActivation();return}
          self.captureDiagnostics.focusPublicationRetries=(self.captureDiagnostics.focusPublicationRetries ?? 0)+1
          self.requestActivation(deadline:limit)
        }
        return
      }
      updateModeIndicator()
      if NSApp != nil {showActivationRefusal(statusReason ?? "Swipepad stayed off · focused input unavailable")}
      return
    }
    guard pid != nil,currentApplicationPID==pid else {
      abandonActivation();target=nil;originalSelection=nil;originalContentDigest=nil
      captureDiagnostics.stage="activationAbandoned";return
    }
    finishActivation()
  }
  func finishActivation() {
    statusReason=nil;feedbackPanel?.orderOut(nil)
    activationScreen=NSWorkspace.shared.frontmostApplication.flatMap {screenForTarget($0.processIdentifier)} ?? NSScreen.main
    active = true
    pending = false;pendingWriteID=nil;queuedWords=[];continuationAnchor=nil
    // Fresh starting/making contacts work without an initial idle callback.
    // Ambiguous already-touching contact at activation must actually lift once.
    contactGate.reset()
    deferredLift=nil;liftTimerGeneration += 1;bounceCount=0;missingSeconds=0
    touchSeen=false;liftSeen=false
    frameOrdering.reset(receivedAfter:ProcessInfo.processInfo.systemUptime)
    path = []
    strokeSamples=[];strokeSource=inputMode;strokeCalibration=nil
    finger = nil
    captureDiagnostics.stage="ready"
    guard OpenMTManager.systemSupportsMultitouch() else {
      cancel("OFF");showFeedback("No supported trackpad");showActivationRefusal("No supported trackpad · typing stayed off")
      return
    }
    listener = OpenMTManager.shared().addListener(
      withTarget: self, selector: #selector(touchFrame(_:)))
    guard listener != nil else {
      cancel("OFF");showFeedback("Trackpad capture unavailable");showActivationRefusal("Trackpad capture unavailable · typing stayed off")
      return
    }
    guard cornerProtection.start() else {cancel("OFF");let reason=cornerProtection.startFailureReason ?? "Mouse protection unavailable · existing Accessibility access could not create filter";showFeedback(reason);showActivationRefusal(reason);return}
    inputProtectionHealthy=true
    updateModeIndicator()
    setupPanel?.orderOut(nil)
    label.stringValue = "Ready · swipe and lift to type. Escape or double-Command turns typing off"
    target=nil;originalSelection=nil;originalContentDigest=nil
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
    applyGuideVisibility()
    if strokeSource == .trackpad && UserDefaults.standard.bool(forKey:"showGuide") {panel.orderFrontRegardless()}
  }
  func recordTargetRefusal(_ reason:String) {
    if captureDiagnostics.firstTargetRefusal==nil {captureDiagnostics.firstTargetRefusal=reason}
    captureDiagnostics.lastTargetRefusal=reason;captureDiagnostics.result=reason
  }
  @discardableResult func acquireTarget() -> Bool {
    captureDiagnostics.targetAttempts += 1
    captureDiagnostics.targetApplicationPID=currentApplicationPID
    captureDiagnostics.applicationFocusAXError=nil;captureDiagnostics.systemFocusAXError=nil
    guard !secureContextActive() else {exitSecureContext();return false}
    focusLookupErrors=(nil,nil)
    let candidatePID=currentApplicationPID
    if let pid=candidatePID,trackingBlocks(pid) {
      captureDiagnostics.stage="fieldRefused";recordTargetRefusal("preservedUnconfirmedWrite")
      showFeedback("Previous write unconfirmed · review tracking from the Swipepad menu; nothing replayed");return false
    }
    let candidateField=candidatePID.flatMap {$0 == ProcessInfo.processInfo.processIdentifier ? nil:focused($0)}
    captureDiagnostics.applicationFocusAXError=focusLookupErrors.application
    captureDiagnostics.systemFocusAXError=focusLookupErrors.system
    captureDiagnostics.targetBundleIdentifier=candidatePID.flatMap {NSRunningApplication(processIdentifier:$0)?.bundleIdentifier}
    captureDiagnostics.focusLookupKind=candidatePID==ProcessInfo.processInfo.processIdentifier ? "swipepadFrontmost":FocusLookup.kind(application:focusLookupErrors.application,system:focusLookupErrors.system,fieldFound:candidateField != nil)
    guard let pid=candidatePID,let field=candidateField else {
      captureDiagnostics.stage="activationRefused";recordTargetRefusal("missingFocusedField")
      let why:String
      switch captureDiagnostics.focusLookupKind {
      case "accessibilityDisabled":why="Accessibility is unavailable to Swipepad"
      case "focusNotPublished":why="The app reported no focused text field · click inside the field, then double-Command"
      case "providerNotResponding":why="The app did not answer Accessibility in time"
      default:why="Typing is off · focus an editable field, then double-Command"
      }
      showFeedback(active ? "Focus unavailable · turn typing off to choose a field" : why);return false
    }
    let metadata=fieldMetadata(field)
    let selected=attributeWritable(field,kAXSelectedTextAttribute)
    let value=attributeWritable(field,kAXValueAttribute)
    let rangeWrite=attributeWritable(field,kAXSelectedTextRangeAttribute)
    let role=["AXTextArea","AXTextField","AXComboBox"].contains(metadata.role ?? "") ? metadata.role!:"other"
    let subrole:String
    switch metadata.subrole {case .absent:subrole="absent";case .unreadable:subrole="unreadable";case .named(let name):subrole=["AXUnknown","AXSearchField","AXSecureTextField"].contains(name) ? name:"unrecognized"}
    captureDiagnostics.inputCapabilities="Role \(role) · subrole \(subrole) · selected-text write \(selected) · value write \(value) · selection write \(rangeWrite)"
    // Admit from the same metadata snapshot the diagnostics just recorded, not a second read.
    guard FieldPolicy.permits(role:metadata.role,subrole:metadata.subrole,insertionSettable:metadata.writable,secureInput:secureInputActive) else {
      captureDiagnostics.stage="activationRefused";recordTargetRefusal("unsupportedField")
      showFeedback("This field does not expose safe editable input · see Setup diagnostics");return false
    }
    // Qualify content only for a requested activation/new stroke, never in the metadata doctor.
    let content=fieldText(field)
    captureDiagnostics.contentReadable=content != nil
    guard let content else {
      captureDiagnostics.stage="fieldRefused";recordTargetRefusal("contentEvidenceUnavailable")
      showFeedback("This field cannot supply safe content evidence · no text sent");return false
    }
    guard let range = selection(field) else {
      captureDiagnostics.stage="activationRefused";recordTargetRefusal("selectionUnavailable")
      showFeedback("Waiting for a field with a safe insertion range")
      return false
    }
    // A confirmed own write is the next stroke's anchor until a deliberate keyboard/focus
    // action clears it. Re-reading a temporarily stale range is not a new insertion position.
    if !pending,let anchor=continuationAnchor,!unresolvedWrites.contains(where:{$0.pid==pid}) {
      guard anchor.pid==pid,CFEqual(anchor.field,field),range.length==0,range.location==anchor.expectedCaret,
        anchor.expectedDigest != nil,fingerprint(field)==anchor.expectedDigest else {
        captureDiagnostics.stage="fieldRefused";recordTargetRefusal("verifiedContinuationChanged")
        showFeedback("Caret or field changed · waiting for a safe next word");return false
      }
    }
    guard permitsResolvedWrite(field,pid:pid,range:range) || (pending && permitsPendingCapture(field,pid:pid,range:range)) else {captureDiagnostics.stage="fieldRefused";recordTargetRefusal("unresolvedPreviousWrite");showFeedback("Waiting for the previous write to settle · no further text sent");return false}
    if let refusal=WordInsertion.boundaryRefusal(content,location:range.location,length:range.length) {
      captureDiagnostics.stage="fieldRefused";recordTargetRefusal(refusal == .partialWord ? "partialWord":"invalidRange")
      showFeedback("Use a word boundary or select a whole word · no text sent");return false
    }
    originalSelection = range
    originalContentDigest=Data(SHA256.hash(data:Data(content.utf8)))
    originalPID = pid
    target = field
    captureDiagnostics.targetAdmissions += 1
    return true
  }
  @objc func touchFrame(_ event: OpenMTEvent) {
    // Bridge dispatches callbacks to main before invoking this selector.
    if active {
      captureDiagnostics.callbacks += 1
      for touch in event.touches as? [OpenMTTouch] ?? [] {captureDiagnostics.states[String(touch.state.rawValue),default:0] += 1}
      let delay=(ProcessInfo.processInfo.systemUptime-event.receivedAt)*1000
      if delay.isFinite,delay>=0,delay<60_000 {captureDiagnostics.maximumCallbackDelayMilliseconds=max(captureDiagnostics.maximumCallbackDelayMilliseconds,delay)}
    }
    guard active,inputProtectionHealthy else {return}
    guard frameOrdering.accept(receivedAt:event.receivedAt,timestamp:event.timestamp,frame:event.frameID,deviceID:event.deviceID) else {captureDiagnostics.droppedFrames += 1;return}
    let all=event.touches as? [OpenMTTouch] ?? []
    let touches=all.filter {$0.state == .touching || $0.state == .making || $0.state == .starting}
    let wasWaiting=waitForLift
    contactGate.observe(activeContacts:touches.count)
    if touches.isEmpty {captureDiagnostics.idleFrames += 1} else {captureDiagnostics.contactFrames += 1}
    if wasWaiting {captureDiagnostics.gateWaitFrames += 1;return}
    if (finger != nil || deferredLift != nil) && !validTarget() {cancel("Field changed · next fresh swipe uses the current field");return}
    if deferredLift != nil {
      guard touches.count<=1 else {deferredLift=nil;liftTimerGeneration += 1;resetStrokeForRetry("Multiple fingers · lift, then swipe one word");return}
      if let touch=touches.first {
        let contact=GraceContact(id:touch.identifier,point:Point(Double(touch.posX),Double(touch.posY)),time:event.timestamp,state:touch.state)
        if handleGraceContact(contact) {return}
      } else if let release=deferredLift,release.candidate != nil {
        guard commitDeferredLift() else {return}
        for candidate in release.candidateSamples {consumeContact(candidate)}
      } else {return} // Empty/linger frames never extend the release deadline.
    }
    guard touches.count<=1 else {lastOwnedWord=nil;resetStrokeForRetry("Multiple fingers · lift, then swipe one word");return}
    if let tracked=finger {
      let terminal=all.first {$0.identifier==tracked && $0.state == .breaking}
      if terminal != nil || touches.isEmpty {
        liftSeen=true;captureDiagnostics.releaseFrames += 1;contactGate.noteLift()
        let end=terminal.map {Point(Double($0.posX),Double($0.posY))} ?? path.last
        if let end {appendSample(end,time:event.timestamp,phase:.ended,sourcePoint:end)}
        renderStroke();finger=nil // Retire BEFORE any own AX write, including mixed break/new-down frames.
        let cancellation=strokeCancellationGeneration
        if terminal != nil && touches.count==1 {
          // Distinct contacts already coexist in this callback: preserve a true word boundary.
          finishStroke()
        } else {deferLift(tracked)}
        guard active,strokeCancellationGeneration==cancellation else {return}
        if terminal != nil,touches.count==1 {waitForLift=false} // Old lift + new touchdown in the SAME frame.
      } else if touches.first?.identifier != tracked {
        lastOwnedWord=nil;resetStrokeForRetry("Contact changed · lift, then retry");return
      }
    }
    guard let touch=touches.first,!waitForLift else {return}
    consumeContact(GraceContact(id:touch.identifier,point:Point(Double(touch.posX),Double(touch.posY)),time:event.timestamp,state:touch.state))
  }
  func consumeContact(_ touch:GraceContact) {
    guard active,!waitForLift else {return}
    if finger==nil {
      lastOwnedWord=nil;lastSuggestion=nil;lastSwipeChoices=[];buttons.forEach {$0.isHidden=true}
      strokeFreshContact=contactGate.observedLift || touch.state == .starting || touch.state == .making
      guard strokeFreshContact else {waitForLift=true;label.stringValue="Lift resting finger, then swipe or tap";return}
      guard acquireTarget() else {waitForLift=true;return}
      statusReason=nil
      strokeActualContact=false
      finger=touch.id;path=[];strokeSamples=[];strokeCalibration=overlayFrame
      strokeToken += 1;bounceCount=0;missingSeconds=0
    }
    if touch.state == .making || touch.state == .touching {strokeActualContact=true;touchSeen=true}
    appendSample(touch.point,time:touch.time,phase:strokeSamples.isEmpty ? .began : .moved,sourcePoint:touch.point)
    captureDiagnostics.stage="swiping";if label.stringValue != "Swiping · lift to type" {label.stringValue="Swiping · lift to type"};renderStroke()
  }
  func deferLift(_ id:Int32) {
    guard liftGraceSeconds>0,strokeActualContact else {finishStroke();return}
    deferredLift=DeferredLift(id:id,hostTime:ProcessInfo.processInfo.systemUptime,token:strokeToken)
    liftTimerGeneration += 1;let generation=liftTimerGeneration
    captureDiagnostics.stage="releaseGrace";label.stringValue="Lift detected · finishing word"
    DispatchQueue.main.asyncAfter(deadline:.now()+liftGraceSeconds) {[weak self] in
      guard let self,self.active,self.liftTimerGeneration==generation else {return}
      let candidates=self.deferredLift?.candidateSamples ?? []
      guard self.commitDeferredLift() else {return}
      for candidate in candidates {self.consumeContact(candidate)}
    }
  }
  @discardableResult func commitDeferredLift() -> Bool {
    guard let release=deferredLift,release.token==strokeToken else {return false}
    let cancellation=strokeCancellationGeneration
    deferredLift=nil;liftTimerGeneration += 1;captureDiagnostics.graceCommits += 1
    finishStroke()
    // A cancellation retires buffered contacts too. It cannot authorize their
    // replay against the new field/caret or clear a held-contact lift gate.
    guard active,strokeCancellationGeneration==cancellation else {return false}
    waitForLift=false // The deferred release already proved the old contact lifted.
    return true
  }
  /// Returns true when the frame is owned by a tentative or accepted bounce.
  func handleGraceContact(_ contact:GraceContact)->Bool {
    guard var release=deferredLift else {return false}
    let now=ProcessInfo.processInfo.systemUptime
    let elapsed=(release.candidateHostTime ?? now)-release.hostTime
    guard LiftGrace.nearby(strokeSamples,point:release.candidate?.point ?? contact.point,elapsed:elapsed,idChanged:contact.id != release.id,bounces:bounceCount,missing:missingSeconds,grace:liftGraceSeconds) else {
      guard commitDeferredLift() else {return true}
      for point in release.candidateSamples {consumeContact(point)}
      return false
    }
    guard let first=release.candidate else {release.candidate=contact;release.candidateHostTime=now;release.candidateSamples=[contact];deferredLift=release;return true}
    guard first.id==contact.id else {deferredLift=nil;liftTimerGeneration += 1;resetStrokeForRetry("Contact changed · lift, then retry");return true}
    guard let continuation=LiftGrace.directionContinues(strokeSamples,first:first.point,next:contact.point) else {release.candidateSamples.append(contact);deferredLift=release;return true}
    guard continuation else {
      guard commitDeferredLift() else {return true}
      for point in release.candidateSamples {consumeContact(point)}
      return false
    }
    deferredLift=nil;liftTimerGeneration += 1;bounceCount += 1;missingSeconds += elapsed
    finger=contact.id;waitForLift=false;captureDiagnostics.graceRejoins += 1
    if first.state == .making || first.state == .touching || contact.state == .making || contact.state == .touching {strokeActualContact=true;touchSeen=true}
    for point in release.candidateSamples {appendSample(point.point,time:point.time,phase:.moved,sourcePoint:point.point)}
    appendSample(contact.point,time:contact.time,phase:.moved,sourcePoint:contact.point)
    captureDiagnostics.stage="swiping";renderStroke();return true
  }
  func finishStroke() {
    guard strokeToken>retiredToken else {return}
    retiredToken=strokeToken // One terminal/one write attempt, even on failure.
    let completed=strokeSamples
    guard active,validTarget() else {cancel("Focus changed · stroke cancelled");return}
    guard strokeActualContact else {rejectCompletedStroke("No contact · swipe or tap again");return}
    let singleLetter=Recognition.singleLetter(completed,freshContact:strokeFreshContact)
    guard singleLetter != nil || (path.count>=3 && path.first.map {first in path.contains(where:{first.distance($0)>0.06})} == true) else {
      rejectCompletedStroke("Swipe longer words, or tap A/I");return
    }
    lastCompletedSamples=completed
    let ranking=singleLetter==nil ? gestureLexicon.rank(completed):[]
    captureDiagnostics.recognitionRankedCount=ranking.count
    captureDiagnostics.recognitionTopGeometry=ranking.first?.geometryScore
    captureDiagnostics.recognitionMargin=ranking.count>1 ? ranking[1].score-ranking[0].score:nil
    let accepted=singleLetter != nil || StrokeDecoder.accepts(ranking)
    let reason=ranking.isEmpty ? "emptyRanking":(ranking[0].geometryScore>=StrokeDecoder.maximumAcceptedScore ? "shapeDistance":"candidateMargin")
    captureDiagnostics.recognitionReason=accepted ? "accepted":reason
    let choices=singleLetter.map {[$0]} ?? ranking.map(\.word)
    lastSwipeChoices=choices
    let candidates=accepted ? choices:[]
    captureDiagnostics.candidates=candidates.count
    guard let top=candidates.first else {
      if let target,let range=originalSelection,let digest=originalContentDigest,!choices.isEmpty {lastSuggestion=UninsertedSuggestion(field:target,pid:originalPID,range:range,digest:digest,choices:choices)}
      rejectCompletedStroke(choices.isEmpty ? "No matching path · swipe across the letter keys again":"Uncertain: "+choices.prefix(3).joined(separator:" / ")+" · not typed. Swipe again, or Escape → Last Swipe Suggestions.",reason:reason);return
    }
    lastSuggestion=nil
    showFeedback("Recognized: "+top+" · inserting",kind:"recognized")
    captureDiagnostics.recognizedWords += 1
    if pending || !queuedWords.isEmpty {
      guard let target,queuedWords.count<8 else {rejectCompletedStroke("Waiting for earlier text · queue full");return}
      queuedWords.append(QueuedWord(word:top,alternatives:candidates,field:target,pid:originalPID))
      captureDiagnostics.pendingWords=queuedWords.count+(pending ? 1:0)
      prepareNextStroke(preserveTrail:true);drainQueuedWords();return
    }
    let cancellation=strokeCancellationGeneration
    guard insertWord(top,alternatives:candidates) else {
      if pending,active,strokeCancellationGeneration==cancellation {
        prepareNextStroke(preserveTrail:true);showFeedback("Candidate: "+top+" · waiting for field confirmation. Nothing retried; next words queue safely",kind:"writePending")
      }
      return
    }
    prepareNextStroke(preserveTrail:true)
    for (i,button) in buttons.enumerated() {
      button.isHidden=true
      if i<candidates.count {button.title=candidates[i];button.contentTintColor=i==0 ? .controlAccentColor : .labelColor
        button.setAccessibilityLabel("Correct last word to "+candidates[i]);button.setAccessibilityHelp("Optional replacement of the last owned word. Stop capture, then choose Correct Last Word from the menu.")}
    }
    showFeedback("Typed: "+top+" · swipe next",kind:"inserted")
  }
  func rejectCompletedStroke(_ message:String,reason:String="strokeIncomplete") {
    captureDiagnostics.rejectedWords += 1
    captureDiagnostics.recognitionReason=reason
    captureDiagnostics.rejectionReasons[reason,default:0] += 1
    prepareNextStroke(preserveTrail:true);showFeedback(message,kind:"strokeRejected")
    // Earlier accepted gestures must not wait for a later successful word.
    drainQueuedWords()
  }
  func pauseForInputProtectionFailure() {
    captureDiagnostics.inputProtectionFailures += 1
    inputProtectionHealthy=false
    cancel("OFF")
    showFeedback("Mouse protection unavailable · typing stopped; pointer released")
    captureDiagnostics.stage="inputProtectionPaused"
    captureDiagnostics.result="mouseProtectionUnavailable"
  }
  func samplePoint(_ touch:OpenMTTouch) -> (normalized:Point,native:Point)? {
    // Both presentations consume the same immutable normalized physical contact.
    // Neither current OS cursor position nor pointer acceleration contributes.
    let point=Point(Double(touch.posX),Double(touch.posY));return (point,point)
  }
  func appendSample(_ point:Point,time:Double,phase:ContactPhase,sourcePoint:Point? = nil) {
    guard strokeSamples.count<4096 else {cancel("Stroke too long; cancelled");return}
    strokeSamples.append(StrokeSample(point,time:time,phase:phase,source:strokeSource,sourcePoint:sourcePoint))
    captureDiagnostics.samples=strokeSamples.count
    path.append(point) // Identical contacts and recognition for both guide presentations.
  }
  func renderStroke() {
    keyboard.path=path;keyboard.needsDisplay=true
    overlayKeyboard.path=strokeSamples.map(\.point);overlayKeyboard.needsDisplay=true
  }
  func prepareNextStroke(preserveTrail:Bool=false) {
    deferredLift=nil;liftTimerGeneration += 1;bounceCount=0;missingSeconds=0
    if !pending && queuedWords.isEmpty {target=nil;originalSelection=nil;originalContentDigest=nil}
    strokeFreshContact=false;strokeActualContact=false;contactGate.rearm();path=[];strokeSamples=[];finger=nil;strokeCalibration=nil
    captureDiagnostics.samples=0;captureDiagnostics.candidates=0;captureDiagnostics.stage="ready"
    buttons.forEach {$0.isHidden=true};if !preserveTrail {renderStroke()}
  }
  func resetStrokeForRetry(_ message:String) {
    captureDiagnostics.resetReasons[message.hasPrefix("Multiple fingers") ? "multipleContacts":"contactChanged",default:0] += 1
    prepareNextStroke();label.stringValue=message
  }
  func sameTargetIdentity() -> Bool {
    guard !secureInputActive,let target,let pid=currentApplicationPID,
      let current=focused(pid) else {return false}
    return FocusGuard.permits(originalPID:originalPID,currentPID:pid,sameElement:CFEqual(target,current),secure:secureInputActive,editable:supportedField(current))
  }
  func fingerprint(_ field:AXUIElement)->Data? {
    guard supportedField(field),let text=fieldText(field) else {return nil}
    return Data(SHA256.hash(data:Data(text.utf8))) // Memory only; neither field text nor digest is logged.
  }
  func identity(_ field:AXUIElement,pid:pid_t)->Bool {
    guard (!active || inputProtectionHealthy),!secureInputActive,let currentPID=currentApplicationPID,let current=focused(currentPID) else {return false}
    return FocusGuard.permits(originalPID:pid,currentPID:currentPID,sameElement:CFEqual(field,current),secure:secureInputActive,editable:supportedField(current))
  }
  func permitsPendingCapture(_ field:AXUIElement,pid:pid_t,range:CFRange)->Bool {
    guard let id=pendingWriteID,let write=unresolvedWrites.first(where:{$0.id==id}),write.pid==pid,CFEqual(write.field,field),let digest=fingerprint(field) else {return false}
    let oldRange=range.location==write.originalRange.location && range.length==write.originalRange.length
    let newRange=range.location==write.expectedCaret && range.length==0
    return (oldRange && (digest==write.beforeDigest || matchesReceipt(write,digest))) || (newRange && matchesReceipt(write,digest))
  }
  func drainQueuedWords() {
    guard active,!pending,finger==nil,!queuedWords.isEmpty,let anchor=continuationAnchor else {return}
    let item=queuedWords[0]
    guard item.pid==anchor.pid,CFEqual(item.field,anchor.field),identity(item.field,pid:item.pid),let caret=selection(item.field),caret.length==0,caret.location==anchor.expectedCaret,anchor.expectedDigest != nil,fingerprint(item.field)==anchor.expectedDigest else {cancel("Field changed · queued words discarded");return}
    queuedWords.removeFirst();captureDiagnostics.pendingWords=queuedWords.count
    target=item.field;originalPID=item.pid;originalSelection=caret;originalContentDigest=anchor.expectedDigest
    if insertWord(item.word,alternatives:item.alternatives) {drainQueuedWords()}
  }
  func matchesReceipt(_ write:UnresolvedWrite,_ digest:Data?)->Bool {
    guard let digest else {return false}
    return digest==write.expectedDigest || (write.separatorDigest != nil && digest==write.separatorDigest) || write.receiptDigests.contains(digest)
  }
  func permitsResolvedWrite(_ field:AXUIElement,pid:pid_t,range:CFRange,resolvePending:Bool=false)->Bool {
    guard !trackingBlocks(pid) else {return false}
    let sameProcess=unresolvedWrites.filter {$0.pid==pid}
    guard !sameProcess.isEmpty else {return true}
    // A rebuilt AX reference or sibling field cannot make an uncertain mutation disappear.
    guard sameProcess.allSatisfy({CFEqual($0.field,field)}) else {
      recordTargetRefusal("unresolvedOriginalField");return false
    }
    let matching=sameProcess
    if !resolvePending,let id=pendingWriteID,matching.contains(where:{$0.id==id}) {return false}
    guard matching.allSatisfy({write in
      range.length==0 && range.location==write.expectedCaret && matchesReceipt(write,fingerprint(field))
    }) else {return false}
    if let last=matching.last {
      // Anchor the exact observed bytes, including a provider-normalized NEW separator.
      let confirmed=UnresolvedWrite(id:last.id,field:last.field,pid:last.pid,originalRange:last.originalRange,beforeDigest:last.beforeDigest,expectedCaret:last.expectedCaret,expectedDigest:fingerprint(field),trimmedSeparator:last.trimmedSeparator,generatedTrailingSeparator:last.generatedTrailingSeparator && !last.trimmedSeparator,originalBundleIdentifier:last.originalBundleIdentifier)
      continuationAnchor=confirmed
    }
    let ids=Set(matching.map(\.id));unresolvedWrites.removeAll {ids.contains($0.id)}
    if !persistWriteTracking() {writeTrackingReadable=false}
    return true
  }
  static func textEvents(_ text:String)->(CGEvent,CGEvent)? {
    guard !text.isEmpty,let down=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:true),
      let up=CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:false) else {return nil}
    let units=Array(text.utf16)
    units.withUnsafeBufferPointer {buffer in
      down.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
      up.keyboardSetUnicodeString(stringLength:buffer.count,unicodeString:buffer.baseAddress)
    }
    for event in [down,up] {event.flags=[];event.setIntegerValueField(.eventSourceUserData,value:Self.ownTextEventTag)}
    return (down,up)
  }
  func postText(_ events:(CGEvent,CGEvent),to pid:pid_t) {
    events.0.postToPid(pid);events.1.postToPid(pid)
  }
  func replaceSelectedText(_ field:AXUIElement,pid:pid_t,range:CFRange,inserted:String,expectedBefore:String?=nil)->AXError {
    guard runtimeSignatureValid else {stopForChangedBuild();return .cannotComplete}
    guard identity(field,pid:pid),let current=selection(field),current.location==range.location,current.length==range.length,
      permitsResolvedWrite(field,pid:pid,range:range) else {return .cannotComplete}
    let evidence=textEvidence(field)
    guard let before=evidence?.text,expectedBefore.map({$0==before}) ?? true,
      let expected=TextReplacement.replacing(before,location:range.location,length:range.length,with:inserted) else {return .cannotComplete}
    let valueBackend=attributeWritable(field,kAXValueAttribute) && attributeWritable(field,kAXSelectedTextRangeAttribute)
    let directBackend=attributeWritable(field,kAXSelectedTextAttribute)
    let keyboardBackend = insertionTransport == .keyboard
    // Prefer the focused selection's insertion API. Replacing the complete AXValue
    // can bypass a controlled editor's input handling and write its accessible
    // representation back as document text. Choose once; never switch after mutation.
    let useValueBackend=valueBackend && !directBackend
    // A whole-value rewrite publishes AXValue as document text. Refuse when that value is only a
    // placeholder-equal hint that no character count verified (see FieldText.Evidence).
    guard !(useValueBackend && !keyboardBackend && evidence?.placeholderAmbiguous == true) else {return .cannotComplete}
    guard (keyboardBackend ? canPostText : (valueBackend || directBackend)),identity(field,pid:pid),let checked=selection(field),checked.location==range.location,checked.length==range.length,
      fieldText(field)==before else {return .cannotComplete}
    // Allocate before recording a transaction; never retry AX after posting an event.
    let events: (CGEvent,CGEvent)?
    if keyboardBackend {
      guard let prepared=Self.textEvents(inserted) else {return .cannotComplete}
      events=prepared
    } else {events=nil}
    guard identity(field,pid:pid),let finalRange=selection(field),finalRange.location==range.location,finalRange.length==range.length,fieldText(field)==before else {return .cannotComplete}
    // WebKit reflows an OWN trailing NBSP to ordinary space as the next word arrives.
    // Permit that one boundary only with the exact confirmed previous app/field/caret
    // and whole-value anchor. No provenance means no preceding-space alternate.
    let previousOwn=continuationAnchor.map {$0.pid==pid && CFEqual($0.field,field) && $0.expectedCaret==range.location && $0.generatedTrailingSeparator && !$0.trimmedSeparator && $0.expectedDigest==Data(SHA256.hash(data:Data(before.utf8)))} ?? false
    guard let receipts=WordReceipts.values(before:before,location:range.location,length:range.length,inserted:inserted,previousOwnSeparator:previousOwn) else {return .cannotComplete}
    var write=UnresolvedWrite(id:UUID(),field:field,pid:pid,originalRange:range,beforeDigest:Data(SHA256.hash(data:Data(before.utf8))),expectedCaret:range.location+inserted.utf16.count,expectedDigest:Data(SHA256.hash(data:Data(expected.utf8))),separatorDigest:receipts.freshNBSP.map {Data(SHA256.hash(data:Data($0.utf8)))},trimmedDigest:(inserted.hasSuffix(" ") && range.location+inserted.utf16.count==expected.utf16.count) ? Data(SHA256.hash(data:Data(expected.dropLast().utf8))):nil,deferredCaret:!keyboardBackend && useValueBackend,receiptDigests:receipts.all.map {Data(SHA256.hash(data:Data($0.utf8)))},generatedTrailingSeparator:inserted.hasSuffix(" "))
    write.evidence=MutationEvidence(before:before,range:range,inserted:inserted)
    write.originalBundleIdentifier=NSRunningApplication(processIdentifier:pid)?.bundleIdentifier
    unresolvedWrites.append(write) // BEFORE mutation: even an error may follow accepted AXValue.
    guard persistWriteTracking() else {unresolvedWrites.removeAll {$0.id==write.id};writeTrackingReadable=false;return .cannotComplete}
    captureDiagnostics.writeAttempts += 1
    captureDiagnostics.writeBeforeUTF16Length=before.utf16.count;captureDiagnostics.writeExpectedUTF16Length=expected.utf16.count
    captureDiagnostics.writeInsertedUTF16Length=inserted.utf16.count
    captureDiagnostics.writeBeforeEvidenceSource=captureDiagnostics.textEvidenceSource
    captureDiagnostics.writeBeforeValueMatchesRange=captureDiagnostics.textEvidenceValueMatchesRange
    captureDiagnostics.writeBeforeMatchesPlaceholder=captureDiagnostics.textEvidenceMatchesPlaceholder
    captureDiagnostics.confirmationObservedUTF16Length=nil;captureDiagnostics.confirmationInsertedSpanMatches=nil
    captureDiagnostics.confirmationPrefixMatches=nil;captureDiagnostics.confirmationSuffixMatches=nil;captureDiagnostics.confirmationEvidenceKind=nil
    captureDiagnostics.lastInsertionBackend=keyboardBackend ? "targetedKeyboard":(useValueBackend ? "valueAndCaret":"selectedText")
    let result:AXError
    if let events {
      postText(events,to:pid)
      // Posting has no delivery receipt. Existing exact content/caret polling is mandatory.
      result = .success
    } else if useValueBackend {
      // Used only when selected-text insertion is unavailable. Setter success is
      // still not delivery evidence; never retry through another backend.
      result=setAttribute(field,kAXValueAttribute,expected as CFString)
    } else {
      result=setAttribute(field,kAXSelectedTextAttribute,inserted as CFString)
    }
    captureDiagnostics.lastAXError=Int(result.rawValue)
    guard result == .success else {return result}
    if !keyboardBackend {
      captureDiagnostics.acceptedMutations += 1
      write.mutationAccepted=true
      if let index=unresolvedWrites.firstIndex(where:{$0.id==write.id}) {unresolvedWrites[index]=write}
      if !persistWriteTracking() {writeTrackingReadable=false}
    }
    if !keyboardBackend && useValueBackend {return settleDeferredCaret(write.id)}
    return result
  }
  // A provider may acknowledge AXValue before publishing the changed value.
  // Wait for this transaction's exact content; never repost text, and attempt its caret only once.
  func settleDeferredCaret(_ id:UUID)->AXError {
    guard let index=unresolvedWrites.firstIndex(where:{$0.id==id}) else {return .cannotComplete}
    var write=unresolvedWrites[index]
    guard write.deferredCaret,write.mutationAccepted,identity(write.field,pid:write.pid),
      let selected=selection(write.field),let observed=fingerprint(write.field),
      (selected.location==write.originalRange.location && selected.length==write.originalRange.length) ||
      (selected.location==write.expectedCaret && selected.length==0) else {return .cannotComplete}
    if !matchesReceipt(write,observed) {
      guard let trimmed=write.trimmedDigest,observed==trimmed else {return .cannotComplete}
      write=UnresolvedWrite(id:write.id,field:write.field,pid:write.pid,originalRange:write.originalRange,beforeDigest:write.beforeDigest,expectedCaret:write.expectedCaret-1,expectedDigest:observed,trimmedSeparator:true,deferredCaret:true,mutationAccepted:true,originalBundleIdentifier:write.originalBundleIdentifier)
    }
    // Retire the caret attempt before calling AX, including errors or delayed acknowledgements.
    write.deferredCaret=false;unresolvedWrites[index]=write
    guard persistWriteTracking() else {writeTrackingReadable=false;return .cannotComplete}
    var caret=CFRange(location:write.expectedCaret,length:0)
    guard let value=AXValueCreate(.cfRange,&caret) else {return .cannotComplete}
    let result=setAttribute(write.field,kAXSelectedTextRangeAttribute,value)
    captureDiagnostics.lastAXError=Int(result.rawValue)
    return result
  }
  func insertWord(_ word:String,alternatives:[String])->Bool {
    guard active,validTarget(),let target,let original=originalSelection else {cancel("Focus or caret changed · no word inserted");return false}
    guard let before=fieldText(target),
      originalContentDigest==Data(SHA256.hash(data:Data(before.utf8))) else {cancel("Content changed during swipe · no word inserted");return false}
    guard let plan=try? WordInsertion.plan(before,location:original.location,length:original.length,word:word).get() else {cancel("Use a word boundary or select a whole word · no word inserted");return false}
    let inserted=plan.text
    let priorIDs=Set(unresolvedWrites.map(\.id))
    let result=replaceSelectedText(target,pid:originalPID,range:original,inserted:inserted,expectedBefore:before)
    let newWrite=unresolvedWrites.last(where:{!priorIDs.contains($0.id) && $0.pid==originalPID && CFEqual($0.field,target)})
    lastInsertionSucceeded=result == .success
    guard result == .success else {
      if let write=newWrite {beginCaretWait(write,original:original,inserted:inserted,alternatives:alternatives)} else {cancel("Insertion refused · no text retry")}
      return false
    }
    if confirmOwnCaret(target,pid:originalPID,original:original,inserted:inserted,alternatives:alternatives) {return true}
    if let write=newWrite {beginCaretWait(write,original:original,inserted:inserted,alternatives:alternatives)}
    return false
  }
  // Total settle budget is the initial 250ms plus this bounded slow wait.
  static let acceptedWriteSettleSeconds=2.0
  func beginCaretWait(_ write:UnresolvedWrite,original:CFRange,inserted:String,alternatives:[String]) {
    pending=true;pendingWriteID=write.id
    captureDiagnostics.pendingWords=queuedWords.count+1;captureDiagnostics.stage="confirmingAcceptedWrite"
    pollOwnCaret(writeID:write.id,pid:write.pid,original:original,inserted:inserted,alternatives:alternatives,generation:sessionGeneration,deadline:ProcessInfo.processInfo.systemUptime+0.25)
  }
  func pollOwnCaret(writeID:UUID,pid:pid_t,original:CFRange,inserted:String,alternatives:[String],generation:Int,deadline:Double) {
    guard active,pending,sessionGeneration==generation,pendingWriteID==writeID,
      let write=unresolvedWrites.first(where:{$0.id==writeID}) else {return}
    let field=write.field
    captureDiagnostics.confirmationIdentityMatches=identity(field,pid:pid)
    guard captureDiagnostics.confirmationIdentityMatches == true else {cancel("Field changed during caret verification");return}
    if write.deferredCaret {_ = settleDeferredCaret(writeID)}
    if confirmOwnCaret(field,pid:pid,original:original,inserted:inserted,alternatives:alternatives) {
      pending=false;pendingWriteID=nil;captureDiagnostics.pendingWords=queuedWords.count
      // A new physical stroke may already be in progress; preserve its samples.
      if finger==nil {prepareNextStroke(preserveTrail:true)}
      drainQueuedWords();return
    }
    let now=ProcessInfo.processInfo.systemUptime
    captureDiagnostics.confirmationWaitMilliseconds=max(0,(now-(deadline-0.25))*1000)
    if now>=deadline+Self.acceptedWriteSettleSeconds {
      // Unsent queued words drop; uncertain mutation evidence must survive.
      cancel("OFF")
      captureDiagnostics.stage="acceptedWriteUnresolved";captureDiagnostics.result="Write unresolved · capture stopped; record retained"
      showFeedback("Last word not confirmed · check the field; nothing was retried")
      if NSApp != nil {showActivationRefusal("Last word not confirmed · check the field; nothing was retried")}
      return
    }
    let slow=ProcessInfo.processInfo.systemUptime>=deadline
    if slow {captureDiagnostics.stage="waitingForAcceptedWrite";captureDiagnostics.result="Write unresolved · further delivery held safely"}
    DispatchQueue.main.asyncAfter(deadline:.now()+(slow ? 0.1:0.02)) {[weak self] in
      self?.pollOwnCaret(writeID:writeID,pid:pid,original:original,inserted:inserted,alternatives:alternatives,generation:generation,deadline:deadline)
    }
  }
  func confirmOwnCaret(_ field:AXUIElement,pid:pid_t,original:CFRange,inserted:String,alternatives:[String])->Bool {
    let observed=selection(field)
    let transaction=unresolvedWrites.last(where:{$0.pid==pid && CFEqual($0.field,field)})
    let expectedCaret=transaction?.expectedCaret ?? original.location+inserted.utf16.count
    captureDiagnostics.expectedCaret=expectedCaret
    captureDiagnostics.observedCaretLocation=observed?.location;captureDiagnostics.observedCaretLength=observed?.length
    let sameTarget=identity(field,pid:pid)
    captureDiagnostics.confirmationIdentityMatches=sameTarget
    captureDiagnostics.confirmationCaretMatches=observed.map {InsertionContinuation.permits(originalLocation:original.location,insertedUTF16Count:expectedCaret-original.location,resultLocation:$0.location,resultLength:$0.length,sameTarget:sameTarget)} ?? false
    if let write=unresolvedWrites.last(where:{$0.pid==pid && CFEqual($0.field,field)}) {
      let text=sameTarget && supportedField(field) ? fieldText(field):nil
      let digest=text.map {Data(SHA256.hash(data:Data($0.utf8)))}
      captureDiagnostics.confirmationContentMatches=matchesReceipt(write,digest)
      captureDiagnostics.confirmationBeforeContentMatches=digest != nil && write.beforeDigest != nil && digest==write.beforeDigest
      captureDiagnostics.confirmationObservedUTF16Length=text?.utf16.count
      if let text,let evidence=write.evidence {
        let comparison=evidence.compare(text,location:write.originalRange.location)
        captureDiagnostics.confirmationInsertedSpanMatches=comparison.inserted
        captureDiagnostics.confirmationPrefixMatches=comparison.prefix;captureDiagnostics.confirmationSuffixMatches=comparison.suffix
        captureDiagnostics.confirmationEvidenceKind=captureDiagnostics.confirmationContentMatches==true ? "fullReceipt":
          (captureDiagnostics.confirmationBeforeContentMatches==true ? "unchangedContent":
          (comparison.inserted && (!comparison.prefix || !comparison.suffix) ? "surroundingTextChanged":
          (comparison.prefix && comparison.suffix && !comparison.inserted ? "insertedTextChanged":
          (text.utf16.count != evidence.expectedLength ? "lengthChanged":"contentChanged"))))
      } else {captureDiagnostics.confirmationEvidenceKind=sameTarget ? "contentUnavailable":"identityChanged"}
    }
    guard sameTarget,let next=observed,captureDiagnostics.confirmationCaretMatches == true,
      permitsResolvedWrite(field,pid:pid,range:next,resolvePending:true) else {return false}
    originalSelection=next;originalContentDigest=continuationAnchor?.expectedDigest
    captureDiagnostics.insertions += 1;captureDiagnostics.result="Insertion request accepted; caret confirmed"
    if let digest=fingerprint(field) {lastOwnedWord=OwnedWord(field:field,pid:pid,range:CFRange(location:original.location,length:expectedCaret-original.location),alternatives:alternatives,fingerprint:digest,leadingSeparator:inserted.hasPrefix(" "),trailingSeparator:inserted.hasSuffix(" ") && transaction?.trimmedSeparator != true)}
    updateModeIndicator();return true
  }
  func restoreCorrectionCaret(_ owned:OwnedWord,selectedRange:CFRange) {
    guard !unresolvedWrites.contains(where:{$0.pid==owned.pid}),identity(owned.field,pid:owned.pid),fingerprint(owned.field)==owned.fingerprint,
      let selected=selection(owned.field),selected.location==selectedRange.location,selected.length==selectedRange.length else {return}
    var restored=CFRange(location:owned.range.location+owned.range.length,length:0)
    if let value=AXValueCreate(.cfRange,&restored) {_=setAttribute(owned.field,kAXSelectedTextRangeAttribute,value)}
  }
  @objc func selectCandidate(_ sender:NSButton) {
    guard !active else {return}
    if lastSuggestion != nil {
      guard !sender.isHidden else {showFeedback("Suggestion unavailable · choose a visible candidate",kind:"suggestionRefused");return}
      insertSuggestion(sender.title);return
    }
    guard runtimeSignatureValid else {stopForChangedBuild();return}
    guard !sender.isHidden else {rejectCorrection("candidateHidden");return}
    guard let owned=lastOwnedWord else {rejectCorrection("ownershipUnavailable");return}
    guard !unresolvedWrites.contains(where:{$0.pid==owned.pid}) else {rejectCorrection("unresolvedPreviousWrite");return}
    guard owned.alternatives.contains(sender.title) else {rejectCorrection("candidateUnavailable");return}
    guard finger==nil else {rejectCorrection("contactStillActive");return}
    guard identity(owned.field,pid:owned.pid) else {rejectCorrection("targetIdentityChanged");return}
    guard let caret=selection(owned.field) else {rejectCorrection("caretUnavailable");return}
    guard caret.location==owned.range.location+owned.range.length,caret.length==0 else {rejectCorrection("caretChanged");return}
    guard fingerprint(owned.field)==owned.fingerprint else {rejectCorrection("contentChanged");return}
    var range=owned.range
    guard let value=AXValueCreate(.cfRange,&range),setAttribute(owned.field,kAXSelectedTextRangeAttribute,value) == .success,
      identity(owned.field,pid:owned.pid),let selected=selection(owned.field),selected.location==range.location,selected.length==range.length,
      fingerprint(owned.field)==owned.fingerprint else {restoreCorrectionCaret(owned,selectedRange:range);lastOwnedWord=nil;cancel("Correction stopped · field changed");return}
    guard let correctionBefore=fieldText(owned.field),
      Data(SHA256.hash(data:Data(correctionBefore.utf8)))==owned.fingerprint else {restoreCorrectionCaret(owned,selectedRange:range);rejectCorrection("contentChanged");return}
    let inserted=(owned.leadingSeparator ? " ":"")+sender.title+(owned.trailingSeparator ? " ":"")
    let previousIDs=Set(unresolvedWrites.map(\.id))
    _=replaceSelectedText(owned.field,pid:owned.pid,range:range,inserted:inserted,expectedBefore:correctionBefore)
    let transaction=unresolvedWrites.last(where:{!previousIDs.contains($0.id) && $0.pid==owned.pid && CFEqual($0.field,owned.field)})
    guard let transaction else {
      restoreCorrectionCaret(owned,selectedRange:range)
      captureDiagnostics.correctionResult="prewriteRefused";lastOwnedWord=nil
      cancel("Correction stopped · no text sent");return
    }
    // Input dispatch is asynchronous. A successful acknowledgement or an AX error
    // is never a reason to resend; wait only for this transaction's exact receipt.
    if confirmCorrection(owned,transaction:transaction) {return}
    correctionPollToken += 1
    pollCorrection(owned,writeID:transaction.id,token:correctionPollToken,deadline:ProcessInfo.processInfo.systemUptime+0.25+Self.acceptedWriteSettleSeconds)
  }
  func confirmCorrection(_ owned:OwnedWord,transaction:UnresolvedWrite)->Bool {
    guard identity(owned.field,pid:owned.pid),let next=selection(owned.field),
      InsertionContinuation.permits(originalLocation:transaction.originalRange.location,insertedUTF16Count:transaction.expectedCaret-transaction.originalRange.location,resultLocation:next.location,resultLength:next.length,sameTarget:true),permitsResolvedWrite(owned.field,pid:owned.pid,range:next,resolvePending:true) else {return false}
    let range=transaction.originalRange
    if let digest=fingerprint(owned.field) {lastOwnedWord=OwnedWord(field:owned.field,pid:owned.pid,range:CFRange(location:range.location,length:transaction.expectedCaret-range.location),alternatives:owned.alternatives,fingerprint:digest,leadingSeparator:owned.leadingSeparator,trailingSeparator:owned.trailingSeparator)} else {lastOwnedWord=nil}
    captureDiagnostics.correctionResult="confirmed"
    if suggestionWriteID==transaction.id {suggestionWriteID=nil;showFeedback("Suggestion typed · double-Command to continue",kind:"suggestionInserted")}
    else {label.stringValue=active ? "Last word corrected · swipe next" : "Last word corrected"}
    if !active {panel?.orderOut(nil)}
    return true
  }
  func pollCorrection(_ owned:OwnedWord,writeID:UUID,token:Int,deadline:Double) {
    guard !active,token==correctionPollToken,let transaction=unresolvedWrites.first(where:{$0.id==writeID}) else {return}
    guard runtimeSignatureValid,identity(owned.field,pid:owned.pid) else {
      lastOwnedWord=nil;captureDiagnostics.correctionResult="postwriteUnconfirmed"
      cancel("Correction stopped · check receiving field");return
    }
    if transaction.deferredCaret {_=settleDeferredCaret(writeID)}
    if confirmCorrection(owned,transaction:transaction) {return}
    guard ProcessInfo.processInfo.systemUptime<deadline else {
      lastOwnedWord=nil;captureDiagnostics.correctionResult="postwriteUnconfirmed"
      cancel("Correction not confirmed · nothing retried");return
    }
    captureDiagnostics.correctionResult="awaitingReceipt"
    DispatchQueue.main.asyncAfter(deadline:.now()+0.02) {[weak self] in self?.pollCorrection(owned,writeID:writeID,token:token,deadline:deadline)}
  }
  func rejectCorrection(_ reason:String) {captureDiagnostics.correctionResult=reason;lastOwnedWord=nil;cancel("Correction unavailable · "+reason)}
  @objc func stopOrDismiss() {if !active {lastOwnedWord=nil;panel?.orderOut(nil)}}
  @objc func retry() {} // Fresh contact retries; clicking never toggles capture.
  func applyGuideVisibility() {
    let show=UserDefaults.standard.bool(forKey:"showGuide")
    keyboard.isHidden=strokeSource == .screenOverlay || !show
    guideKeyboardHeight?.constant=strokeSource == .trackpad && show ? 210 : 0
    panel?.setContentSize(NSSize(width:600,height:strokeSource == .trackpad && show ? 360 : 145))
    if strokeSource == .screenOverlay,active,show {overlayPanel?.orderFrontRegardless()} else {overlayPanel?.orderOut(nil)}
  }
  @objc func dismissFeedback() {feedbackPanel?.orderOut(nil)}
  func showActivationRefusal(_ reason:String) {
    // Only an explicit activation refusal calls this. It cannot take focus or
    // intercept a click, and it disappears without requiring dismissal.
    guard !active else {return}
    showFeedbackHUD(reason)
  }
  func showFeedbackHUD(_ reason:String) {
    guard feedbackWindowsEnabled,NSApp != nil else {return}
    feedbackGeneration += 1
    let generation=feedbackGeneration
    let notice=feedbackPanel ?? GuidePanel(contentRect:NSRect(x:0,y:0,width:420,height:76),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    notice.isReleasedWhenClosed=false;notice.level = .floating
    notice.hidesOnDeactivate=false;notice.ignoresMouseEvents=true
    notice.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient,.ignoresCycle]
    let surface=NSVisualEffectView(frame:NSRect(x:0,y:0,width:420,height:76))
    surface.material = .hudWindow;surface.blendingMode = .behindWindow;surface.state = .active
    surface.wantsLayer=true;surface.layer?.cornerRadius=12
    let message=NSTextField(wrappingLabelWithString:reason)
    message.frame=NSRect(x:18,y:12,width:384,height:52);message.font = .systemFont(ofSize:13,weight:.medium)
    surface.addSubview(message);notice.contentView=surface;feedbackPanel=notice
    if let screen=NSScreen.main {let frame=screen.visibleFrame;notice.setFrameOrigin(NSPoint(x:frame.midX-210,y:frame.minY+48))}
    notice.orderFrontRegardless()
    Timer.scheduledTimer(withTimeInterval:4,repeats:false) {[weak self] _ in
      MainActor.assumeIsolated {guard let self,self.feedbackGeneration==generation else {return};self.feedbackPanel?.orderOut(nil)}
    }
  }
  func showFeedback(_ reason:String,kind:String="status") {
    captureDiagnostics.feedbackCount=(captureDiagnostics.feedbackCount ?? 0)+1
    captureDiagnostics.feedbackKind=kind
    statusReason=reason
    if active {label.stringValue=reason} else {feedbackPanel?.orderOut(nil);panel?.orderOut(nil);overlayPanel?.orderOut(nil)}
    // Feedback is nonactivating and click-through; it never requires dismissal.
    updateModeIndicator()
    if NSApp != nil {showFeedbackHUD(reason)}
  }
  @objc func showSwipeSuggestions() {
    guard !active,let suggestion=lastSuggestion else {showFeedback("No uninserted suggestion · swipe first");return}
    for (i,b) in buttons.enumerated() {b.isHidden=i>=suggestion.choices.count;if i<suggestion.choices.count {b.title=suggestion.choices[i]}}
    keyboard.isHidden=true;guideKeyboardHeight?.constant=0;panel?.setContentSize(NSSize(width:600,height:145))
    label.stringValue="Choose a suggestion · insertion requires the original field and unchanged caret"
    panel?.orderFrontRegardless()
  }
  func insertSuggestion(_ word:String) {
    guard !active,let s=lastSuggestion else {return}
    lastSuggestion=nil // Retire BEFORE any attempt; never replay after a repeated click.
    guard s.choices.contains(word),runtimeSignatureValid,!trackingBlocks(s.pid),identity(s.field,pid:s.pid),let current=selection(s.field),current.location==s.range.location,current.length==s.range.length,
      let before=fieldText(s.field),Data(SHA256.hash(data:Data(before.utf8)))==s.digest,
      let plan=try? WordInsertion.plan(before,location:s.range.location,length:s.range.length,word:word).get() else {showFeedback("Suggestion not sent · original field or caret changed",kind:"suggestionRefused");return}
    let previous=Set(unresolvedWrites.map(\.id))
    _=replaceSelectedText(s.field,pid:s.pid,range:s.range,inserted:plan.text,expectedBefore:before)
    guard let transaction=unresolvedWrites.last(where:{!previous.contains($0.id)}) else {showFeedback("Suggestion not sent · write refused",kind:"suggestionRefused");return}
    suggestionWriteID=transaction.id
    let owned=OwnedWord(field:s.field,pid:s.pid,range:s.range,alternatives:s.choices,fingerprint:s.digest,leadingSeparator:plan.leadingSeparator,trailingSeparator:plan.trailingSeparator)
    if confirmCorrection(owned,transaction:transaction) {return}
    showFeedback("Suggestion write unconfirmed · check the field; nothing retried",kind:"writeUnconfirmed")
    correctionPollToken += 1;pollCorrection(owned,writeID:transaction.id,token:correctionPollToken,deadline:ProcessInfo.processInfo.systemUptime+0.25+Self.acceptedWriteSettleSeconds)
  }
  @objc func showLastCorrection() {
    guard !active else {return}
    guard !active,let owned=lastOwnedWord,identity(owned.field,pid:owned.pid),
      let caret=selection(owned.field),caret.location==owned.range.location+owned.range.length,caret.length==0,
      fingerprint(owned.field)==owned.fingerprint else {lastOwnedWord=nil;showFeedback("Last-word correction unavailable · field or caret changed");return}
    for (i,button) in buttons.enumerated() {button.isHidden=i>=owned.alternatives.count;if i<owned.alternatives.count {button.title=owned.alternatives[i]}}
    keyboard.isHidden=true;guideKeyboardHeight?.constant=0
    panel?.setContentSize(NSSize(width:600,height:145))
    label.stringValue="Optional last-word correction"
    panel?.orderFrontRegardless()
  }

  func cancel(_ reason: String) {
    correctionPollToken += 1
    abandonActivation()
    deferredLift=nil;liftTimerGeneration += 1
    if active && reason != "OFF" && reason != "Quit" {
      lastSuggestion=nil;lastSwipeChoices=[]
      let category:String
      switch reason {
      case "Focus changed — cancelled", "Field changed · next fresh swipe uses the current field",
        "Focus changed · stroke cancelled", "Focus or caret changed · no word inserted":
        category=captureDiagnostics.focusRejection ?? "focusChanged"
      case "Keyboard input · next swipe uses the current field":category="keyboardInput"
      case "Application changed":category="applicationChanged"
      default:category="otherCaptureCancel"
      }
      captureDiagnostics.cancelReasons[category,default:0] += 1
      captureDiagnostics.focusRejection=nil
      strokeCancellationGeneration += 1
      retiredToken=strokeToken;lastOwnedWord=nil;pending=false;pendingWriteID=nil;queuedWords=[];continuationAnchor=nil;captureDiagnostics.pendingWords=0
      prepareNextStroke();frameOrdering.reset(receivedAfter:ProcessInfo.processInfo.systemUptime)
      captureDiagnostics.stage="waitingForSafeField";captureDiagnostics.result=reason
      showFeedback(reason);return
    }
    if active {captureDiagnostics.result=reason;captureDiagnostics.stage="cancelled"}
    let retained=(["OFF","Cancelled"].contains(reason) && lastOwnedWord != nil) ? lastOwnedWord : nil
    lastOwnedWord=retained
    let notify = !["Cancelled","OFF","Quit","Setup","Settings","Overlay layout preview; capture off"].contains(reason) && !reason.lowercased().contains("fixture")
    active = false
    pending = false;pendingWriteID=nil;queuedWords=[];continuationAnchor=nil;captureDiagnostics.pendingWords=0
    contactGate.reset()
    if let listener { OpenMTManager.shared().remove(listener) }
    listener = nil
    cornerProtection.stop()
    target = nil
    originalSelection = nil
    originalContentDigest=nil
    path = []
    finger = nil
    keyboard.path = []
    if retained==nil {buttons.forEach {$0.title="";$0.isHidden=true}}
    panel?.orderOut(nil)
    overlayPanel?.orderOut(nil);overlayKeyboard.path=[];overlayKeyboard.needsDisplay=true
    strokeSamples=[];strokeCalibration=nil;overlayFrame=nil
    activationScreen=nil
    updateModeIndicator()
    status?.button?.toolTip = reason
    status?.menu?.items.first?.title = "Swipepad: " + reason
    label.stringValue = reason
    if notify {showFeedback(reason)} else {statusReason=nil;feedbackPanel?.orderOut(nil);updateModeIndicator()}
    // Escape, double-Command Off and Quit disable capture; unresolved mutations survive exit cycles.
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === panel {
      if active {return false}
      if !active {lastOwnedWord=nil}
      cancel("Cancelled")
      return false
    }
    return true
  }
  @objc func appChanged() {
    abandonActivation();lastOwnedWord=nil
    if !active {panel?.orderOut(nil)}
    if active {
      lastFocusPreserved = false
      cancel("Application changed")
    }
    hotkey.cancel()
  }
  @objc func toggleGuide(_ sender: NSMenuItem) {
    guard !active else {return}
    let show = !UserDefaults.standard.bool(forKey: "showGuide")
    UserDefaults.standard.set(show, forKey: "showGuide")
    sender.state = show ? .on : .off
    keyboard.showKeys = show
    applyGuideVisibility()
    keyboard.needsDisplay = true
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

/// Temporary mouse-event filter; never edits Dock preferences or requests access.
@MainActor final class HotCornerProtection {
  private var port:CFMachPort?,source:CFRunLoopSource?
  private(set) var capturedButtons:Set<Int64>=[]
  private(set) var startFailureReason:String?
  let isActive:()->Bool,failed:()->Void,escapePressed:()->Void,observedScroll:()->Void
  init(isActive:@escaping ()->Bool,failed:@escaping ()->Void,escapePressed:@escaping ()->Void,observedScroll:@escaping ()->Void = {}) {self.isActive=isActive;self.failed=failed;self.escapePressed=escapePressed;self.observedScroll=observedScroll}
  func start()->Bool {
    // Never swallow the release of a drag/click that started in another app.
    guard capturedButtons.isEmpty,NSEvent.pressedMouseButtons==0 else {startFailureReason="Release the mouse button before starting swiping";return false}
    startFailureReason=nil
    stop()
    let types:[CGEventType]=[.keyDown,.scrollWheel,.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged,.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp]
    let mask=types.reduce(CGEventMask(0)) {$0 | (CGEventMask(1)<<$1.rawValue)}
    port=CGEvent.tapCreate(tap:.cghidEventTap,place:.headInsertEventTap,options:.defaultTap,eventsOfInterest:mask,callback:{_,type,event,info in
      guard let info else {return Unmanaged.passUnretained(event)}
      let blocked = MainActor.assumeIsolated {
        let owner=Unmanaged<HotCornerProtection>.fromOpaque(info).takeUnretainedValue()
        if type == .keyDown {
          return owner.handleCaptureKey(type,keyCode:event.getIntegerValueField(.keyboardEventKeycode))
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
          if let port=owner.port {CGEvent.tapEnable(tap:port,enable:true)}
          if owner.isActive() {owner.failed()};return true
        }
        // Drop at HID ingress; never warp the cursor, rewrite a location or fabricate input.
        return owner.handlePointer(type,button:event.getIntegerValueField(.mouseEventButtonNumber))
      }
      return blocked ? nil : Unmanaged.passUnretained(event)
    },userInfo:Unmanaged.passUnretained(self).toOpaque())
    guard let port,let s=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,port,0) else {stop();return false}
    source=s;CFRunLoopAddSource(CFRunLoopGetMain(),s,.commonModes);CGEvent.tapEnable(tap:port,enable:true);return true
  }
  func handleCaptureKey(_ type:CGEventType,keyCode:Int64)->Bool {
    guard isActive(),type == .keyDown,keyCode==53 else {return false}
    escapePressed()
    return true // Consume mode-exit Escape before the receiving editor handles it.
  }
  func blocksClick(_ type:CGEventType)->Bool {
    isActive() && [.leftMouseDown,.leftMouseUp,.rightMouseDown,.rightMouseUp,.otherMouseDown,.otherMouseUp].contains(type)
  }
  func blocksPointerAction(_ type:CGEventType)->Bool {
    // Physical contacts render their own guide marker. While capture is on,
    // suppress pointer motion as well as clicks/drags before receiver hover,
    // cursor-region and orphaned-drag handling. No OS pointer position is input.
    blocksClick(type) || (isActive() && [.mouseMoved,.leftMouseDragged,.rightMouseDragged,.otherMouseDragged].contains(type))
  }
  func handlePointer(_ type:CGEventType,button:Int64)->Bool {
    if type == .scrollWheel {if isActive() {observedScroll()};return false} // Observe only; preserve scroll ownership/termination.
    if [.leftMouseDown,.rightMouseDown,.otherMouseDown].contains(type) {
      guard isActive() else {return false}
      capturedButtons.insert(button);return true
    }
    if [.leftMouseUp,.rightMouseUp,.otherMouseUp].contains(type) {
      let owned=capturedButtons.remove(button) != nil
      if owned && !isActive() && capturedButtons.isEmpty {detach()}
      return owned // Always deliver a release whose down was not ours, including activation races.
    }
    if [.leftMouseDragged,.rightMouseDragged,.otherMouseDragged].contains(type) {
      return isActive() || capturedButtons.contains(button)
    }
    return isActive() && type == .mouseMoved
  }
  func stop() {
    // Only consume releases for downs we swallowed; ordinary movement/keys resume immediately.
    if capturedButtons.isEmpty {detach()}
  }
  private func detach() {
    if let port {CGEvent.tapEnable(tap:port,enable:false);CFMachPortInvalidate(port)}
    if let source {CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)}
    port=nil;source=nil
  }
}
