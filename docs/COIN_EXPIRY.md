# Coin expiry client support

1 October 2026. Deploy Server PR #8 before this client. Expiry activation remains a separate owner decision.

The Energy page displays the Server's batch snapshot, non-expiring balance, next expiry and paginated credit history only when that policy is enabled. UTC instants are formatted in local time. Cached balance is advisory; only the Server authorizes spending. Existing Server wallet fields remain readable without expiry fields.

Conversion IDs and amounts are saved in the existing secure storage before sending, under the account ID. A timeout, unknown response or session loss keeps the request. Retry unconfirmed conversion works even when no coins remain on screen. A different amount cannot replace an unresolved request; a successful response or explicit no-write refusal clears it. Concurrent taps do not send multiple requests. Session revision guards prevent account-switch responses being adopted. Before any conversion, the API verifies the Server advertises coin_request_replay; an older backend safely refuses conversion instead of ignoring retry IDs.

Tests use mocked HTTP/storage and Flutter widgets. Cases cover response loss/restart, account isolation, simultaneous taps, old-server refusal, wire dates, and 375px at 1x/2x text. No real wallet, purchase, production account or authenticated phone action is involved.

Remaining boundary: clearing application storage/uninstalling destroys a pending local request. The permanent Server operation record still prevents replay of its ID, but cannot infer whether a new ID represents a retry. Operator/device testing must not claim this as an unlimited crash/reinstall guarantee.
