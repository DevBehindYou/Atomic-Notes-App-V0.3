# R8 sync billing and completion messages

The Server charges per recorded upload request, not per note or per user tap.
Instant sync can send several batches. Server responses contain charged/refunded
amounts, but the current NotesSource contract returns only a completion boolean.
A fixed "-10 energy" confirmation therefore cannot describe the operation's
actual cost. A receive-only sync can also download changes, and partial upload
success can precede a failed pull or another batch.

Successful manual sync now says "Sync finished". The fallback incomplete-sync
message confirms local preservation without claiming every change exists only
on this device. Detailed repository errors remain unchanged. The obsolete
instant-price callback is removed from NotesBloc and its callers.

The Energy screen and tour explain per-batch charging, the shared account hourly
window, potentially larger instant costs and free receive-only sync. Upload
prices come from the existing EnergyLimits model (with existing offline defaults),
not a new economy policy. No charge, refund, batching, cooldown or replay behavior
changes.

## Proof and boundaries

Test-only baseline `6738062` against main
`3a26c2cd19ef59356815bda686e12f057cf1f8db`: five regressions fail and a
specific-error control passes. Cases cover a successful upload, receive-only
completion, incomplete sync, standard mode and the actual pricing-tour text.
The baseline corrects the widget fixture's uppercase navigation labels; earlier
fixture failures are not counted as pricing proof.

This is the first R8 correction, not receipt-based cost reporting. It does not
prove a live wallet debit, a refund, two-device behavior or exact charges for the
user's latest tap. The App still discards the Server receipt and must carry it
through the repository before such reporting can be added. R8 remains partial.

A separate double-text-size tour overflow was found during verification. Its
layout fix is separate from these pricing and result messages. No new service,
dependency, migration, device action or production write. Rollback is to revert
the PR, including constructor/caller changes together.
