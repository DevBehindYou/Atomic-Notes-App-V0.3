# Current and delayed actual 401 responses preserve account work

Fixture-only follow-up from verified App main
`bf2b505097fb30f680a38f6417b70589d0809ea0`. The Server fixture pin advances to
`327bcf8dc1834da5f3c72159bd0d429160da7cc4` after exact destination-main CI passed.
Production source, schemas, dependencies and session policy are unchanged.

Two additional live cases use the real logout/auth/notes routes and actual
Mongo sessions, alongside the real ApiClient/repository/Hive and independent
synthetic secure-storage stores:

- The fixture revokes the first client's token through real logout. A dirty
  push gets a current 401; the API emits session-ended, hides account access and
  clears its queued synthetic token/user keys. The note, owner tag and saved
  pending operation remain on disk, with unknown receipts. Restoring the other
  same-owner synthetic session reopens the offline note and retains that same
  saved operation. It does not prove eventual upload: this owner's fixture
  energy is already exhausted.
- A fully received real 401 from the revoked token is held at the transport
  boundary. The API reloads a newer same-owner session before release. The old
  reply becomes session_changed, without a session-ended event, key deletion,
  cache mutation or revocation of the current session. A subsequent request with
  the current token succeeds. This is response-ordering proof, not a network
  packet-loss or native Google account-switch test.

Wallet/history and fake Drive writes are unchanged in both cases. Sixteen live
cases explicitly skip locally and execute only in CI. Strict local analysis and
ten origin/transport controls pass. The factory's optional independent test store
and response barrier exist only in this test file.

Native SessionGuard navigation, actual keystore/Google sign-in, sign-out UI,
inactivity policy, concurrent session issuance and signed upgrade remain separate.
Server #35 characterizes real logout, expiry without TTL timing, seven-day hashed
issuance and the five-session cap, with ordering ties explicitly unproved.
R25 remains partial and R28 policy remains open. Both exact-head jobs and
destination-main checks are required.
