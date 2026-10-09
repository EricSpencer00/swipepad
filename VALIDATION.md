# Prototype validation

Verified locally on Apple Silicon using Swift 6.3.3 and the macOS 26 SDK:

- Native debug executable compiled.
- Release build and `scripts/build-app.sh` completed.
- Standalone `SwipepadChecks`: 68 synthetic checks passed, covering normalized keyboard geometry, five exact synthetic word paths, empty/nonfinite/out-of-range decoder input, double-Command transitions, repeated events, shortcut cancellation, held/additional modifiers, debounce, focus-guard rejection cases, structural field-policy regression cases, and mocked permission/process/bundle/monitor/device/field/telemetry doctor states with JSON schema roundtrip.
- App bundle Info.plist passed `plutil -lint`; executable is arm64 Mach-O.
- Linked system libraries include AppKit, ApplicationServices, Carbon and private MultitouchSupport. No downloaded binary dependency or hosted CI is used.
- Public source reviewed for local filesystem paths, credentials and unrelated files. Vendored licenses are retained and copied into the local bundle.

Not verified: physical touch capture, candidate accuracy on real gestures, focus preservation or actual insertion in TextEdit/browsers, OS/hardware compatibility beyond compilation, permission-request behavior or sleep/wake. The initial prototype was not launched during its initial checks; subsequent setup/doctor UI review used the actual rebuilt app without changing access permissions. See README for the hands-on test plan. Synthetic checks are not evidence of working physical swipe input.

Field-policy fix: read-only probes found ordinary writable `AXTextArea` fields with absent optional subroles in Brave (`attributeUnsupported`) and TextEdit (`noValue`). No field text was read and no text was inserted by these probes. These structural cases are accepted; password subroles, single-line missing metadata, other metadata errors, read-only fields and active Secure Input remain refused. This is not a physical swipe/insertion validation.

Setup/doctor adds explicit Accessibility request and exact-pane actions, in-app reconnect/reset/relaunch, read-only JSON preflight, and original generated icon sizes. Live pass indicators require observations and do not infer physical e2e success from metadata. No Input Monitoring request, TCC reset/edit, test text injection, or clipboard fallback was added. UI and real doctor validation details are recorded after final build below.
