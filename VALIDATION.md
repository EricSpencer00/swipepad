# Prototype validation

Verified locally on Apple Silicon using Swift 6.3.3 and the macOS 26 SDK:

- Native debug executable compiled.
- Release build and `scripts/build-app.sh` completed.
- Standalone `SwipepadChecks`: 28 synthetic checks passed, covering normalized keyboard geometry, five exact synthetic word paths, empty/nonfinite/out-of-range decoder input, double-Command transitions, repeated events, shortcut cancellation, held/additional modifiers, debounce, and focus-guard rejection cases.
- App bundle Info.plist passed `plutil -lint`; executable is arm64 Mach-O.
- Linked system libraries include AppKit, ApplicationServices, Carbon and private MultitouchSupport. No downloaded binary dependency or hosted CI is used.
- Public source reviewed for local filesystem paths, credentials and unrelated files. Vendored licenses are retained and copied into the local bundle.

Not verified: physical touch capture, candidate accuracy on real gestures, focus preservation or actual insertion in TextEdit/browsers, OS/hardware compatibility beyond compilation, permission behavior, sleep/wake, or UI appearance in an active desktop session. The app was not launched and no access permissions were changed during these checks. See README for the hands-on test plan. Synthetic checks are not evidence of working physical swipe input.
