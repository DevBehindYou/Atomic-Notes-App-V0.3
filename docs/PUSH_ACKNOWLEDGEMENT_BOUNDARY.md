# Native push acknowledgement preservation

## Behavior

The real API client now validates every returned note acknowledgement before
returning a reply to the repository. A malformed or incomplete batch cannot
partially clear dirty notes, regress versions/signatures, advance the cursor, or
discard the saved request. The same saved request remains available for retry.

Submitted IDs and base versions are captured before HTTP awaits. Returned IDs
must cover that exact batch once each. Every result has a boolean outcome; a
success has a positive integer version newer than its submitted base version,
or equal when explicitly unchanged, plus a calendar-valid UTC timestamp.
Optional sequence numbers must be positive integers and optional unchanged
flags must be boolean. Failures require a nonempty error string and do not
require success-only fields. Returned result containers are immutable.

Ordinary sync still accepts valid acknowledgements when optional billing
metadata is missing/malformed, reporting the cost as unknown. Logout uses the
same note preflight and continues to require its mandatory funding receipt.

## Compatibility authority

- Accepted Server `95070c0cff488e4984bd669d31bfdf348ec74aca`,
  `src/routes/notes.ts:327`–333: conflict failure and unchanged success.
- `src/lib/syncOperation.ts:137`–144: exactly one settled result per submitted
  note, with an explicit interrupted-write failure for uncommitted rows.
- `src/lib/noteMetadata.ts:33`,106,140: committed success version/time/sequence
  and incremented versions. `src/routes/notes.ts:455`–459: a fresh first-upload
  tombstone receives version one, not zero.
- Legacy Server `src/routes/notes.ts:243`: unchanged success has the existing
  version and timestamp and may omit sequence. UTC whole-second timestamps
  remain accepted. No wire fields or Server policy were added.

The UTC validator is the existing recovery receipt round-trip validation,
extracted without changing that parser's behavior. Impossible dates cannot
pass merely because Dart normalizes them.

## Before/after causal evidence

Tests-only source `26101793460238bea65e7656d336eb17f34a4ee3`, CI
`38589436697`, used the unchanged production parser from accepted App
`986ff448c8822324cd9cc050016f9ab9b7a3a93c`. The named sanitized proof recorded:

- 11 malformed-batch preservation cases failed.
- Seven compatible write/billing/unchanged/failure/tombstone/sequence controls
  passed.
- All 18 owned Hive/transport/session-fixture cleanup receipts passed.

The causal test file SHA-256 is
`178b51b33978146da8b26eccb97917731e4eea9e270d150c8f4d6b6d3c625f4a`.
Its body stays unchanged after the fix. These cases use the real ApiClient and
NotesRepository through controlled HTTP and real disposable Hive; they compare
complete memory/disk note maps, dirty flags, cursor and pending request before
retrying the identical original HTTP body. They do not access real accounts,
Drive, production MongoDB or devices.

The 16 existing R8 billing/replay/transport cases retain all assertions. Their
shared accepted fixture now includes the timestamp the actual Server always
returns, instead of omitting a repository-required field. Additional API
controls cover timestamp shape, zero/string/equal versions, optional field
types, immutable results, caller mutation and logout preflight.

After-change acceptance requires exact-head required CI checks, all 18 causal
cases and cleanup receipts passing with the identical test-file hash, source
review, then merged-main re-verification. This document records the design and
before-change proof; a successful merged-main acceptance is not yet claimed.

## Verification boundary

This validates response structure before note acknowledgement processing. It
does not authenticate the Server's truthfulness, change Server charging or
Drive transactions, make sequential Hive writes atomic after a valid reply, or
prove physical-device/crash durability. Browser editing remains disabled.
