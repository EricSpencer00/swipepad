# Recreate Swipepad

This file is the single source of truth for what Swipepad does and how to build, run, and test it. Code must match this file. If they differ, fix the code or update this file in the same change.

## Requirements

- macOS 13 or later.
- A MacBook with a built-in trackpad. External trackpads are not supported.
- Swift 6 toolchain with the Apple Command Line Tools (`xcode-select --install`).
- Accessibility permission for the built app (see below).
- No network access is used. No account, no server, no telemetry.

## How macOS grants access

| Permission | Why | When it is asked |
| --- | --- | --- |
| Accessibility | Reads the focused text field and writes words into it. Detects the Double-⌘ shortcut. | Setup window, **Request Access…**. Enabled by hand in System Settings → Privacy & Security → Accessibility. |
| Screen Recording | Only for recording demos with `scripts/record-demo.sh`. The app never records the screen. | Asked of the terminal, only when you record a demo. |

Swipepad does not request Input Monitoring. Keystrokes are only read to detect Escape and Delete while swiping is on.

Permission belongs to one bundle at one path. After a rebuild or a move, remove old Swipepad entries in Accessibility and add `dist/Swipepad.app` again.

## Build and run

```sh
swift build
swift run SwipepadChecks              # headless checks, about 2 seconds
./scripts/build-app.sh                # signed app at dist/Swipepad.app
open dist/Swipepad.app
```

Relaunch after a rebuild:

```sh
./scripts/doctor.sh --relaunch
./dist/Swipepad.app/Contents/MacOS/Swipepad --doctor --text
```

## Test

| Command | What it checks | Needs |
| --- | --- | --- |
| `swift run SwipepadChecks` | Recognizer, keyboard layout, crop, pad areas, lift delay, insertion route, undo, settings rules | Nothing |
| `SWIPE_TUNE=1 swift run SwipepadChecks` | Slow measurements on the full word list | Nothing |
| `SWIPE_MARGIN=1 swift run SwipepadChecks` | Confidence margins by correctness | Nothing |
| `./scripts/e2e-write.sh textedit` | Writes words into TextEdit through the app's insertion code | Accessibility, focus |
| `./scripts/e2e-write.sh web` | Writes into the test page in a browser | Accessibility, click into the field |
| `./scripts/e2e-write.sh claude` | Writes into Claude's composer | Accessibility, click into the composer |
| `./scripts/demo-setup.sh` | Builds, launches, and opens a clean test page and TextEdit | Accessibility, Screen Recording (for demos) |
| `./scripts/record-demo.sh 40` | Records the frontmost window and writes `docs/demo.gif` | Screen Recording |

Physical trackpad behavior cannot be tested headlessly. Check it by swiping on a real MacBook.

## Architecture

- `Sources/SwipepadCore`: pure logic with no AppKit. Recognition, keyboard layout, crop (`KeyboardViewport`), pad area (`PadRegion`), jump filter, lift delay, candidate decision, insertion route, undo. Everything here is checked headlessly.
- `Sources/Swipepad`: the macOS app. Menu bar item, setup window, on-screen overlay, settings window, trackpad input, Accessibility writes.
- `Sources/SwipepadChecks`: the headless test executable.
- `site/`: the swipetype.app website, deployed with Wrangler (`cd site && wrangler deploy`).

## Features and settings

### Typing

- **Double-⌘** turns swiping on and off.
- **Swipe** one finger across the keyboard. The word is typed with a trailing space.
- **Best word always.** The top candidate is typed. Close calls do not wait for confirmation.
- **Delete** removes the last typed word and its space, then offers the runner-up candidates on the top strip. Tap one to type it.
- **Escape** turns swiping off.
- **Short words** like "hi" are checked on the full word list.

### Keyboard

- **Keyboard guide:** On Screen (floating overlay) or In Panel (menu bar panel). Stored as `inputMode`.
- **Show Keyboard Guide** hides or shows the keyboard. Stored as `showGuide`.
- **Key opacity** in the overlay layout. Stored as `overlayOpacity`.
- **Overlay layout:** position and size per display, stored per screen (`overlayLayout.*`). Reset Layout clears it.
- **Crop:** drag the edges of the layout preview to show only part of the keyboard. Stored as `keyboardViewport`. Reset Layout clears it.
- **Lenient starts:** a swipe may begin up to about four keys from the first letter.

### Trackpad

- **Pad area** (Settings → Trackpad Area): Full (the whole pad), iPhone (about 71 × 36 mm), Compact (smaller). Drag a corner to make a custom area. Stored as `padRegion`.
- Touches outside the area are ignored.
- **Roll spikes** (a sudden jump in the contact position) are dropped before drawing and recognition.

### Timing

- **Pause before a word ends** (Settings → Typing): 0 to 0.4 seconds, default 0.10. A brief pause mid-swipe keeps the same word going. Stored as `liftGrace`.
- **Tap interval** and **debounce** for Double-⌘, stored as `interval` and `debounce`.

### Setup and diagnostics

- **Setup window:** shows what is missing (Accessibility, keyboard, trackpad) and offers Request Access…
- **Doctor:** `--doctor` and `--doctor --text` report each stage. `--capture-status` prints live counters without text.
- **Copy Report** copies the diagnostic report. It contains no typed text and no gesture paths.

### Privacy and safety

- No typed text, key contents, or gesture paths are logged or saved.
- The clipboard is never used.
- Return is never sent.
- Secure text fields and Secure Input are refused.
- A write is only typed when the same app and field still have focus.
- Web editors (such as Claude's composer) are typed with key presses, because accessibility writes there cannot be confirmed. Native fields use a verified accessibility write.

### Settings screen

- Opens from **Settings…** (⌘,).
- Grouped sections: Trackpad Area (preset picker, trackpad drawing with corner handles, size in millimetres), and Typing (pause slider).

### Website

- `swipetype.app`: animated intro (a Three.js MacBook that types "SwipeType.app"), title, Download for macOS, and Windows and Linux marked "Coming soon". Tutorial at `/tutorial`.

## Platform status

| Platform | Status |
| --- | --- |
| macOS (Apple silicon, macOS 13 or later) | Built, signed with a local development certificate, not notarized. Physical trackpad behavior is validated on one machine. |
| Windows | Not started. Coming soon on the website. |
| Linux | Not started. Coming soon on the website. |

A port needs a platform-specific input layer (touch and accessibility APIs). The logic in `SwipepadCore` can be reused without change.

## Known limits

- Recognition is weakest when the swipe starts far from the first letter. On the full word list, starts three keys away find the intended word in the top three only about 1 time in 5.
- Proper nouns such as place names are not in the dictionary.
- The trackpad framework is private to Apple. macOS updates can break it. Swipepad cannot ship on the Mac App Store.
- Built with a local development certificate. macOS blocks the first launch: right-click the app, then Open.
