# Cloud Notes per-batch pricing

Cloud Notes previously described both instant actions as costing a flat 10
energy and said Upload all sent only edited notes. The repository can send
multiple charged upload batches, and Upload all marks every live note for
upload. The action labels now say "10 energy / batch"; the explanation describes
the 50-change and size limits, potentially larger totals, free receive-only
sync and the account's standard hourly upload window.

The existing prices, upload selection, batch limits, API, charge/refund logic,
replay behavior and note storage are unchanged. This is accurate explanatory
copy, not a new pricing policy or a receipt-based cost display.

## Verification

Test-only baseline `3851f46` on main `742d1e4`: the two new pricing cases fail,
while five existing count-verdict controls pass. After the correction all seven
cases pass. Strict local Flutter analysis and all 365 tests pass. Each pricing
case also checks that opening the page neither starts sync nor marks notes.
App CI must independently pass analysis, tests and debug APK verification.

The App still discards Server charge/refund receipts, so R8 remains partial.
No live wallet charge, physical-device layout, multi-device sync or signed
release is established by these widget tests. Revert this PR to roll back.
