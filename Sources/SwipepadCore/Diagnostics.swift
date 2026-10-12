import Foundation

public enum CheckStatus: String, Codable, Sendable { case pass, fail, warning, waiting }
public struct DoctorCheck: Codable, Sendable {
  public let id: String
  public let status: CheckStatus
  public let message: String
  public let repair: String
}
public struct DoctorInput: Sendable {
  public var bundled = false
  public var identityMatches = false
  public var signatureValid = false
  public var developerSigned = false
  public var ownedInstances = 0
  public var accessibility = false
  public var secureInput = false
  public var frameworkPresent = false
  public var deviceAvailable = false
  public var live = false
  public var monitorInstalled = false
  public var globalEventSeen = false
  public var hotkeySeen = false
  public var touchSeen = false
  public var liftSeen = false
  public var fieldFound = false
  public var fieldSupported = false
  public var fieldRole: String? = nil
  public var fieldSubrole: FieldSubrole = .unreadable
  public var targetedInsertionSettable = false
  public var active = false
  public var focusPreserved: Bool? = nil
  public var insertionSucceeded: Bool? = nil
  public init() {}
}
public struct OutstandingWriteReport: Codable, Sendable {
  public let pid:Int32
  public let bundleIdentifier:String?
  public let expectedCaret:Int
  public let transactionID:String?
  public let mutationAccepted:Bool?
  public let caretAttemptPending:Bool?
  public init(pid:Int32,bundleIdentifier:String?,expectedCaret:Int,transactionID:String?=nil,mutationAccepted:Bool?=nil,caretAttemptPending:Bool?=nil) {
    self.pid=pid;self.bundleIdentifier=bundleIdentifier;self.expectedCaret=expectedCaret
    self.transactionID=transactionID;self.mutationAccepted=mutationAccepted;self.caretAttemptPending=caretAttemptPending
  }
}
public struct DoctorReport: Codable, Sendable {
  public var outstandingWrites:[OutstandingWriteReport]? = nil
  public let schemaVersion: Int
  public let scope: String
  public let state: String
  public let checks: [DoctorCheck]
  public var runtimeIdentity: String? = nil
  public var capture: CaptureDiagnostics? = nil
  public init(schemaVersion:Int=1,scope:String,state:String,checks:[DoctorCheck]=[]) {
    self.schemaVersion=schemaVersion;self.scope=scope;self.state=state;self.checks=checks
  }
  public var text: String {
    "Swipepad — \(state)\n\(scope)\n" + (runtimeIdentity.map { $0 + "\n" } ?? "") + "\n"
      + (capture.map { "Capture trial \($0.trial) · mode \($0.mode) · stage \($0.stage)\nCoordinates: normalized physical trackpad\nCallbacks \($0.callbacks) · active frames \($0.contactFrames) · idle frames \($0.idleFrames) · samples \($0.samples) · candidates \($0.candidates) · accepted words \($0.insertions)\nWords: recognized \($0.recognizedWords) · write attempts \($0.writeAttempts) · mutations accepted \($0.acceptedMutations) · confirmed \($0.insertions) · pending \($0.pendingWords) · rejected \($0.rejectedWords) · backend \($0.lastInsertionBackend ?? "none") · AX error \($0.lastAXError.map(String.init) ?? "none")\nInput: \($0.inputCapabilities ?? "not inspected") · target \($0.targetBundleIdentifier ?? "unknown") · focus \($0.focusLookupKind ?? "none") · retries \($0.focusPublicationRetries ?? 0)\nLast target refusal \($0.lastTargetRefusal ?? "none")\nFocus rejection \($0.focusRejection ?? "none") · last result \($0.result ?? "none")\n\n" } ?? "")
      + checks.map {
        "[\($0.status.rawValue.uppercased())] \($0.id): \($0.message)\nNext: \($0.repair)"
      }.joined(separator: "\n\n")
  }
}
/// Per-trial structural counters only: no words, key contents, field text or coordinates.
public struct CaptureDiagnostics: Codable, Sendable {
  public var firstTargetRefusal:String?
  public var targetAttempts=0
  public var targetAdmissions=0
  public var targetApplicationPID:Int32?
  public var targetBundleIdentifier:String?
  public var focusLookupKind:String?
  public var focusPublicationRetries:Int?
  public var applicationFocusAXError:Int?
  public var systemFocusAXError:Int?
  public var confirmationIdentityMatches:Bool?
  public var confirmationCaretMatches:Bool?
  public var confirmationContentMatches:Bool?
  public var confirmationBeforeContentMatches:Bool?
  public var lastTargetRefusal:String?
  public var releaseFrames=0
  public var graceRejoins=0
  public var graceCommits=0
  public var liftGraceSeconds=0.0
  public var droppedFrames=0
  public var recognizedWords=0
  public var rejectedWords=0
  public var pendingWords=0
  public var writeAttempts=0
  public var acceptedMutations=0
  public var contentReadable:Bool?
  public var valueReadAXError:Int?
  public var valueReadKind:String?
  public var textEvidenceSource:String?
  public var textEvidenceLength:Int?
  public var rangeTextAXError:Int?
  public var correctionResult:String?
  public var lastInsertionBackend:String?
  public var confirmationWaitMilliseconds=0.0
  public var expectedCaret:Int?
  public var observedCaretLocation:Int?
  public var observedCaretLength:Int?
  public var lastAXError:Int?
  public var insertions=0
  public var trial=0
  public var mode="trackpad"
  public var stage="off"
  public var callbacks=0
  public var contactFrames=0
  public var idleFrames=0
  public var states:[String:Int]=[:]
  public var gateWaitFrames=0
  public var samples=0
  public var candidates=0
  public var maximumCallbackDelayMilliseconds=0.0
  public var axRequests=0
  public var maximumAXMilliseconds=0.0
  public var totalAXMilliseconds=0.0
  public var resetReasons:[String:Int]=[:]
  public var cancelReasons:[String:Int]=[:]
  public var scrollEventsPassed=0
  public var inputProtectionFailures=0
  public var rejectionReasons:[String:Int]=[:]
  public var inputCapabilities:String?
  public var focusRejection:String?
  public var result:String?
  public var recognitionRankedCount:Int?
  public var recognitionTopGeometry:Double?
  public var recognitionMargin:Double?
  public var recognitionReason:String?
  public var feedbackCount:Int?
  public var feedbackKind:String?
  public init() {}
}
public enum Doctor {
  public static func evaluate(_ input: DoctorInput) -> DoctorReport {
    var checks: [DoctorCheck] = []
    func add(_ id: String, _ status: CheckStatus, _ message: String, _ repair: String) {
      checks.append(DoctorCheck(id: id, status: status, message: message, repair: repair))
    }
    add(
      "bundle", input.bundled && input.identityMatches ? .pass : .fail,
      input.bundled && input.identityMatches
        ? "Bundled as com.ericspencer00.swipepad."
        : "Run the built app bundle, not the bare Swift executable.",
      "Build with scripts/build-app.sh; use dist/Swipepad.app at one stable location before requesting access."
    )
    add(
      "signing", input.signatureValid ? (input.developerSigned ? .pass : .warning) : .fail,
      input.signatureValid
        ? (input.developerSigned
          ? "Bundle signature validates."
          : "Valid local ad hoc signature; not Developer ID signed or notarized.")
        : "Bundle signature is missing or invalid.",
      "Rebuild the complete bundle. For a macOS security warning, review the source and use the normal explicit approval flow; never disable Gatekeeper."
    )
    add(
      "instances", input.ownedInstances > 1 ? .fail : .pass,
      "\(input.ownedInstances) running owned app instance(s).",
      "Choose Quit in extra Swipepad instances, or explicitly run scripts/doctor.sh --relaunch to gracefully close only this bundle and launch once."
    )
    add(
      "accessibility", input.accessibility ? (input.live ? .pass : .warning) : .fail,
      input.accessibility
        ? (input.live
          ? "Accessibility is granted to the running app."
          : "Command process is trusted; macOS caller attribution can differ from the GUI app. Verify live Setup & Doctor.")
        : "Accessibility is needed for global shortcuts and selected-text insertion.",
      "Click Request Accessibility. In macOS's pane, enable Swipepad and complete any authentication yourself, then click Recheck / reconnect. If an old enabled entry is stale after a rebuild, switch only Swipepad off/on or add the current stable bundle yourself."
    )
    add(
      "secure-input", input.secureInput ? .fail : .pass,
      input.secureInput
        ? "Secure Input is active; capture and insertion are suspended."
        : "Secure Input is inactive.",
      "Leave the password/secure-input context yourself, focus an ordinary text area, and Recheck. Swipepad never disables Secure Input."
    )
    add(
      "trackpad", input.frameworkPresent && input.deviceAvailable ? .pass : .fail,
      input.frameworkPresent && input.deviceAvailable
        ? "Private framework and a default multitouch device are available; physical capture remains to be tested."
        : "Private framework or default multitouch device is unavailable.",
      "Use a supported MacBook built-in trackpad. Recheck after wake. Private API/hardware incompatibility requires a compatible build or device; there is no permission or cursor fallback fix."
    )
    add(
      "keyboard",
      !input.accessibility
        ? .fail
        : (input.live && !input.monitorInstalled
          ? .fail : (input.globalEventSeen ? .pass : .waiting)),
      input.globalEventSeen
        ? "A global keyboard event was observed (no key/text recorded)."
        : (input.live && !input.monitorInstalled
          ? (!input.accessibility ? "Keyboard monitor is not installed because this app lacks Accessibility access." : "Global event monitor could not be installed.")
          : "Keyboard delivery has not been observed in this session; monitor installation alone is not proof."),
      "With Accessibility enabled and Secure Input off, click Recheck / reconnect; return to your text area and tap Command. This NSEvent path does not request Input Monitoring. If delivery still fails, use the explicit relaunch action and report the diagnostic state."
    )
    add(
      "hotkey", input.hotkeySeen ? .pass : .waiting,
      input.hotkeySeen
        ? "A double-Command sequence was recognized."
        : "Double-Command has not been recognized in this session.",
      "Return to a text area, tap and release Command twice without another key. Adjust Hotkey timing if needed; held Command or ordinary shortcuts do not activate."
    )
    add(
      "touch-lift", input.touchSeen && input.liftSeen ? .pass : .waiting,
      input.touchSeen && input.liftSeen
        ? "A physical touch frame and lift were observed; word accuracy is not verified."
        : "A touch-and-lift cycle has not been observed in active mode.",
      "Activate, slide one finger and lift to type a word. Use Reset session if stuck waiting for lift; multi-finger contact discards the gesture. No capture runs outside active mode."
    )
    let subrole: String
    switch input.fieldSubrole {
    case .named(let name): subrole = name
    case .absent: subrole = "optional subrole absent"
    case .unreadable: subrole = "metadata unreadable"
    }
    add(
      "field",
      input.fieldFound ? (input.fieldSupported && !input.secureInput ? .pass : .fail) : .waiting,
      input.fieldFound
        ? "Role: \(input.fieldRole ?? "unknown"); \(subrole); targeted insertion available: \(input.targetedInsertionSettable)."
        : "No external focused field is available.",
      "Focus an editable text field or composer and Recheck. Missing optional subrole is allowed for supported writable text controls. Secure, read-only, single-line fields without safe metadata, and unsupported AX controls are refused; there is no automatic compatibility override."
    )
    add(
      "focus", input.focusPreserved.map { $0 ? .pass : .fail } ?? .waiting,
      input.focusPreserved.map {
        $0
          ? "Original app and field identity remained unchanged at the last check."
          : "Original app or field changed; session was cancelled."
      } ?? "Original focus preservation has not been checked in an active session.",
      "Cancel/Reset session, focus the intended field, then activate again. Never reuse a target after an app/field change."
    )
    add(
      "insertion", input.insertionSucceeded.map { $0 ? .pass : .fail } ?? .waiting,
      input.insertionSucceeded.map {
        $0
          ? "Last word insertion returned AX success; visually verify the receiving document."
          : "Last insertion could not be confirmed; check the receiving field."
      }
        ?? "No word insertion has been attempted; writable metadata is not end-to-end success.",
      "In a disposable text area, complete a physical swipe, lift to commit, then visually verify it. If AX rejects the write, use a supported ordinary field; no clipboard or broadcast typing fallback is used."
    )
    let setup =
      !input.bundled || !input.identityMatches || !input.signatureValid || !input.accessibility
      || !input.frameworkPresent || !input.deviceAvailable || input.ownedInstances > 1
      || (input.live && !input.monitorInstalled)
    let state =
      setup
      ? "Setup needed"
      : (!input.live
        ? "Preflight only — verify live Setup & Doctor"
        : (input.active
          ? "On"
          : (input.fieldSupported && !input.secureInput
            ? "Ready to test" : "Off — focus an ordinary text area")))
    return DoctorReport(
      schemaVersion: 1,
      scope: input.live
        ? "Live app checks; no field text or key contents recorded."
        : "Read-only command preflight; permission attribution can differ from the GUI app. Run Setup & Doctor for authoritative live trust and keyboard/touch/focus/insertion evidence.",
      state: state, checks: checks)
  }
}

public enum RelaunchPolicy {
  public static func isDistinctLaunch(helperPID: Int32, resultPID: Int32?) -> Bool {
    guard let resultPID else { return false }
    return resultPID != helperPID
  }
}
