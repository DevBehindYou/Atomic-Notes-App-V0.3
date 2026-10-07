# App row/UTF-8 batch limits, pending work and actual charges

Fixture-only follow-up from verified App main
`6c4dc1bb3add47d615e5c39fc6198ae829815161`. Server fixture pin advances to
verified main `9043f90c276f7095f4551b415e41dfbaf6ac52b4` (#34).
Production source, schemas, dependencies, limits and pricing are unchanged.

The fixture's separate synthetic 100-note-tier owner has its own wallet and
standard window. It does not borrow energy or capacity from preceding scenarios.
The existing cloud-wipe case now finds the other account by ID, avoiding an array
position assumption after the fixture added this third test owner.

Two additional real-client cases observe complete actual outgoing HTTP envelopes
without changing requests or responses:

- 51 dirty notes: one standard request carries 50 rows for 5 energy; one note
  stays dirty and visible. Another standard attempt is held by the client's
  known window without an HTTP push or charge. Instant sync sends the remaining
  row for 10 with a new request ID. Every ID is delivered once, Hive is clean,
  and actual wallet/ledger/Drive-write deltas equal the two receipts.
- 14 notes with 60,000 three-byte UTF-8 characters each: the 2.5 MB envelope
  budget splits 13 plus 1 rows, both actual requests remain within that budget,
  and appending the final row to the first envelope would exceed it. Two instant
  operations cost 20, all 14 bodies survive, and no saved operation remains.

Together with earlier cases, fourteen live tests run in CI only. Strict local
analysis and ten origin/transport controls pass; all fourteen live cases
explicitly skip locally. Server #34 separately proves its real 429 refusal,
per-request pricing, replay and six-page pull behavior. The Server permits up
to 100 rows; the 50-row ceiling here is the App's batch choice.

These use real App/repository/Hive/Cubit/API and real notes/auth/Mongo with fake
Drive and a test vault. They do not prove encrypted-payload byte expansion,
full app.ts request middleware, production performance/quotas, native devices,
crash compensation, signed upgrade or durable repair. R25 remains partial.
Both exact-head jobs and destination-main checks must pass.
