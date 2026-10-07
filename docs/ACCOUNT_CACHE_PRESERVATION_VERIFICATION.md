# Preserve unfinished work across a different-account sign-in

Verified locally, 7 October 2026. This supplements R3's same-owner reload proof;
it does not change the original 28-finding denominator or close native acceptance.

## Before / after evidence

Before-test commit `50ae71a3f0be59d64406802119bfd6ba0a442557` used unchanged
production code from main `0338ee4da9a07cccb9c989f5b20ededcdbd199e1`.
Seven Hive/repository tests produced five failures and two passing controls.
Plain and encrypted dirty rows and an unresolved operation were actually removed
when another owner started. A hot owner change could submit previous-owner rows
or persist a new note into the old cache. Same-owner reload and replacement of a
fully acknowledged cache passed. Synthetic data only; no real account was used.

After the guards, thirteen repository tests and four recovery-widget tests pass.
The existing lifecycle suite still passes, including same-owner restart and the
now explicit acknowledged-clean cross-owner control. Strict analysis passes;
the full local suite passes **475 tests**, with **six live wire cases skipped**
locally. Those six cases require the dedicated disposable Server CI job.
The first full run caught pre-initialization getter errors; an empty-cache
initialization guard corrected them before the successful full rerun.

## Implemented boundary — verified in code

- `lib/database/notes_repository.dart:109`: cache ownership is checked against
  the active account. Foreign reads return no notes, counts or ciphertext sample.
- `lib/database/notes_repository.dart:116`: raw dirty metadata (including locked
  ciphertext) or any unresolved operation prevents foreign-cache adoption.
- `lib/database/notes_repository.dart:228`: loading never deletes a foreign
  cache, including signed-out startup and vault-lock reload.
- `lib/database/notes_repository.dart:312`: start replaces only a foreign cache
  with no unfinished work; unfinished work raises a dedicated recovery error
  while keeping rows, cursor, request and owner tag intact.
- `lib/database/notes_repository.dart:393` and `:607`: writes and sync require
  cache ownership; delayed sealing and merge results are checked again after
  asynchronous work. Maintenance paths cannot erase another owner's cache.
- `lib/page/splash_screen.dart:73`: a foreign pending cache routes to opaque
  recovery before normal note access. Background-start rejection is handled too.
- `lib/page/account_cache_recovery_page.dart:20`: recovery signs out the new
  session using ApiClient, without calling local-note clearing. Back is blocked;
  loading, safe retry text and a scrollable small-screen layout are tested.

No new cache format, dependency, Server route, data migration or production
operation. Existing owner tags and raw dirty/pending metadata remain authoritative.
The user must sign back into the original account, unlock its vault if needed,
finish syncing, then switch accounts. Multiple offline accounts remain unsupported.

## Verification boundaries

Repository controls use real disposable Hive files, simulated ApiClient sessions,
and a fixed-key test vault. Recovery widgets inject sign-out callbacks. The disk
loader exercised by vault lock is the same loader used by init; cold native init
and actual splash/session-guard/Google navigation are inferred from code, not
end-to-end widget or device proof. Keystore, Android lifecycle, retained editor
screens, two physical devices, Google/Drive/Atlas/Vercel and signed 2.03.5-to-2.03.9
upgrade remain unverified. Unknown/unowned legacy cache rows retain their existing
policy; this change guards caches that have an owner tag.

Exact-head parallel Flutter/debug-build and six-case wire CI, conflict-free merge,
and destination-main CI are required before integration is declared complete.
