# App delete/edit conflict preservation through actual HTTP

Two additional cases extend the existing real App API/repository/Hive/Cubit to
actual notes/auth routes and disposable MongoDB fixture, with simulated Drive.
They use the fixture's otherwise read-only isolated owner and wallet. Each client
has independent Hive and synthetic secure storage, but both use the same public
synthetic bearer session. Session/device-management behavior is not claimed.

- A stale offline delete loses to a newer accepted edit. The original receives
  the accepted edit; the older content is preserved in a new live conflict copy.
  The deletion intent is refused, not silently applied to that newer version.
- A stale offline edit loses to a newer accepted delete. The original remains
  a tombstone; the offline edited content is preserved in a new live conflict copy.

Both cases capture actual server versions; require visible conflict messaging,
10 charged / 10 refunded matching the actual wallet and ledger, no stale Drive
write/live-count change, a dirty local copy, its next-request acknowledgement,
and delivery of that copy to the other client without changing the original's
accepted live/deleted state.

Local strict analysis passes and ten transport/origin controls pass. Eight live
cases explicitly skip locally; only the dedicated disposable CI job executes
them. Production code, fixture safety, dependencies, wallet rules, Drive adapter
and workflow pin remain unchanged. The pin is verified Server main `0ff9158`;
Server #31 separately verifies stale-delete/edit refusal using those same routes.

This is logical-client content preservation, not two physical devices, native
secure storage or navigation, Google Drive/Atlas/Vercel, tombstone TTL expiry,
durable cross-store crash recovery or a signed upgrade. R25 remains partial.
Exact-head CI and conflict-free merge plus destination-main CI remain required.
