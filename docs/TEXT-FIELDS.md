# Why text fields differ, and how Swipepad handles it

Swipepad never inspects pixels or app names. It reads what each field's Accessibility (AX) provider
exposes, and each framework exposes something different. This page lists the differences that
matter, the rule applied to each, and the check that locks that rule in.

"Locked by" names a check in `SwipepadChecks` (headless: `swift run SwipepadChecks`), in
`Tests/RepeatFlow` (memory-only production handlers: `scripts/test-repeat-flow.sh`), or in the
offscreen native fixture (`scripts/test-native-text-evidence.sh`). Nothing here is a claim about a
live app.

## Document text

Rule rows are in `FieldText.resolve` (`Sources/SwipepadCore/FieldText.swift`). Each row below names
its check, prefixed `field text:` in `SwipepadChecks`.

| Provider shape | What differs | Rule | Locked by |
| --- | --- | --- | --- |
| AppKit text view with the full AX text suite | `AXValue`, `AXNumberOfCharacters` and `AXStringForRange` agree | Full-range text is preferred. Its UTF-16 length must equal the count, and the count must be stable across the read | `field text: native field: full range agrees with its count`; native fixture |
| `AXValue` omitted, full text suite present (contenteditable-like) | `AXValue` returns no value | Full-range text is used | `field text: AXValue omitted; full range authoritative (contenteditable shape)` |
| `AXValue` omitted and no count | Nothing verifiable | Refused, with zero writes | `field text: AXValue omitted and no count: nothing verifiable`; RepeatFlow `missing, invalid, truncated or changing full-range evidence refuses with zero writes` |
| Placeholder or label exposed as `AXValue`, count available | `AXValue` is hint text, not content | Never preferred over a full range. Never copied into document text | `field text: placeholder-equal value verified by a matching count`; RepeatFlow `contradictory accessible placeholder is never copied into the document or expected receipt` |
| Placeholder as `AXValue`, no count, whole-value rewrite | The hint cannot be told apart from authored text | Whole-value rewrites are refused. Caret insertion may proceed and is checked by exact receipts | `field text: value-only provider reports its placeholder as the value`; RepeatFlow `ambiguous hint-valued whole-value rewrite is refused before any mutation` |
| Authored text equal to the placeholder, no count, caret insertion | Same text, but the user typed it | Accepted and checked by exact receipts | RepeatFlow `real authored text identical to a placeholder is retained and receives a normal exact append` |
| Full range truncated, or count changes during the read | Partial or unstable evidence | Refused | `field text: provider truncates the full range`; `field text: count changes while the range is read` |
| Count disagrees with `AXValue` length, or a zero count with non-empty `AXValue` | Contradictory evidence | Refused | `field text: count disagrees with AXValue length`; `field text: zero count never accepts a non-empty placeholder value` |
| `AXValue` read denied (`apiDisabled`, `cannotComplete`) | A failure, not an absence | Refused before any other read, so no text-suite fallback runs | `permission and provider failures are never read as absence`; RepeatFlow `permission/provider failures never become text-suite fallback` |

Surrogate pairs are counted in UTF-16 units, the unit AX uses for ranges:
`field text: surrogate pair is counted in UTF-16 units`.

## Whether a field can take insertion

Rule rows are in `InsertionCapability.available` and `FieldPolicy.permits`
(`Sources/SwipepadCore/Core.swift`).

| Provider shape | Rule | Locked by |
| --- | --- | --- |
| `AXEditable=false` with writable attributes | Refused. Read-only controls win | `explicit AXEditable=false refuses despite writable attributes` |
| Writable `AXSelectedText`, no `AXEditable` | Allowed | `native field with writable selected text and no AXEditable` |
| Writable `AXValue` and `AXSelectedTextRange`, no `AXEditable` | Allowed | `value-and-range provider without AXEditable` |
| Only `AXValue` writable, no selection range | Not an insertion path | `value alone without a selection range is not an insertion path` |
| No writable attribute, `AXEditable=true`, keyboard path available | Allowed through the keyboard path. `AXEditable` must be stated, never inferred | `explicitly editable field uses the keyboard path when no attribute is writable` |
| `AXEditable` absent, keyboard path available | Refused | `keyboard path never qualifies a field that lacks AXEditable=true` |
| Secure text field, or Secure Input active | Refused | `password subrole`; `secure metadata cannot bypass via text area role` |
| Search field, or ordinary field with no subrole | Allowed | `ordinary search field`; `ordinary browser/TextEdit textarea without optional subrole` |
| Unknown role, such as a button | Refused. Anything outside the allowlist fails closed | `unrelated control` in `SwipepadChecks` |

## Writes that succeed without changing the field

Some controlled editors accept an `AXSelectedText` write and then ignore it. Others publish the
change late, or let rich text reflow a trailing non-breaking space.

- Every write is confirmed by an exact content and caret receipt. The app never assumes success
  from the AX return code. RepeatFlow `selected-text acknowledgement without content/caret change remains unresolved`.
- Only the generated trailing separator may reflow, and only for the exact previous receipt.
  `exact four receipts for own adjacent separator and fresh separator`; RepeatFlow
  `nine repeated words confirm exact own-separator WebKit reflow`.
- An unconfirmed write holds capture. Nothing is replayed, and nothing is retried through another
  transport after mutation.
- The write backend is chosen once, before mutation. Selected text is preferred. A whole-value
  rewrite is used only when selected text is not settable.

## Known limits

- Chromium and Electron build their AX tree lazily. Focus can read as "no value" until it is
  published. Swipepad waits briefly, then refuses. It does not set `AXEnhancedUserInterface` or
  `AXManualAccessibility`, because that changes another app's behavior and is outside this change.
  No headless check covers this. It needs a live run.
- The default transport is targeted Unicode keyboard events. `VALIDATION.md` describes that path as
  not yet qualified in receiving apps. Core rules cannot prove delivery. Only a live run can.
- These rows are rules, not tested apps. This document makes no claim of universal compatibility.
