# Swipepad

**Swipe to type on your MacBook trackpad.**

Swipepad is an open-source macOS menu-bar app. Double-tap ⌘ in any text field, slide one finger across a QWERTY keyboard, and lift. The word you traced is typed, followed by a space.

<!-- Demo: docs/demo.gif (coming soon) -->

## How it works

1. **Double-tap ⌘** to turn swiping on. Escape or double-⌘ turns it off.
2. **Swipe** one finger across the on-screen keyboard. A line follows your finger.
3. **Lift.** The best-matching word is typed into the focused field, with a trailing space.

The keyboard can be cropped to a part of QWERTY, and the start of a swipe doesn't have to land exactly on the first letter.

## Requirements

- macOS 13 or later
- A MacBook with a built-in trackpad
- Accessibility permission (asked for during setup)

Built and tested on Apple Silicon with Swift 6.3 and the macOS 26 SDK. Other versions have not been verified.

## Install

Pre-built releases are not published yet. For now, build from source:

```sh
./scripts/build-app.sh
open dist/Swipepad.app
```

The app is signed with a local development certificate, not a paid Apple Developer ID, and it is not notarized. macOS will block the first launch. Right-click the app, choose **Open**, and confirm. Keep the app in one stable location, because macOS ties Accessibility permission to the app's signature.

## Privacy

- Swipepad makes no network connections.
- Typed text, key contents, and gesture paths are never logged or saved.
- It never uses the clipboard and never sends Return.
- Secure text fields and Secure Input are refused.

## Status

Swipepad is experimental.

- Recognition works well for words swiped from the right starting key. On a large word list, a start three keys off the first letter finds the intended word in the top three only about 1 time in 5, so it's still a weak spot.
- Physical-trackpad behavior has been validated on one machine only.
- Typing into some apps is not yet confirmed to work reliably. Test in a plain text field first.
- It uses Apple's private `MultitouchSupport` framework to read trackpad contacts. An OS update can break that, and the app can't be distributed through the App Store.

The engineering log, review history, and validation evidence are in [docs/ENGINEERING-NOTES.md](docs/ENGINEERING-NOTES.md).

## Development

```sh
swift build
swift run SwipepadChecks        # ~400 headless checks, ~2 seconds
SWIPE_TUNE=1 swift run SwipepadChecks   # slow real-lexicon measurements
```

The `SwipepadCore` target holds the recognizer, layout, and crop logic and has no AppKit dependency. `SwipepadChecks` runs headless checks against it. The `Swipepad` target is the menu-bar app.

## Contributing

Issues and pull requests are welcome. Please keep changes covered by `SwipepadChecks`, and never add logging of typed text or gesture paths.

## Credits

Swipepad uses MIT-licensed components. See [NOTICE.md](NOTICE.md) for their licenses and sources. The word list is derived from SCOWL, and the keyboard layout follows the MIT-licensed SwipeType project. Swipepad is not affiliated with those projects.

## License

[MIT](LICENSE) © 2026 Eric Spencer
