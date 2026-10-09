# Swipepad

An experimental native macOS menu-bar app for swiping words on a MacBook's **physical trackpad**. Double-tap Command while an editable text field is focused, lift any resting fingers, then slide one finger across the QWERTY layout shown in the guide, lift, and click the intended candidate to insert it followed by a space. Escape cancels. Each insertion ends the session.

This is an early prototype with a small English demonstration vocabulary, not a polished keyboard replacement. There are no accuracy claims. Physical swipe capture still requires hands-on validation. Separate native fixtures verify candidate controls and insertion into owned TextEdit documents using synthetic geometry; they do not establish hardware accuracy. The selectable Screen Overlay mode explicitly uses cursor coordinates; Trackpad mode always uses physical coordinates.

## Choose an input mode

**Trackpad Mode** is the default. Its guide maps the full physical trackpad to QWERTY regardless of cursor position. The persistent guide setting can hide its keyboard drawing while leaving candidate controls available.

**Screen Overlay Mode** places a large translucent QWERTY keyboard on the display containing your cursor. Move the cursor onto the first letter, lift all fingers, then swipe with one finger and lift to see candidates. A contact beginning outside the keyboard is a positioning step: place the cursor, lift, then start again. A stroke that leaves the keyboard requires **Swipe Again**. The cursor remains visible, and a translucent blue trail follows the complete sampled stroke. The overlay receives clicks so taps within its rectangle do not click through into the document. Clicking a candidate commits explicitly. This mode samples screen cursor positions while physical single-finger contact is active; cursor movement by itself does not begin a stroke.

Choose **Overlay Layout…** from the menu or Setup to move and resize a normal preview window with capture off. Its keyboard canvas keeps its aspect ratio. **Use This Layout** saves the canvas's screen position and size for that display, and the opacity slider adjusts key translucency. **Reset Layout** restores that display's default geometry. Return to the intended text field before activating. Calibration is frozen for each stroke; changing displays cancels active capture. Screen Overlay's keyboard remains visible while active, independent of the physical guide setting.

Screen Overlay is implemented and covered by synthetic geometry checks, but physical cursor/contact timing, tap-to-click behavior, multiple displays, and candidate interactions in this mode still need hands-on validation.

## Build and run

Requires macOS 13+, an installed Swift 6 toolchain and Apple Command Line Tools. The current build is verified on Apple Silicon with Swift 6.3.3 and the macOS 26 SDK. Other machines and OS versions have not been verified.

```sh
swift run SwipepadChecks
./scripts/build-app.sh
open dist/Swipepad.app
```

The complete local app bundle is ad hoc signed, and is not Developer ID signed or notarized. macOS may block opening it. Review the source and follow macOS's normal explicit approval flow if you choose to run your own build; do not disable Gatekeeper. No installer, App Store distribution, or hosted CI is provided. Keep the app at a stable location before choosing to grant access, and restart after permissions change.

## Setup, permissions and doctor

Swipepad uses an icon-only menu-bar item with an accessible **Ready**, **On**, or **Needs setup** value. The first launch opens **Swipepad Setup** if Accessibility is missing; later launches do not repeatedly open it. Open **Setup…** explicitly whenever needed. Setup is a regular, keyboard-focusable window at normal level, with Command-W and Escape to close. Only the nonactivating keyboard guide floats while capture is active; cancellation or a focus change immediately hides it.

Setup has one next action and collapsed **Diagnostics** containing Check Again, Open Accessibility Settings, Reset Session, Relaunch Swipepad, Copy Report, and separate tap/debounce fields. **Request Access…** explicitly requests macOS approval without another app confirmation. macOS owns the Accessibility switch and any authentication. Readiness uses live process trust and the actual listener; doctor warnings cannot override a trusted process. A checked entry for an older build does not establish trust for a rebuilt app. Freeze the bundle or deliberately select an existing signing identity before approving access. No TCC database edits, permission resets, credential entry, or security bypass is performed.

The implementation uses `NSEvent` global key observation with Accessibility access, not a CGEvent input tap. It does **not request Input Monitoring**. The doctor separates installed-monitor status from an actually observed global event, and gives narrow recovery steps rather than treating another permission as a generic fix. No permission prompt is opened by read-only diagnosis.

```sh
./scripts/doctor.sh             # read-only machine-readable JSON (schemaVersion 1)
./scripts/doctor.sh --text      # read-only report with a repair/next step for every stage
./scripts/doctor.sh --setup     # explicitly open the setup panel; never self-grant access
./scripts/doctor.sh --relaunch  # explicitly Quit only this exact bundle, wait, then launch once
```

The script uses `dist/Swipepad.app` by default. Set `SWIPEPAD_APP` to your own stable app location if you moved it. JSON output contains structural checks, not field contents. Exit status is 2 for a failed check or launcher preflight; warnings/waiting tests do not imply failure or e2e success. The command asks the matching running app for a read-only diagnostic snapshot through local notifications. With no responding app, it labels the result as command preflight: macOS may attribute terminal-launched permission differently, so that result cannot establish GUI trust. No touch capture or synthetic test input is attached by the command. Live keyboard, hotkey, touch/lift, focus and insertion evidence appears in **Setup & Doctor** after your actions. Those in-memory booleans reset when the app restarts; no typed text, key contents, or gesture path is written to diagnostics.

| Stage | Supported recovery |
| --- | --- |
| Bundle identity / signature | Build the complete bundle, keep one stable location, and use normal macOS explicit approval if blocked. The build uses a local ad hoc signature, not Developer ID/notarization. |
| Duplicate instances | Quit extras or explicitly select **Relaunch app** / `--relaunch`. Only instances with the exact current bundle executable path are closed; other copies require manual Quit. No force-kill is used by the repair. |
| Accessibility | **Request Accessibility**, approve only Swipepad through macOS, then **Recheck / reconnect**. Complete OS authentication yourself. |
| Keyboard / double-Command | Reconnect, return to a text area and tap/release Command twice without another key. Adjust **Hotkey timing** or explicitly relaunch if needed. |
| Private framework / device | Recheck after wake; use a supported built-in MacBook trackpad and compatible macOS build. No automatic compatibility override exists. |
| Touch / lift | Activate, lift resting fingers, use one finger, then lift. **Reset session** discards a stuck session. |
| Secure Input / field | Leave the secure context yourself and focus a supported writable ordinary text area; never disable Secure Input. |
| Original focus | Reset, focus the intended field, and activate afresh. An app/element change cancels insertion. |
| Insertion | Explicitly choose a candidate in a disposable supported field and visually verify it. AX success alone is not proof of correct visible text; unsupported AX writes have no clipboard/broadcast fallback. |

## Privacy and insertion safety

The app refuses secure text fields, single-line fields without explicit nonsecure subrole metadata, active Secure Input, unsupported/unsettable selected-text fields, and unexpected app or element focus changes. It never uses a clipboard fallback, broadcasts synthetic typing, sends Return, logs typed text, or sends text over the network. A candidate must be clicked after a completed finger gesture. Insertion targets the original Accessibility element and rechecks its identity, original insertion range, and foreground app immediately beforehand.

Ordinary writable `AXTextArea` controls are accepted when the optional subrole is absent (`attributeUnsupported` or `noValue`); other metadata read failures are refused. Single-line fields require `AXUnknown` or `AXSearchField` rather than missing metadata. Apps that do not expose safe writable text attributes and a readable selected-text range will not work. Moving the caret or changing the selection during a swipe cancels insertion. Accessibility state can change asynchronously; targeted writes avoid broadcasting text to a newly focused app.

## Trackpad behavior

Public AppKit `NSTouch.normalizedPosition` gives absolute physical coordinates, but [Apple documents that touch sequences are view/focus constrained](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html). It cannot supply this global nonactivating workflow. This prototype builds the MIT OpenMultitouchSupport source and uses Apple's **private MultitouchSupport framework**, outside App Sandbox. OS updates can break it; external Magic Trackpads are not supported by upstream's documented scope. No system security setting is changed. See [NOTICE.md](NOTICE.md) for pinned source provenance and licenses.

The guide is a non-key, nonactivating floating window: the original text field stays focused. The keyboard maps the full normalized physical trackpad (bottom-left origin) to three QWERTY rows. Pointer position does not determine letters. The physical trackpad still moves the normal pointer; cursor motion and clicks are **not suppressed**, including during capture. Clicking another application or changing text focus cancels the session. Use light contact and lift before choosing a candidate. Multi-finger contact clears the partial gesture.

Menu settings persist: hide the keyboard drawing (candidate controls and mode status remain visible), and configure double-Command tap interval and debounce. Command shortcuts cancel the pending tap sequence; ordinary shortcuts are never intercepted. Outside active mode no touch listener is registered. Escape is observed rather than swallowed and may also reach the foreground app.

Candidates are ranked by a small DTW path matcher. Click one to commit, or click **Swipe again** to discard the gesture and correct it. No automatic commit occurs on lift. Unsupported words will produce approximate candidates; cancel rather than accept an incorrect word. There is no language model, punctuation gesture, personalized dictionary, or post-insertion undo engine; use the receiving app's usual editing tools.

## Hands-on validation still required

1. Start from an ordinary TextEdit text field after explicitly choosing any necessary permissions. Verify that double-Command opens the guide without taking focus. Test Command+A and held modifiers do not activate it.
2. Swipe `hello` and `world` with one finger. Verify the trail follows physical position, then select a candidate and confirm insertion only into the original field.
3. Change app/field before selection: insertion must cancel. Try a secure/password field and Secure Input: activation must refuse or cancel. Escape and Quit must stop capture.
4. Try browser textarea/contenteditable fields. Refusal is expected when Accessibility support or required safe subrole metadata is absent. Ordinary writable `AXTextArea` controls may omit their optional subrole. Repeat with the guide drawing disabled, multi-finger touches, sleep/wake, and rapid activation/cancellation.

These steps have not been reported as passed until an actual hardware/user test is performed.

## Replace the placeholder logo

`Assets/logo.svg` and `scripts/make-icon.swift` contain the original simple trackpad-and-finger-trail design. The build generates all standard 16–1024 pixel icon sizes and assembles the app's `.icns`. The small menu-bar mark is a template image drawn in `DoctorSupport.swift`, so macOS can tint it for light/dark appearance. No external image/model/license is involved. Replace these assets when a final brand is ready.

For repeated local development builds, an existing certificate-backed signing identity can be selected with `SWIPEPAD_SIGN_IDENTITY` when running `scripts/build-app.sh`. No identity is created or automatically selected. Default ad hoc signatures are bound to a changing code hash and can invalidate prior Accessibility approval after a rebuild. Freeze a build before approving access, or deliberately use an existing suitable signing identity; signing does not itself grant permissions or imply notarization.

For an explicit interactive native integration check, run `./scripts/test-integration.sh` with Swift 6.2+ when ready for a brief TextEdit test. It creates its own disposable document, builds a separate harness from application sources, supplies synthetic geometry and performs actual candidate clicks/AX writes only into that owned document. It aborts if existing access or exact focus is unavailable; it never grants permissions. These fixture tests do not emulate physical trackpad input or certify hardware accuracy. The installed app bundle is not replaced by the test.
