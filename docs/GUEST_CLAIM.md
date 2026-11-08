# Guest claim preparation (C18)

`lib/recovery/guest_claim_manifest.dart` models moving a Guest's local notes
into a signed-in library. It is tested against ports only. Nothing here is
reachable from the app.

`GuestClaimFeature.enabled` is `false`, and the coordinator refuses to run
unless a fixture passes `enabled: true`. A live claim, and any account or
library binding change, waits for B05 and the accepted identity and binding
contracts (C28, C29).

## Ports

- `ClaimSource`: the current Guest notes. They are read again at each step,
  because the Guest may still be editing.
- `ClaimDestination`: the signed-in library. It has three read-only queries
  (existing ids, remaining note capacity, a note by id) and one
  id-preserving `put`.
- `ClaimJournal`: durable claim progress, so an interrupted claim resumes.

## Rules

1. **Preflight writes nothing.**
   - A library that already has notes is refused with
     `claim_target_occupied`. A claim never merges into an occupied library.
   - A library without room for every live note is refused with
     `claim_capacity_exceeded`. Recycle-bin notes do not count.
2. **The snapshot is frozen.** `GuestClaimManifest` records the ids and
   content signatures, including recycle-bin notes. It is journalled before
   the first write. Ids are kept exactly.
3. **Puts are idempotent.** A put is skipped when the library already holds
   that id with the same content. A retry, a duplicate claim or a resume never
   writes a note twice. The crash sweep confirms at most the interrupted put
   is repeated.
4. **Edits after the snapshot are caught up.** The Guest notes are read again
   after each round.
   - Changed or added notes become a new round.
   - A copied note the Guest removed goes into the library's recycle bin. It
     is not dropped and not left live, and it is reported in
     `removedDuringClaim`.
   - A Guest who keeps editing stops the claim after `maxRounds`, with
     `claim_unsettled`. The journal is kept, and the claim can be resumed.
5. **The Guest's own notes are never removed.** Releasing the Guest profile
   is a separate step that is not modelled here.

## Tests

`test/recovery/guest_claim_manifest_test.dart` has 9 tests:

- the gate is off by default;
- every note is copied with its id, including recycle-bin notes;
- an occupied library is refused;
- a library without enough capacity is refused;
- a duplicate or resumed claim writes nothing twice;
- edits, additions and removals made during the claim are not lost;
- a claim that cannot settle stops and can be resumed;
- a crash at every persistence boundary resumes without loss;
- the manifest round-trips, and unknown versions are refused.

## Open decisions (Codex or owner)

- **Server-side capacity.** The limit comes from the account's Energy note
  limit. Whether claimed notes are charged like new notes is an economic
  rule, and it is not decided here.
- **A removed note's recycle-bin copy.** It keeps the claim's `touch` time,
  not the Guest's deletion time.
- **The first real adapters.** These are the native repository, which is
  reserved, and the Server push path. They come after B05.
