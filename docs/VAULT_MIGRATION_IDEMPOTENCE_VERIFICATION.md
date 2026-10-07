# Unlock must not reupload acknowledged encrypted notes

**Verified before correction:** commit
`065fda726d148a5e8f55d23d3e2f9bfaaab745f6` adds five local causal tests while
production source remains unchanged. All five failed: acknowledged ciphertext
was requeued on unlock; repeated plaintext migration requeued completed work;
an acknowledged encrypted edit was requeued; a cold cache with unknown cloud
format never settled on repeat; and partial migration requeued successful rows.
The valid sixteen-note wire fixture also failed its unlocked-content group in
run 37662736723. Earlier oversized positive fixtures and the initial wrong
rejection assumption are retained separately, not used as causal evidence.

**Correction:** NotesRepository remembers an encrypted cloud version only from
an actual pull or a successful push acknowledgement of the sent encrypted row.
It does not infer cloud encryption from locally sealed Hive content. Migration
still seals local persistence, but forces upload only when the local cloud
version lacks that proof. Actual dirty edits and interrupted plaintext conversions
retain their pending state; completed encrypted rows are not marked dirty again.
Equal-version pulls can establish format proof; older pages cannot replace newer
acknowledgements. Account/cache teardown and cloud wipe clear the in-memory map.

The map is not persisted. **No Hive/Mongo schema, migration, wire format, policy,
dependency, keystore or cryptography changes.** Unknown cloud formats remain
conservative after a cold restart without a successful pull. A successful unlock
reload revisits the cursor and establishes proof from the real encrypted rows.
This prevents needless uploads; it does not skip actual plaintext migration.

**Verification required before merge:** the five causal tests pass after the
correction, strict analysis and the full local suite pass, all twenty-one real
wire cases pass in CI, and the independent Flutter test/debug-build job passes
on the exact latest head. Scoped optimized mirroring waits for merged-main CI.
Native keystore, recovery phrase/Argon2/verifier, physical two-device and signed
upgrade/production acceptance remain separate. R25 remains partial.

**Verified locally in the review clone:** all five before-failing controls pass,
strict analysis reports no issues, and the full suite passes 480 tests with
twenty-one real HTTP/Mongo cases explicitly skipped. No local APK, database or
device action occurred. CI and optimized-source acceptance remain separate gates.
