# Swipepad

An experimental native macOS menu-bar app for swiping words on a MacBook's **physical trackpad**. Double-tap Command while an editable text field is focused, lift any resting fingers, then slide one finger across the QWERTY layout shown in the guide, lift, and click the intended candidate to insert it followed by a space. Escape cancels. Each insertion ends the session.

This is an early prototype with a small English demonstration vocabulary, not a polished keyboard replacement. There are no accuracy claims. Physical swipe capture and real-app insertion still require hands-on validation; automated tests cover synthetic geometry, decoding, hotkey transitions, and focus policy. No cursor-pointer tracing fallback exists.

## Build and run

Requires macOS 13+, an installed Swift 6 toolchain and Apple Command Line Tools. The current build is verified on Apple Silicon with Swift 6.3.3 and the macOS 26 SDK. Other machines and OS versions have not been verified.

```sh
swift run SwipepadChecks
./scripts/build-app.sh
open dist/Swipepad.app
```

The app is not Developer ID signed or notarized (the Apple Silicon linker adds an ad hoc executable signature). macOS may block opening it. Review the source and follow macOS's normal explicit approval flow if you choose to run your own build; do not disable Gatekeeper. No installer, App Store distribution, or hosted CI is provided. Keep the app at a stable location before choosing to grant access, and restart after permissions change.

## Permissions and privacy

Accessibility access is required to observe global double-Command and insert into the captured field using its settable selected-text attribute. Global key observation may also depend on Input Monitoring on your macOS version. Swipepad reads existing permission status and **does not request or grant permissions automatically**. Use the menu's Permission status item to inspect status. If you choose to grant access, do so in System Settings → Privacy & Security, then restart Swipepad.

The app refuses secure text fields, fields without subrole metadata, active Secure Input, unsupported/unsettable selected-text fields, and unexpected app or element focus changes. It never uses a clipboard fallback, broadcasts synthetic typing, sends Return, logs typed text, or sends text over the network. The candidate must be clicked after a completed finger gesture. Insertion targets the original Accessibility element and rechecks its identity and foreground app immediately beforehand. Apps that do not expose these attributes will not work. Accessibility state can change asynchronously; targeted writes are used to avoid broadcasting text to a newly focused app.

## Trackpad behavior

Public AppKit `NSTouch.normalizedPosition` gives absolute physical coordinates, but [Apple documents that touch sequences are view/focus constrained](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html). It cannot supply this global nonactivating workflow. This prototype builds the MIT OpenMultitouchSupport source and uses Apple's **private MultitouchSupport framework**, outside App Sandbox. OS updates can break it; external Magic Trackpads are not supported by upstream's documented scope. No system security setting is changed. See [NOTICE.md](NOTICE.md) for pinned source provenance and licenses.

The guide is a non-key, nonactivating floating window: the original text field stays focused. The keyboard maps the full normalized physical trackpad (bottom-left origin) to three QWERTY rows. Pointer position does not determine letters. The physical trackpad still moves the normal pointer; cursor motion and clicks are **not suppressed**, including during capture. Clicking another application or changing text focus cancels the session. Use light contact and lift before choosing a candidate. Multi-finger contact clears the partial gesture.

Menu settings persist: hide the keyboard drawing (candidate controls and mode status remain visible), and configure double-Command tap interval and debounce. Command shortcuts cancel the pending tap sequence; ordinary shortcuts are never intercepted. Outside active mode no touch listener is registered. Escape is observed rather than swallowed and may also reach the foreground app.

Candidates are ranked by a small DTW path matcher. Click one to commit, or click **Swipe again** to discard the gesture and correct it. No automatic commit occurs on lift. Unsupported words will produce approximate candidates; cancel rather than accept an incorrect word. There is no language model, punctuation gesture, personalized dictionary, or post-insertion undo engine; use the receiving app's usual editing tools.

## Hands-on validation still required

1. Start from an ordinary TextEdit text field after explicitly choosing any necessary permissions. Verify that double-Command opens the guide without taking focus. Test Command+A and held modifiers do not activate it.
2. Swipe `hello` and `world` with one finger. Verify the trail follows physical position, then select a candidate and confirm insertion only into the original field.
3. Change app/field before selection: insertion must cancel. Try a secure/password field and Secure Input: activation must refuse or cancel. Escape and Quit must stop capture.
4. Try browser textarea/contenteditable fields. Refusal is expected when Accessibility support or safe subrole metadata is absent. Repeat with the guide drawing disabled, multi-finger touches, sleep/wake, and rapid activation/cancellation.

These steps have not been reported as passed until an actual hardware/user test is performed.
