# Cloud wipe preserves local work and other-client cache

Fixture-only follow-up from App main `f46938946e9b387e8c81c9606aa5302500605672`,
whose exact-main CI passed. It keeps the reviewed Server fixture pin
`b6b113cf49594a8bcc748e1cc1921221e8097778`: no new fixture endpoint is needed.
Production source, dependencies, schemas, policies and credentials are unchanged.

The twelfth wire case first pulls existing notes into two independent logical
clients, then saves an unsent note on the client requesting a cloud wipe.
The real repository/API/Server wipe must preserve all local content and dirty
flags, reset cloud versions/signatures, and leave that offline work waiting.
Cloud Notes must show zero cloud notes while retaining the device count.

A second client with an earlier actual cache/cursor then receives no tombstones
and keeps its entire Hive snapshot. A fresh client receives no notes or recycle
bin entries. Actual Server wallet/ledger and other-account state remain unchanged;
pulls write no files. Explicit refill marks live local notes dirty without
uploading or billing. This owner's synthetic energy is already exhausted, so
successful refill and simultaneous wipe/push are separate unproved scenarios.

Server #33 separately checks authenticated wipe, metadata removal, retained
sequence, other-account isolation, historical replay without restoration or
charge, and repeated wipe. This App case exercises existing notes/auth routes
with disposable Mongo transactions and fake Drive. Native UI/navigation, real
Drive trash, vault-verifier retention, durable recovery and physical devices
remain outside scope. R25 remains partial.

Strict local analysis and ten transport/origin controls must pass; twelve live
cases explicitly skip locally and run only in CI. Both exact-head jobs and
destination-main CI are required before integration is accepted.
