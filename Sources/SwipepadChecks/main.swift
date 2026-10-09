import Foundation
import SwipepadCore

var count = 0
@MainActor func check(_ condition: @autoclosure () -> Bool, _ name: String) {
  guard condition() else { fatalError("FAIL: \(name)") }
  count += 1
}
check(Keyboard.keys.count == 26, "26 QWERTY keys")
check(Keyboard.keys["q"]!.y > Keyboard.keys["z"]!.y, "bottom-left coordinate orientation")
check(Keyboard.keys["q"]!.x < Keyboard.keys["p"]!.x, "left/right geometry")
check(
  Keyboard.keys.values.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) },
  "bounded normalized keys")
for word in ["hello", "world", "test", "cat", "typing"] {
  check(
    Decoder.candidates(Keyboard.path(word), words: ["hello", "world", "test", "cat", "typing"])
      .first == word, "synthetic exact path \(word)")
}
check(Decoder.candidates([], words: ["hello"]).isEmpty, "empty gesture")
check(
  Decoder.candidates([Point(.nan, 0), Point(0, 0)], words: ["hello"]).isEmpty, "nonfinite input")
check(Decoder.candidates([Point(-1, 0), Point(0, 0)], words: ["hello"]).isEmpty, "out of bounds")
check(Decoder.distance([], Keyboard.path("hello")).isInfinite, "empty DTW")
var h = CommandTap()
check(!h.update(isDown: true, onlyCommand: true, time: 0), "first down")
check(!h.update(isDown: true, onlyCommand: true, time: 0.01), "repeated down")
check(!h.update(isDown: false, onlyCommand: true, time: 0.05), "first release")
check(!h.update(isDown: true, onlyCommand: true, time: 0.15), "second down")
check(h.update(isDown: false, onlyCommand: true, time: 0.2), "double Command fires")
check(!h.update(isDown: false, onlyCommand: true, time: 0.21), "repeated release")
h = CommandTap()
_ = h.update(isDown: true, onlyCommand: true, time: 0)
h.cancel()
check(!h.update(isDown: false, onlyCommand: true, time: 0.1), "shortcut invalidates tap")
h = CommandTap()
_ = h.update(isDown: true, onlyCommand: true, time: 0)
check(!h.update(isDown: false, onlyCommand: true, time: 1), "held modifier")
h = CommandTap()
_ = h.update(isDown: true, onlyCommand: true, time: 0)
_ = h.update(isDown: false, onlyCommand: true, time: 0.05)
_ = h.update(isDown: true, onlyCommand: false, time: 0.1)
check(!h.update(isDown: false, onlyCommand: true, time: 0.2), "additional modifier cancels")
h = CommandTap()
h.debounce = 1
for (down, t) in [(true, 0.0), (false, 0.05), (true, 0.1), (false, 0.15)] {
  _ = h.update(isDown: down, onlyCommand: true, time: t)
}
_ = h.update(isDown: true, onlyCommand: true, time: 0.2)
_ = h.update(isDown: false, onlyCommand: true, time: 0.25)
_ = h.update(isDown: true, onlyCommand: true, time: 0.3)
check(
  !h.update(isDown: false, onlyCommand: true, time: 0.35),
  "debounce prevents rapid second activation")
check(
  FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: true, secure: false, editable: true),
  "same safe field")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 2, sameElement: true, secure: false, editable: true), "changed app")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: false, secure: false, editable: true),
  "changed field")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: true, secure: true, editable: true), "secure field")
check(
  !FocusGuard.permits(
    originalPID: 1, currentPID: 1, sameElement: true, secure: false, editable: false),
  "unsettable field")
// Regression: observed Brave AXTextArea, subrole attributeUnsupported, selectedText writable.
check(
  FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, selectedTextSettable: true, secureInput: false),
  "ordinary browser/TextEdit textarea without optional subrole")
check(
  FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("AXUnknown"), selectedTextSettable: true, secureInput: false
  ), "native text area with explicit ordinary subrole")
check(
  FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXUnknown"), selectedTextSettable: true,
    secureInput: false), "ordinary single-line text field")
check(
  FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXSearchField"), selectedTextSettable: true,
    secureInput: false), "ordinary search field")
check(
  !FieldPolicy.permits(
    role: "AXTextField", subrole: .named("AXSecureTextField"), selectedTextSettable: true,
    secureInput: false), "password subrole")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("AXSecureTextField"), selectedTextSettable: true,
    secureInput: false), "secure metadata cannot bypass via text area role")
check(
  !FieldPolicy.permits(
    role: "AXTextField", subrole: .absent, selectedTextSettable: true, secureInput: false),
  "single-line missing safety metadata")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .unreadable, selectedTextSettable: true, secureInput: false),
  "AX metadata errors fail closed")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, selectedTextSettable: false, secureInput: false),
  "read-only text area")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .absent, selectedTextSettable: true, secureInput: true),
  "Secure Input still blocks ordinary textarea")
check(
  !FieldPolicy.permits(
    role: "AXButton", subrole: .absent, selectedTextSettable: true, secureInput: false),
  "unrelated control")
check(
  !FieldPolicy.permits(role: nil, subrole: .absent, selectedTextSettable: true, secureInput: false),
  "missing role")
check(
  !FieldPolicy.permits(
    role: "AXTextArea", subrole: .named("UnrecognizedSubrole"), selectedTextSettable: true,
    secureInput: false), "unknown subrole fail closed")
print("Passed \(count) synthetic core checks. No physical touches or text insertion tested.")
