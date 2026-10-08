# Retained local-only cache preservation — 9 October 2026

## Causal evidence

**Verified locally against unchanged production source:** on main
`6fb12cc2d191fe6c1210ff89df55d55604b56ae5`, test-only commit
`e8c7bff412dbb49503940ab296ce710c8c5b13d1` reproduced four failures and one
passing control. Create a note, receive an upload acknowledgement, wipe the cloud,
then log out or switch accounts. The note still has content, but its cloud version
is zero and its dirty flag is false. Both plain and sealed/locked rows were erased.
Intentionally deleted, never-uploaded notes remained eligible for clearing.

The before tests used real disposable Hive and the test vault's AES sealing,
with a synthetic ApiClient. They do not prove actual HTTP, device keystore,
Google sign-in, production Drive or two-device behavior.

## Source behavior

**Verified in code:** `NotesRepository._hasLocalOnlyNotes` checks raw local
metadata for live note maps without a positive cloud version. It does not need
the key or plaintext. `hasForeignPendingCache` now includes that condition, so
`start` refuses a foreign account without clearing the prior owner's disk rows.
`clearLocal` refuses it even when dirty counts are zero. Existing dirty and
unanswered-operation protections remain in force.

The settings logout catch displays a fixed `LocalOnlyCacheError` message directing
the owner to unlock if needed, use **Upload all** in Cloud Notes and sync.
The account-cache recovery page likewise explains local-only notes. Nothing
automatically uploads a note or charges energy on behalf of this guard.

**Verified by the scoped tests:** the original owner can reload both plain and
sealed content, deliberately mark it for upload, receive a new version and then
clear the acknowledged cache. Existing positive-version logout/account-switch
controls and the deliberately deleted local-only control remain valid.

The CI wire fixture pins Server main `cea850875d932235ac6ab2c8846529d01646589a`,
whose exact-main verification passed before publication. Its 22 existing live
cases are a separate regression gate; this new guard's causal proof is local
repository/Hive testing. No new wire shape, Hive field, crypto algorithm,
price, migration or production activation is introduced.

## Boundaries

**Inferred:** a positive locally cached version is an historical acknowledgement,
not a current proof that another device has not wiped the cloud. This guard cannot
detect a wipe performed elsewhere because that operation creates no tombstones.
Cloud wipes performed while sealed rows are already hidden may leave those
hidden rows' cached positive versions unchanged; that separate path is not fixed
or claimed by this change. User-initiated local wiping remains a destructive
explicit action. Signed upgrades, device storage and production rollout remain
separate acceptance gates.

Tests and source symbols are in `test/notes_repository_lifecycle_test.dart`,
`lib/database/notes_repository.dart`, `lib/page/settings_page.dart`, and
`lib/page/account_cache_recovery_page.dart`. Use the exact PR diff for line
references, since subsequent changes can move them.
