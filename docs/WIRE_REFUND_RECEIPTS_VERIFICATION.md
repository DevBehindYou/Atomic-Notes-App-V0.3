# App consumes actual Server partial/all-failed receipts

The App fixture pins Server main `0ff91587b77150c4edcd4018bfad7324cf3aac78`
(#30 exact-head/main CI both passed). A bounded fake Drive failure rejects one of
two notes. Real ApiClient/Repository/Hive/Cubit must acknowledge only the accepted
note, retain the failed note dirty, and show the actual 10 charged / 0 refunded
receipt matching the real wallet/ledger delta.

A new attempt containing only the failed note must receive 10 charged / 10
refunded, leave the wallet unchanged, and preserve dirty state. Clearing the fake
failure allows a fresh request to upload that note; the already accepted note is
not sent/written again. Each attempt's receipt and request identity is checked.

These are real HTTP/notes/auth/Mongo transactions with simulated Drive failures.
They do not prove Google retries, crash recovery, cap-limited refund, native UI
rendering, two phones or production operations. Existing five wire scenarios
remain enabled; R25 remains partial. No production source/dependency changes.

Required gates: local strict analysis and targeted test compilation, then both
exact-head CI jobs (all six live cases) and destination-main CI before completion.

Publication checkpoint: local strict analysis and ten targeted safety/transport
tests pass. Six live cases explicitly skip locally and require dedicated CI.
