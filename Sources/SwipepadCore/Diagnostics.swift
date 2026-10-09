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
  public var selectedTextSettable = false
  public var active = false
  public var focusPreserved: Bool? = nil
  public var insertionSucceeded: Bool? = nil
  public init() {}
}
public struct DoctorReport: Codable, Sendable {
  public let schemaVersion: Int
  public let scope: String
  public let state: String
  public let checks: [DoctorCheck]
  public var text: String {
    "Swipepad — \(state)\n\(scope)\n\n"
      + checks.map {
        "[\($0.status.rawValue.uppercased())] \($0.id): \($0.message)\nNext: \($0.repair)"
      }.joined(separator: "\n\n")
  }
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
          ? "Global event monitor could not be installed."
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
      "Activate, lift all resting fingers first, then slide one finger and lift. Use Reset session if stuck waiting for lift; multi-finger contact discards the gesture. No capture runs outside active mode."
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
        ? "Role: \(input.fieldRole ?? "unknown"); \(subrole); selected-text writable: \(input.selectedTextSettable)."
        : "No external focused field is available.",
      "Focus an ordinary TextEdit or browser text area and Recheck. Missing optional subrole is allowed for AXTextArea only. Secure, read-only, single-line fields without safe metadata, and unsupported AX controls are refused; there is no automatic compatibility override."
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
          ? "Last explicit candidate selection returned AX success; visually verify the receiving document."
          : "Last targeted selected-text write was rejected."
      }
        ?? "No candidate insertion has been attempted; writable metadata is not end-to-end success.",
      "In a disposable text area, complete a physical swipe and explicitly click the intended candidate, then visually verify it. If AX rejects the write, use a supported ordinary field; no clipboard or broadcast typing fallback is used."
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
