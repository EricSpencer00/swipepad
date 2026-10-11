# Implementation review — 2026-10-11

Review baseline: `94af7a7`. The reproduced cancellation defect below is repaired in `800d609`. This is a development audit, not release approval. Actual repeated Codex typing and reported jitter remain unresolved. The signed v0.2.23 build containing the cancellation repair is installed. A new physical Codex trial reached an acknowledged mutation without confirming delivery; it remains guarded and Off. The selected-text-first v0.2.24 repair is built and signed separately, with native delivery still unqualified.

## Where the work is

The public repository is [EricSpencer00/swipepad](https://github.com/EricSpencer00/swipepad). [Draft PR #1](https://github.com/EricSpencer00/swipepad/pull/1) consolidates the work on `checkpoint/codex-input-review-20261011`. `main` remains at `8878f5b`. The accumulated development work was committed on October 11 in `a472ab2`, followed by diagnostics in `94af7a7` and the cancellation repair in `800d609`. The available Git history has no October 10-dated commits; the checkpoint preserves those accumulated changes without inventing or backdating history.

GitHub reports the branch can merge without conflicts. That is not functional readiness: no hosted CI is configured, and the live editor acceptance below has not passed. Keep this PR a draft until its behavior is qualified.

## Ranked findings

### 1. Buffered contacts could survive cancellation and acquire a new caret — fixed

A production-handler reproduction created a completed `cat` stroke, buffered the beginning of the next contact during release grace, then changed the simulated caret before the grace timer fired. Completion rejected the old target, but sticky mode remained On. The timer replayed the buffered contact, acquired the new caret, and subsequent frames wrote there. The reproduction made one unintended write in a memory-only field; it did not access a user document.

`commitDeferredLift()` now requires an unchanged cancellation generation before replay or release-gate clearing. `consumeContact()` also refuses Off or lift-gated input. Regressions cover timer, proximity, direction and empty-frame flushes, continued held input, a genuinely fresh contact, and legitimate queued continuation while an earlier write waits for its caret. See [App.swift](../Sources/Swipepad/App.swift) and [RepeatFlow](../Tests/RepeatFlow/main.swift).

### 2. Cross-app insertion is not qualified — high priority, observed failure

The actual Codex trial reached recognition and an AX-acknowledged `valueAndCaret` mutation, but neither expected content nor caret was confirmed. This proves an unconfirmed mutation, not a harmless no-op or successful delivery. It also disproves the claim that the only problem is a missing shortcut or a multiline restriction.

The installed v0.2.23 `replaceSelectedText()` prefers replacing the complete `AXValue` whenever value/range setters are advertised, even if selected-text replacement is available. Settable metadata is not a behavioral guarantee. Whole-field replacement has a larger effect than inserting a word and needs qualification for rich editors and framework-controlled inputs. The alternative selected-text and experimental keyboard paths are not established fixes for Codex.

**Source repair staged:** v0.2.24 prefers `AXSelectedText` when available, limiting mutation to the current selection. Whole-value/caret fallback is chosen only when selected-text is unavailable. It keeps exact identity/range/content checks and records uncertainty before mutation. New regressions cover an acknowledged no-op and a mutation followed by error; neither retries through the other backend. Native delivery is not proven. A selected-text provider that leaves the old caret or trims the separator can still stall safely.

**Smallest next step:** account explicitly for the latest uncertain write, then test the preselected narrower transport with one word in an owned blank unsent composer, followed by exact text/caret confirmation. Never try a second transport after an uncertain write. Retain original app/field/range/protection checks. See [App.swift](../Sources/Swipepad/App.swift), `replaceSelectedText`, `settleDeferredCaret`, and `confirmOwnCaret`.

### 3. The latency-critical work shares one main run loop — high priority, source-proven architecture

The private bridge queues every contact frame on main. A tracked frame performs synchronous target validation, including about eight provider attribute/settable requests on the ordinary path, plus local PID checks. Rendering, word ranking, confirmation polling and the HID event tap also run there. The queue has no overload bound. A slow receiving editor can delay both capture and the filter intended to protect the pointer.

This is a credible jitter/timeout mechanism, not a measured cause of the reported jitter. The new host-clock queue-delay, AX timing and filter-failure counters make a discriminating trial possible. Observe them at boundaries; the old full doctor itself hashes/signature-checks and queries AX.

**Minimal repair direction after measurement:** remove repeated full AX qualification from every motion frame while retaining exact pre-write guards and bounded focus cancellation; render only the latest state per display refresh. Isolate the tiny input-filter path from blocking AX work if contention remains. Do not drop terminal/contact-boundary frames or introduce blind typing. See [App.swift](../Sources/Swipepad/App.swift) and [OpenMTManager.m](../Sources/TrackpadBridge/OpenMTManager.m).

### 4. Uncertain-write recovery is incomplete — high priority, source and live evidence

The guard correctly survives ordinary cancellation and mode toggles, records before mutation, and prevents replay. But it blocks every field in the same process until the exact original element/content/caret can be reconciled. Confirmation continues polling without an overall stop while active. Relaunch/quit destroys the memory-only record, and the normal relaunch helper has no unresolved-write check.

The original uncertain outcome was preserved in a text-free receipt. The user then explicitly approved abandoning it without replay and restarting. Only that instance was retired, and one signed candidate was started. Abandonment does not establish whether the original text was inserted. A clean trial must never bypass an unresolved guard by launching another writer.

**Smallest fix:** explicitly represent unresolved delivery, stop expensive repeated polling after a bounded observation period, and refuse ordinary relaunch while it remains unresolved. Provide deliberate reconciliation or informed abandonment without retransmitting text. Do not describe memory-only protection as surviving a crash. See [DoctorSupport.swift](../Sources/Swipepad/DoctorSupport.swift), `relaunchOwned`, and the transaction methods in App.swift.

### 5. Sleep/wake does not retire application capture state — high priority, source-proven omission

The bridge stops on sleep and restarts on wake without clearing the owner's active stroke, grace state, field ownership or frame-ordering state. Restart failure is not reported to the owner. A hardware frame-number/device reset could then cause persistent frame rejection; that particular device behavior is untested.

**Smallest fix:** turn capture Off on sleep while preserving unresolved writes; require explicit activation after wake. Test sleep during an unfinished stroke and during an uncertain mutation. Do not resume an old stroke automatically. See [OpenMTManager.m](../Sources/TrackpadBridge/OpenMTManager.m), `willSleep` / `didWakeUp`.

### 6. Active failures can be invisible — medium priority, source-proven UI path

On-Screen mode shows the keyboard but not the panel containing the status label. `showFeedback()` changes that hidden label and the menu tooltip. While On, mouse clicks are suppressed globally, so the menu is not an ordinary way to inspect the reason. Normal Off clears the status reason. Hiding the guide can leave no visible capture status, and the menu-bar icon itself does not visually change with state. The Start/Stop menu row has no action. Setup also says only double-Command stops capture, although Escape works.

**Smallest fix:** one small nonactivating, mouse-transparent state/reason indicator, visible even with the guide hidden; preserve the most recent failure through exit. Make shortcut/escape instructions consistent. Keep automatic dismissal of explicit activation refusals, verified by the installed synthetic-hotkey refusal check; that check does not qualify physical typing. See [Overlay.swift](../Sources/Swipepad/Overlay.swift), `applyGuideVisibility`, and [SetupView.swift](../Sources/Swipepad/SetupView.swift).

### 7. Recognition scores are not intent confidence — medium priority, measured synthetic limitation

Production ranks canonical keyboard paths using absolute position, normalized shape and endpoints; a bounded SCOWL tier penalty reranks the shortlist. It does not use sentence context or a calibrated probability of correctness. A margin can arise from the prior even when two words have identical geometry. Shortlist pruning can exclude a word before the full matcher. Offset, reversal and repeated-letter ambiguity remain real concerns.

The fresh straight A-to-O test labeled `auto` was accepted as `ado`. The eight other `auto` variants all ranked and accepted `auto`, but preserve its U-to-T reversal. The straight trace removes information; it must not be called a successful natural-`auto` test. No input was recentered, snapped or repositioned, and no word-specific production fix was added.

**Smallest next step:** collect separately authorized first-attempt natural strokes, including nearly straight `auto`, measure wrong commits and refusals, and test general shape/context changes on independent traces. Do not tune a special case for the complaint word or equate synthetic scores with human accuracy. See [GestureLexicon.swift](../Sources/SwipepadCore/GestureLexicon.swift), [Stroke.swift](../Sources/SwipepadCore/Stroke.swift), and [StressRecognition](../Tests/StressRecognition/main.swift).

### 8. Segmentation and bridge assumptions still need physical evidence — medium priority

Release grace is 220 ms by default, reconnection eligibility is capped at 140 ms, and decisions use main-thread processing time. The bounds and starting/hover/making semantics have generated tests, not a measured natural-contact distribution. Stalls can change whether a gap is interpreted as a bounce or a new word. A long-lived queued contact must never revive after a cancellation; finding 1 repairs one such path.

The bridge dereferences an opaque private device handle to obtain an integer ID even though a device-ID function is declared. Listener removal during indexed iteration skips a shifted successor. The latter is source-proven for multiple listeners; the app normally uses one, so current user impact is not established. Prefer an explicit device token/API and snapshot listener iteration. Private MultitouchSupport remains an OS compatibility risk regardless of tests.

## Fresh test results and their limits

| Check | Result | What it establishes |
|---|---:|---|
| Core checks | 282 pass | Pure geometry, policies, hotkey and generated contact logic |
| Offscreen mapping/transport checks | 177 pass | Production mapping/render-state helpers and synthetic event decisions; no live tap or AX delivery |
| Production handler regressions after both source repairs | 267 pass | Memory-only target ports, cancellation, exact-once attempts and delayed continuation |
| Synthetic stress | 16,000 cases, 2,000 words | Generated geometry robustness; no hardware or human accuracy |
| Synthetic lexical validation | 1,200 cases | 1,132 correct commits, 6 wrong commits, 62 refusals |
| Unknown-word cases | 14 of 60 falsely accepted | The acceptance rule cannot reliably reject out-of-vocabulary gestures |
| Installed non-text activation | Passed | Synthetic Command taps on an actual Codex non-text container: Off, zero writes, same focus, notice auto-dismissed |

Stress totals: 15,063 correct commits (**94.14%**), 93 wrong commits (**0.58%**), 844 refusals (**5.28%**). Excluding the 2,000 center-baseline cases gives 13,144 correct, 91 wrong, 765 refused across 14,000 perturbations. These perturbations still derive from the same canonical generator. They are not 14,000 independently recorded gestures.

Stress ranking-call latency was median 5.86 ms, p95 9.97 ms, maximum 222.87 ms on a shared development machine with other local work. The separate lexical run measured median 4.75 ms and p95 7.30 ms. Neither includes physical capture, release grace, AX delivery or confirmation. The stress maximum is not an isolated production latency measurement.

Tests and app retain raw normalized contacts. Display smoothing is not fed back into recognition. The mapping freeze test checks a retained property rather than dynamically resizing a live stroke; ordinary production panels are nonmovable/nonresizable, but that test alone is not proof of dynamic display behavior. The native integration harness injects contacts and uses disposable receivers; it cannot qualify the installed physical callback path.

## Simplification priorities

`AppDelegate` currently combines hotkey admission, capture ownership, segmentation, recognition, queueing, mutation confirmation, correction, UI and diagnostics in over 1,100 lines. Parallel flags and generations made the buffered replay defect difficult to see. Preserve the safety invariants, but make one small change at a time: explicit capture state, a separate transaction outcome, and one place that retires all buffered input. Avoid an immediate rewrite before a controlled failing trial.

Remove unused legacy helpers only after checking callers: old corner-redirection code is not the production filter, the legacy DTW decoder is not the production ranker, and some guide/calibration fields no longer determine input. Experimental transports should remain clearly unqualified. Do not grow more generated tests from the same path model as a substitute for a real editor trial.

## Acceptance and merge gate

1. Account explicitly for the old uncertain mutation without replay; retain the original instance until that decision. Preserve evidence before replacing its process.
2. Stage/sign the exact candidate with the existing identity, verify one GUI, existing trust, Off state and clean transaction state. Pin the watcher to that final binary; refuse wrong versions and duplicate instances before launching a helper.
3. In an owned blank unsent Codex composer, activate once and naturally swipe `cat`, `world`, `auto`, then repeat. Read exact expected content/caret only at boundaries, in the same app/field/trial. Do not send the draft or manufacture a caret match.
4. Observe real callback states, lifts, recognition, write attempts, confirmations, filter failures and timing. Check pointer/window stability and visible status, then Escape and double-Command exits with ordinary pointer/click behavior restored. Boundary sampling alone cannot exclude brief or internal editor jitter.
5. Qualify ordinary native single-line/search/multiline and a browser input separately. Include rejection of secure/read-only fields, field/caret changes, duplicate terminal frames, mixed lift/new-contact, sleep/wake and uncertain mutations. Stop at the first unexpected write and preserve its record.

The user approved retiring the old uncertain record without replay, and v0.2.23 now passes live signature, sole-instance, existing-trust and clean-Off checks. Its counters-only IPC also responds correctly. That participant trial now has actual callback evidence, but failed delivery confirmation. One newly acknowledged uncertain mutation is still retained in the original v0.2.23 process, which is Off. The earlier approved abandonment does not cover this new record. The separately staged v0.2.24 candidate needs explicit handling of that record before replacing the current instance, followed by native/physical qualification. No permissions were changed or text submitted. The small cancellation fix can be reviewed independently, but the consolidated draft is not ready to merge as a working typing release.


## Sentence continuation repair

Memory-based reproduction found missing separators when appending to existing text and duplicated separators before existing whitespace. The candidate now derives spacing from both sides of the exact selection, preserves punctuation, rejects partial words and broken graphemes, and binds that plan to the writer snapshot. Correction reuses recorded separators. Same-caret content edits invalidate an active stroke; confirmed own writes refresh the continuation digest. Local handler/core tests pass; receiving-control and physical qualification remain pending.
